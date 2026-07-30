#!/bin/sh
set -eu

STATE_DIR="${OBDCLAW_CONTROL_STATE_DIR:-/overlay/obdclaw/local-control}"
DEVICE_ID_FILE="$STATE_DIR/device_id"
CERT="${OBDCLAW_CONTROL_CERT:-/etc/uhttpd.crt}"

printf 'Content-Type: application/json\r\nCache-Control: no-store\r\n\r\n'

if [ ! -s "$DEVICE_ID_FILE" ] || [ ! -s "$CERT" ]; then
    printf '{"ok":false,"error":"identity-not-ready"}\n'
    exit 0
fi

fingerprint="$(openssl x509 -in "$CERT" -noout -fingerprint -sha256 | sed 's/^.*=//' | tr -d ':')"
device_id="$(cat "$DEVICE_ID_FILE")"
printf '{"ok":true,"deviceId":"%s","certificateSha256":"%s","api":"https://<device>:8443/cgi-bin/obdclaw-runner.cgi"}\n' "$device_id" "$fingerprint"
