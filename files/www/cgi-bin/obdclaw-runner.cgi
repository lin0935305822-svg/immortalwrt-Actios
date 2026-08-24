#!/bin/sh
# Local-only Runner boundary. TLS-pinned APK enrollment establishes the
# phone -> 410 trust path; UI frames and controls stay on that LAN link.
set -eu
umask 077

STATE_DIR="${OBDCLAW_CONTROL_STATE_DIR:-/overlay/obdclaw/local-control}"
DEVICE_ID_FILE="$STATE_DIR/device_id"
SESSION_DIR="${OBDCLAW_RUNNER_SESSION_DIR:-/tmp/obdclaw-runner-sessions}"
AUTH_CLOCK="${OBDCLAW_AUTH_CLOCK:-/usr/bin/obdclaw_auth_clock}"
# The packaged Runner normally writes under /usr/share. A verified sidecar
# launched from /tmp uses its own handoff directory; follow it when present so
# the APK cannot receive a stale frame from a previous runtime.
if [ -n "${OBDCLAW_RUNNER_TMP_DIR:-}" ]; then
    RUNNER_TMP_DIR="$OBDCLAW_RUNNER_TMP_DIR"
elif [ -d /tmp/obdclaw-runner/tmp ]; then
    RUNNER_TMP_DIR=/tmp/obdclaw-runner/tmp
else
    RUNNER_TMP_DIR=/tmp/obdclaw-runner/tmp
fi
NATIVE_FRAME_FILE="${OBDCLAW_NATIVE_UI_FRAME_FILE:-$RUNNER_TMP_DIR/native-ui.json}"
NATIVE_REPLY_FILE="${OBDCLAW_NATIVE_UI_REPLY_FILE:-$RUNNER_TMP_DIR/native-ui-reply.json}"
MOBILE_RESOURCE_DIR="${OBDCLAW_MOBILE_RESOURCE_DIR:-$RUNNER_TMP_DIR/mobile-resource}"
MAX_REQUEST_BODY=98304
MAX_NATIVE_FRAME=65536

lock_dir=""

reply() { printf 'Content-Type: application/json\r\nCache-Control: no-store\r\n\r\n%s\n' "$1"; exit 0; }
safe_id() { case "$1" in ''|*[!A-Za-z0-9_-]*) return 1;; esac; [ "${#1}" -le 128 ]; }
safe_share_type() { case "$1" in ''|*[!A-Za-z0-9_]*) return 1;; esac; [ "${#1}" -le 64 ]; }
safe_resource_path() { case "$1" in ''|*..*|*[!A-Za-z0-9_.-]*) return 1;; esac; [ "${#1}" -le 128 ]; }
safe_base64() { case "$1" in ''|*[!A-Za-z0-9+/=]*) return 1;; esac; [ "$((${#1} % 4))" -eq 0 ] && [ "${#1}" -le 90112 ]; }
valid_number() { case "$1" in ''|*[!0-9]*) return 1;; esac; return 0; }
valid_hash() { case "$1" in *[!0-9A-Fa-f]*|'') return 1;; esac; [ "${#1}" -eq 64 ]; }
auth_now() { "$AUTH_CLOCK"; }
new_session_id() {
    if [ -r /proc/sys/kernel/random/uuid ]; then
        tr -d '-' </proc/sys/kernel/random/uuid
        return
    fi
    # Keeps host-side CGI regression tests runnable without weakening OpenWrt's
    # normal kernel UUID path.
    od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n'
}

wifi_state() { ubus call network.interface.wifi_sta status 2>/dev/null | grep -q '"up": true' && printf up || printf down; }
# Kernel-owned RFCOMM bindings report `clean` after the userspace binder hands
# the DLC to the broker.  That is an established link, not a disconnect.
rfcomm_state() { rfcomm -a 2>/dev/null | grep -Eq 'rfcomm0:.*(connected|clean)' && printf connected || printf disconnected; }
status_reply() { printf '{"ok":true,"sessionId":"%s","wifiSta":"%s","rfcomm0":"%s"}' "$1" "$(wifi_state)" "$(rfcomm_state)"; }
platform_frame_reply() {
    printf '{"protocol":"obdclaw.runner-ui.v1","sessionId":"%s","nativeFrameId":"platform-status","sequence":%s,"shareSeq":%s,"shareType":0,"layout":"MSG","title":"410 Platform Link","rows":[{"Wi-Fi STA":"%s","VCI RFCOMM":"%s","Vehicle diagnostics":"Waiting for Runner UI"}],"controls":[{"id":"refresh","label":"Refresh link state","nativeSelection":1},{"id":"cancel","label":"End local session","nativeSelection":0}]}' "$1" "$2" "$2" "$(wifi_state)" "$(rfcomm_state)"
}

