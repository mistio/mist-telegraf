#!/bin/sh

VERSION=1.6.2

SHA256=a4b0bc6d0fe88545dcc9fd297373fd5ce22eb49f9a4042bdd879b8c075793db8
TELEGRAF=telegraf-${VERSION}_linux_amd64.tar.gz
TELEGRAF_DL_PREFIX="https://dl.influxdata.com/telegraf/releases"

INFLUX_DB="telegraf"
INFLUX_HOST="http://influxdb:8086"

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

set -e

while getopts ":hip:m:s:p:d:" opt; do
    case "$opt" in
        h)
            echo "$USAGE"
            exit 0
            ;;
        i)
            SHA256=4b8717214d6e983ed468dad819c441418dcc7ec0f3127d056326cb1b8b29f454
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

exists() { command -v $@ > /dev/null 2>&1; }

untar() { echo >&2; echo "Extracting $1" >&2; tar -xvf $1; }

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

if ! echo "$INFLUX_HOST" | grep -q -i -E '^https?://[a-z0-9.-]+(:[1-9][0-9]*)?(/.+)?$'; then
    echo >&2
    echo >&2
    echo "Invalid destination endpoint: $INFLUX_HOST" >&2
    echo >&2
    echo >&2
    echo "$USAGE" >&2
    exit 1
fi

if [ -z "$MACHINE_UUID" ]; then
    echo >&2
    echo >&2
    echo "Required argument missing" >&2
    echo >&2
    echo >&2
    echo "$USAGE" >&2
    exit 1
fi

WORKDIR=/opt/mistio/
ENVFILE=/opt/mistio/mist-telegraf/service/mist-telegraf-env

echo >&2
echo "Setting up working directory at $WORKDIR" >&2
if [ ! -d $WORKDIR ]; then
    mkdir -p $WORKDIR
fi
cd $WORKDIR && rm -rf *telegraf*

echo >&2
echo "Setting up Telegraf" >&2
echo "Monitoring data will be sent to $INFLUX_HOST" >&2
echo "Monitoring data will be written to database: $INFLUX_DB" >&2

# Download Telegraf binary.
fetch $TELEGRAF_DL_PREFIX/$TELEGRAF
checksum $TELEGRAF
untar $TELEGRAF

# Download Telegraf and system config files.
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
