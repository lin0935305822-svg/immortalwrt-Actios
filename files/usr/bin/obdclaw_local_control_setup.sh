#!/bin/sh
set -eu

STATE_DIR="${OBDCLAW_CONTROL_STATE_DIR:-/overlay/obdclaw/local-control}"
SECRET_FILE="$STATE_DIR/token_hmac.hex"
DEVICE_ID_FILE="$STATE_DIR/device_id"
CERT="${OBDCLAW_CONTROL_CERT:-/etc/uhttpd.crt}"
KEY="${OBDCLAW_CONTROL_KEY:-/etc/uhttpd.key}"

umask 077
mkdir -p "$STATE_DIR"

if [ ! -s "$SECRET_FILE" ]; then
    dd if=/dev/urandom bs=32 count=1 2>/dev/null | hexdump -v -e '/1 "%02x"' >"$SECRET_FILE"
fi

if [ ! -s "$DEVICE_ID_FILE" ]; then
    dd if=/dev/urandom bs=16 count=1 2>/dev/null | hexdump -v -e '/1 "%02x"' >"$DEVICE_ID_FILE"
fi

if [ ! -s "$CERT" ] || [ ! -s "$KEY" ]; then
    rm -f "$CERT" "$KEY"
    openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
        -subj "/CN=OBDclaw-410-$(cat "$DEVICE_ID_FILE")" \
        -keyout "$KEY" -out "$CERT" >/dev/null 2>&1
    chmod 600 "$KEY"
    chmod 644 "$CERT"
fi
