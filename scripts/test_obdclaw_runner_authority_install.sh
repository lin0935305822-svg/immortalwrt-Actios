#!/bin/sh
set -eu

root="${1:-.}"
installer="$root/files/usr/bin/obdclaw_runner_authority_install.sh"
[ -x "$installer" ] || { echo "authority installer is not executable: $installer" >&2; exit 1; }

tmp="$(mktemp -d)"
cleanup() {
    if [ "$(id -u)" -eq 0 ]; then
        rm -rf "$tmp"
    else
        sudo -n rm -rf "$tmp"
    fi
}
trap cleanup EXIT HUP INT TERM
openssl genpkey -algorithm ED25519 -out "$tmp/ed-private.pem" >/dev/null 2>&1
openssl pkey -in "$tmp/ed-private.pem" -pubout -out "$tmp/ed-public.pem" >/dev/null 2>&1
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$tmp/rsa-private.pem" >/dev/null 2>&1
openssl pkey -in "$tmp/rsa-private.pem" -pubout -out "$tmp/rsa-public.pem" >/dev/null 2>&1

state="$tmp/state"

run_installer() {
    if [ "$(id -u)" -eq 0 ]; then
        OBDCLAW_CONTROL_STATE_DIR="$state" "$installer" "$1"
    else
        sudo -n env OBDCLAW_CONTROL_STATE_DIR="$state" "$installer" "$1"
    fi
}

run_installer "$tmp/ed-public.pem" | grep -Fq 'installed Ed25519 Runner authority key'
if [ "$(id -u)" -eq 0 ]; then
    cmp -s "$tmp/ed-public.pem" "$state/hub_authority_ed25519.pem"
else
    sudo -n cmp -s "$tmp/ed-public.pem" "$state/hub_authority_ed25519.pem"
fi
! run_installer "$tmp/rsa-public.pem" >/dev/null 2>&1
! run_installer "$tmp/ed-private.pem" >/dev/null 2>&1
! run_installer "$tmp/missing.pem" >/dev/null 2>&1

echo 'obdclaw runner authority installation tests passed.'
