#!/bin/sh
set -eu

root="${1:-.}"
script="$root/files/usr/bin/obdclaw_local_control_setup.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

cat >"$tmp/od" <<'EOF'
#!/bin/sh
printf 'od was called\n' >"$OBDCLAW_OD_SENTINEL"
exit 99
EOF
chmod 755 "$tmp/od"
printf 'existing certificate\n' >"$tmp/cert"
printf 'existing key\n' >"$tmp/key"

OBDCLAW_OD_SENTINEL="$tmp/od-called" \
OBDCLAW_CONTROL_STATE_DIR="$tmp/state" \
OBDCLAW_CONTROL_CERT="$tmp/cert" \
OBDCLAW_CONTROL_KEY="$tmp/key" \
PATH="$tmp:$PATH" /bin/sh "$script"

test ! -e "$tmp/od-called"
test -s "$tmp/state/token_hmac.hex"
test -s "$tmp/state/device_id"
grep -Eq '^[0-9a-f]{64}$' "$tmp/state/token_hmac.hex"
grep -Eq '^[0-9a-f]{32}$' "$tmp/state/device_id"

secret_before="$(cat "$tmp/state/token_hmac.hex")"
device_before="$(cat "$tmp/state/device_id")"
OBDCLAW_OD_SENTINEL="$tmp/od-called" \
OBDCLAW_CONTROL_STATE_DIR="$tmp/state" \
OBDCLAW_CONTROL_CERT="$tmp/cert" \
OBDCLAW_CONTROL_KEY="$tmp/key" \
PATH="$tmp:$PATH" /bin/sh "$script"
test ! -e "$tmp/od-called"
test "$(cat "$tmp/state/token_hmac.hex")" = "$secret_before"
test "$(cat "$tmp/state/device_id")" = "$device_before"

echo 'local control setup without od passed'
