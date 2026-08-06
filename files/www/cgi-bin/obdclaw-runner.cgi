#!/bin/sh
# Local-only Runner boundary. TLS-pinned APK enrollment establishes the
# phone -> 410 trust path; all frames and controls remain on that LAN link.
set -eu
umask 077

STATE_DIR="${OBDCLAW_CONTROL_STATE_DIR:-/overlay/obdclaw/local-control}"
DEVICE_ID_FILE="$STATE_DIR/device_id"
SESSION_DIR="${OBDCLAW_RUNNER_SESSION_DIR:-/tmp/obdclaw-runner-sessions}"
AUTH_CLOCK="${OBDCLAW_AUTH_CLOCK:-/usr/bin/obdclaw_auth_clock}"
NATIVE_FRAME_FILE="${OBDCLAW_NATIVE_UI_FRAME_FILE:-/tmp/obdclaw-runner/tmp/native-ui.json}"
MAX_BODY=2048

reply() { printf 'Content-Type: application/json\r\nCache-Control: no-store\r\n\r\n%s\n' "$1"; exit 0; }
safe_id() { case "$1" in ''|*[!A-Za-z0-9_-]*) return 1;; esac; [ "${#1}" -le 128 ]; }
valid_number() { case "$1" in ''|*[!0-9]*) return 1;; esac; return 0; }
auth_now() { "$AUTH_CLOCK"; }
new_session_id() { od -An -N16 -tx1 /dev/urandom | tr -d ' \n'; }

wifi_state() { ubus call network.interface.wifi_sta status 2>/dev/null | grep -q '"up": true' && printf up || printf down; }
rfcomm_state() { rfcomm -a 2>/dev/null | grep -q 'rfcomm0:.*connected' && printf connected || printf disconnected; }
status_reply() { printf '{"ok":true,"sessionId":"%s","wifiSta":"%s","rfcomm0":"%s"}' "$1" "$(wifi_state)" "$(rfcomm_state)"; }
frame_reply() {
    # This is transport state, not vehicle data. No control maps to RFCOMM I/O.
    printf '{"protocol":"obdclaw.runner-ui.v1","sessionId":"%s","nativeFrameId":"platform-status","sequence":%s,"shareSeq":%s,"shareType":0,"layout":"MSG","title":"410 Platform Link","rows":[{"Wi-Fi STA":"%s","VCI RFCOMM":"%s","Vehicle diagnostics":"Not available until a verified native protocol is installed"}],"controls":[{"id":"refresh","label":"Refresh link state","nativeSelection":1},{"id":"cancel","label":"End local session","nativeSelection":0}]}' "$1" "$2" "$2" "$(wifi_state)" "$(rfcomm_state)"
}
native_frame_reply() {
    [ -s "$NATIVE_FRAME_FILE" ] || return 1
    frame_size="$(wc -c <"$NATIVE_FRAME_FILE" 2>/dev/null || true)"
    valid_number "$frame_size" && [ "$frame_size" -gt 1 ] && [ "$frame_size" -le "$MAX_BODY" ] || return 1
    grep -q '"cmd":"UI_INIT"' "$NATIVE_FRAME_FILE" 2>/dev/null || return 1
    cat "$NATIVE_FRAME_FILE"
}

[ "${REQUEST_METHOD:-}" = POST ] || reply '{"ok":false,"error":"method-not-allowed"}'
content_length="${CONTENT_LENGTH:-0}"
valid_number "$content_length" || reply '{"ok":false,"error":"invalid-length"}'
[ "$content_length" -le "$MAX_BODY" ] || reply '{"ok":false,"error":"body-too-large"}'
body="$(dd bs=1 count="$content_length" 2>/dev/null)"

