#!/bin/sh

# chkconfig: 2345 99 01
# description: Telegraf agent

### BEGIN INIT INFO
# Provides:          mist-telegraf
# Required-Start:    $all
# Required-Stop:     $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start Telegraf at boot
### END INIT INFO

USER=root
GROUP=root

DEFAULT=/opt/mistio/mist-telegraf/service/mist-telegraf-env
TELEGRAF_OPTS=

OPEN_FILE_LIMIT=65536

# Service name.
NAME=mist-telegraf

# Configuration file.
CONFIG=/opt/mistio/mist-telegraf/telegraf.conf

# The actual executable.
DAEMON=/opt/mistio/telegraf/usr/bin/telegraf

# The PID file for the service daemon.
PIDFILE=/opt/mistio/telegraf/var/run/telegraf.pid
PIDDIR=`dirname $PIDFILE`

# If the executable is not there, exit.
[ -x $DAEMON ] || exit 5

if [ -r /lib/lsb/init-functions ]; then
    . /lib/lsb/init-functions
fi

if [ -r $DEFAULT ]; then
    . $DEFAULT
fi

if [ -z "$STDOUT" ]; then
    STDOUT=/dev/null
fi

if [ -z "$STDERR" ]; then
    STDERR=/opt/mistio/telegraf/var/log/telegraf/telegraf.log
fi

if [ ! -f "$STDOUT" ]; then
    mkdir -p `dirname $STDOUT`
fi

if [ ! -f "$STDERR" ]; then
    mkdir -p `dirname $STDERR`
fi

if [ ! -d "$PIDDIR" ]; then
    mkdir -p $PIDDIR
    chown -R $USER:$GROUP $PIDDIR
fi

log_success_msg() { echo "$@" "[ OK ]" >&2; }

log_failure_msg() { echo "$@" "[ FAILED ]" >&2; }

sendsignal() {
    kill -s $1 `cat $PIDFILE`
}

isrunning() {
    if [ -f $PIDFILE ] && [ -s $PIDFILE ]; then
        local pid=`cat $PIDFILE`
        if ps --pid "$pid" | grep -q $(basename $DAEMON); then
            return 0
        fi
    fi
    return 1
}

case $1 in
    start)
        if isrunning; then
            log_failure_msg "Service $NAME is running"
            exit 0
        fi

        # Bump the file limits before launching the daemon.
        # These will carry over to launched processes.
        ulimit -n $OPEN_FILE_LIMIT

        if [ $? -ne 0 ]; then
            log_failure_msg "Set open file limit to $OPEN_FILE_LIMIT"
        fi

        log_success_msg "Service $NAME is starting"

        if command -v startproc > /dev/null 2>&1; then
            startproc -u "$USER" -g "$GROUP" -p "$PIDFILE" -q -- "$DAEMON" -pidfile "$PIDFILE" -config "$CONFIG" $TELEGRAF_OPTS
        elif which start-stop-daemon > /dev/null 2>&1; then
            start-stop-daemon --chuid $USER:$GROUP --start --quiet --pidfile $PIDFILE --exec $DAEMON -- -pidfile $PIDFILE -config $CONFIG $TELEGRAF_OPTS >>$STDOUT 2>>$STDERR &
        else
            su -s /bin/sh -c "nohup $DAEMON -pidfile $PIDFILE -config $CONFIG $TELEGRAF_OPTS >>$STDOUT 2>>$STDERR &" $USER
        fi

        log_success_msg "Service $NAME is running"
        ;;

    stop)
        if isrunning; then
            if sendsignal TERM && rm -rf $PIDFILE; then
                log_success_msg "Service $NAME stopped"
            else
                log_failure_msg "Failed to stop service $NAME"
            fi
        else
            log_failure_msg "Service $NAME is not running"
        fi
        ;;

    reload)
        if isrunning; then
            if sendsignal HUP; then
                log_success_msg "Service $NAME was reloaded"
            else
                log_failure_msg "Failed to reload service $NAME"
            fi
        else
            log_failure_msg "Service $NAME is not running"
        fi
        ;;

    restart)
        $0 stop && sleep 2 && $0 start
        ;;

    status)
        if [ ! -e $PIDFILE ]; then
            log_failure_msg "Service $NAME is not running"
            exit 3
        fi
        if ! isrunning; then
            log_failure_msg "Service $NAME is not running"
            exit 1
        else
            log_success_msg "Service $NAME is running"
            exit 0
        fi
        ;;

    version)
        $DAEMON version
        ;;

    *)
        echo "Usage: $0 {start|stop|restart|status|version}"
        exit 2
        ;;
esac
