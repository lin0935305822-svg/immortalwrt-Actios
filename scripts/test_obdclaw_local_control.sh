#!/bin/sh
set -eu

root="${1:-.}"
control="$root/files/www/cgi-bin/obdclaw-control.cgi"
[ -x "$control" ] || { echo "control CGI is not executable: $control" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
state="$tmp/state"
nonces="$tmp/nonces"
mkdir -p "$state"
secret='00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff'
device='0123456789abcdef0123456789abcdef'
printf '%s\n' "$secret" >"$state/token_hmac.hex"
printf '%s\n' "$device" >"$state/device_id"

make_token() {
    session="$1"
    expires="$2"
    nonce="$3"
    canonical="v1|$device|$session|$expires|$nonce|status"
    signature="$(printf '%s' "$canonical" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$secret" | awk '{print $NF}')"
    printf 'v1.%s.%s.%s.%s.status.%s' "$device" "$session" "$expires" "$nonce" "$signature"
}

call() {
    token="$1"
    body="token=$token&action=STATUS"
    printf '%s' "$body" | REQUEST_METHOD=POST CONTENT_LENGTH="${#body}" \
        OBDCLAW_CONTROL_STATE_DIR="$state" OBDCLAW_CONTROL_NONCE_DIR="$nonces" "$control"
}

now="$(date +%s)"
valid="$(make_token session-a $((now + 60)) nonce-a)"
response="$(call "$valid")"
printf '%s' "$response" | grep -Fq '"ok":true'

response="$(call "$valid")"
printf '%s' "$response" | grep -Fq '"error":"replayed-token"'

expired="$(make_token session-b $((now - 1)) nonce-b)"
response="$(call "$expired")"
printf '%s' "$response" | grep -Fq '"error":"expired-token"'

last_char="${valid#${valid%?}}"
case "$last_char" in 0) invalid="${valid%?}1";; *) invalid="${valid%?}0";; esac
response="$(call "$invalid")"
printf '%s' "$response" | grep -Fq '"error":"invalid-signature"'

echo 'obdclaw local control tests passed.'
