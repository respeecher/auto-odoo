#!/bin/bash

set -feuo pipefail
IFS=

. $(dirname $0)/variables

echo 'Testing if auto-odoo service is active...'
if systemctl is-active auto-odoo; then
    finish () {
	systemctl start auto-odoo
    }
    trap finish EXIT
    systemctl stop auto-odoo
fi
certbot certonly --standalone -d $domain -d crm.$domain