release_session_lock() {
    if [ -n "$lock_dir" ]; then
        rmdir "$lock_dir" 2>/dev/null || true
        lock_dir=""
    fi
}
trap release_session_lock EXIT HUP INT TERM

acquire_session_lock() {
    mkdir -p "$SESSION_DIR/.locks"
    lock_dir="$SESSION_DIR/.locks/$1"
    mkdir "$lock_dir" 2>/dev/null || { lock_dir=""; reply '{"ok":false,"error":"session-busy"}'; }
}

# Session files are rewritten atomically while the matching lock directory is
# held. Fields after sequence bind one delivered native frame to one reply.
write_session() {
    session_tmp="${session_file}.tmp.$$"
    printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
        "$expires_at" "$sequence" "$frame_id" "$frame_share_seq" \
        "$frame_share_type" "$frame_native_type" "$frame_hash" "$frame_replied" >"$session_tmp"
    chmod 0600 "$session_tmp" && mv "$session_tmp" "$session_file" || {
        rm -f "$session_tmp"
        reply '{"ok":false,"error":"session-write-failed"}'
    }
}

read_session() {
    expires_at="$(sed -n '1p' "$session_file")"
    sequence="$(sed -n '2p' "$session_file")"
    frame_id="$(sed -n '3p' "$session_file")"
    frame_share_seq="$(sed -n '4p' "$session_file")"
    frame_share_type="$(sed -n '5p' "$session_file")"
    frame_native_type="$(sed -n '6p' "$session_file")"
    frame_hash="$(sed -n '7p' "$session_file")"
    frame_replied="$(sed -n '8p' "$session_file")"
    valid_number "$expires_at" && valid_number "$sequence" &&
        valid_number "$frame_share_seq" && valid_number "$frame_share_type" &&
        { [ "$frame_replied" = 0 ] || [ "$frame_replied" = 1 ]; } ||
        reply '{"ok":false,"error":"invalid-session"}'
}

# Capture metadata and a content hash at delivery time. UI_SELECT is accepted
# only while this exact native frame is still current.
capture_native_frame() {
    [ -s "$NATIVE_FRAME_FILE" ] || return 1
    frame_size="$(wc -c <"$NATIVE_FRAME_FILE" 2>/dev/null || true)"
    valid_number "$frame_size" && [ "$frame_size" -gt 1 ] && [ "$frame_size" -le "$MAX_NATIVE_FRAME" ] || return 1
    grep -q '"cmd":"UI_INIT"' "$NATIVE_FRAME_FILE" 2>/dev/null || return 1

    frame_id="$(sed -n 's/.*"nativeFrameId":"\([A-Za-z0-9_-]*\)".*/\1/p' "$NATIVE_FRAME_FILE" | head -n 1)"
    frame_share_seq="$(sed -n 's/.*"shareSeq":\([0-9][0-9]*\).*/\1/p' "$NATIVE_FRAME_FILE" | head -n 1)"
    frame_share_type="$(sed -n 's/.*"nativePt":\([0-9][0-9]*\).*/\1/p' "$NATIVE_FRAME_FILE" | head -n 1)"
    frame_native_type="$(sed -n 's/.*"shareType":"\([A-Za-z0-9_]*\)".*/\1/p' "$NATIVE_FRAME_FILE" | head -n 1)"
    frame_hash="$(sha256sum "$NATIVE_FRAME_FILE" | awk '{print $1}')"
    safe_id "$frame_id" && valid_number "$frame_share_seq" && valid_number "$frame_share_type" &&
        safe_share_type "$frame_native_type" && valid_hash "$frame_hash" || return 1
    return 0
}

read_mobile_resource_request() {
    resource_request="$MOBILE_RESOURCE_DIR/request"
    [ -r "$resource_request" ] || return 1
    resource_session="$(sed -n '1p' "$resource_request")"
    resource_request_id="$(sed -n '2p' "$resource_request")"
    resource_path="$(sed -n '3p' "$resource_request")"
    resource_block_index="$(sed -n '4p' "$resource_request")"
    safe_id "$resource_session" && valid_number "$resource_request_id" &&
        safe_resource_path "$resource_path" && valid_number "$resource_block_index"
}

