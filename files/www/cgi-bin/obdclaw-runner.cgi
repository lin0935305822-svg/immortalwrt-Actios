#!/bin/sh
# Local-only Runner boundary. Hub authorization is verified once; all runner
# frames and controls remain on the phone -> 410 TLS link.
set -eu
umask 077

STATE_DIR="${OBDCLAW_CONTROL_STATE_DIR:-/overlay/obdclaw/local-control}"
DEVICE_ID_FILE="$STATE_DIR/device_id"
HUB_PUBLIC_KEY="$STATE_DIR/hub_authority_ed25519.pem"
NONCE_DIR="${OBDCLAW_RUNNER_NONCE_DIR:-/tmp/obdclaw-runner-nonces}"
SESSION_DIR="${OBDCLAW_RUNNER_SESSION_DIR:-/tmp/obdclaw-runner-sessions}"
AUTH_CLOCK="${OBDCLAW_AUTH_CLOCK:-/usr/bin/obdclaw_auth_clock}"
MAX_BODY=2048

reply() { printf 'Content-Type: application/json\r\nCache-Control: no-store\r\n\r\n%s\n' "$1"; exit 0; }
safe_id() { case "$1" in ''|*[!A-Za-z0-9_-]*) return 1;; esac; [ "${#1}" -le 128 ]; }
safe_signature() { safe_id "$1"; }
valid_number() { case "$1" in ''|*[!0-9]*) return 1;; esac; return 0; }
auth_now() { "$AUTH_CLOCK"; }

wifi_state() { ubus call network.interface.wifi_sta status 2>/dev/null | grep -q '"up": true' && printf up || printf down; }
rfcomm_state() { rfcomm -a 2>/dev/null | grep -q 'rfcomm0:.*connected' && printf connected || printf disconnected; }
status_reply() { printf '{"ok":true,"sessionId":"%s","wifiSta":"%s","rfcomm0":"%s"}' "$1" "$(wifi_state)" "$(rfcomm_state)"; }
frame_reply() {
    # This is transport state, not vehicle data. No control maps to RFCOMM I/O.
    printf '{"protocol":"obdclaw.runner-ui.v1","sessionId":"%s","nativeFrameId":"platform-status","sequence":%s,"shareSeq":%s,"shareType":0,"layout":"MSG","title":"410 Platform Link","rows":[{"Wi-Fi STA":"%s","VCI RFCOMM":"%s","Vehicle diagnostics":"Not available until a verified native protocol is installed"}],"controls":[{"id":"refresh","label":"Refresh link state","nativeSelection":1},{"id":"cancel","label":"End local session","nativeSelection":0}]}' "$1" "$2" "$2" "$(wifi_state)" "$(rfcomm_state)"
}

[ "${REQUEST_METHOD:-}" = POST ] || reply '{"ok":false,"error":"method-not-allowed"}'
content_length="${CONTENT_LENGTH:-0}"
valid_number "$content_length" || reply '{"ok":false,"error":"invalid-length"}'
[ "$content_length" -le "$MAX_BODY" ] || reply '{"ok":false,"error":"body-too-large"}'
body="$(dd bs=1 count="$content_length" 2>/dev/null)"

