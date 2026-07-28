#!/bin/sh
# MSM8916 WCNSS SMD Bluetooth HCI initializer and Classic SPP manager.

LOG_TAG='bt_spp_manager'
LOCAL_BT_NAME='OBDclaw-410'

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$LOG_TAG] $*" | tee -a /tmp/bluetooth_spp.log
}

if ! pgrep -x dbus-daemon >/dev/null; then
    log 'Starting D-Bus.'
    /etc/init.d/dbus start 2>/dev/null || true
    sleep 1
fi

start_bluez() {
    if pgrep -x bluetoothd >/dev/null; then
        return 0
    fi

    # bluez-daemon owns its D-Bus name through OpenWrt's init service.  A
    # second manually spawned daemon cannot acquire that name and prevents
    # the SPP manager from pairing reliably.
    if [ -x /etc/init.d/bluetooth ]; then
        log 'Starting BlueZ through the OpenWrt service.'
        /etc/init.d/bluetooth start 2>/dev/null || true
    else
        log 'OpenWrt BlueZ service is unavailable; using direct fallback.'
        bluetoothd_bin="$(command -v bluetoothd 2>/dev/null || true)"
        if [ -n "$bluetoothd_bin" ]; then
            "$bluetoothd_bin" --compat --noplugin=avrcp,network &
        else
            log 'bluetoothd is not installed.'
            return 1
        fi
    fi

    retry=0
    while [ "$retry" -lt 10 ]; do
        pgrep -x bluetoothd >/dev/null && return 0
        sleep 1
        retry=$((retry + 1))
    done

    log 'BlueZ did not become ready.'
    return 1
}

start_bluez || true

# This board exposes Bluetooth through Qualcomm WCNSS SMD. It is not a UART
# or USB HCI device. Do not attach arbitrary serial ports because that cannot
# initialize the board radio and can consume a console device.
setup_wcnss_hci() {
    if hciconfig hci0 2>/dev/null | grep -q 'UP RUNNING\|DOWN'; then
        return 0
    fi

    log 'Loading Qualcomm WCNSS SMD Bluetooth modules.'
    modprobe btqca 2>/dev/null || true
    modprobe btqcomsmd 2>/dev/null || true

    retry=0
    while [ "$retry" -lt 15 ]; do
        if hciconfig hci0 >/dev/null 2>&1; then
            log 'WCNSS SMD created hci0.'
            return 0
        fi
        sleep 2
        retry=$((retry + 1))
    done

    log 'WCNSS SMD did not create hci0; no UART or USB fallback is permitted.'
    return 1
}

while true; do
    setup_wcnss_hci || true

    if hciconfig hci0 >/dev/null 2>&1; then
        hciconfig hci0 up 2>/dev/null || true
        hciconfig hci0 name "$LOCAL_BT_NAME" 2>/dev/null || true
        hciconfig hci0 piscan 2>/dev/null || true
        hciconfig hci0 noauth noencrypt 2>/dev/null || true

        if ! sdptool browse local 2>/dev/null | grep -i 'Serial Port' >/dev/null; then
            log 'Registering local Classic Bluetooth SPP profile.'
            sdptool add --channel=1 SP 2>/dev/null || true
        fi
    fi

    sleep 10
done
