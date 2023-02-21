#!/bin/sh
# file: enable-telegraf.sh
# This shell script is to install/enable telegraf service.
# It will check if telegraf service is already installed.
# If doesn't exist, then it downloads from internet.
# After that it's all about configuring the service.

# Variable for telegraf version
VERSION=1.25.0

SHA256=0e5eb54cd77180a5d61db4c6f580b94b3fae8f06dfecfe34e40f2d4f0f403fd6
TELEGRAF=telegraf-${VERSION}_linux_amd64.tar.gz
TELEGRAF_DL_PREFIX="https://dl.influxdata.com/telegraf/releases"

# Influx DB default details for output
INFLUX_DB="telegraf"
INFLUX_HOST="http://influxdb:8086"

# Usage for help
USAGE="Usage: $0 [-h] [-i] -m <MACHINE> [-p <PASSWORD>] [-s <HOST>] [-d <DB>]

Install Telegraf

Options:
    -h             Show this help message
    -i             Download the i386-architecture binary, instead of 64-bit
    -p <PASSWORD>  The Password to be used for authentication
    -m <MACHINE>   The UUID of the monitored machine
    -s <HOST>      The InfluxDB host to send data to. Defaults to $INFLUX_HOST
    -d <DB>        The database to write metrics to.  Defaults to $INFLUX_DB
"

# Exit on any failure
set -e

# Validate input and assign value
while getopts ":hip:m:s:p:d:" opt; do
    case "$opt" in
        h)
            echo "$USAGE"
            exit 0
            ;;
        i)
            SHA256=3434b2ede062e50495f4dc0e13ba81741b04a85487ee723e8ee996ff1ca9ab3c
            TELEGRAF=telegraf-${VERSION}_linux_i386.tar.gz
            ;;
        p)
            MACHINE_PASS=$OPTARG
            ;;
        m)
            MACHINE_UUID=$OPTARG
            ;;
        s)
            INFLUX_HOST=$OPTARG
            ;;
        d)
            INFLUX_DB=$OPTARG
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            echo "$USAGE" >&2
            exit 1
    esac
done

# exists: Function to know if given command is pressent or not.
exists() { command -v $1 > /dev/null 2>&1; }

# untar: Function to untar given file
untar() { echo >&2; echo "Extracting $1" >&2; tar -xvf $1; }

# fetch: Function to fetch given file(s). It uses wget/curl to download
# file. Fails if no command supported.
fetch() {
    if [ $# -eq 2 ]; then
        local dst="$2"
    fi
    if exists wget; then
        [ -n "$dst" ] && local cmd="wget -O $dst" || local cmd="wget"
    elif exists curl; then
        [ -n "$dst" ] && local cmd="curl -sSL -o $dst" || local cmd="curl -O -ssL"
    else
        echo >&2
        echo "Failed to locate wget/cURL" >&2
        echo "Unable to download $1" >&2
        echo >&2
        return 1
    fi
    echo >&2
    echo "Fetching $1" >&2
    echo >&2
    $cmd $1
}

# checksum: Function to calculate and validate checksums of
# given file(s) to ensure integrity of file. We use SHA256 here.
checksum() {
    echo >&2
    echo "Verifying SHA256 sum of $1" >&2
    sum=$( sha256sum $1 | awk '{ print $1 }' )
    if [ "$sum" != "$SHA256" ]; then
        echo "SHA256 mismatch!" >&2
        echo >&2
        return 1
    fi
}

# Validate HOST input
if ! echo "$INFLUX_HOST" | grep -q -i -E '^https?://[a-z0-9.-]+(:[1-9][0-9]*)?(/.+)?$'; then
    echo >&2
    echo >&2
    echo "Invalid destination endpoint: $INFLUX_HOST" >&2
    echo >&2
    echo >&2
    echo "$USAGE" >&2
    exit 1
fi

# Validate and ensure Machine ID is not empty
if [ -z "$MACHINE_UUID" ]; then
    echo >&2
    echo >&2
    echo "Required argument missing" >&2
    echo >&2
    echo >&2
    echo "$USAGE" >&2
    exit 1
fi

# Work directory and environment variable file
WORKDIR=/opt/mistio/
TELEGRAF_DIR=/opt/mistio/telegraf/usr/bin/
ENVFILE=/opt/mistio/mist-telegraf/service/mist-telegraf-env

# Create work directory if doesn't exist
echo >&2
echo "Setting up working directory at $WORKDIR" >&2
if [ ! -d $WORKDIR ]; then
    mkdir -p $WORKDIR
fi
# Change to directory and remove anything regarding telegraf
cd $WORKDIR && rm -rf *telegraf*

echo >&2
echo "Setting up Telegraf" >&2
echo "Monitoring data will be sent to $INFLUX_HOST" >&2
echo "Monitoring data will be written to database: $INFLUX_DB" >&2

if exists telegraf; then
    if [ ! -d $TELEGRAF_DIR ]; then
        mkdir -p $TELEGRAF_DIR
    fi
    ln -sf `which telegraf` $TELEGRAF_DIR
else
    # Download Telegraf binary.
    fetch $TELEGRAF_DL_PREFIX/$TELEGRAF telegraf.tar.gz
    checksum telegraf.tar.gz
    untar telegraf.tar.gz

    mv $( ls | grep -e ^telegraf-.*$ ) telegraf
fi

# Download Telegraf and system config files.
# TODO: Update reference to access from PORTAL_URI
fetch https://gitlab.ops.mist.io/mistio/mist-telegraf/-/archive/master/mist-telegraf-master.tar.gz mist-telegraf.tar.gz
untar mist-telegraf.tar.gz

# Move original directory to get rid of the branch name so that we
# don't have to worry about it in systemd and init.d files.
mv $( ls | grep -e ^mist-telegraf-.*$ ) mist-telegraf

echo >&2
echo "Configuring Telegraf service" >&2
echo "Appending environment variables to $ENVFILE" >&2

cat > $ENVFILE << EOF
TELEGRAF_DB="$INFLUX_DB"
TELEGRAF_HOST="$INFLUX_HOST"
TELEGRAF_MACHINE="$MACHINE_UUID"
TELEGRAF_PASSWORD="$MACHINE_PASS"
EOF

# Update service file and restart the service
if exists systemctl && [ "$(cat /proc/1/comm)" = "systemd" ]; then
    [ -d /lib/systemd/system ] && systemdir=/lib/systemd/system || systemdir=/usr/lib/systemd/system
    cp -f /opt/mistio/mist-telegraf/service/mist-telegraf.service $systemdir/mist-telegraf.service
    systemctl enable mist-telegraf
    systemctl daemon-reload
    systemctl restart mist-telegraf
else
    sed -i "s/^/export /" $ENVFILE
    cp -f /opt/mistio/mist-telegraf/service/mist-telegraf-init.sh /etc/init.d/mist-telegraf
    chmod +x /etc/init.d/mist-telegraf
    if exists update-rc.d; then
        update-rc.d mist-telegraf defaults
    else
        chkconfig --add mist-telegraf
    fi
    sleep 1
    /etc/init.d/mist-telegraf restart
    sleep 2
fi

echo >&2
echo "Telegraf installed successfully!" >&2
echo >&2
