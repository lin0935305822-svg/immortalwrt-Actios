#!/bin/sh
set -eu

root="${1:-.}"
runner="$root/files/www/cgi-bin/obdclaw-runner.cgi"
[ -x "$runner" ] || { echo "runner CGI is not executable: $runner" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
state="$tmp/state"
nonces="$tmp/nonces"
mkdir -p "$state"
device='0123456789abcdef0123456789abcdef'
printf '%s\n' "$device" >"$state/device_id"
openssl genpkey -algorithm ED25519 -out "$tmp/hub-private.pem" >/dev/null 2>&1
openssl pkey -in "$tmp/hub-private.pem" -pubout -out "$state/hub_authority_ed25519.pem" >/dev/null 2>&1

make_envelope() {
    session="$1"; expires="$2"; nonce="$3"
    canonical="v2|$device|$session|$expires|$nonce|runner"
    printf '%s' "$canonical" >"$tmp/message"
    signature="$(openssl pkeyutl -sign -inkey "$tmp/hub-private.pem" -rawin -in "$tmp/message" | openssl base64 -A | tr '/+' '_-' | tr -d '=')"
    printf 'v2.%s.%s.%s.%s.runner.%s' "$device" "$session" "$expires" "$nonce" "$signature"
}

call() {
    envelope="$1"
    body="envelope=$envelope&action=OPEN_SESSION"
    printf '%s' "$body" | REQUEST_METHOD=POST CONTENT_LENGTH="${#body}" \
        OBDCLAW_CONTROL_STATE_DIR="$state" OBDCLAW_RUNNER_NONCE_DIR="$nonces" \
        OBDCLAW_RUNNER_SOCKET="$tmp/missing.sock" "$runner"
}

now="$(date +%s)"
valid="$(make_envelope session-a $((now + 60)) nonce-a)"
response="$(call "$valid")"
printf '%s' "$response" | grep -Fq '"error":"runner-not-installed"'

response="$(call "$valid")"
printf '%s' "$response" | grep -Fq '"error":"replayed-envelope"'

expired="$(make_envelope session-b $((now - 1)) nonce-b)"
response="$(call "$expired")"
printf '%s' "$response" | grep -Fq '"error":"expired-envelope"'

last_char="${valid#${valid%?}}"
case "$last_char" in A) invalid="${valid%?}B";; *) invalid="${valid%?}A";; esac
response="$(call "$invalid")"
printf '%s' "$response" | grep -Fq '"error":"invalid-signature"'

echo 'obdclaw runner authorization tests passed.'
