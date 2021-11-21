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

# Get the script directory see: https://stackoverflow.com/a/11114547/180733
DIR=$(dirname $(realpath -s $0))

# Update packages index
apt-get update

# Webserver
apt-get -y install apache2
a2enmod rewrite
a2enmod headers

# PHP
apt-get -y install php php-cli php-mbstring
apt-get -y install libapache2-mod-php
service apache2 restart

# MySQL
apt-get -y install mysql-server

# Tippecanoe, for tile generation; see: https://github.com/mapbox/tippecanoe
apt-get -y install build-essential libsqlite3-dev zlib1g-dev
if ! which tippecanoe >/dev/null; then
	echo 'Installing tippecanoe'
	cd /tmp/
	git clone https://github.com/mapbox/tippecanoe.git
	cd tippecanoe
	make -j
	make install
	rm -rf /tmp/tippecanoe/
	cd "${DIR}/"
fi

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

# Site main directory, into which repos will go
mkdir -p /var/www/sdca/
chown sdca.rollout /var/www/sdca/ && chmod g+ws /var/www/sdca/

# Add main site repo
if [ ! -d /var/www/sdca/sdca-website/ ]; then
	cd /var/www/sdca/
	git clone https://github.com/SDCA-tool/sdca-website.git
	chown -R sdca.rollout /var/www/sdca/sdca-website/ && chmod -R g+ws /var/www/sdca/sdca-website/
fi

# Add data repo
if [ ! -d /var/www/sdca/sdca-data/ ]; then
	cd /var/www/sdca/
	git clone https://github.com/SDCA-tool/sdca-data.git
	chown -R sdca.rollout /var/www/sdca/sdca-data/ && chmod -R g+ws /var/www/sdca/sdca-data/
fi

# Add library repo
if [ ! -d /var/www/sdca/Mapboxgljs.LayerViewer/ ]; then
	cd /var/www/sdca/
	git clone https://github.com/cyclestreets/Mapboxgljs.LayerViewer.git
	chown -R sdca.rollout /var/www/sdca/Mapboxgljs.LayerViewer/ && chmod -R g+ws /var/www/sdca/Mapboxgljs.LayerViewer/
fi

# Keep the repos updated
cp /var/www/sdca/sdca-website-deploy/sdca.cron /etc/cron.d/sdca
chown root.root /etc/cron.d/sdca && chmod 0600 /etc/cron.d/sdca

# Add data directory
mkdir -p /var/www/sdca/data/
chown -R sdca.rollout /var/www/sdca/data/ && chmod -R g+ws /var/www/sdca/data/

# VirtualHost
cp "${DIR}/apache-sdca.conf" /etc/apache2/sites-available/sdca.conf
a2ensite sdca.conf
service apache2 restart

# Build data
su - sdca "${DIR}/build-data.sh"

