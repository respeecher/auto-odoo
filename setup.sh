#!/bin/bash
set -e
useradd --create-home odoo-docker
usermod -aG docker odoo-docker
cp -r . /home/odoo-docker/odoo-docker
chown -R odoo-docker.odoo-docker /home/odoo-docker/odoo-docker
cp auto-odoo.service /etc/systemd/system
