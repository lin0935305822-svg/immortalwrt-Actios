#!/bin/sh
set -eu

root="${1:-.}"
installer="$root/files/usr/bin/obdclaw_runner_authority_install.sh"
[ -x "$installer" ] || { echo "authority installer is not executable: $installer" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
openssl genpkey -algorithm ED25519 -out "$tmp/ed-private.pem" >/dev/null 2>&1
openssl pkey -in "$tmp/ed-private.pem" -pubout -out "$tmp/ed-public.pem" >/dev/null 2>&1
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$tmp/rsa-private.pem" >/dev/null 2>&1
openssl pkey -in "$tmp/rsa-private.pem" -pubout -out "$tmp/rsa-public.pem" >/dev/null 2>&1

state="$tmp/state"
OBDCLAW_CONTROL_STATE_DIR="$state" "$installer" "$tmp/ed-public.pem" | grep -Fq 'installed Ed25519 Runner authority key'
cmp -s "$tmp/ed-public.pem" "$state/hub_authority_ed25519.pem"
! OBDCLAW_CONTROL_STATE_DIR="$state" "$installer" "$tmp/rsa-public.pem" >/dev/null 2>&1
! OBDCLAW_CONTROL_STATE_DIR="$state" "$installer" "$tmp/ed-private.pem" >/dev/null 2>&1
! OBDCLAW_CONTROL_STATE_DIR="$state" "$installer" "$tmp/missing.pem" >/dev/null 2>&1

echo 'obdclaw runner authority installation tests passed.'
