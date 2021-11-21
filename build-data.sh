#!/bin/sh

# Builds vector tile data for the site
# See tutorial at: https://github.com/ITSLeeds/VectorTiles
# See examples at: https://github.com/creds2/CarbonCalculator/blob/master/tippercanoe


# Can specify argument giving path to data repo; defaults as shown
dataRepo=${1:-/var/www/sdca/sdca-data/}


# Do work in /tmp/
cd /tmp/

# Specify output data folder
OUTPUT=/var/www/sdca/data/

# Public transport stops
wget https://github.com/creds2/CarbonCalculator/releases/download/1.0/PBCC_transit_stop_frequency_2020.zip
unzip PBCC_transit_stop_frequency_2020.zip
rm PBCC_transit_stop_frequency_2020.zip
tippecanoe --output-to-directory=publictransport --name=publictransport --layer=publictransport --attribution=MALCOLMMORGAN --maximum-zoom=13 --minimum-zoom=4 --drop-densest-as-needed -rg4 --force  transit_stop_frequency_v3.geojson
rm transit_stop_frequency_v3.geojson
rm -rf "${OUTPUT}/publictransport/"
mv publictransport "${OUTPUT}/"
