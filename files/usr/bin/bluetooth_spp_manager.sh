#!/bin/sh
# Bluetooth HCI Initializer & SPP Manager Service
# Supporting UART HCI with USB Bluetooth Adapter Fallback

LOG_TAG="bt_spp_manager"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$LOG_TAG] $*" | tee -a /tmp/bluetooth_spp.log
}

# 1. 确保 D-Bus 与 BlueZ bluetoothd 运行
if ! pgrep -x dbus-daemon >/dev/null; then
    log "Starting dbus service..."
    /etc/init.d/dbus start 2>/dev/null || true
    sleep 1
fi

if ! pgrep -x bluetoothd >/dev/null; then
    log "Starting bluetoothd daemon..."
    /usr/libexec/bluetooth/bluetoothd --compat --noplugin=avrcp,network &
    sleep 2
fi

# 2. 板载 UART HCI 与 USB 适配器回退拉起流程
setup_hci_interface() {
    if hciconfig hci0 2>/dev/null | grep -q "UP RUNNING\|DOWN"; then
        log "HCI interface hci0 already detected."
        return 0
    fi

    log "Searching for onboard UART Bluetooth node..."
    # 尝试高通板载 UART 节点（如 /dev/ttyHS0 /dev/ttyMSM1 /dev/ttyS1）
    for tty_dev in /dev/ttyHS0 /dev/ttyMSM1 /dev/ttyS1; do
        if [ -c "$tty_dev" ]; then
            log "Found UART node $tty_dev, running hciattach..."
            hciattach -s 115200 "$tty_dev" any 115200 2>/dev/null || \
            hciattach -s 115200 "$tty_dev" qca 115200 2>/dev/null || true
            sleep 2
            if hciconfig hci0 >/dev/null 2>&1; then
                log "Successfully attached onboard UART Bluetooth to hci0!"
                return 0
            fi
        fi
    done

    log "Onboard UART HCI not available. Falling back to USB Bluetooth adapter..."
    # USB 适配器回退逻辑：等待由 kmod-bluetooth-hci-usb / btusb 生成的 hci0
    retry=0
    while [ $retry -lt 5 ]; do
        if hciconfig hci0 >/dev/null 2>&1; then
            log "USB Bluetooth adapter hci0 detected!"
            return 0
        fi
        sleep 2
        retry=$((retry + 1))
    done

    log "Warning: No hci0 device found (neither UART nor USB)."
    return 1
}

# 主循环守护
while true; do
    setup_hci_interface || true

    if hciconfig hci0 >/dev/null 2>&1; then
        # 激活 hci0 并设置为可搜索/配对 (PISCAN)
        hciconfig hci0 up 2>/dev/null || true
        hciconfig hci0 piscan 2>/dev/null || true
        hciconfig hci0 auth encrypt 2>/dev/null || true

        # 注册 Classic Bluetooth SPP (Serial Port Profile)
        if ! sdptool browse local 2>/dev/null | grep -i "Serial Port" >/dev/null; then
            log "Registering Classic Bluetooth SPP service profile via sdptool..."
            sdptool add --channel=1 SP 2>/dev/null || true
        fi
    fi

    sleep 10
done
