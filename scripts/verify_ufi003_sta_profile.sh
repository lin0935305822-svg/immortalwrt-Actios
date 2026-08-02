#!/bin/sh
# Verifies the physically accepted TP-LINK_7335 STA profile before UFI003 builds.
set -eu

root="${1:-.}"
if [ "$root" = '--rootfs-root' ]; then
    root="${2:?missing rootfs root}"
fi
wireless="$root/files/etc/config/wireless"
network="$root/files/etc/config/network"

require_once_pattern() {
    file="$1"
    pattern="$2"
    [ "$(tr -d '\r' < "$file" | grep -Ecx "$pattern")" -eq 1 ] || {
        echo "missing or duplicated UFI003 STA profile pattern: $pattern" >&2
        exit 1
    }
}

require_sta_option() {
    option_name="$1"
    option_value="$2"
    if ! awk -v expected_name="$option_name" -v expected_value="$option_value" '
        $1 == "config" { in_sta = ($2 == "wifi-iface" && $3 == "'\''sta'\''"); next }
        in_sta && $1 == "option" && $2 == expected_name && $3 == expected_value { matches++ }
        END { exit(matches == 1 ? 0 : 1) }
    ' "$wireless"; then
        echo "missing or duplicated STA option: $option_name $option_value" >&2
        exit 1
    fi
}

require_sta_encryption() {
    if ! awk '
        $1 == "config" { in_sta = ($2 == "wifi-iface" && $3 == "'\''sta'\''"); next }
        in_sta && $1 == "option" && $2 == "encryption" {
            count++
            if ($3 == "'\''psk2'\''" || $3 == "'\''sae-mixed'\''") allowed++
        }
        END { exit(count == 1 && allowed == 1 ? 0 : 1) }
    ' "$wireless"; then
        echo 'UFI003 STA encryption must be exactly one WPA2-compatible profile: psk2 or sae-mixed' >&2
        exit 1
    fi
}

[ -f "$wireless" ] || { echo "missing UFI003 wireless profile" >&2; exit 1; }
[ -f "$network" ] || { echo "missing UFI003 network profile" >&2; exit 1; }

require_once_pattern "$wireless" "^config wifi-device 'radio1'$"
require_once_pattern "$wireless" "^[[:space:]]*option[[:space:]]+channel[[:space:]]+'auto'$"
require_once_pattern "$wireless" "^[[:space:]]*option[[:space:]]+band[[:space:]]+'2g'$"
require_once_pattern "$wireless" "^config wifi-iface 'sta'$"
require_sta_option device "'radio1'"
require_sta_option mode "'sta'"
require_sta_option network "'wifi_sta'"
require_sta_option ssid "'TP-LINK_7335'"
require_sta_encryption
require_sta_option macaddr "'34:CE:00:10:9F:03'"

if ! awk '
    $1 == "config" { in_wifi_sta = ($2 == "interface" && $3 == "'\''wifi_sta'\''") }
    in_wifi_sta && $1 == "option" && $2 == "proto" && $3 == "'\''dhcp'\''" { found = 1 }
    END { exit(found ? 0 : 1) }
' "$network"; then
    echo 'UFI003 wifi_sta interface must obtain its address through DHCP' >&2
    exit 1
fi

echo 'UFI003 STA profile gate passed.'