action="${body##*&action=}"
if [ "$action" = OPEN_SESSION ]; then
    case "$body" in deviceId=*'&'action=OPEN_SESSION) ;; *) reply '{"ok":false,"error":"malformed-request"}';; esac
        [ -s "$DEVICE_ID_FILE" ] || reply '{"ok":false,"error":"identity-not-ready"}'
        device_id="${body#deviceId=}"
        device_id="${device_id%%&*}"
        safe_id "$device_id" || reply '{"ok":false,"error":"malformed-device"}'
        [ "$device_id" = "$(cat "$DEVICE_ID_FILE")" ] || reply '{"ok":false,"error":"wrong-device"}'
        now="$(auth_now)"; valid_number "$now" || reply '{"ok":false,"error":"clock-unavailable"}'
        session_id="$(new_session_id)"; safe_id "$session_id" || reply '{"ok":false,"error":"session-unavailable"}'
        expires_at=$((now + 300))
        mkdir -p "$SESSION_DIR"
        ( set -C; printf '%s\n%s\n' "$expires_at" 0 >"$SESSION_DIR/$session_id" ) 2>/dev/null || reply '{"ok":false,"error":"session-unavailable"}'
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
            NEXT_FRAME)
                sequence=$((sequence + 1)); printf '%s\n%s\n' "$expires_at" "$sequence" >"$session_file"
                reply "$(native_frame_reply || frame_reply "$session_id" "$sequence")"
                ;;
            UI_SELECT)
                native_frame_id="${body#*nativeFrameId=}"; native_frame_id="${native_frame_id%%&*}"
                share_seq="${body#*shareSeq=}"; share_seq="${share_seq%%&*}"
                share_type="${body#*shareType=}"; share_type="${share_type%%&*}"
                selection="${body#*nativeSelection=}"; selection="${selection%%&*}"
                if [ -s "$NATIVE_FRAME_FILE" ]; then
                    actual_frame_id="$(sed -n 's/.*"nativeFrameId":"\([A-Za-z0-9_-]*\)".*/\1/p' "$NATIVE_FRAME_FILE" | head -n 1)"
                    actual_share_seq="$(sed -n 's/.*"shareSeq":\([0-9][0-9]*\).*/\1/p' "$NATIVE_FRAME_FILE" | head -n 1)"
                    actual_share_type="$(sed -n 's/.*"shareType":"\([A-Za-z0-9_]*\)".*/\1/p' "$NATIVE_FRAME_FILE" | head -n 1)"
                    safe_id "$actual_frame_id" && valid_number "$actual_share_seq" && safe_id "$actual_share_type" && valid_number "$selection" || reply '{"ok":false,"error":"invalid-native-frame"}'
                    [ "$native_frame_id" = "$actual_frame_id" ] && [ "$share_seq" = "$actual_share_seq" ] || reply '{"ok":false,"error":"stale-frame"}'
                    grep -q "\"nativeSelection\":$selection" "$NATIVE_FRAME_FILE" 2>/dev/null || reply '{"ok":false,"error":"undeclared-control"}'
                    reply_file="${OBDCLAW_NATIVE_UI_REPLY_FILE:-/tmp/obdclaw-runner/tmp/native-ui-reply.json}"
                    reply_tmp="${reply_file}.tmp.$$"
                    printf '{"cmd":"NATIVE_SHARE_REPLY","nativeSelection":%s,"shareSeq":%s,"shareType":"%s","nativeFrameId":"%s"}' "$selection" "$actual_share_seq" "$actual_share_type" "$actual_frame_id" >"$reply_tmp"
                    chmod 0600 "$reply_tmp" && mv "$reply_tmp" "$reply_file" || { rm -f "$reply_tmp"; reply '{"ok":false,"error":"local-410-unavailable"}'; }
                    reply '{"ok":true}'
                fi
                [ "$native_frame_id" = platform-status ] && valid_number "$share_seq" && [ "$share_type" = 0 ] && { [ "$selection" = 0 ] || [ "$selection" = 1 ]; } || reply '{"ok":false,"error":"undeclared-control"}'
                [ "$share_seq" = "$sequence" ] || reply '{"ok":false,"error":"stale-frame"}'
                if [ "$selection" = 0 ]; then rm -f "$session_file"; reply '{"ok":true,"cancelled":true}'; fi
                sequence=$((sequence + 1)); printf '%s\n%s\n' "$expires_at" "$sequence" >"$session_file"; reply '{"ok":true}'
                ;;
        esac
fi
