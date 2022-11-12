#!/bin/bash

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

# Enable unattended upgrades; see: https://wiki.debian.org/UnattendedUpgrades
apt-get install -y unattended-upgrades apt-listchanges
printf "\nUnattended-Upgrade::Mail \"root\";\n" >> /etc/apt/apt.conf.d/50unattended-upgrades
echo unattended-upgrades unattended-upgrades/enable_auto_updates boolean true | debconf-set-selections
dpkg-reconfigure -f noninteractive unattended-upgrades

# Exim mail; see: https://ubuntu.com/server/docs/mail-exim4 and https://manpages.ubuntu.com/manpages/jammy/en/man8/update-exim4.conf.8.html
apt-get -y install exim4
if [ ! -e /etc/exim4/update-exim4.conf.conf.original ]; then
	cp -pr /etc/exim4/update-exim4.conf.conf /etc/exim4/update-exim4.conf.conf.original
	sed -i "s/dc_eximconfig_configtype=.*/dc_eximconfig_configtype='internet'/" /etc/exim4/update-exim4.conf.conf
	sed -i "s/dc_local_interfaces=.*/dc_local_interfaces=''/" /etc/exim4/update-exim4.conf.conf
	update-exim4.conf
	service exim4 restart
fi

# Set e-mail for notifications below; this is split her to avoid bot scraping
email='webmaster''@''carbon.place'

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

# MySQL; configuration is done later below
apt-get install -y mysql-server mysql-client
apt-get install -y php-mysql

# PostgreSQL & PostGIS packages; configuration is done later below
apt-get install -y gnupg2
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
echo "deb https://apt.postgresql.org/pub/repos/apt/ `lsb_release -cs`-pgdg main" | tee /etc/apt/sources.list.d/pgdg.list
apt-get update
apt-get install -y postgresql-14 postgis postgresql-14-postgis-3		# NB If updating version, change pg_hba.conf path below also
apt-get install -y php-pgsql

# Node - later version than v. 8.10.0 which is supplied with Ubuntu 18.04
apt-get install -y curl
curl -sL https://deb.nodesource.com/setup_16.x | bash -
apt-get install -y nodejs

# Yarn, for JS package management; see: https://www.howtoforge.com/how-to-install-yarn-npm-package-manager-on-ubuntu-20-04/
curl -sL https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list
apt-get update
apt-get install -y yarn

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
	git config --global --add safe.directory /var/www/sdca/sdca-website/
	chown -R sdca.rollout /var/www/sdca/sdca-website/ && chmod -R g+ws /var/www/sdca/sdca-website/
fi

# Add data repo
if [ ! -d /var/www/sdca/sdca-data/ ]; then
	cd /var/www/sdca/
	git clone https://github.com/SDCA-tool/sdca-data.git
	git config --global --add safe.directory /var/www/sdca/sdca-data/
	chown -R sdca.rollout /var/www/sdca/sdca-data/ && chmod -R g+ws /var/www/sdca/sdca-data/
fi

# Add package repo
if [ ! -d /var/www/sdca/sdca-package/ ]; then
	cd /var/www/sdca/
	git clone https://github.com/SDCA-tool/sdca-package.git
	git config --global --add safe.directory /var/www/sdca/sdca-package/
	chown -R sdca.rollout /var/www/sdca/sdca-package/ && chmod -R g+ws /var/www/sdca/sdca-package/
fi

# Install website dependencies
cd /var/www/sdca/sdca-website/
yarn install

# Copy in the Javascript config file
cp "${DIR}/.config.js" /var/www/sdca/sdca-website/

# Keep the repos updated
cp /var/www/sdca/sdca-website-deploy/sdca.cron /etc/cron.d/sdca
chown root.root /etc/cron.d/sdca && chmod 0600 /etc/cron.d/sdca

# Add data directory
mkdir -p /var/www/sdca/data/
chown -R sdca.rollout /var/www/sdca/data/ && chmod -R g+ws /var/www/sdca/data/

# Create .htpassword file for site protection
sitepassword=`date +%s | sha256sum | base64 | head -c 32`
htpasswd -b -B -c /etc/apache2/sites-enabled/sdca.htpasswd sdca $sitepassword
mail -s 'SDCA Carbon Tool website login' $email <<< "Initial site password is as follows - please log in to change it in .htaccess: $sitepassword"

# VirtualHosts - enable HTTP site
cp "${DIR}/apache-sdca.conf" /etc/apache2/sites-available/sdca.conf
a2ensite sdca.conf
service apache2 restart

# VirtualHosts - attempt to add SSL cert and enable HTTPS site
# This section will naturally fail if DNS is not pointed to machine (hence use of set +e temporarily), and will need to be run subsequently
cp "${DIR}/apache-sdca_ssl.conf" /etc/apache2/sites-available/sdca_ssl.conf
set +e
certbot --agree-tos --no-eff-email certonly --keep-until-expiring --webroot -w /var/www/sdca/sdca-website/ --email $email -d dev.carbon.place
if [ $? -eq 0 ]; then
	a2ensite sdca_ssl.conf
	service apache2 restart
fi
set -e

# Add packages for helping download and process datasets
# CSV support for use in scripts; see: https://colin.maudry.fr/csvtool-manual-page/ and install instructions for Ubuntu/MacOS at https://thinkinginsoftware.blogspot.com/2018/03/parsing-csv-from-bash.html
apt-get install -y csvtool
apt-get install -y curl
apt-get install -y jq
apt-get install -y zip
apt-get install -y python3 python-is-python3