action="${body##*&action=}"
if [ "$action" = OPEN_SESSION ]; then
    case "$body" in envelope=*'&'action=OPEN_SESSION) ;; *) reply '{"ok":false,"error":"malformed-request"}';; esac
        [ -s "$DEVICE_ID_FILE" ] || reply '{"ok":false,"error":"identity-not-ready"}'
        [ -s "$HUB_PUBLIC_KEY" ] || reply '{"ok":false,"error":"authorization-not-provisioned"}'
        envelope="${body#envelope=}"
        envelope="${envelope%%&*}"
        old_ifs="$IFS"; IFS='.'; set -- $envelope; IFS="$old_ifs"
        [ "$#" -eq 7 ] || reply '{"ok":false,"error":"malformed-envelope"}'
        version="$1"; device_id="$2"; session_id="$3"; expires_at="$4"; nonce="$5"; scope="$6"; signature="$7"
        [ "$version" = v2 ] && [ "$scope" = runner ] || reply '{"ok":false,"error":"scope-denied"}'
        safe_id "$device_id" && safe_id "$session_id" && safe_id "$nonce" && safe_signature "$signature" || reply '{"ok":false,"error":"malformed-envelope"}'
        valid_number "$expires_at" || reply '{"ok":false,"error":"malformed-envelope"}'
        [ "$device_id" = "$(cat "$DEVICE_ID_FILE")" ] || reply '{"ok":false,"error":"wrong-device"}'
        now="$(auth_now)"; valid_number "$now" || reply '{"ok":false,"error":"clock-unavailable"}'
        [ "$expires_at" -ge "$now" ] && [ "$expires_at" -le $((now + 300)) ] || reply '{"ok":false,"error":"expired-envelope"}'
        tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT HUP INT TERM
        printf '%s' "$version|$device_id|$session_id|$expires_at|$nonce|$scope" >"$tmp/message"
        signature_std="$(printf '%s' "$signature" | tr '_-' '/+')"
        case $((${#signature_std} % 4)) in 0) pad='';; 2) pad='==';; 3) pad='=';; *) reply '{"ok":false,"error":"malformed-envelope"}';; esac
        printf '%s%s' "$signature_std" "$pad" | openssl base64 -d -A >"$tmp/signature" 2>/dev/null || reply '{"ok":false,"error":"malformed-envelope"}'
        openssl pkeyutl -verify -pubin -inkey "$HUB_PUBLIC_KEY" -rawin -in "$tmp/message" -sigfile "$tmp/signature" >/dev/null 2>&1 || reply '{"ok":false,"error":"invalid-signature"}'
        mkdir -p "$NONCE_DIR" "$SESSION_DIR"
        nonce_key="$(printf '%s' "$session_id|$nonce" | sha256sum | awk '{print $1}')"
        ( set -C; : >"$NONCE_DIR/$nonce_key" ) 2>/dev/null || reply '{"ok":false,"error":"replayed-envelope"}'
        ( set -C; printf '%s\n%s\n' "$expires_at" 0 >"$SESSION_DIR/$session_id" ) 2>/dev/null || reply '{"ok":false,"error":"session-already-active"}'
        reply "$(status_reply "$session_id")"
else
        # Parse only fixed, safe field order. This keeps CGI from becoming a
        # generic parameter relay or an arbitrary RFCOMM command endpoint.
        case "$action" in STATUS|NEXT_FRAME|CANCEL|UI_SELECT) ;; *) reply '{"ok":false,"error":"malformed-request"}';; esac
        session_id="${body#sessionId=}"; session_id="${session_id%%&*}"
        safe_id "$session_id" || reply '{"ok":false,"error":"malformed-session"}'
        session_file="$SESSION_DIR/$session_id"
        [ -r "$session_file" ] || reply '{"ok":false,"error":"unknown-session"}'
        expires_at="$(sed -n '1p' "$session_file")"; sequence="$(sed -n '2p' "$session_file")"
        valid_number "$expires_at" && valid_number "$sequence" || reply '{"ok":false,"error":"invalid-session"}'
        now="$(auth_now)"; valid_number "$now" || reply '{"ok":false,"error":"clock-unavailable"}'
        [ "$expires_at" -ge "$now" ] || { rm -f "$session_file"; reply '{"ok":false,"error":"session-expired"}'; }
        case "$action" in
            STATUS) reply "$(status_reply "$session_id")" ;;
            CANCEL) rm -f "$session_file"; reply '{"ok":true,"cancelled":true}' ;;
            NEXT_FRAME) sequence=$((sequence + 1)); printf '%s\n%s\n' "$expires_at" "$sequence" >"$session_file"; reply "$(frame_reply "$session_id" "$sequence")" ;;
            UI_SELECT)
                native_frame_id="${body#*nativeFrameId=}"; native_frame_id="${native_frame_id%%&*}"
                share_seq="${body#*shareSeq=}"; share_seq="${share_seq%%&*}"
                share_type="${body#*shareType=}"; share_type="${share_type%%&*}"
                selection="${body#*nativeSelection=}"; selection="${selection%%&*}"
                [ "$native_frame_id" = platform-status ] && valid_number "$share_seq" && [ "$share_type" = 0 ] && { [ "$selection" = 0 ] || [ "$selection" = 1 ]; } || reply '{"ok":false,"error":"undeclared-control"}'
                [ "$share_seq" = "$sequence" ] || reply '{"ok":false,"error":"stale-frame"}'
                if [ "$selection" = 0 ]; then rm -f "$session_file"; reply '{"ok":true,"cancelled":true}'; fi
                sequence=$((sequence + 1)); printf '%s\n%s\n' "$expires_at" "$sequence" >"$session_file"; reply '{"ok":true}'
                ;;
        esac
fi
