#!/bin/sh
# Narrow phone-to-410 control boundary.  Tokens are provisioned by the Hub but
# verified locally; no diagnostic request is forwarded to www.obdclaw.com.
set -eu

STATE_DIR="${OBDCLAW_CONTROL_STATE_DIR:-/overlay/obdclaw/local-control}"
SECRET_FILE="$STATE_DIR/token_hmac.hex"
DEVICE_ID_FILE="$STATE_DIR/device_id"
NONCE_DIR="${OBDCLAW_CONTROL_NONCE_DIR:-/tmp/obdclaw-control-nonces}"
MAX_BODY=1024

reply() {
    printf 'Content-Type: application/json\r\nCache-Control: no-store\r\n\r\n%s\n' "$1"
    exit 0
}

is_safe_field() {
    case "$1" in ''|*[!A-Za-z0-9_-]*) return 1;; esac
    [ "${#1}" -le 128 ]
}

is_hex() {
    case "$1" in ''|*[!0-9A-Fa-f]*) return 1;; esac
    [ "${#1}" -eq 64 ]
}

[ "${REQUEST_METHOD:-}" = POST ] || reply '{"ok":false,"error":"method-not-allowed"}'
[ -s "$SECRET_FILE" ] && [ -s "$DEVICE_ID_FILE" ] || reply '{"ok":false,"error":"identity-not-ready"}'

content_length="${CONTENT_LENGTH:-0}"
case "$content_length" in *[!0-9]*|'') reply '{"ok":false,"error":"invalid-length"}';; esac
[ "$content_length" -le "$MAX_BODY" ] || reply '{"ok":false,"error":"body-too-large"}'
body="$(dd bs=1 count="$content_length" 2>/dev/null)"
case "$body" in token=*"&"action=*) ;; *) reply '{"ok":false,"error":"malformed-request"}';; esac
token="${body#token=}"
token="${token%%&*}"
action="${body#*&action=}"
case "$action" in *'&'*) reply '{"ok":false,"error":"malformed-request"}';; esac
[ "$action" = STATUS ] || reply '{"ok":false,"error":"unsupported-action"}'

old_ifs="$IFS"
IFS='.'
set -- $token
IFS="$old_ifs"
[ "$#" -eq 7 ] || reply '{"ok":false,"error":"malformed-token"}'
version="$1"; device_id="$2"; session_id="$3"; expires_at="$4"; nonce="$5"; scope="$6"; signature="$7"
[ "$version" = v1 ] && [ "$scope" = status ] || reply '{"ok":false,"error":"token-scope-denied"}'
is_safe_field "$device_id" && is_safe_field "$session_id" && is_safe_field "$nonce" && is_hex "$signature" || reply '{"ok":false,"error":"malformed-token"}'
case "$expires_at" in *[!0-9]*|'') reply '{"ok":false,"error":"malformed-token"}';; esac
[ "$device_id" = "$(cat "$DEVICE_ID_FILE")" ] || reply '{"ok":false,"error":"wrong-device"}'

now="$(date +%s)"
[ "$expires_at" -ge "$now" ] && [ "$expires_at" -le $((now + 300)) ] || reply '{"ok":false,"error":"expired-token"}'
canonical="$version|$device_id|$session_id|$expires_at|$nonce|$scope"
expected="$(printf '%s' "$canonical" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$(cat "$SECRET_FILE")" | awk '{print $NF}')"
[ "$expected" = "$(printf '%s' "$signature" | tr 'A-F' 'a-f')" ] || reply '{"ok":false,"error":"invalid-signature"}'

mkdir -p "$NONCE_DIR"
nonce_key="$(printf '%s' "$session_id|$nonce" | sha256sum | awk '{print $1}')"
( set -C; : >"$NONCE_DIR/$nonce_key" ) 2>/dev/null || reply '{"ok":false,"error":"replayed-token"}'

wifi_state=down
ubus call network.interface.wifi_sta status 2>/dev/null | grep -q '"up": true' && wifi_state=up
rfcomm_state=disconnected
rfcomm -a 2>/dev/null | grep -q 'rfcomm0:.*connected' && rfcomm_state=connected
printf 'Content-Type: application/json\r\nCache-Control: no-store\r\n\r\n'
printf '{"ok":true,"sessionId":"%s","wifiSta":"%s","rfcomm0":"%s"}\n' "$session_id" "$wifi_state" "$rfcomm_state"
