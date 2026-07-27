#!/bin/sh
# Production diagnostic endpoint: read-only and normally unreachable because
# the production image disables uhttpd.  Keep this safe if a recovery image
# enables the web server explicitly.

printf 'Content-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\n\r\n'

if [ "${REQUEST_METHOD:-GET}" != GET ]; then
    echo 'Maintenance updates are disabled in production firmware.'
    exit 0
fi

case "${QUERY_STRING:-}" in
    action=status)
        echo 'OBDclaw 410 diagnostic status'
        /usr/bin/dump_led_debug_info.sh 2>/dev/null || true
        ;;
    *) echo 'Unsupported diagnostic request.' ;;
esac
