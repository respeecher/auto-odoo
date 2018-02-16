#!/bin/bash

set -feuo pipefail
IFS=

cd $(dirname $0)

if [[ $# != 1 ]]; then
    echo "Usage: $0 backup-path"
    echo "backup-path should be something like odoodocker-2018-02-13-10-17-05.txz"
    exit 1
fi

if [[ $EUID != 0 ]]; then
    echo "Must run as root"
    exit 1
fi

if [[ -d backup ]]; then
    echo "Please remove existing `backup` directory before running restore."
    exit 1
fi

echo
echo "About to restore.  Restoring will PERMANENTLY ERASE the existing Odoo data volumes, so be sure that you have"
echo "a backup before you do this!"
echo
echo "Also be sure that Auto Odoo is NOT RUNNING."
echo
echo "To continue, type 'understood'."
echo

read
if [[ $REPLY != understood ]]; then
    echo "aborting"
    exit 1
fi

set -x
tar --numeric-owner -xJf $1

volume_prefix=$(basename $(pwd) | sed s/-//g)

docker volume rm ${volume_prefix}_odoo-db-data || /bin/true
docker volume create ${volume_prefix}_odoo-db-data
docker volume rm ${volume_prefix}_odoo-web-data || /bin/true
docker volume create ${volume_prefix}_odoo-web-data

docker run -v $(pwd)/backup/odoo-db-data:/source:ro -v ${volume_prefix}_odoo-db-data:/target ubuntu cp -a /source/. /target
docker run -v $(pwd)/backup/odoo-web-data:/source:ro -v ${volume_prefix}_odoo-web-data:/target ubuntu cp -a /source/. /target
cp -a backup/odoo.conf .
cp -a backup/.env .

rm -rf backup

echo "Restore complete.  You may now restart Auto Odoo."
