#!/bin/sh
# Root-only offline provisioning for the Hub Ed25519 verification key.
set -eu

STATE_DIR="${OBDCLAW_CONTROL_STATE_DIR:-/overlay/obdclaw/local-control}"
TARGET="$STATE_DIR/hub_authority_ed25519.pem"

[ "$#" -eq 1 ] || { echo "usage: $0 <hub-ed25519-public-key.pem>" >&2; exit 2; }
[ "$(id -u)" -eq 0 ] || { echo 'root privileges are required' >&2; exit 1; }
[ -s "$1" ] || { echo 'public key file is missing or empty' >&2; exit 1; }

mkdir -p "$STATE_DIR"
umask 077
tmp="$(mktemp "$STATE_DIR/.hub-authority.XXXXXX")"
trap 'rm -f "$tmp"' EXIT HUP INT TERM

# Normalize the PEM first, then require exactly an Ed25519 public key.
openssl pkey -pubin -in "$1" -pubout -out "$tmp" >/dev/null 2>&1 || {
    echo 'invalid public key PEM' >&2
    exit 1
}
openssl pkey -pubin -in "$tmp" -text -noout 2>/dev/null | grep -Fq 'ED25519 Public-Key:' || {
    echo 'authority key must be Ed25519' >&2
    exit 1
}
chmod 600 "$tmp"
mv -f "$tmp" "$TARGET"
trap - EXIT HUP INT TERM
echo "installed Ed25519 Runner authority key: $TARGET"