[ "${REQUEST_METHOD:-}" = POST ] || reply '{"ok":false,"error":"method-not-allowed"}'
content_length="${CONTENT_LENGTH:-0}"
valid_number "$content_length" || reply '{"ok":false,"error":"invalid-length"}'
[ "$content_length" -le "$MAX_REQUEST_BODY" ] || reply '{"ok":false,"error":"body-too-large"}'
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
    mkdir -p "$SESSION_DIR"
    mkdir -p "$MOBILE_RESOURCE_DIR"
    chmod 0700 "$MOBILE_RESOURCE_DIR"
    session_file="$SESSION_DIR/$session_id"
    expires_at=$((now + 300)); sequence=0; frame_id=""; frame_share_seq=0
    frame_share_type=0; frame_native_type=""; frame_hash=""; frame_replied=1
    ( set -C; write_session ) 2>/dev/null || reply '{"ok":false,"error":"session-unavailable"}'
    printf '%s\n' "$session_id" >"$MOBILE_RESOURCE_DIR/active-session.tmp.$$" &&
        chmod 0600 "$MOBILE_RESOURCE_DIR/active-session.tmp.$$" &&
        mv "$MOBILE_RESOURCE_DIR/active-session.tmp.$$" "$MOBILE_RESOURCE_DIR/active-session" ||
        reply '{"ok":false,"error":"resource-session-unavailable"}'
    reply "$(status_reply "$session_id")"
fi

case "$action" in STATUS|NEXT_FRAME|CANCEL|UI_SELECT|RESOURCE_NEXT|RESOURCE_REPLY) ;; *) reply '{"ok":false,"error":"malformed-request"}';; esac
session_id="${body#sessionId=}"
session_id="${session_id%%&*}"
safe_id "$session_id" || reply '{"ok":false,"error":"malformed-session"}'
session_file="$SESSION_DIR/$session_id"
[ -r "$session_file" ] || reply '{"ok":false,"error":"unknown-session"}'
acquire_session_lock "$session_id"
read_session
now="$(auth_now)"; valid_number "$now" || reply '{"ok":false,"error":"clock-unavailable"}'
[ "$expires_at" -ge "$now" ] || { rm -f "$session_file"; reply '{"ok":false,"error":"session-expired"}'; }

