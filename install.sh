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

# Update packages
apt-get update
apt-get -y upgrade
apt-get -y dist-upgrade
apt-get -y autoremove

# Webserver
apt-get install -y apache2
a2enmod ssl
a2enmod rewrite
a2enmod headers
apt-get install -y certbot

# PHP
apt-get install -y php php-cli php-mbstring
apt-get install -y libapache2-mod-php
service apache2 restart

# MySQL
apt-get install -y mysql-server
apt-get install -y php-mysql

# Tippecanoe, for tile generation; see: https://github.com/mapbox/tippecanoe
apt-get install -y build-essential libsqlite3-dev zlib1g-dev
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
apt-get install -y ufw
ufw logging low
ufw --force reset
ufw --force enable
ufw default deny
ufw allow ssh
ufw allow http
ufw allow https
ufw reload
ufw status verbose

# Site main directory, into which repos will go
mkdir -p /var/www/sdca/
chown sdca.rollout /var/www/sdca/ && chmod g+ws /var/www/sdca/

# Add main site repo
if [ ! -d /var/www/sdca/sdca-website/ ]; then
	cd /var/www/sdca/
	git clone https://github.com/SDCA-tool/sdca-website.git
	chown -R sdca.rollout /var/www/sdca/sdca-website/ && chmod -R g+ws /var/www/sdca/sdca-website/
fi

# Add library repo
if [ ! -d /var/www/sdca/Mapboxgljs.LayerViewer/ ]; then
	cd /var/www/sdca/
	git clone https://github.com/cyclestreets/Mapboxgljs.LayerViewer.git
	chown -R sdca.rollout /var/www/sdca/Mapboxgljs.LayerViewer/ && chmod -R g+ws /var/www/sdca/Mapboxgljs.LayerViewer/
fi

# Add data repo
if [ ! -d /var/www/sdca/sdca-data/ ]; then
	cd /var/www/sdca/
	git clone https://github.com/SDCA-tool/sdca-data.git
	chown -R sdca.rollout /var/www/sdca/sdca-data/ && chmod -R g+ws /var/www/sdca/sdca-data/
fi

# Add package repo
if [ ! -d /var/www/sdca/sdca-package/ ]; then
	cd /var/www/sdca/
	git clone https://github.com/SDCA-tool/sdca-package.git
	chown -R sdca.rollout /var/www/sdca/sdca-package/ && chmod -R g+ws /var/www/sdca/sdca-package/
fi

# Keep the repos updated
cp /var/www/sdca/sdca-website-deploy/sdca.cron /etc/cron.d/sdca
chown root.root /etc/cron.d/sdca && chmod 0600 /etc/cron.d/sdca

# Add data directory
mkdir -p /var/www/sdca/data/
chown -R sdca.rollout /var/www/sdca/data/ && chmod -R g+ws /var/www/sdca/data/

# VirtualHosts - enable HTTP site, add SSL cert, enable HTTPS site
cp "${DIR}/apache-sdca.conf" /etc/apache2/sites-available/sdca.conf
cp "${DIR}/apache-sdca_ssl.conf" /etc/apache2/sites-available/sdca_ssl.conf
a2ensite sdca.conf
service apache2 restart
email='webmaster''@''carbon.place'		# Split in script to prevent bots
certbot --agree-tos --no-eff-email certonly --keep-until-expiring --webroot -w /var/www/sdca/sdca-website/ --email $email -d dev.carbon.place
a2ensite sdca_ssl.conf
service apache2 restart

# Add packages for helping download and process datasets
# CSV support for use in scripts; see: https://colin.maudry.fr/csvtool-manual-page/ and install instructions for Ubuntu/MacOS at https://thinkinginsoftware.blogspot.com/2018/03/parsing-csv-from-bash.html
apt-get install -y csvtool
apt-get install -y curl
apt-get install -y jq
apt-get install -y zip
apt-get install -y python3 python-is-python3

