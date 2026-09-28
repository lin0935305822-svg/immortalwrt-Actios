#!/bin/sh
set -eu
SETUP_LOG=/tmp/obdclaw-control-setup.log
exec >>"$SETUP_LOG" 2>&1

logger -t obdclaw-control 'initializing local TLS control material' 2>/dev/null || true

STATE_DIR="${OBDCLAW_CONTROL_STATE_DIR:-/overlay/obdclaw/local-control}"
SECRET_FILE="$STATE_DIR/token_hmac.hex"
DEVICE_ID_FILE="$STATE_DIR/device_id"
CERT="${OBDCLAW_CONTROL_CERT:-/etc/uhttpd.crt}"
KEY="${OBDCLAW_CONTROL_KEY:-/etc/uhttpd.key}"

umask 077
if ! mkdir -p "$STATE_DIR"; then
    STATE_DIR=/tmp/obdclaw-local-control
    mkdir -p "$STATE_DIR"
fi

if [ ! -s "$SECRET_FILE" ]; then
    od -An -N32 -tx1 /dev/urandom | tr -d ' \n' >"$SECRET_FILE"
fi

if [ ! -s "$DEVICE_ID_FILE" ]; then
    od -An -N16 -tx1 /dev/urandom | tr -d ' \n' >"$DEVICE_ID_FILE"
fi

if [ ! -s "$CERT" ] || [ ! -s "$KEY" ]; then
    rm -f "$CERT" "$KEY"
    if command -v openssl >/dev/null 2>&1; then
        # Generate ECDSA in separate steps for compatibility with older OpenSSL.
        openssl ecparam -name prime256v1 -genkey -noout -out "$KEY"
        openssl req -x509 -new -sha256 -days 3650 -key "$KEY" \
            -subj "/CN=OBDclaw-410-$(cat "$DEVICE_ID_FILE")" \
            -out "$CERT"
        chmod 600 "$KEY"
        chmod 644 "$CERT"
    elif [ -x /usr/sbin/px5g ]; then
        # uhttpd's init script owns px5g invocation and will create the DER
        # pair immediately before its HTTPS instance starts.
        logger -t obdclaw-control 'openssl unavailable; deferring TLS material to uhttpd/px5g' 2>/dev/null || true
        exit 0
    else
        logger -t obdclaw-control 'no TLS certificate generator available' 2>/dev/null || true
        exit 1
    fi
fi

if [ ! -s "$CERT" ] || [ ! -s "$KEY" ]; then
    logger -t obdclaw-control 'TLS material generation failed' 2>/dev/null || true
    exit 1
fi
logger -t obdclaw-control 'local TLS control material ready' 2>/dev/null || true
