#!/bin/bash

set -feuxo pipefail
IFS=

. .env

tmpdir=$(mktemp -d)
docker run --user $(id -u) -v $tmpdir:/tmpdir $odoo_image cp -a /etc/odoo/odoo.conf /tmpdir
cp -a $tmpdir/odoo.conf .
