#!/bin/sh
set -eu

root="${1:-.}"
runner="$root/files/www/cgi-bin/obdclaw-runner.cgi"
[ -x "$runner" ] || { echo "runner CGI is not executable: $runner" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
state="$tmp/state"
mkdir -p "$state"
clock="$tmp/auth-clock"
printf '#!/bin/sh\nprintf "1700000000\\n"\n' >"$clock"
chmod 700 "$clock"
device='0123456789abcdef0123456789abcdef'
printf '%s\n' "$device" >"$state/device_id"
call() {
    body="$1"
    printf '%s' "$body" | REQUEST_METHOD=POST CONTENT_LENGTH="${#body}" \
        OBDCLAW_CONTROL_STATE_DIR="$state" \
        OBDCLAW_RUNNER_SESSION_DIR="$tmp/sessions" OBDCLAW_AUTH_CLOCK="$clock" "$runner"
}

response="$(call "deviceId=$device&action=OPEN_SESSION")"
printf '%s' "$response" | grep -Fq '"ok":true'
session="$(printf '%s' "$response" | sed -n 's/.*"sessionId":"\([A-Za-z0-9_-]*\)".*/\1/p')"
[ -n "$session" ]

response="$(call "sessionId=$session&action=NEXT_FRAME")"
printf '%s' "$response" | grep -Fq '"protocol":"obdclaw.runner-ui.v1"'
printf '%s' "$response" | grep -Fq '"sequence":1'

# Native frames can wait for a reply with a stable Runner seq. The CGI must
# attach a new local-session sequence to every delivery while keeping the
# native share sequence used by UI_SELECT.
native_frame="$tmp/native-ui.json"
printf '%s' '{"cmd":"UI_INIT","seq":1201,"payload":{"nativeFrameId":"runner-00000001-0000000000000001","source":"runner_native_share","nativePt":4,"shareSeq":0,"shareType":"PT_MSG","title":"AUTO SCAN","requiresNativeReply":true,"buttons":[{"mask":1,"text":"OK","key":1}]}}' >"$native_frame"
call_native() {
    body="$1"
    printf '%s' "$body" | REQUEST_METHOD=POST CONTENT_LENGTH="${#body}" \
        OBDCLAW_CONTROL_STATE_DIR="$state" \
        OBDCLAW_RUNNER_SESSION_DIR="$tmp/sessions" OBDCLAW_AUTH_CLOCK="$clock" \
        OBDCLAW_NATIVE_UI_FRAME_FILE="$native_frame" OBDCLAW_NATIVE_UI_REPLY_FILE="$tmp/native-ui-reply.json" "$runner"
}
response="$(call_native "sessionId=$session&action=NEXT_FRAME")"
printf '%s' "$response" | grep -Fq '"seq":2'
printf '%s' "$response" | grep -Fq '"shareSeq":0'
response="$(call_native "sessionId=$session&action=NEXT_FRAME")"
printf '%s' "$response" | grep -Fq '"seq":3'
response="$(call_native "sessionId=$session&nativeFrameId=runner-00000001-0000000000000001&shareSeq=0&shareType=4&nativeSelection=1&action=UI_SELECT")"
printf '%s' "$response" | grep -Fq '"ok":true'
grep -Fq '"nativeSelection":1' "$tmp/native-ui-reply.json"

response="$(call "sessionId=$session&nativeFrameId=platform-status&shareSeq=1&shareType=0&nativeSelection=1&action=UI_SELECT")"
printf '%s' "$response" | grep -Fq '"ok":true'

response="$(call "sessionId=$session&nativeFrameId=platform-status&shareSeq=1&shareType=0&nativeSelection=1&action=UI_SELECT")"
printf '%s' "$response" | grep -Fq '"error":"stale-frame"'

response="$(call "deviceId=wrong-device&action=OPEN_SESSION")"
printf '%s' "$response" | grep -Fq '"error":"wrong-device"'

printf '#!/bin/sh\nprintf "1700000301\\n"\n' >"$clock"
response="$(call "sessionId=$session&action=STATUS")"
printf '%s' "$response" | grep -Fq '"error":"session-expired"'

echo 'obdclaw runner local-session tests passed.'
