# Auto Odoo

Quickly configure a production Odoo server with SSL and backups.

To run a production Odoo server, you need to run the server itself, a database, and a
reverse proxy to terminate SSL.  Furthermore, you need to get an SSL certificate, and
you need to implement a backup system.  Finally, you should make all this start
automatically when your machine boots.

Auto Odoo aims to make this all as simple as possible to set up while being as simple
as possible itself.  And it is relatively paranoid about trying to set up SSL in the
most secure possible way.

To orchestrate the three servers, Auto Odoo uses docker-compose.  Unlike other dockerized
Odoo systems which use custom images that can be complicated to understand, Auto Odoo
only uses the standard odoo, postgres, and nginx images.

For SSL certificates, Auto Odoo uses `certbot` from letsencrypt in standalone mode.

For backups, Auto Odoo uses `scp` to copy the postgres data directory, odoo data directory,
and nginx logs to a machine or machines of your choice.  It also then truncates the logs so
successive backups contain successive segments of the logs.

Auto Odoo is tested only on Ubuntu 16.04.

## Standard installation

Follow the following steps:

### Generate a strong prime for Diffie-Hellman key exchange

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

### Install certbot

Follow the instructions at `https://certbot.eff.org/#ubuntuxenial-other`:

As root,

```
apt-get update
apt-get install software-properties-common
add-apt-repository -y ppa:certbot/certbot
apt-get update
apt-get install -y certbot
```

### Install docker

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

### Install docker-compose

Follow the instructions at `https://docs.docker.com/compose/install/#install-compose`:

As root,

```
curl -L https://github.com/docker/compose/releases/download/1.19.0/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
```

### Configure site-specific variables

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
specified by default.  Then, if you upgrade Auto Odoo, even if the default images change, the images used in your
installation will not, which is good because upgrading between major versions of Postgres and Odoo requires running
special migration scripts.

Odoo uses `/etc/odoo/odoo.conf` not only for configuration that is done not changeable through the web interface but
also for things that are so changeable including, crucially, the database management password.  So this file must be
persisted for Odoo to be secure.  We achieve this by bind mounting `odoo.conf` in the Auto Odoo directory into the
container.  To obtain a good starting `odoo.conf` for the Odoo image selected in `.env`, run

```
./get-default-odoo-conf.sh
```

In order that this file have its normal owner and group, as root run

```
chown 101.0 ./odoo.conf
```

Run

```
mkdir backup-configs
cp backup-config.template backup-configs/myconfig
```

Edit `backup-config/myconfig` to conform to your needs.  You can also add additional backup configs if you would like
your backups stored in multiple places.

### Get certificates

As root,

```
./get-or-renew-certs.sh
```

Auto Odoo does not automatically renew your certificate.  However, if you like you can run `crontab -e` as root and setup
a cron job to run `/home/odoo-docker/odoo-docker/get-or-renew-certs.sh`.

### Make CAA DNS record (optional)

For extra security, you may wish to set up a CAA DNS record to instruct browsers that only letsencrypt.org can issue
certificates for your domain.

### Test it

Test that Auto Odoo will work by running `docker-compose up` and browsing to the "crm" subdomain of your domain
(or it will also work to browse to the domain itself).

Test that backups work by running `./backup.sh` as root.  (Root is needed because the backups are created preserving
the original file owners.)

If anything goes wrong with the backups, you can see output from the backup process in `backup/backup.sh.output` and
`backup-end-trace`.  If something goes wrong, the `backup` directory may be left over.  Remove it before trying again.

Now stop odoo with Ctrl-C or `docker-compose down`.

### Install, set up automatic backups, start, enable

- As root, run `./setup.sh`.  This will create a user called odoo-docker, copy the installation into that user's
  home directory, and install a systemd service to control auto-odoo.

- As root, run `crontab -e` and make a cron entry like `13 4 * * * /home/odoo-docker/odoo-docker/backup.sh` (to run
  backups at 4:13AM every day).  Note that Odoo will briefly go down for backups.

- As root, run `systemctl start auto-odoo` to start Odoo.

- As root, run `systemctl enable auto-odoo` to start Odoo on boot.

## Notes on backups

- You can manually run a backup anytime by running `backup.sh` as root.

- You should run a manual test backup anytime you change the backup configs.

- You should regularly check that backups are working properly.  A good practice is to have at least one backup be
  to a cloud server with Auto Odoo installed.  You might even run Auto Odoo and restore each night from the nightly
  backup.  Then any Odoo user can check that this backup server is always running the previous day's backup.

- All backups are kept permanently on the machines backed up to as well as in the Auto Odoo directory on the
  machine being backed up.  If that machine runs out of disk space, backups will start to fail.  (And also Odoo
  itself may start to malfunction if the machine runs out of disk space.)  In the future, we might implement
  systems to auto-prune backups and/or send alerts if backups begin to fail, but currently Auto Odoo does not
  support anything like this.  So it is important to be vigilant in monitoring disk usage.

## Restoring from backups

Restoring works by deleting the web and db data volumes used by Auto Odoo and replacing them with new data volumes
that the backup data is copied into.  So you should only restore if you are sure you don't need the existing data
volumes.  Note that nothing is changed regarding the nginx data volume during a restore because that volume is only
used for logs.

Before restoring, you must bring down Auto Odoo.  You can manually remove the old web and db volumes, or `restore.sh`
will do it for you.  But be aware that removing data volumes sometimes fails in docker if there are defunct containers
that used them.  So you may want to run something like `docker ps -aq | xargs docker rm` to clean up such containers
before running the restore.

As root, in Auto Odoo's directory, run `./restore.sh XXX` where XXX is the name of the `.txz` archive you wish to
restore from.  Then bring up Auto Odoo as usual.
