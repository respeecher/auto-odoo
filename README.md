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
and nginx logs to a machine of your choice.  It also then truncates the logs so successive
backups contain successive segments of the logs.

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
- As root, run `crontab -e` and make a cron entry like  `13 4 * * * /home/odoo-docker/odoo-docker/backup.sh`
  (to run backups at 4:13AM every day).  Note that Odoo will briefly go down for backups.
- As root, run `systemctl start auto-odoo` to start Odoo.
- As root, run `systemctl enable auto-odoo` to start Odoo on boot.

## Notes

- You can manually run a backup anytime by running `backup.sh` as root.

## Restoring from backups

To do ...
