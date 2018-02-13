#!/bin/bash
set -e
useradd --create-home --shell /bin/false
usermod -aG docker odoo-docker
cp -r . /home/odoo-docker/odoo-docker
chown -R odoo-docker.odoo-docker /home/odoo-docker/odoo-docker
cp auto-odoo.service /etc/systemd/system
