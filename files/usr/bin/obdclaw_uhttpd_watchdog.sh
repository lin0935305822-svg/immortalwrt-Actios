#!/bin/sh

while true; do
    if ! wget -q -T 3 -O /dev/null http://127.0.0.1/; then
        logger -t obdclaw-uhttpd 'local health check failed; restarting uhttpd'
        killall uhttpd 2>/dev/null || true
        /etc/init.d/uhttpd start >/dev/null 2>&1 || true
    fi
    sleep 20
done
