#!/bin/sh
# A30M Bluetooth RFCOMM Automatic Pair & Serial Port Binding Service

LOG_TAG="rfcomm_a30m"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$LOG_TAG] $*" | tee -a /tmp/rfcomm_a30m.log
}

get_config() {
    uci get bluetooth_a30m.settings."$1" 2>/dev/null || echo "$2"
}

ENABLED="$(get_config enabled 1)"
if [ "$ENABLED" -ne 1 ]; then
    log "A30M RFCOMM service is disabled in UCI configuration."
    exit 0
fi

TARGET_MAC="$(get_config target_mac '')"
PIN_CODE="$(get_config pin '1234')"
RFCOMM_DEV_INDEX="$(get_config rfcomm_dev '0')"
RFCOMM_NODE="/dev/rfcomm${RFCOMM_DEV_INDEX}"

# 等待 hci0 就绪
while ! hciconfig hci0 2>/dev/null | grep -q "UP RUNNING"; do
    log "Waiting for Bluetooth adapter hci0 to be UP..."
    sleep 3
done

# 如果未指定 MAC 地址，尝试自动扫描匹配 'A30M' 的设备
scan_for_a30m() {
    log "Scanning for A30M Bluetooth device..."
    local found_mac
    found_mac="$(hcitool scan 2>/dev/null | awk '/A30M/ {print $1; exit}')"
    if [ -n "$found_mac" ]; then
        log "Discovered A30M device at MAC: $found_mac"
        echo "$found_mac"
    else
        echo ""
    fi
}

# 绑定逻辑
do_rfcomm_bind() {
    local mac="$1"
    if [ -z "$mac" ]; then
        return 1
    fi

    # 检查是否已挂载
    if [ -c "$RFCOMM_NODE" ]; then
        log "$RFCOMM_NODE already exists."
        return 0
    fi

    log "Attempting RFCOMM bind $RFCOMM_DEV_INDEX -> $mac (Channel 1)..."
    
    # 配对/设置 PIN 码支持 (BlueZ 5 / simple agent)
    if command -v bluetoothctl >/dev/null 2>&1; then
        echo -e "power on\nagent on\ndefault-agent\npair $mac\ntrust $mac\nconnect $mac\nquit" | bluetoothctl >/dev/null 2>&1 || true
    fi

    rfcomm bind "$RFCOMM_DEV_INDEX" "$mac" 1 2>/dev/null || true
    sleep 1

    if [ -c "$RFCOMM_NODE" ]; then
        log "Successfully bound $mac to $RFCOMM_NODE!"
        return 0
    else
        log "RFCOMM bind failed for MAC $mac."
        return 1
    fi
}

log "Starting A30M RFCOMM daemon..."

while true; do
    CURRENT_MAC="$TARGET_MAC"
    if [ -z "$CURRENT_MAC" ]; then
        CURRENT_MAC="$(scan_for_a30m)"
    fi

    if [ -n "$CURRENT_MAC" ]; then
        do_rfcomm_bind "$CURRENT_MAC" || true
    else
        log "No A30M device found yet. Retrying scan..."
    fi

    sleep 10
done
