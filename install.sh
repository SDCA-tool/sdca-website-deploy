#!/bin/sh

# Installs the system software
# Written for Ubuntu Server 20.04 LTS
# This script is idempotent - it can be safely re-run without destroying existing data


# Ensure this script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "# This script must be run as root." 1>&2
    exit 1
fi

# Bomb out if something goes wrong
set -e


# Update packages index
apt-get update

# Webserver
apt-get -y install apache2

# PHP
apt-get -y install php
service apache2 restart

# MySQL
apt-get -y install mysql-server



# Patch system
apt-get -y upgrade
apt-get -y dist-upgrade
apt-get -y autoremove
