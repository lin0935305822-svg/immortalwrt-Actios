#!/bin/sh
# Run one controlled Bluetooth discovery pass with Wi-Fi temporarily disabled.

LOG_DIR=/tmp/obdclaw
LOG_FILE=$LOG_DIR/bt_coexistence_test.log
TARGET_MAC='C4:65:4D:9D:09:34'
RESTORED=0

log() {
    line="[$(date '+%Y-%m-%d %H:%M:%S')] [bt_coex_test] $*"
    echo "$line" | tee -a "$LOG_FILE"
    logger -t bt_coex_test "$*"
}

[ "$(uci -q get bluetooth_a30m.settings.coexistence_test)" = 1 ] || exit 0

restore_services() {
    [ "$RESTORED" = 1 ] && return
    ifup wifi_sta >/dev/null 2>&1 || true
    sleep 5
    /etc/init.d/rfcomm_a30m start >/dev/null 2>&1 || true
    RESTORED=1
}

trap restore_services EXIT INT TERM

scan_window() {
    label="$1"
    scan_log="/tmp/bt_coexistence_${label}.log"

    log "Starting 25-second Bluetooth scan with ${label}."
    {
        echo "=== bluetoothctl scan: ${label} ==="
        printf 'power on\n'
        printf 'scan on\n'
        sleep 25
        printf 'scan off\n'
        printf 'devices\n'
        printf 'quit\n'
    } | bluetoothctl >"$scan_log" 2>&1

    cat "$scan_log" >>"$LOG_FILE" 2>/dev/null || true
    echo "=== Target state after ${label} ===" >>"$LOG_FILE"
    bluetoothctl info "$TARGET_MAC" >>"$LOG_FILE" 2>&1 || true
}

mkdir -p "$LOG_DIR"
: >"$LOG_FILE"
log 'Waiting for normal boot before the one-time coexistence test.'
sleep 60

log 'Stopping RFCOMM daemon for controlled Wi-Fi/BT A/B scan.'
/etc/init.d/rfcomm_a30m stop >/dev/null 2>&1 || true
echo '=== Wi-Fi state before A/B test ===' >>"$LOG_FILE"
ubus call network.interface.wifi_sta status >>"$LOG_FILE" 2>&1 || true
scan_window wifi_sta_up

log 'Disabling wifi_sta for matching Bluetooth scan.'
ifdown wifi_sta >/dev/null 2>&1 || log 'wifi_sta was already down.'
sleep 5
scan_window wifi_sta_down

log 'Restoring wifi_sta and normal RFCOMM discovery.'
restore_services
uci set bluetooth_a30m.settings.coexistence_test='0'
uci commit bluetooth_a30m
log 'Coexistence test complete. Results are retained in overlay storage.'
