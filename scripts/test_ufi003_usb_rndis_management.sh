#!/bin/sh
# Regression coverage for the physical USB deployment transport.
set -eu

root="${1:-.}"
cd "$root"

acm='files/etc/init.d/usb_acm_console'
rndis='files/etc/init.d/usb_rndis_gadget'
dhcp='files/etc/config/dhcp'
firewall='files/etc/uci-defaults/92-obdclaw-tls-firewall'

grep -Fq 'GADGET_DIR="/sys/kernel/config/usb_gadget/g1"' "$acm"
! grep -Fq '/etc/init.d/usb_rndis_gadget stop' "$acm"
grep -Fq '/etc/init.d/usb_rndis_gadget start' "$acm"
grep -Fq 'functions/rndis.usb0' "$acm"
grep -Fq 'functions/acm.GS0' "$acm"
grep -Fq 'RNDIS + CDC ACM Console' "$acm"
grep -Fq "config dhcp 'usb_rndis'" "$dhcp"
grep -Fq "option interface 'usb_rndis'" "$dhcp"
grep -Fq "option ipaddr '192.168.41.2'" files/etc/config/network
grep -Fq "firewall.usb_rndis_control.name='usb_rndis'" "$firewall"
grep -Fq "firewall.usb_rndis_ssh.src='usb_rndis'" "$firewall"
grep -Fq "firewall.usb_rndis_ssh.src_ip='192.168.41.0/24'" "$firewall"
grep -Fq "firewall.usb_rndis_ssh.dest_port='22'" "$firewall"
grep -Fq "firewall.obdclaw_tls_control.dest_port='8443'" "$firewall"

echo 'UFI003 USB RNDIS management regression passed.'
