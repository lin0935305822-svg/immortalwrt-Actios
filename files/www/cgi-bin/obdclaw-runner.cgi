#!/bin/sh
# Narrow local Runner session boundary. The Hub signs authorization only; it
# never receives diagnostic traffic from this endpoint.
set -eu

STATE_DIR="${OBDCLAW_CONTROL_STATE_DIR:-/overlay/obdclaw/local-control}"
DEVICE_ID_FILE="$STATE_DIR/device_id"
HUB_PUBLIC_KEY="$STATE_DIR/hub_authority_ed25519.pem"
NONCE_DIR="${OBDCLAW_RUNNER_NONCE_DIR:-/tmp/obdclaw-runner-nonces}"
RUNNER_SOCKET="${OBDCLAW_RUNNER_SOCKET:-/var/run/obdclaw-runner.sock}"
MAX_BODY=2048

reply() {
    printf 'Content-Type: application/json\r\nCache-Control: no-store\r\n\r\n%s\n' "$1"
    exit 0
}

safe_id() {
    case "$1" in ''|*[!A-Za-z0-9_-]*) return 1;; esac
    [ "${#1}" -le 128 ]
}

safe_signature() {
    case "$1" in ''|*[!A-Za-z0-9_-]*) return 1;; esac
    [ "${#1}" -le 128 ]
}

[ "${REQUEST_METHOD:-}" = POST ] || reply '{"ok":false,"error":"method-not-allowed"}'
[ -s "$DEVICE_ID_FILE" ] || reply '{"ok":false,"error":"identity-not-ready"}'
[ -s "$HUB_PUBLIC_KEY" ] || reply '{"ok":false,"error":"authorization-not-provisioned"}'

content_length="${CONTENT_LENGTH:-0}"
case "$content_length" in *[!0-9]*|'') reply '{"ok":false,"error":"invalid-length"}';; esac
[ "$content_length" -le "$MAX_BODY" ] || reply '{"ok":false,"error":"body-too-large"}'
body="$(dd bs=1 count="$content_length" 2>/dev/null)"
case "$body" in envelope=*'&'action=OPEN_SESSION) ;; *) reply '{"ok":false,"error":"malformed-request"}';; esac
envelope="${body#envelope=}"
envelope="${envelope%%&*}"

old_ifs="$IFS"
IFS='.'
set -- $envelope
IFS="$old_ifs"
[ "$#" -eq 7 ] || reply '{"ok":false,"error":"malformed-envelope"}'
version="$1"; device_id="$2"; session_id="$3"; expires_at="$4"; nonce="$5"; scope="$6"; signature="$7"
[ "$version" = v2 ] && [ "$scope" = runner ] || reply '{"ok":false,"error":"scope-denied"}'
safe_id "$device_id" && safe_id "$session_id" && safe_id "$nonce" && safe_signature "$signature" || reply '{"ok":false,"error":"malformed-envelope"}'
case "$expires_at" in *[!0-9]*|'') reply '{"ok":false,"error":"malformed-envelope"}';; esac
[ "$device_id" = "$(cat "$DEVICE_ID_FILE")" ] || reply '{"ok":false,"error":"wrong-device"}'
now="$(date +%s)"
[ "$expires_at" -ge "$now" ] && [ "$expires_at" -le $((now + 300)) ] || reply '{"ok":false,"error":"expired-envelope"}'

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
canonical="$version|$device_id|$session_id|$expires_at|$nonce|$scope"
printf '%s' "$canonical" >"$tmp/message"
signature_std="$(printf '%s' "$signature" | tr '_-' '/+')"
case $((${#signature_std} % 4)) in 0) pad='';; 2) pad='==';; 3) pad='=';; *) reply '{"ok":false,"error":"malformed-envelope"}';; esac
printf '%s%s' "$signature_std" "$pad" | openssl base64 -d -A >"$tmp/signature" 2>/dev/null || reply '{"ok":false,"error":"malformed-envelope"}'
openssl pkeyutl -verify -pubin -inkey "$HUB_PUBLIC_KEY" -rawin -in "$tmp/message" -sigfile "$tmp/signature" >/dev/null 2>&1 || reply '{"ok":false,"error":"invalid-signature"}'

mkdir -p "$NONCE_DIR"
nonce_key="$(printf '%s' "$session_id|$nonce" | sha256sum | awk '{print $1}')"
( set -C; : >"$NONCE_DIR/$nonce_key" ) 2>/dev/null || reply '{"ok":false,"error":"replayed-envelope"}'

# Do not claim diagnostic availability before the local Runner service exists.
[ -S "$RUNNER_SOCKET" ] || reply '{"ok":false,"error":"runner-not-installed"}'
reply '{"ok":false,"error":"runner-session-api-not-implemented"}'
