# Auto Odoo

Quickly configure a production Odoo server with SSL and backups.

To run a production Odoo server, you need to run the server itself, a database, and a reverse proxy to terminate
SSL.  Furthermore, you need to get an SSL certificate, and you need to implement a backup system.  Finally, you
should make all this start automatically when your machine boots.

Auto Odoo aims to make this all as simple as possible to set up while being as simple and transparent as possible
itself.  (This README is longer than all the code making up Auto Odoo.)

To orchestrate the three servers, Auto Odoo uses docker-compose.  Unlike other dockerized Odoo systems which use
custom images that can be complicated to understand, Auto Odoo only uses the standard odoo, postgres, and nginx
images.  Of the three servers, only nginx requires any configuration, and Auto Odoo uses a simple reverse proxy
configuration optimized for security and performance (not compatibility with old browsers).

For SSL certificates, Auto Odoo uses certbot from letsencrypt in standalone mode.

For backups, Auto Odoo uses scp to copy the postgres data directory, odoo data directory, and nginx logs to a
machine or machines of your choice.  It also then truncates the logs so successive backups contain successive
segments of the logs.  By restricting the ssh key used to scp to only be able to scp into a particular
directory and regularly moving backups out of that directory, Auto Odoo ensures that your backups will be safe even
if your Odoo server is hacked.

Auto Odoo is tested only on Ubuntu 16.04.

To install, follow the following steps:

## Generate a strong prime for Diffie-Hellman key exchange

We start this first because the computation requires a long time.  You can do other steps while it is running that
don't involve starting Auto Odoo.

As root,

```
cd /etc/ssl/certs
openssl dhparam -out dhparam.pem 4096
```

See the section "Forward Secrecy & Diffie Hellman Ephemeral Parameters" of
https://raymii.org/s/tutorials/Strong_SSL_Security_On_nginx.html and
https://security.stackexchange.com/questions/94390/whats-the-purpose-of-dh-parameters
if you are interested in knowing more about how generating this parameter can, at least in
theory, help security.

## Install certbot

Follow the instructions at `https://certbot.eff.org/#ubuntuxenial-other`:

As root,

```
apt-get update
apt-get install software-properties-common
add-apt-repository -y ppa:certbot/certbot
apt-get update
apt-get install -y certbot
```

## Install docker

Follow the instructions at `https://docs.docker.com/install/linux/docker-ce/ubuntu/`:

As root,

```
apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
apt-key fingerprint 0EBFCD88
add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y docker-ce
```

You can add yourself to the `docker` group to be able to run docker as non-root.  (Note that any user that
can run docker effectively has root privileges, however.)

## Install docker-compose

Follow the instructions at `https://docs.docker.com/compose/install/#install-compose`:

As root,

```
curl -L https://github.com/docker/compose/releases/download/1.19.0/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
```

## Configure site-specific variables

Run

```
cp variables.template variables
```

Then edit the `variables` file to conform to your site's needs.

Run

```
./propagate-variables.sh
```

to propagate the variable values into config files.

Run

```
cp .env.template .env
```

Then edit .env if you want to specify the images to use for nginx, postgres, and odoo differently from how they are
specified by default.  If you upgrade Auto Odoo, even if the default images change, the images used in your
installation will not, which is good because upgrading between major versions of Postgres and Odoo requires running
special migration scripts.  The default settings only fix the major versions of Postgres and Odoo and nothing at
all about nginx.  This means that you can upgrade to the latest minor versions of Postgres and Odoo and the latest
version of nginx simply by doing a `docker pull` on the image labels specified in `.env` and restarting Auto Odoo.

Odoo uses `/etc/odoo/odoo.conf` not only for configuration that is not changeable through the web interface but
also for things that are so changeable including, crucially, the database management password.  So this file must
be persisted for Odoo to be secure.  We achieve this by bind mounting `odoo.conf` in the Auto Odoo directory into
the container.  To obtain a good starting `odoo.conf` for the Odoo image selected in `.env`, run

```
./get-default-odoo-conf.sh
```

In order that this file have its normal owner and group, as root run

```
chown 101.0 ./odoo.conf
```

## Get certificates

As root,

```
./get-or-renew-certs.sh
```

To setup auto-renewal of your certificates, run `crontab -e` as root and add a line like
`43 4 * * * /home/odoo-docker/odoo-docker/get-or-renew-certs.sh`.
This will attempt to renew your certificates every night.
Letsencrypt will reject the attempt until you are one month from expiry, and then it will renew them.

## Make a CAA DNS record (optional)

For extra security, you may wish to set up a CAA DNS record to instruct browsers that only letsencrypt.org can issue
certificates for your domain.  In your DNS, add records of type CAA with content `0 issue "letsencrypt.org"` for
your domain and its "crm" subdomain.

## Test it (optional)

If you want, you can now test that Auto Odoo will work by running `docker-compose up` and browsing to the "crm"
subdomain of your domain (or it will also work to browse to the domain itself).

Now stop odoo with Ctrl-C or `docker-compose down`.

## Install, set up automatic backups, start, enable

- As root, run `./setup.sh`.  This will create a user called odoo-docker, copy the installation into that user's
  home directory, generate an ssh key for the user, and install a systemd service to control auto-odoo.

