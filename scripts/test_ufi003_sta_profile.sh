#!/bin/sh
# Exercises accepted and rejected UFI003 STA configuration variants in isolation.
set -eu

root="${1:-.}"
checker="$root/scripts/verify_ufi003_sta_profile.sh"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT

mkdir -p "$temp/files/etc/config"
cp "$root/files/etc/config/wireless" "$temp/files/etc/config/wireless"
cp "$root/files/etc/config/network" "$temp/files/etc/config/network"

/bin/sh "$checker" "$temp"

sed -i "s/option encryption 'sae-mixed'/option encryption 'psk2'/" "$temp/files/etc/config/wireless"
/bin/sh "$checker" "$temp"

sed -i "s/option encryption 'psk2'/option encryption 'none'/" "$temp/files/etc/config/wireless"
if /bin/sh "$checker" "$temp"; then
    echo 'STA profile gate accepted unsupported encryption profile' >&2
    exit 1
fi

cp "$root/files/etc/config/wireless" "$temp/files/etc/config/wireless"
sed -i "s/option proto 'dhcp'/option proto 'static'/" "$temp/files/etc/config/network"
if /bin/sh "$checker" "$temp"; then
    echo 'STA profile gate accepted non-DHCP regression' >&2
    exit 1
fi

echo 'UFI003 STA profile tests passed.'
