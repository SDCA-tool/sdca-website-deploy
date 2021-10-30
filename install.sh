#!/bin/sh

# Installs the system


# Update packages index
sudo apt-get update

# Webserver
sudo apt-get -y install apache2


# Patch system
sudo apt-get -y upgrade
sudo apt-get -y dist-upgrade
sudo apt-get -y autoremove