case "$action" in
    STATUS) reply "$(status_reply "$session_id")" ;;
    CANCEL)
        rm -f "$session_file"
        [ "$(cat "$MOBILE_RESOURCE_DIR/active-session" 2>/dev/null || true)" != "$session_id" ] || rm -f "$MOBILE_RESOURCE_DIR/active-session" "$MOBILE_RESOURCE_DIR/request" "$MOBILE_RESOURCE_DIR/response"
        reply '{"ok":true,"cancelled":true}'
        ;;
    NEXT_FRAME)
        prior_frame_hash="$frame_hash"
        if capture_native_frame; then
            # Polling must not reopen a frame that has already been replied
            # to. Runner must emit a changed native frame before another UI
            # control can be accepted for this session.
            [ "$frame_hash" = "$prior_frame_hash" ] && reply 'null'
            sequence=$((sequence + 1))
            frame_replied=0
            write_session
            native_response="$(sed "s/\"seq\":[0-9][0-9]*/\"seq\":$sequence/" "$NATIVE_FRAME_FILE")"
            reply "$native_response"
        fi
        [ "$frame_id" = platform-status ] && reply 'null'
        sequence=$((sequence + 1))
        frame_id=platform-status; frame_share_seq="$sequence"; frame_share_type=0
        frame_native_type=PLATFORM_STATUS; frame_hash=""; frame_replied=0
        write_session
        reply "$(platform_frame_reply "$session_id" "$sequence")"
        ;;
    UI_SELECT)
        native_frame_id="${body#*nativeFrameId=}"; native_frame_id="${native_frame_id%%&*}"
        share_seq="${body#*shareSeq=}"; share_seq="${share_seq%%&*}"
        share_type="${body#*shareType=}"; share_type="${share_type%%&*}"
        selection="${body#*nativeSelection=}"; selection="${selection%%&*}"
        safe_id "$native_frame_id" && valid_number "$share_seq" && valid_number "$share_type" && valid_number "$selection" &&
            [ "$selection" -le 65535 ] || reply '{"ok":false,"error":"invalid-ui-reply"}'
        [ "$frame_replied" = 0 ] || reply '{"ok":false,"error":"frame-already-replied"}'
        [ "$native_frame_id" = "$frame_id" ] && [ "$share_seq" = "$frame_share_seq" ] &&
            [ "$share_type" = "$frame_share_type" ] || reply '{"ok":false,"error":"stale-frame"}'
        if [ "$frame_id" != platform-status ]; then
            delivered_id="$frame_id"; delivered_seq="$frame_share_seq"; delivered_type="$frame_share_type"
            delivered_native_type="$frame_native_type"; delivered_hash="$frame_hash"
            capture_native_frame && [ "$frame_id" = "$delivered_id" ] &&
                [ "$frame_share_seq" = "$delivered_seq" ] && [ "$frame_share_type" = "$delivered_type" ] &&
                [ "$frame_native_type" = "$delivered_native_type" ] && [ "$frame_hash" = "$delivered_hash" ] ||
                reply '{"ok":false,"error":"stale-frame"}'
            grep -Eq "\"(nativeSelection|mask|key)\":$selection([^0-9]|$)" "$NATIVE_FRAME_FILE" 2>/dev/null ||
                reply '{"ok":false,"error":"undeclared-control"}'
            reply_tmp="${NATIVE_REPLY_FILE}.tmp.$$"
            printf '{"cmd":"NATIVE_SHARE_REPLY","nativeSelection":%s,"shareSeq":%s,"shareType":"%s","nativeFrameId":"%s"}' \
                "$selection" "$delivered_seq" "$delivered_native_type" "$delivered_id" >"$reply_tmp"
            chmod 0600 "$reply_tmp" && mv "$reply_tmp" "$NATIVE_REPLY_FILE" || {
                rm -f "$reply_tmp"
                reply '{"ok":false,"error":"local-410-unavailable"}'
            }
            frame_id="$delivered_id"; frame_share_seq="$delivered_seq"; frame_share_type="$delivered_type"
            frame_native_type="$delivered_native_type"; frame_hash="$delivered_hash"; frame_replied=1
            write_session
            reply '{"ok":true}'
        fi
        [ "$selection" = 0 ] || [ "$selection" = 1 ] || reply '{"ok":false,"error":"undeclared-control"}'
        frame_replied=1
        if [ "$selection" = 0 ]; then rm -f "$session_file"; reply '{"ok":true,"cancelled":true}'; fi
        write_session
        reply '{"ok":true}'
        ;;
    RESOURCE_NEXT)
        if read_mobile_resource_request && [ "$resource_session" = "$session_id" ]; then
            reply "{\"protocol\":\"obdclaw.mobile-resource.v1\",\"sessionId\":\"$resource_session\",\"requestId\":$resource_request_id,\"path\":\"$resource_path\",\"blockIndex\":$resource_block_index}"
        fi
        reply 'null'
        ;;
    RESOURCE_REPLY)
        reply_request_id="${body#*requestId=}"; reply_request_id="${reply_request_id%%&*}"
        reply_resource_path="${body#*path=}"; reply_resource_path="${reply_resource_path%%&*}"
        reply_block_index="${body#*blockIndex=}"; reply_block_index="${reply_block_index%%&*}"
        reply_payload="${body#*payloadBase64=}"; reply_payload="${reply_payload%%&*}"
        valid_number "$reply_request_id" && safe_resource_path "$reply_resource_path" &&
            valid_number "$reply_block_index" && safe_base64 "$reply_payload" ||
            reply '{"ok":false,"error":"invalid-resource-reply"}'
        read_mobile_resource_request && [ "$resource_session" = "$session_id" ] &&
            [ "$reply_request_id" = "$resource_request_id" ] &&
            [ "$reply_resource_path" = "$resource_path" ] &&
            [ "$reply_block_index" = "$resource_block_index" ] ||
            reply '{"ok":false,"error":"stale-resource-request"}'
        resource_tmp="$MOBILE_RESOURCE_DIR/response.tmp.$$"
        printf '%s\n%s\n%s\n%s\n%s\n' "$session_id" "$reply_request_id" "$reply_resource_path" "$reply_block_index" "$reply_payload" >"$resource_tmp"
        chmod 0600 "$resource_tmp" && mv "$resource_tmp" "$MOBILE_RESOURCE_DIR/response" || {
            rm -f "$resource_tmp"
            reply '{"ok":false,"error":"resource-response-unavailable"}'
        }
        reply '{"ok":true}'
        ;;
esac
