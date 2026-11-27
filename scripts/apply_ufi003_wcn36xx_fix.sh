#!/bin/sh
# Stage the reviewed fix for the backports archive used by the UFI003 build.
set -eu

source_root="${1:?usage: apply_ufi003_wcn36xx_fix.sh <OpenWrt source root>}"
control_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
recipe="$source_root/package/kernel/mac80211/Makefile"
patch_source="$control_root/patches/wcn36xx-scan-band-guard.patch"
patch_target="$source_root/package/kernel/mac80211/patches/ath/996-wcn36xx-scan-band-guard.patch"

test -f "$recipe"
grep -Fx 'PKG_VERSION:=6.18.26' "$recipe" >/dev/null || {
    echo 'WCN36xx fix requires review for this backports version' >&2
    exit 1
}
grep -Fx 'PKG_HASH:=2ad578c6cae22f192fefd44e1449725228d4109ee781998b41dcbae872554968' "$recipe" >/dev/null || {
    echo 'WCN36xx fix backports archive digest mismatch' >&2
    exit 1
}
test -d "$(dirname "$patch_target")"
if test -e "$patch_target"; then
    cmp "$patch_source" "$patch_target" || {
        echo 'A different WCN36xx patch is already staged' >&2
        exit 1
    }
else
    install -m 0644 "$patch_source" "$patch_target"
fi
sha256sum "$patch_target"
echo 'UFI003 WCN36xx scan band fix staged'
