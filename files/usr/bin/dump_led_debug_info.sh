#!/bin/sh

active_trigger() {
    sed -n 's/.*\[\(.*\)\].*/\1/p' "$1/trigger" 2>/dev/null
}

dt_node_name() {
    tr -d '\000' < "$1/device/of_node/name" 2>/dev/null || true
}

echo "=== LED Debug Snapshot ==="
echo "uptime: $(cut -d. -f1 /proc/uptime 2>/dev/null)s"

echo ""
echo "=== 1. UCI LED Configuration ==="
uci -q show system 2>/dev/null | grep -E '^system\..*=led|^system\..*\.(sysfs|trigger|delayon|delayoff|dev|mode)=' || true

echo ""
echo "=== 2. sysfs LED Parameters ==="
for d in /sys/class/leds/*; do
    [ -d "$d" ] || continue
    echo "--- Node: ${d##*/} ---"
    echo "  dt_node:   $(dt_node_name "$d")"
    echo "  trigger:   $(cat "$d/trigger" 2>/dev/null)"
    echo "  active:    $(active_trigger "$d")"
    echo "  delay_on:  $(cat "$d/delay_on" 2>/dev/null)"
    echo "  delay_off: $(cat "$d/delay_off" 2>/dev/null)"
    echo "  brightness: $(cat "$d/brightness" 2>/dev/null)"
done

echo ""
echo "=== 3. LED Startup Order ==="
ls -l /etc/rc.d/S96led /etc/rc.d/S99blue_led_fix /etc/rc.d/S??blue_timer_guard 2>/dev/null || true

echo ""
echo "=== 4. Related Running Processes ==="
ps | grep -iE 'led|timer|wlan' | grep -v grep

echo ""
echo "=== 5. Recent LED Events ==="
logread 2>/dev/null | grep -E 'led_status|blue_led_fix' | tail -n 80 || true

echo ""
echo "=== 6. Explicit State Control ==="
echo "normal: /usr/bin/svci_led_state normal"
echo "fault:  /usr/bin/svci_led_state fault"
