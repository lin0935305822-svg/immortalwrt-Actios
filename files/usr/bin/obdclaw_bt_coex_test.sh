#!/bin/sh
# Opt-in coexistence observation. Wi-Fi STA must remain connected throughout.

LOG_DIR=/tmp/obdclaw
LOG_FILE=$LOG_DIR/bt_coexistence_test.log
TARGET_MAC='C4:65:4D:9D:09:34'

log() {
    line="[$(date '+%Y-%m-%d %H:%M:%S')] [bt_coex_test] $*"
    echo "$line" | tee -a "$LOG_FILE"
    logger -t bt_coex_test "$*"
}

[ "$(uci -q get bluetooth_a30m.settings.coexistence_test)" = 1 ] || exit 0

scan_window() {
    log 'Starting 25-second Bluetooth scan while Wi-Fi STA remains enabled.'
    {
        printf 'power on\n'
        printf 'scan on\n'
        sleep 25
        printf 'scan off\n'
        printf 'devices\n'
        printf 'quit\n'
    } | bluetoothctl > /tmp/bt_coexistence_scan.log 2>&1

    cat /tmp/bt_coexistence_scan.log >> "$LOG_FILE" 2>/dev/null || true
    bluetoothctl info "$TARGET_MAC" >> "$LOG_FILE" 2>&1 || true
}

mkdir -p "$LOG_DIR"
: > "$LOG_FILE"
log 'Waiting for normal boot before the opt-in coexistence observation.'
sleep 60
echo '=== Wi-Fi state before discovery ===' >> "$LOG_FILE"
ubus call network.interface.wifi_sta status >> "$LOG_FILE" 2>&1 || true
scan_window
echo '=== Wi-Fi state after discovery ===' >> "$LOG_FILE"
ubus call network.interface.wifi_sta status >> "$LOG_FILE" 2>&1 || true
log 'Coexistence observation complete; Wi-Fi STA was never disabled.'
uci set bluetooth_a30m.settings.coexistence_test='0'
uci commit bluetooth_a30m