# CSV support for putting into MySQL; see: https://stackoverflow.com/a/23532171/180733 and https://stackoverflow.com/a/23978968/180733
# This is installed via pip, as the Ubuntu version is too old, with a critical bug fixed in 1.0.3
apt-get install -y python3-pip
pip install mysqlclient
pip install "csvkit>=1.0.6"

# Database
if ! command -v mysqlx &> /dev/null ; then
	
	# Install MySQL 8, non-interactively
	apt-get install -y mysql-server mysql-client
	
	# Set the root user password
	mysqlpassword=`date +%s | sha256sum | base64 | head -c 32`
	echo "${rootmysqlpassword}" > /root/mysqlpassword
	chmod 400 /root/mysqlpassword
	mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${rootmysqlpassword}';"
	
	# Secure the installation
	mysql_secure_installation -u root --password="${rootmysqlpassword}" --use-default
	
	# Disable MySQL password expiry system; see: http://stackoverflow.com/a/41552022
	mysql -u root -p"${rootmysqlpassword}" -e "SET GLOBAL default_password_lifetime = 0;"
	
	# Amend MySQL password validation as passwords will already be complex
	mysql -u root -p"${rootmysqlpassword}" -e "SET GLOBAL validate_password.special_char_count = 0;"
	
	# Create database
	mysql -u root -p"${rootmysqlpassword}" -e "CREATE DATABASE IF NOT EXISTS sdca;"
	
	# Create runtime user
	sdcamysqlpassword=`date +%s | sha256sum | base64 | head -c 32`
	echo "${sdcamysqlpassword}" > /home/sdca/mysqlpassword
	chown sdca.sdca /home/sdca/mysqlpassword
	chmod 400 /home/sdca/mysqlpassword
	mysql -u root -p"${rootmysqlpassword}" -e "CREATE USER IF NOT EXISTS sdca@localhost IDENTIFIED WITH mysql_native_password BY '${sdcamysqlpassword}';"
	mysql -u root -p"${rootmysqlpassword}" -e "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, DROP ON sdca.* TO sdca@localhost;"
fi

# Install GDAL/OGR
add-apt-repository -y ppa:ubuntugis/ppa
apt-get update
apt-get install -y gdal-bin

# Install R
#!# Upgrade to R v. 4: https://linuxize.com/post/how-to-install-r-on-ubuntu-20-04/
apt-get install -y r-base
apt-get install -y r-base-dev build-essential

# Install R package; see: https://github.com/SDCA-tool/sdca-package
apt-get install -y libssl-dev libcurl4-openssl-dev libxml2-dev libudunits2-dev libgdal-dev
R -e 'if (!require("remotes")) install.packages("remotes");'
R -e 'if (!require("units")) install.packages("units");'
R -e 'if (!require("sf")) install.packages("sf");'
R -e 'if (!require("sdca-package")) remotes::install_github("SDCA-tool/sdca-package");'

# Enable webserver to access SDCA account MySQL password
sudo usermod -a -G sdca www-data
service apache2 restart
chmod g+r /home/sdca/mysqlpassword

# Exim; see: https://ubuntu.com/server/docs/mail-exim4 and https://manpages.ubuntu.com/manpages/jammy/en/man8/update-exim4.conf.8.html
apt-get -y install exim4
if [ ! -e /etc/exim4/update-exim4.conf.conf.original ]; then
	cp -pr /etc/exim4/update-exim4.conf.conf /etc/exim4/update-exim4.conf.conf.original
	sed -i "s/dc_eximconfig_configtype=.*/dc_eximconfig_configtype='internet'/" /etc/exim4/update-exim4.conf.conf
	sed -i "s/dc_local_interfaces=.*/dc_local_interfaces=''/" /etc/exim4/update-exim4.conf.conf
	update-exim4.conf
	service exim4 restart
fi

# Add locate
apt-get install -y locate
updatedb

# Build data
su - sdca "${DIR}/build-data.sh"
