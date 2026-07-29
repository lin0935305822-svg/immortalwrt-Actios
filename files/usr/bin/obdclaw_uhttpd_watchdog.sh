#!/bin/sh

while true; do
    # The local control listener is HTTPS-only and uses a per-device
    # certificate.  Process supervision avoids a second HTTP client package
    # and never probes an unencrypted listener.
    if ! pidof uhttpd >/dev/null 2>&1; then
        logger -t obdclaw-uhttpd 'uhttpd is absent; restarting local TLS service'
        /etc/init.d/uhttpd restart >/dev/null 2>&1 || true
    fi
    sleep 20
done
