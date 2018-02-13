#!/bin/bash

. variables
mkdir -p nginx-conf
sed s/DOMAIN/$domain/g < nginx.template.conf > nginx-conf/nginx.conf
