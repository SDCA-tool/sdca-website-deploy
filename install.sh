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

# VirtualHost
mkdir -p /var/www/sdca/
cp apache-sdca.conf /etc/apache2/sites-available/sdca.conf
a2ensite sdca.conf
service apache2 restart


# Munin Node, which should be installed after all other software; see: https://www.digitalocean.com/community/tutorials/how-to-install-the-munin-monitoring-tool-on-ubuntu-14-04
# Include dependencies for Munin MySQL plugins; see: https://raymii.org/s/snippets/Munin-Fix-MySQL-Plugin-on-Ubuntu-12.04.html
apt-get install -y libcache-perl libcache-cache-perl
# Add libdbi-perl as otherwise /usr/share/munin/plugins/mysql_ suggest will show missing DBI.pm; see: http://stackoverflow.com/questions/20568836/cant-locate-dbi-pm and https://github.com/munin-monitoring/munin/issues/713
apt-get install -y libdbi-perl libdbd-mysql-perl
apt-get install -y munin-node
apt-get install -y munin-plugins-extra
munin-node-configure --suggest --shell | sh
service munin-node restart

# Add firewall
# https://help.ubuntu.com/community/UFW
# Check status using: sudo ufw status verbose
apt-get -y install ufw
ufw logging low
ufw --force reset
ufw --force enable
ufw default deny
ufw allow ssh
ufw allow http
ufw allow https
ufw reload
ufw status verbose

# Patch system
apt-get -y upgrade
apt-get -y dist-upgrade
apt-get -y autoremove
