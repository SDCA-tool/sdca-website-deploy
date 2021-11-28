#!/bin/bash

# Builds vector tile data for the site
# See tutorial at: https://github.com/ITSLeeds/VectorTiles
# See examples at: https://github.com/SDCA-tool/sdca-data-prep/blob/main/tippecanoe


# Can specify argument giving path to data repo; defaults as shown
dataRepo=${1:-/var/www/sdca/sdca-data/}


# Stop on any error
set -e

# Get the list of datasets
datasets=`csvtool col 2 $dataRepo/datasets.csv`

# Do work in /tmp/
rm -rf /tmp/sdca/
mkdir -p /tmp/sdca/
cd /tmp/sdca/

# Specify output data folder
OUTPUT=/var/www/sdca/data/

# Loop through datasets; see: https://unix.stackexchange.com/a/622269/168900
# Data at: https://github.com/SDCA-tool/sdca-data/releases
csvtool namedcol id,zipfile,title,description,has_attributes,source,source_url,tippecanoeparams $dataRepo/datasets.csv \
 | csvtool -u '|' drop 1 - \
 | while IFS=$'|' read -r id zipfile title description has_attributes source source_url tippecanoeparams; do
	
	echo -e "\n\nProcessing dataset ${id}:\n"

	# # Download - public repo
	# wget "https://github.com/SDCA-tool/sdca-data/releases/download/map_data/${zipfile}"
	
	# Download - private repo, which requires use of the Github API; see: https://stackoverflow.com/a/51427434/180733 and https://stackoverflow.com/a/60061148/180733
	# Requires environment variable, e.g. export GITHUB_CREDENTIALS=username:tokenstring
	CURL="curl -u $GITHUB_CREDENTIALS https://api.github.com/repos/SDCA-tool/sdca-data/releases"
	ASSET_ID=$(eval "$CURL/latest" | jq -r '.assets[] | select(.name=="'$zipfile'").id')
	eval "$CURL/assets/$ASSET_ID -LJOH 'Accept: application/octet-stream'"
	
	# Unzip
	unzip $zipfile
	rm $zipfile
	
	# Process data
	if [ -n "$tippecanoeparams" ]; then
		tippecanoe --output-to-directory=$id $tippecanoeparams --force $id.geojson
		rm -rf "${OUTPUT}/${id}/"		# Remove existing directory if present from a previous run; this is done just before the move to minimise public unavailability
		mv $id "${OUTPUT}/"
		rm $id.geojson
	fi
	
done

# Add dataset metadata as JSON file for website
cat $dataRepo/datasets.csv | python -c 'import csv, json, sys; print(json.dumps([dict(r) for r in csv.DictReader(sys.stdin)], indent="\t"))' | cat > /var/www/sdca/sdca-website/datasets.json
