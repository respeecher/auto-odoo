#!/bin/bash

set -feuxo pipefail
IFS=

. .env

tmpdir=$(mktemp -d)
docker run --rm --user $(id -u) -v $tmpdir:/tmpdir $odoo_image cp -a /etc/odoo/odoo.conf /tmpdir
cp -a $tmpdir/odoo.conf .
