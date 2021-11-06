#!/bin/sh

# Installs the system software
# Written for Ubuntu Server 20.04 LTS
# This script is idempotent - it can be safely re-run without destroying existing data


# Ensure this script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "# This script must be run as root." 1>&2
    exit 1
fi


# Update packages index
apt-get update

# Webserver
apt-get -y install apache2




# Patch system
apt-get -y upgrade
apt-get -y dist-upgrade
apt-get -y autoremove
