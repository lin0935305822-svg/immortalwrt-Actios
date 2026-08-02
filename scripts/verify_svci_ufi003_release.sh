#!/bin/sh
# Source-stage gate for SVCI UFI003 release builds.
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
control_root="$(dirname "$script_dir")"
root=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --control-root) control_root="$2"; shift 2 ;;
        --rootfs-root) root="$2"; shift 2 ;;
        *) [ -z "$root" ] || { echo "unexpected argument: $1" >&2; exit 2; }; root="$1"; shift ;;
    esac
done

[ -n "$root" ] || { echo 'missing rootfs root' >&2; exit 2; }
cd "$root"

require_file() {
    [ -f "$1" ] || { echo "missing required file: $1" >&2; exit 1; }
}

require_exec() {
    [ -x "$1" ] || { echo "required script is not executable: $1" >&2; exit 1; }
}

require_config_once() {
    value="$1"
    config_file="config/ufi003.config"
    [ "$(tr -d '\r' < "$config_file" | grep -cx "$value")" -eq 1 ] || {
        echo "missing or duplicated UFI003 config: $value" >&2
        exit 1
    }
}

verify_all_custom_scripts_executable() {
    for directory in files/etc/init.d files/etc/uci-defaults files/etc/hotplug.d files/usr/bin files/usr/sbin files/www/cgi-bin; do
        [ -d "$directory" ] || { echo "missing custom script directory: $directory" >&2; exit 1; }
        non_executable="$(find "$directory" -type f ! -perm -0100 -print -quit)"
        [ -z "$non_executable" ] || {
            echo "custom script is not executable: $non_executable" >&2
            exit 1
        }
    done
}

# This check runs before the machine profile is moved into OpenWrt's .config.
if [ -f config/ufi003.config ]; then
    require_config_once 'CONFIG_PACKAGE_kmod-bluetooth=y'
    require_config_once 'CONFIG_PACKAGE_kmod-btqcomsmd=y'
    require_config_once 'CONFIG_PACKAGE_bluez-daemon=y'
    require_config_once 'CONFIG_PACKAGE_bluez-utils=y'
    require_config_once 'CONFIG_PACKAGE_bluez-libs=y'
    require_config_once 'CONFIG_PACKAGE_dbus=y'
    require_config_once 'CONFIG_PACKAGE_uhttpd=y'
    require_config_once 'CONFIG_PACKAGE_libuhttpd-openssl=y'
    require_config_once 'CONFIG_PACKAGE_openssl-util=y'
    ! tr -d '\r' < config/ufi003.config | grep -Fx '# CONFIG_PACKAGE_openssl-util is not set'
    ! tr -d '\r' < config/ufi003.config | grep -Fx 'CONFIG_PACKAGE_kmod-hci-uart=y'
    ! tr -d '\r' < config/ufi003.config | grep -Fx 'CONFIG_PACKAGE_kmod-btusb=y'
fi

verify_all_custom_scripts_executable

require_file files/usr/sbin/obdclaw_led_status
require_file files/usr/bin/bluetooth_spp_manager.sh
require_file files/usr/bin/rfcomm_a30m_bind.sh
require_file files/usr/bin/obdclaw_bt_coex_test.sh
require_file files/usr/bin/usb_console_debug.sh
require_file files/usr/bin/obdclaw_local_control_setup.sh
require_file files/usr/bin/obdclaw_runner_authority_install.sh
require_file files/www/cgi-bin/obdclaw-device-identity.cgi
require_file files/www/cgi-bin/obdclaw-control.cgi
require_file files/www/cgi-bin/obdclaw-runner.cgi
require_file files/etc/config/uhttpd
require_file files/etc/config/wireless
require_file files/etc/config/network
require_file files/etc/uci-defaults/92-obdclaw-tls-firewall

require_exec files/etc/init.d/obdclaw_led_status
require_exec files/etc/init.d/usb_acm_console
require_exec files/etc/init.d/bluetooth_spp_service
require_exec files/etc/init.d/rfcomm_a30m
require_exec files/usr/sbin/obdclaw_led_status
require_exec files/usr/bin/bluetooth_spp_manager.sh
require_exec files/usr/bin/rfcomm_a30m_bind.sh
require_exec files/usr/bin/usb_console_debug.sh
require_exec files/etc/init.d/obdclaw_local_control
require_exec files/etc/init.d/obdclaw_uhttpd_watchdog
require_exec files/etc/uci-defaults/92-obdclaw-tls-firewall
require_exec files/usr/bin/obdclaw_local_control_setup.sh
require_exec files/usr/bin/obdclaw_runner_authority_install.sh
require_exec files/www/cgi-bin/obdclaw-device-identity.cgi
require_exec files/www/cgi-bin/obdclaw-control.cgi
require_exec files/www/cgi-bin/obdclaw-runner.cgi

