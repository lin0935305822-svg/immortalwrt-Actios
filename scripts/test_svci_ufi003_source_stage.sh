#!/bin/sh
# Reproduces the workflow's staged-rootfs release gate invocation.
set -eu

root="${1:-.}"
control_root="$(CDPATH= cd -- "$root" && pwd)"
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
gate="$script_dir/verify_svci_ufi003_release.sh"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT HUP INT TERM

mkdir -p "$temp/openwrt"
cp -R "$root/." "$temp/openwrt/"
rm -rf "$temp/openwrt/scripts"

(
    cd "$temp/openwrt"
    /bin/sh "$gate" --control-root "$control_root" --rootfs-root .
)

echo 'SVCI UFI003 staged source release gate passed.'
