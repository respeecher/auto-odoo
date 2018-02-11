#!/bin/bash

. variables
sed s/DOMAIN/$domain/g < nginx.template.conf > nginx-conf/nginx.conf