grep -Fq 'set_timer "$red" 700 700' files/usr/sbin/obdclaw_led_status
grep -Fq 'set_timer "$red" 120 120' files/usr/sbin/obdclaw_led_status
grep -Fq 'set_timer "$blue" 120 120' files/usr/sbin/obdclaw_led_status
grep -Fq 'set_timer "$blue" 1000 1000' files/usr/sbin/obdclaw_led_status
/bin/sh "$control_root/scripts/verify_ufi003_sta_profile.sh" --rootfs-root .
grep -Fq 'modprobe btqca' files/usr/bin/bluetooth_spp_manager.sh
grep -Fq 'modprobe btqcomsmd' files/usr/bin/bluetooth_spp_manager.sh
grep -Fq '/etc/init.d/bluetoothd start' files/usr/bin/bluetooth_spp_manager.sh
grep -Fq 'Pairing successful' files/usr/bin/rfcomm_a30m_bind.sh
grep -Fq 'sdptool browse' files/usr/bin/rfcomm_a30m_bind.sh
grep -Fq 'rfcomm -i hci0 connect' files/usr/bin/rfcomm_a30m_bind.sh
grep -Fq "SCAN_COMMAND='scan bredr'" files/usr/bin/rfcomm_a30m_bind.sh
grep -Fq "printf '%s\\n' \"\$SCAN_COMMAND\"" files/usr/bin/rfcomm_a30m_bind.sh
grep -Fq 'emit_vci_status()' files/usr/bin/usb_console_debug.sh
grep -Fq 'emit_sta_status()' files/usr/bin/usb_console_debug.sh
grep -Fq 'sta status' files/usr/bin/usb_console_debug.sh
grep -Fq 'vci target=' files/usr/bin/usb_console_debug.sh
grep -Fq 'vci rfcomm' files/usr/bin/usb_console_debug.sh
grep -Fq '/tmp/rfcomm_a30m_sdp.log' files/usr/bin/usb_console_debug.sh
grep -Fq "list listen_https '0.0.0.0:8443'" files/etc/config/uhttpd
if grep -Eq '^[[:space:]]*(list|option)[[:space:]]+listen_http[[:space:]]' files/etc/config/uhttpd; then
    echo 'unencrypted local control listener found' >&2
    exit 1
fi
grep -Fq 'replayed-token' files/www/cgi-bin/obdclaw-control.cgi
grep -Fq 'unsupported-action' files/www/cgi-bin/obdclaw-control.cgi
grep -Fq 'authorization-not-provisioned' files/www/cgi-bin/obdclaw-runner.cgi
grep -Fq 'replayed-envelope' files/www/cgi-bin/obdclaw-runner.cgi
grep -Fq 'obdclaw.runner-ui.v1' files/www/cgi-bin/obdclaw-runner.cgi
grep -Fq 'undeclared-control' files/www/cgi-bin/obdclaw-runner.cgi
grep -Fq 'stale-frame' files/www/cgi-bin/obdclaw-runner.cgi
grep -Fq '"clockUnix"' files/www/cgi-bin/obdclaw-device-identity.cgi
test -x files/usr/bin/obdclaw_auth_clock
grep -Fq 'obdclaw_auth_clock' files/www/cgi-bin/obdclaw-runner.cgi
grep -Fq 'authority key must be Ed25519' files/usr/bin/obdclaw_runner_authority_install.sh
grep -Fq 'openssl req -x509' files/usr/bin/obdclaw_local_control_setup.sh
grep -Fq '/etc/init.d/obdclaw_local_control start' files/etc/uci-defaults/99-modem-led-status
grep -Fq '/etc/init.d/uhttpd restart' files/etc/uci-defaults/99-modem-led-status
grep -Fq '/etc/init.d/obdclaw_uhttpd_watchdog enable' files/etc/uci-defaults/99-modem-led-status
grep -Fq 'Status: 404 Not Found' files/www/cgi-bin/obdclaw-debug.cgi
grep -Fq "firewall.wifi_sta_control.name='wifi_sta'" files/etc/uci-defaults/92-obdclaw-tls-firewall
grep -Fq "firewall.obdclaw_dev_sidecar_ssh.src='wifi_sta'" files/etc/uci-defaults/92-obdclaw-tls-firewall
grep -Fq "firewall.obdclaw_dev_sidecar_ssh.src_ip='192.168.0.0/24'" files/etc/uci-defaults/92-obdclaw-tls-firewall
grep -Fq "firewall.obdclaw_dev_sidecar_ssh.dest_port='22'" files/etc/uci-defaults/92-obdclaw-tls-firewall
grep -Fq "CONFIG_DEFAULT_dropbear=y" "$control_root/config/ufi003.config"
grep -Fq "uci set dropbear.@dropbear[0].enable='1'" files/etc/uci-defaults/92-obdclaw-tls-firewall
grep -Fq "uci set dropbear.@dropbear[0].Port='22'" files/etc/uci-defaults/92-obdclaw-tls-firewall
grep -Fq '/etc/init.d/dropbear enable' files/etc/uci-defaults/92-obdclaw-tls-firewallgrep -Fq "firewall.obdclaw_tls_control.src_ip='192.168.0.0/24'" files/etc/uci-defaults/92-obdclaw-tls-firewall
grep -Fq "firewall.obdclaw_tls_control.dest_port='8443'" files/etc/uci-defaults/92-obdclaw-tls-firewall
grep -Fq "firewall.obdclaw_tls_control.target='ACCEPT'" files/etc/uci-defaults/92-obdclaw-tls-firewall

if grep -Eq 'hciattach|ttyHS0|ttyMSM1|ttyS1' files/usr/bin/bluetooth_spp_manager.sh; then
    echo 'forbidden UART Bluetooth fallback found' >&2
    exit 1
fi

if grep -Fq '"$bluetoothd_bin" --compat --noplugin=avrcp,network &' files/usr/bin/bluetooth_spp_manager.sh \
    && ! grep -Fq 'OpenWrt BlueZ service is unavailable; using direct fallback.' files/usr/bin/bluetooth_spp_manager.sh; then
    echo 'uncontrolled direct bluetoothd startup found' >&2
    exit 1
fi

if grep -Fq 'ifdown wifi_sta' files/usr/bin/obdclaw_bt_coex_test.sh; then
    echo 'forbidden Wi-Fi STA teardown found' >&2
    exit 1
fi

echo 'SVCI UFI003 source release gate passed.'
