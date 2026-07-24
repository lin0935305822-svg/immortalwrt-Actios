#!/bin/sh

TOKEN='OBDclaw-410-maintenance'
MAX_BYTES=524288

header() { printf 'Content-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\n\r\n'; }
status() {
    echo 'OBDclaw 410 diagnostic status'
    echo '[LED]'; /usr/bin/dump_led_debug_info.sh 2>/dev/null || true
    echo '[Wi-Fi]'; ubus call network.wireless status 2>/dev/null || true
}
logs() { logread 2>/dev/null | tail -n 180; }

header
if [ "${REQUEST_METHOD:-GET}" = GET ]; then
    case "${QUERY_STRING:-}" in action=status) status ;; action=logs) logs ;; *) echo 'Unsupported diagnostic request.' ;; esac
    exit 0
fi
[ "${REQUEST_METHOD:-}" = POST ] || { echo 'Unsupported method.'; exit 0; }
[ "${CONTENT_LENGTH:-0}" -le "$MAX_BYTES" ] 2>/dev/null || { echo 'Rejected: update exceeds 512 KiB.'; exit 0; }
body="$(dd bs=1 count="${CONTENT_LENGTH:-0}" 2>/dev/null)"
token="$(printf '%s\n' "$body" | sed -n '1p')"
payload="$(printf '%s\n' "$body" | sed '1d')"
[ "$token" = "$TOKEN" ] || { echo 'Rejected: invalid maintenance token.'; exit 0; }
[ -n "$payload" ] || { echo 'Rejected: no update payload.'; exit 0; }
mkdir -p /overlay/obdclaw
tmp=/tmp/obdclaw-hot-update.$$
target=/overlay/obdclaw/hot-update.sh
trap 'rm -f "$tmp"' EXIT
printf '%s' "$payload" | base64 -d > "$tmp" 2>/dev/null || { echo 'Rejected: invalid script encoding.'; exit 0; }
[ -s "$tmp" ] && [ "$(wc -c < "$tmp")" -le "$MAX_BYTES" ] || { echo 'Rejected: empty or oversized script.'; exit 0; }
head -n 1 "$tmp" | grep -qx '#!/bin/sh' || { echo 'Rejected: script must start with #!/bin/sh.'; exit 0; }
install -m 0700 "$tmp" "$target"
logger -t obdclaw-hot-update 'executing uploaded maintenance script'
if "$target" >/tmp/obdclaw-hot-update.log 2>&1; then echo 'Update applied successfully.'; else echo 'Update script returned an error. Output:'; fi
tail -n 120 /tmp/obdclaw-hot-update.log 2>/dev/null
