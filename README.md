# Auto Odoo

Quickly configure a production Odoo server with SSL and backups.

To run a production Odoo server, you need to run the server itself, a database, and a reverse proxy to terminate
SSL.  Furthermore, you need to get an SSL certificate, and you need to implement a backup system.  Finally, you
should make all this start automatically when your machine boots.

Auto Odoo aims to make this all as simple as possible to set up while being as simple and transparent as possible
itself.  (This README is much longer than all the code making up Auto Odoo.)

To orchestrate the three servers, Auto Odoo uses docker-compose.  Unlike other dockerized Odoo systems which use
custom images that can be complicated to understand, Auto Odoo only uses the standard odoo, postgres, and nginx
images.  Of the three servers, only nginx requires any configuration, and Auto Odoo uses a simple reverse proxy
configuration optimized for security and performance (not compatibility with old browsers).

For SSL certificates, Auto Odoo uses certbot from letsencrypt in standalone mode.

For backups, Auto Odoo uses scp to copy the postgres data directory, odoo data directory, and nginx logs to a
machine or machines of your choice.  It also then truncates the logs so successive backups contain successive
segments of the logs.  No Odoo or Postgres logs are backed up.  (It wouldn't hurt to back them up too, but the
nginx logs are probably the most useful ones to have backups of.)

Using scp for backups is fine for safeguarding data against hardware failure, but unless special precautions are
taken it is not safe against the threat of a hacked Odoo server.  The problem is that hackers could use the ssh key
used to scp to destroy the backups (not to mention compromise the backup servers).  Auto Odoo solves this problem
by restricting this ssh key to only be able to scp into a particular directory and regularly moving backups out of
that directory (with cron jobs on the backup servers).

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

You can add yourself to the `docker` group to be able to run docker as non-root by running `usermod -aG docker XXX`
as root, replacing XXX with your username.  (Note that any user that can run docker effectively has root
privileges, however.)

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

Then edit the `variables` file to conform to your site's needs.  (Currently there is only one variable to
customize: the name of your server.)

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
specified by default.

The default settings only fix the major versions of Postgres and Odoo and nothing at all about nginx.  It is
probably best to pull new versions of these images, or at least of Odoo, regularly, so that any security
patches will be applied in a timely manner.  Therefore, the backup script, which is normally run nightly,
does this.  (Ideally, perhaps, a separate script would pull the images since this functionality has nothing to
do with backups, but it is simpler to just do it in the backup script.)

You may wish to fix minor versions as well for greater stability.

Future versions of Auto Odoo may include changed major versions of Postgres and Odoo in `.env.template`, but since
`.env` is gitignored, your major versions will never change unless you change `.env` yourself.  This is important
because upgrading between major versions of Postgres and Odoo requires running special migration scripts.

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
This will attempt to renew your certificates every night at 4:43AM.
Letsencrypt will reject the attempt until you are one month from expiry, and then it will renew them.

Schedule the auto-renewal late at night since Auto Odoo will briefly go down for it.

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

- As root, run `crontab -e` and make a cron entry like `13 4 * * * /home/odoo-docker/odoo-docker/backup.sh` (to run
  backups at 4:13AM every day).  Schedule backups late at night because Auto Odoo will briefly go down for them.
  Also, schedule it at a significantly different time from certificate auto-renewal so that these two processes
  will never overlap.

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

### Configure the backup servers

Follow these instructions for each backup server:

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

The backup archive (`.txz` file) is made from a directory called `backup` that `backup.sh` creates in the Auto Odoo
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
that used them.  So you may need to run something like `docker ps -aq | xargs docker rm` to clean up such containers
before running the restore.

As root, in Auto Odoo's directory, run `./restore.sh XXX`, where XXX is the name of the `.txz` archive you wish to
restore from.  Then bring up Auto Odoo as usual.

Having Auto Odoo installed on one of the backup servers is a good idea not only because it makes it quick to get
Odoo back up if your primary server dies but also because that way it is easy to periodically verify that restoring
works as intended.

## Firewalling Odoo

On any server, it is a good security practice to set up a firewall to restrict outside access to all ports except
ssh and any you are running services on.  In the case of services that are only used internally to your organization,
like Odoo, it is a good security practice to restrict access to your organization's network (which remote employees
can VPN into).  That way, if there is a security flaw in Odoo, your installation will not immediately vulnerable to
outside hackers.  Note that we do not restrict outbound connections at all.  That can help security, but it takes more
work and can more easily lead to things not working as expected than just restricting inbound connections.

If you are on AWS, you should be able to set this up pretty simply using security groups.  Otherwise, you will need
to use iptables.  Normally blocking access to ports from random IP addresses would be done by configuring the
`INPUT` chain of the `filter` table in iptables.  However, when a docker container is listening on ports, traffic
to them actually goes to the `FORWARD` chain instead, so blocking on the `INPUT` chain is ineffective.  So we need
to block access in the normal way on the `INPUT` chain (for ports other than 80 and 443 and for those ports in case
Odoo is down), but we also need to block access on the `DOCKER-USER` chain (a special chain that docker sets up
that traffic is sent to before being sent anywhere else.

To enable ordinary blocking, as root,

```
# Accept pings
iptables -I INPUT -p icmp --icmp-type any -j ACCEPT
# Accept ssh (optionally, you could accept ssh only from your organization's network)
iptables -I INPUT -p tcp --dport 22 -j ACCEPT
# The following two lines accept stuff that should be accepted on
# almost any system for things to work normally
iptables -I INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -I INPUT -i lo -j ACCEPT
# Drop everything else
iptables -P INPUT DROP
```

(Note: docker creates some special network interfaces.  Possibly we should add rules to accept connections from
them just like from the loopback connection.  Or else we should set the default policy to ACCEPT but explicitly
drop traffic from the external network interface if it doesn't match one of our special ACCEPT rules.  However,
so far I have not had any problems with the config as is.)

(For some suggestions about additional stuff you might want to block on your servers, see
`https://security.blogoverflow.com/2011/08/base-rulesets-in-iptables/`.  It seems to me that these suggestions
are not all that likely to stop an attack, and one of them (dropping fragments) could possibly cause problems.)

To enable docker blocking, assuming there is just one IP address you need to allow access from, as root,

```
iptables -I DOCKER-USER -i <ext_if> ! -s <ok_ip> -j DROP
```

Here you need to replace `<ext_if>` with the name of your network device.  (It might be something like `ens3`.
Run `ifconfig` to find it out.)  And you need to replace `<ok_ip>` with the IP address you want to allow
connections from.

Test this configuration.  It is not persistent yet, so if something goes wrong, reboot your machine and you
will be back to where you started.

To make the rules persistent, as root,

```
apt install iptables-persistent
```

It will prompt you to save your current rules the first time.  Afterwards, if you make any changes to your
rules and want to persist them, as root,

```
iptables-save > /etc/iptables/rules.v4
```

Iptables doesn't do anything about ipv6 connections.  For that you need to use ip6tables.  But unless you
need ipv6 for something, you can just disable it, as explained at
`http://www.neuraldump.net/2016/11/how-to-disable-ipv6-in-ubuntu-16-04-xenial-xerus/`, by adding these
three lines to `/etc/sysctl.conf`:

```
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
```

and then running `sysctl -p`.

Finally, you may wish to similarly firewall your backup servers, or at least the backup server that you plan
to failover to if your main server breaks.
