#!/bin/bash

# Builds vector tile data for the site
# See tutorial at: https://github.com/ITSLeeds/VectorTiles
# See examples at: https://github.com/SDCA-tool/sdca-data-prep/blob/main/tippecanoe


# Can specify argument giving path to data repo; defaults as shown
dataRepo=${1:-/var/www/sdca/sdca-data/}
dataTarget=${2:-/var/www/sdca/data/}


# Stop on any error
set -e

# Start timer
start=`date +%s`

# Create same PATH as sdca user
source /etc/environment

# Do work in /tmp/
rm -rf /tmp/sdca-data-importing/
mkdir -p /tmp/sdca-data-importing/
cd /tmp/sdca-data-importing/
echo 'This folder is safe to delete. See sdca-website-deploy repo: build-data.sh .' > /tmp/sdca-data-importing/README.txt

# Specify output data folder
OUTPUT=$dataTarget

# Get the MySQL password, for use by ogr2ogr
sdcamysqlpassword=`cat /home/sdca/mysqlpassword`

# Loop through datasets; see: https://unix.stackexchange.com/a/622269/168900
# Data at: https://github.com/SDCA-tool/sdca-data/releases
csvtool namedcol id,zipfile,title,description,geometries_type,has_attributes,source,source_url,tippecanoeparams,show,database $dataRepo/datasets.csv \
 | csvtool -u '|' drop 1 - \
 | while IFS=$'|' read -r id zipfile title description geometries_type has_attributes source source_url tippecanoeparams show database; do
	
	echo -e "\n\nProcessing dataset ${id}:\n"
	
	# For now, skip GeoJSON files, pending support below
	if [[ "$zipfile" != *"geojson"* ]]; then
		echo "Skipping non-GeoJSON dataset ${id}"
		continue
	fi
	
	# Determine sets of zip files / tippecanoeparams (or one), by allocating to an array, and count the total; it is assumed that the counts are consistent
	IFS=';' read -ra zipfileList <<< "$zipfile"
	IFS=';' read -ra tippecanoeparamsList <<< "$tippecanoeparams"
	total=${#zipfileList[@]}
	hasMultiple=$(( $total > 1 ))
	
	# Loop through each, which may be 1
	for (( i=0; i<$total; i++ )); do
		zipfile=${zipfileList[$i]}
		tippecanoeparams=${tippecanoeparamsList[$i]}
		
		# Determine directory suffix, if any
		if [ "$hasMultiple" = 1 ]; then suffix="_${i}"; else suffix=""; fi
		
		# Download - public repo
		wget "https://github.com/SDCA-tool/sdca-data/releases/download/map_data/${zipfile}"
		
		# Unzip
		unzip $zipfile
		rm $zipfile
		
		# Determine filename of unzipped file, e.g. foo.geojson.zip -> foo.geojson
		file=$(basename "${zipfile}" .zip)
		
		# Skip vector tile creation for layers not to be shown
		if [[ "$show" == 'FALSE' ]]; then
			echo "Skipping vector tile creation of dataset ${id} as not shown"
			
		# Process data to vector tiles, using default parameters for Tippecanoe if not specified
		else
			if [ -z "$tippecanoeparams" ]; then
				tippecanoeparams="--name=${id} --layer=${id} --attribution='${source}' --maximum-zoom=13 --minimum-zoom=0 --drop-smallest-as-needed --simplification=10 --detect-shared-borders";
			fi
			eval "tippecanoe --output-to-directory=${id}${suffix} ${tippecanoeparams} --force ${file}"
		fi
		
		# Skip database import for layers not needing this
		if [[ "$database" == 'FALSE' ]]; then
			echo "Skipping database import of dataset ${id} as not needed"
			
		# Process data to the database; see options at: https://gdal.org/drivers/vector/mysql.html
		# To minimise unavailability, the data is loaded into a table suffixed with _import, and then when complete, shifted into place
		else
			ogr2ogr -f MySQL "MySQL:sdca,user=sdca,password=${sdcamysqlpassword}" ${file} -nln "${id}_import" -t_srs EPSG:4326 -update -overwrite -lco FID=id -lco GEOMETRY_NAME=geometry -progress
			mysql -u sdca -p"${sdcamysqlpassword}" -e "DROP TABLE IF EXISTS \`$id\`;" sdca
			mysql -u sdca -p"${sdcamysqlpassword}" -e "RENAME TABLE \`${id}_import\` TO \`$id\`;" sdca
		fi
		
		# Remove the downloaded GeoJSON file
		rm "${file}"
	done
	
	# Move vector tiles files into place
	if [[ "$show" != 'FALSE' ]]; then
		
		# If multiple parts, first combine suffixed folders to un-suffixed main folder
		if [ "$hasMultiple" = 1 ]; then
			mkdir "${id}"
			for (( i=0; i<$total; i++ )); do
				suffix="_${i}";
				mv "${id}${suffix}/"* "${id}"
				rmdir "${id}${suffix}/"
			done
		fi
		
		# Remove existing live directory if present from a previous run; this is done just before the move to minimise public unavailability
		rm -rf "${OUTPUT}/${id}/"
		
		# Move file into place
		mv $id "${OUTPUT}/"
	fi
done

# Add dataset metadata as JSON file for website
csvToJson () { python -c 'import csv, json, sys; print(json.dumps([dict(r) for r in csv.DictReader(sys.stdin)], indent="\t"))'; }
cat $dataRepo/datasets.csv | csvToJson | cat > /var/www/sdca/sdca-website/datasets.json

# Add field definitions from each file as a (single) JSON file for website
for file in $dataRepo/data_dictionary/*.csv; do
    cat $file | csvToJson | cat > "${file%.csv}.json"
done
jq -n '[inputs | {(input_filename | gsub(".*/|\\.json$";"")): .} ] | add' $dataRepo/data_dictionary/*.json | cat > /var/www/sdca/sdca-website/fields.json
rm $dataRepo/data_dictionary/*.json

# Add style definitions from each file as a (single) JSON file for website, stripping any comment keys ("_comment": "...")
jq -n '[inputs | {(input_filename | gsub(".*/|\\.json$";"")): .} ] | del(.. | ._comment?) | add' $dataRepo/styles/*.json | cat > /var/www/sdca/sdca-website/styles.json

# Confirm success
echo "Successfully completed."

# End timer and report time
end=`date +%s`
seconds=$((end - start))
echo "Elapsed: $(($seconds / 3600))hrs $((($seconds / 60) % 60))min $(($seconds % 60))sec"
