# SDCA deployment

This repo deploys the SDCA Carbon Tool demonstrator website.

It uses cloud-init.


## Installation

A complete installation can be created on a fully-automated basis, using this repo.

A [cloud-init](https://cloud-init.io/) file at `cloud-config.yaml` is used to boostrap the application. Cloud-init is supported on most cloud hosting platforms. It provides a set of initial instructions that will be run during initial creation of the VM.

The `cloud-config.yaml` file in summary (1) creates a set of users (you can add your own), (2) clones this repo as a whole, and (3) runs the `install.sh` bash script, which installs the software. All this takes place non-interactively.

To create a VM using Multipass, with name sdca, run:

```
multipass launch -n sdca --cloud-init cloud-config.yaml 20.04
```

To create a VM on Google Cloud, run:

```
gcloud compute instances create sdca \
	--zone=europe-west2-a \
	--machine-type=n1-standard-2 \
	--image-project=ubuntu-os-cloud \
	--image-family=ubuntu-2004-lts \
	--metadata-from-file user-data=cloud-config.yaml
```

A similar command can be run for any other cloud provider (e.g. Microsoft Azure, AWS, Mythic Beasts) that supports the cloud-init standard.

Initial software setup takes up to half an hour, and building the data for the first time may take 4 hours or so.

A diagram of the site architecture is below.


## Installation script - install.sh bash script

The cloud-init installer launches the install script. (However, the install script can be run manually also if desired.)

The `install.sh` script is a bash script that does most of the installation. At present this is written in bash, but future work could migrate this to Ansible/Chef/etc.

It is written to be idempotent, i.e. can be re-run safely.

It:

 * Installs Apache and PHP
 * Installs the database (PostgreSQL) and PostGIS
 * Installs Tippecanoe, which is used to convert GeoJSON data to Vector Tiles
 * Adds a firewall
 * Clones from Github various repositories:
   * The [website repository](https://github.com/SDCA-tool/sdca-website/), which contains the website code
   * A javascript dependency
   * The [data repo](https://github.com/SDCA-tool/sdca-data/), which defines the source data and other definitions
   * The [R package repo](https://github.com/SDCA-tool/sdca-package/), which contains the analysis processing, though the R package is actually installed directly so this is not strictly needed
 * Adds cron jobs to keep all the repositories updated
 * Makes a VirtualHost for the site within Apache, including an HTTPS certificate
 * Installs some tools for processing CSV files
 * Installs GDAL/OGR
 * Installs R
 * Installs the R package (see above)
 * Adds Munin for monitoring
 * Then does an initial build of the data, using the `build-data.sh` script (which is later run automatically - see below)

This results in a working site, and sets up automatic updating of the data each night.


## Data building script - build-data.sh bash script

The `build-data.sh` script builds/re-builds the data from the data package each night.

It is launched each night, using a cron job that was installed in the main deployment script.

The [data repo](https://github.com/SDCA-tool/sdca-data/) is refreshed nightly by cron, so the script will then be building against the latest data automatically.

The script's output results in a `/data/` folder aliased to `/data/` in the webspace, so that the website will see it.

The script:

 * Creates a folder where data is built
 * Takes the [list of datasets](https://github.com/SDCA-tool/sdca-data/blob/main/datasets.csv), and, for each dataset:
   * Downloads the data from the Github 'releases' area of the data repository
   * Unzips the file, which will contain GeoJSON normally
   * Makes a Vector Tiles version of the dataset (if show=TRUE), and moves the generated folder into place
   * Copies the data to the database (if database=TRUE)
   * If the file is instead a TIF file, this is moved into place
 * A variety of files in the data repository are copied to `/lexicon/` in the webspace, and where they are CSV they are converted to JSON:
  * The list of datasets, `/datasets.csv`, becomes `/lexicon/datasets.json` in the webspace, which the website can then pick up to generate the layers UI
  * The lists of fields, `/data_dictionary/*.csv`, become combined to `/lexicon/data_dictionary/fields.json` in the webspace, which the website can then pick up for labellings around the site, e.g. popups
  * The styles for a layer, `/styles/*.csv`, are combined to form `/lexicon/styles/styles.json`, which the website uses for styling layers
  * Other folders like `/data_tables/*.csv` become e.g. `/lexicon/data_tables/*.json` in the webspace, again used by the website UI
 * CSV data_tables files are copied into the database, which the SQL queries then use

Note that if the data file to be downloaded from Github is detected as being the same size as previously, this is assumed to be unchanged, and that dataset is skipped. This is done by checking the size using a HEAD request first.

To avoid any downtime, each dataset is processed one-by-one, and when moving the generated data into place (whether vector, database, or TIF). The data is finalised as a new copy with a different name, and then a quick shifting operation moves the old version out and the new one in. This is necessary because some datasets are very large and could take perhaps an hour to process.


## Maintenance

The site should not require any maintenance, other than to patch the Linux packages from time to time.

It is advisible to patch at least monthly, and whenever a major security issue (for the Linux kernel, Apache, PHP, PostgreSQL or R) is issued.

Log in to a server instance is by SSH key as per the cloud-init user definitions.

Patching an Ubuntu machine is done using:

`sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get -y dist-upgrade && sudo apt-get -y autoremove`

If a kernel update is included, this should be caught with a restart:

`sudo shutdown -r now`

In the future, new versions of PostGIS may be released. If it is desired to upgrade to a later full version, careful attention should be given to the release notes. In some cases this may mean exporting and re-importing the data, though this is probably best done by just running the build script to generate the data freshly.

The system will not send out any e-mails routinely.


## Security

The server should remain secure as long as it is kept patched regularly.

The site is entirely read-only, as there is no user-submitted data. Uploading of GeoJSON schemes is done purely client-side and does not result in any data written to the server. Accordingly, routes for denial of service attacks are very limited.


## Site architecture diagram

![Site architecture diagram](/architecture.png)
