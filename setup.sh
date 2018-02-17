#!/bin/bash
set -e
useradd --create-home odoo-docker
usermod -aG docker odoo-docker
sudo -U odoo-docker ssh-keygen -t rsa -b 4096 -N '' -f /home/odoo-docker/.ssh/id_rsa
cp -r . /home/odoo-docker/odoo-docker
chown -R odoo-docker.odoo-docker /home/odoo-docker/odoo-docker
cp auto-odoo.service /etc/systemd/system