# Configure MySQL Database and create database and user
if [ ! -f /root/mysqlpassword ]; then
	
	# Create root password
	rootmysqlpassword=`date +%s | sha256sum | base64 | head -c 32`A_!
	echo "${rootmysqlpassword}" > /root/mysqlpassword
	chmod 400 /root/mysqlpassword
	mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${rootmysqlpassword}';"
	
	# Secure the installation
	mysql_secure_installation -u root --password="${rootmysqlpassword}" --use-default
	
	# Disable MySQL password expiry system; see: https://stackoverflow.com/a/41552022
	mysql -u root -p"${rootmysqlpassword}" -e "SET GLOBAL default_password_lifetime = 0;"
	
	# Create database
	mysql -u root -p"${rootmysqlpassword}" -e "CREATE DATABASE IF NOT EXISTS sdca;"
	
	# Create runtime user
	sdcamysqlpassword=`date +%s | sha256sum | base64 | head -c 32`A_!
	echo "${sdcamysqlpassword}" > /home/sdca/mysqlpassword
	chown sdca.sdca /home/sdca/mysqlpassword
	chmod 440 /home/sdca/mysqlpassword		# Has to be group-readable by sdca group, which includes www-data
	mysql -u root -p"${rootmysqlpassword}" -e "CREATE USER IF NOT EXISTS sdca@localhost IDENTIFIED WITH mysql_native_password BY '${sdcamysqlpassword}';"
	mysql -u root -p"${rootmysqlpassword}" -e "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, DROP ON sdca.* TO sdca@localhost;"
fi

# Install PostgreSQL database and user
# Check connectivity using the following; -h localhost is needed to avoid "Peer authentication failed" error
# PGPASSWORD=`sudo less /home/sdca/postgresqlpassword` psql -h localhost -d sdca -U sdca
database=sdca
username=sdca
passwordfile="/home/${username}/postgresqlpassword"
databaseExists=`sudo -u postgres psql -tAc "SELECT 1 from pg_catalog.pg_database where datname = '${database}';"`
if [ "$databaseExists" != "1" ]; then
	
	# Create password
	runtimepostgresqlpassword=`date +%s | sha256sum | base64 | head -c 32`
	echo "${runtimepostgresqlpassword}" > $passwordfile
	chown $username.$username $passwordfile
	chmod 440 $passwordfile		# Has to be group-readable by the group, which includes www-data
	
	# Create runtime user
	sudo -u postgres psql -c "CREATE USER ${username} WITH PASSWORD '${runtimepostgresqlpassword}';"
	
	# Create database
	sudo -u postgres createdb -O $username $database
	
	# Privileges should not be needed: "By default all public schemas will be available for regular (non-superuser) users." - https://stackoverflow.com/a/42748915/180733
	# See also note that privileges (if relevant) should be on the table, not the database: https://stackoverflow.com/a/15522548/180733
	#sudo -u postgres psql -tAc "GRANT ALL PRIVILEGES ON DATABASE ${database} TO ${username};"
	
	# Add PostGIS to this database
	sudo -u postgres psql -d $database -c "CREATE EXTENSION postgis;"
	
	# Can now connect using the -h localhost option; see: https://stackoverflow.com/a/28783632/180733
	
	# # Enable postgres connectivity, adding to the start of the file, with IPv4 and IPv6 rules
	# if ! grep -q $username /etc/postgresql/14/main/pg_hba.conf; then
	# 	sed -i "1 i\host  $database  $username  ::1/128       trust" /etc/postgresql/14/main/pg_hba.conf	# IPv6 rule, will end up as second line
	# 	sed -i "1 i\host  $database  $username  127.0.0.1/32  trust" /etc/postgresql/14/main/pg_hba.conf	# IPv4 rule, will end up as first line
	# fi
	# sudo service postgresql restart
fi

# Include webserver in sdca group so it can access the database password
sudo usermod -a -G sdca www-data
service apache2 restart

# CSV support for putting into database; see: https://stackoverflow.com/a/23532171/180733 and https://stackoverflow.com/a/23978968/180733
# This is installed via pip, as the Ubuntu version is too old, with a critical bug fixed in 1.0.3
apt-get install -y python3-pip
apt-get install -y libmysqlclient-dev
pip install mysqlclient
apt-get install -y libpq-dev
pip install psycopg2
pip install "csvkit>=1.0.6"

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

# Add locate
apt-get install -y locate
updatedb

# Munin Node, which should be installed after all other software; see: https://www.digitalocean.com/community/tutorials/how-to-install-the-munin-monitoring-tool-on-ubuntu-14-04
# Include dependencies for Munin MySQL plugins; see: https://raymii.org/s/snippets/Munin-Fix-MySQL-Plugin-on-Ubuntu-12.04.html
# Add libdbi-perl as otherwise /usr/share/munin/plugins/mysql_ suggest will show missing DBI.pm; see: https://stackoverflow.com/questions/20568836/cant-locate-dbi-pm and https://github.com/munin-monitoring/munin/issues/713
apt-get install -y libcache-perl libcache-cache-perl
apt-get install -y libdbi-perl libdbd-mysql-perl
# PostgreSQL dependency
apt-get install -y libdbd-pg-perl
apt-get install -y munin-node
apt-get install -y munin-plugins-extra
munin-node-configure --suggest --shell | sh
service munin-node restart

#!# NB Currently no means to write the .config.js file automatically, as that contains secrets

# Build data
su - sdca "${DIR}/build-data.sh"
