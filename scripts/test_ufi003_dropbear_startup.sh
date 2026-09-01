#!/bin/sh
# Guards the first-boot Dropbear listener required by the scoped sidecar path.
set -eu

root="${1:-.}"
config="$root/files/etc/config/dropbear"
defaults="$root/files/etc/uci-defaults/99-modem-led-status"

[ -f "$config" ] || { echo "missing Dropbear configuration: $config" >&2; exit 1; }
[ -x "$defaults" ] || { echo "missing executable first-boot defaults: $defaults" >&2; exit 1; }

[ "$(grep -c '^config dropbear$' "$config")" -eq 1 ] || {
    echo 'Dropbear configuration must define exactly one listener instance' >&2
    exit 1
}
grep -Fq "option enable '1'" "$config"
grep -Fq "option Port '22'" "$config"
grep -Fq '/etc/init.d/dropbear enable' "$defaults"
grep -Fq '/etc/init.d/dropbear start' "$defaults"
grep -Fq "firewall.obdclaw_dev_sidecar_ssh.src_ip='192.168.0.0/24'" \
    "$root/files/etc/uci-defaults/92-obdclaw-tls-firewall"
grep -Fq "firewall.obdclaw_dev_sidecar_ssh.dest_port='22'" \
    "$root/files/etc/uci-defaults/92-obdclaw-tls-firewall"
if grep -Eq 'dropbear\.@dropbear\[0\]\.(DirectInterface|Interface)' \
    "$root/files/etc/uci-defaults/92-obdclaw-tls-firewall"; then
    echo 'Dropbear must not bind directly to wifi_sta' >&2
    exit 1
fi

echo 'UFI003 Dropbear startup tests passed.'
