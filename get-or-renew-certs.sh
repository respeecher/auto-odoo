#!/bin/bash

. variables
systemctl stop auto-odoo
certbot certonly --standalone -d $domain -d crm.$domain
systemctl start auto-odoo
