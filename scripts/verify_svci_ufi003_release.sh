#!/bin/sh
# Source-stage gate for SVCI UFI003 release builds.
set -eu

root="${1:-.}"
cd "$root"

require_file() {
    [ -f "$1" ] || { echo "missing required file: $1" >&2; exit 1; }
}

require_exec() {
    [ -x "$1" ] || { echo "required script is not executable: $1" >&2; exit 1; }
}

require_file files/usr/sbin/obdclaw_led_status
require_file files/usr/bin/bluetooth_spp_manager.sh
require_file files/usr/bin/rfcomm_a30m_bind.sh
require_file files/usr/bin/obdclaw_bt_coex_test.sh

require_exec files/etc/init.d/obdclaw_led_status
require_exec files/etc/init.d/usb_acm_console
require_exec files/etc/init.d/bluetooth_spp_service
require_exec files/etc/init.d/rfcomm_a30m
require_exec files/usr/sbin/obdclaw_led_status
require_exec files/usr/bin/bluetooth_spp_manager.sh
require_exec files/usr/bin/rfcomm_a30m_bind.sh

grep -Fq 'set_timer "$red" 700 700' files/usr/sbin/obdclaw_led_status
grep -Fq 'set_timer "$red" 120 120' files/usr/sbin/obdclaw_led_status
grep -Fq 'set_timer "$blue" 120 120' files/usr/sbin/obdclaw_led_status
grep -Fq 'set_timer "$blue" 1000 1000' files/usr/sbin/obdclaw_led_status
grep -Fq 'modprobe btqca' files/usr/bin/bluetooth_spp_manager.sh
grep -Fq 'modprobe btqcomsmd' files/usr/bin/bluetooth_spp_manager.sh
grep -Fq 'Pairing successful' files/usr/bin/rfcomm_a30m_bind.sh
grep -Fq 'sdptool browse' files/usr/bin/rfcomm_a30m_bind.sh
grep -Fq 'rfcomm -i hci0 connect' files/usr/bin/rfcomm_a30m_bind.sh

if grep -Eq 'hciattach|ttyHS0|ttyMSM1|ttyS1' files/usr/bin/bluetooth_spp_manager.sh; then
    echo 'forbidden UART Bluetooth fallback found' >&2
    exit 1
fi

if grep -Fq 'ifdown wifi_sta' files/usr/bin/obdclaw_bt_coex_test.sh; then
    echo 'forbidden Wi-Fi STA teardown found' >&2
    exit 1
fi

echo 'SVCI UFI003 source release gate passed.'