- As root, run `crontab -e` and make a cron entry like
  `13 4 * * * /home/odoo-docker/odoo-docker/backup.sh`
  (to run backups at 4:13AM every day).  Auto Odoo will briefly go down for backups, so you should schedule them for a time
  when it will not be used much.

- As root, run `systemctl start auto-odoo` to start Odoo.

- As root, run `systemctl enable auto-odoo` to start Odoo on boot.

You may now test that Auto Odoo is working, and any changes you make will be persisted.


## Configure and test backups

In the previous section, we made backups run every night.  But for backups to actually work, we need to configure them.

### Generate an ssh key for Auto Odoo

As odoo-docker,

```
ssh-keygen -t rsa -b 4096
```

and hit enter a few times.

### Configure the Odoo server

Working in `/home/odoo-docker`, as odoo-docker,

```
mkdir backup-configs
cp backup-config.template backup-configs/myconfig
```

Edit `backup-configs/myconfig` to conform to your needs.  Unless you have deviated from the instructions you will
just have to set the name of your backup server, and possibly a port, if you need to run ssh over a non-standard
port.

You can add as many backup configs as you like, and it doesn't matter what they are named.  (The name "myconfig"
was just an example; you may prefer to name your backup configs after your backup servers.)

It's a good idea to configure at least two backup servers.

Another good practice is to install Auto Odoo on at least one of your backup servers so that you can quickly bring
it up if your primary machine self-destructs.

### Configure the backup server

On the backup server, as root,

```
useradd -m -s /bin/bash autoodoobackupreceiver
```

As autoodoobackpreceiver,
```
mkdir /home/autoodoobackupreceiver/backups
echo 'no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty,command="scp -t /home/autoodoobackupreceiver/backups" ' > /home/autoodoobackupreceiver/.ssh/authorized_keys
```
Now edit `/home/autoodoobackupreceiver/.ssh/authorized_keys` to add, without a line break, the ssh key in
`/home/odoo-docker/.ssh/id_rsa.pub` on the Odoo server.

This way of adding the key to `authorized_keys` ensures that the only thing Auto Odoo can do on the backup server
is copy files to `/home/autoodoobackupreceiver/backups`.  So if the Odoo server is compromised, the backup server
will still be safe.

Even with this precaution, if someone hacks your Odoo server, they will still be able to overwrite any files in
`/home/autoodoobackupreceiver/backups`.  Therefore, it is important to regularly move backups from
`/home/autoodoobackupreceiver/backups` to a safe location.

Run,
```
mkdir /home/autoodoobackupreceiver/safe-backups
```

Run `crontab -e` and make a cron entry like `23 5 * * * mv -n /home/autoodoobackupreceiver/backups/*
/home/autoodoobackupreceiver/safe-backups` (to move the backups at 5:23AM every day).  Note that cron uses local
time, so if your servers don't all use the same timezone, it is not simple to tightly synchronize cron actions
between them.  Fortunately, tight synchronization is not important for backup moving.

Even with these precautions, it is still a good idea to regularly copy backups to offline media.  Another good
precaution is to have at least one backup server that can only be accessed from a secure location (not your
laptop).

### Test backups

Test that backups work by running `./backup.sh` as root.  (Root is needed because the backups are created preserving
the original file owners.)  It is important to do at least one manual backup because ssh and scp prompt about
unknown hosts the first time they see a new host, and automated backups will not pass this challenge.

### General information about backups

#### Troubleshooting

The backup archive (`.txz` file) is made from a directory called `backup` that `backupl.sh` creates in the Auto Odoo
directory and then removes after creating the archive.  If something goes wrong with `backup.sh`, the `backup`
directory may be left over, and you should remove it manually.

Output from `backup.sh` is saved in `backup/backup.sh.output`.  After the archive file is made, `backup.sh` can no
longer save output in `backup/backup.sh.output`, so it saves a record of its output in `backup-end-trace` in the
Auto Odoo directory.  This is where you can look for errors that occurred while trying to ship the backups to the
backup servers.

#### Avoiding running out of space and manual monitoring

All backups are kept permanently on the machines backed up to as well as in the Auto Odoo directory on the
machine being backed up.  Be vigilant that there is sufficient disk space on the Odoo server and all backup servers
because Auto Odoo does not monitor disk usage or automatically prune old backups.  In any case, it is a good idea
to regularly verify that the backup system is working as intended (perhaps at the same time that you make offline
copies of the backups).

## Restoring from backups

Restoring works by deleting the web and db data volumes used by Auto Odoo and replacing them with new data volumes
that the backup data is copied into.  So you should only restore if you are sure you don't need the existing data
volumes.  Note that nothing is changed regarding the nginx data volume during a restore because that volume is only
used for logs.

Before restoring, you must bring down Auto Odoo.  You can manually remove the old web and db volumes, or `restore.sh`
will do it for you.  But be aware that removing data volumes sometimes fails in docker if there are defunct containers
that used them.  So you may want to run something like `docker ps -aq | xargs docker rm` to clean up such containers
before running the restore.

As root, in Auto Odoo's directory, run `./restore.sh XXX`, where XXX is the name of the `.txz` archive you wish to
restore from.  Then bring up Auto Odoo as usual.

Having Auto Odoo installed on one of the backup servers is a good idea not only because it makes it quick to get
Odoo back up if your primary server dies but also because that way it is easy to periodically verify that restoring
works as intended.
