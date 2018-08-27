#!/bin/bash

set -feuo pipefail
IFS=

. $(dirname $0)/variables

echo 'Testing if auto-odoo service is active...'
if systemctl is-active auto-odoo && [[ $certbot_method = standalone ]]; then
    echo "Shutting down Odoo to get certs..."
    finish () {
	systemctl start auto-odoo
    }
    trap finish EXIT
    systemctl stop auto-odoo
fi
docker run -it --rm --name certbot \
   -v "/etc/letsencrypt:/etc/letsencrypt" \
   -v "/var/lib/letsencrypt:/var/lib/letsencrypt" \
   -v "/var/log/letsencrypt:/var/log/letsencrypt" \
   -v "/root/.aws:/root/.aws" \
   certbot/dns-route53 certonly \
   --agree-tos --$certbot_method -n -d $domain -d crm.$domain --email $email

