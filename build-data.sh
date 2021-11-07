#!/bin/sh

# Builds data for the site


# Do work in /tmp/
cd /tmp/

# Specify output data folder
OUTPUT=/var/www/sdca/data/

# Bus stops
wget https://github.com/creds2/CarbonCalculator/releases/download/1.0/PBCC_transit_stop_frequency_2020.zip
unzip PBCC_transit_stop_frequency_2020.zip
rm PBCC_transit_stop_frequency_2020.zip
tippecanoe --output-to-directory=transitstops --name=transitstops --layer=transitstops --attribution=MALCOLMMORGAN --maximum-zoom=13 --minimum-zoom=4  --drop-densest-as-needed -rg4 --force  transit_stop_frequency_v3.geojson
rm transit_stop_frequency_v3.geojson
rm -rf "${OUTPUT}/transitstops/"
mv transitstops "${OUTPUT}/"
