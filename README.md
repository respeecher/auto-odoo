# Auto Odoo

Quickly configure a production Odoo server with SSL and backups.

To run a production Odoo server, you need to run the server itself, a database, and a
reverse proxy to terminate SSL.  Furthermore, you need to get an SSL certificate, and
you need to implement a backup system.  Finally, you should make all this start
automatically when your machine boots.

Auto Odoo aims to make this all as simple as possible to set up while being as simple
as possible itself.

To orchestrate the three servers, it uses docker-compose.  Unlike other dockerized
Odoo systems which use custom images that can be complicated to understand, Auto Odoo
only uses the standard odoo, postgres, and nginx images.

For SSL certificates, Auto Odoo uses `certbot` from letsencrypt in standalone mode.

For backups, Auto Odoo uses `scp` to copy the postgres data directory, odoo data directory,
and nginx logs to a machine of your choice.  It also then truncates the logs so successive
backups contain successive segments of the logs.

Auto Odoo is tested only on Ubuntu 16.04.

## Standard installation

Follow the following steps:

- As root, `cd /etc/ssl/certs && openssl dhparam -out dhparam.pem 4096`.  (See comment in `docker-compose.yml` for why we do this.)
- Install certbot, docker, docker-compose, and cron.  (You can probaly install all of this with apt-get, but
  for certbot, docker, and docker-compose, it may be worth following the instructions on the docker web site to get
  the latest versions.)
- Run `cp variables.template variables` and edit the `variables` file to conform to your site's needs.
- Run `./propagate-variables.sh` to propagate the variable values into config files.
- As root, run `./get-or-renew-certs.sh` to get a certificate from letsencrypt.
- For extra security, you may wish to set up a CAA DNS record to instruct browsers that only letsencrypt.org can issue
  certificates for your domain.
- You can now test that odoo will work by running `docker-compose up` and browsing to the "crm" subdomain of your domain
  (or it may work to browse to the domain itself).
- You can now test backups by running `./backup.sh`.
- Now stop odoo with Ctrl-C or `docker-compose down`.
- As root, run `./setup.sh`.  This will create a user called odoo-docker, copy the installation into that user's
  home directory, and install a systemd service to control auto-odoo.
- As root, run `crontab -e` and make a cron entry like  `13 4 * * * /home/odoo-docker/odoo-docker/backup.sh`
  (to run backups at 4:13AM every day).  Note that Odoo will briefly go down for backups.
- As root, run `systemctl start auto-odoo` to start Odoo.
- As root, run `systemctl enable auto-odoo` to start Odoo on boot.

Auto Odoo does not automatically renew your certificate.  However, if you like you can run `crontab -e` as root and setup
a cron job to run `/home/odoo-docker/odoo-docker/get-or-renew-certs.sh`.

## Notes

- You can manually run a backup anytime by running `backup.sh` as root.

## Restoring from backups

To do ...
