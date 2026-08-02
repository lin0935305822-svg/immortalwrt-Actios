#!/bin/sh

TTY=/dev/ttyGS0

[ -c "$TTY" ] || exit 1
stty -F "$TTY" 115200 cs8 -cstopb -parenb -echo 2>/dev/null || true

emit() {
    printf '%s\r\n' "$*" > "$TTY"
    logger -t usb_console_debug "$*"
}

emit_vci_status() {
    target_mac="$(uci -q get bluetooth_a30m.settings.target_mac 2>/dev/null || true)"
    emit "vci target=${target_mac:-unconfigured}"
    hciconfig hci0 2>/dev/null | while IFS= read -r line; do emit "vci hci $line"; done
    if [ -n "$target_mac" ]; then
        bluetoothctl info "$target_mac" 2>/dev/null | \
            grep -E 'Name:|Paired:|Trusted:|Connected:|UUID:' | \
            while IFS= read -r line; do emit "vci bluez $line"; done
    fi
    rfcomm -a 2>/dev/null | while IFS= read -r line; do emit "vci rfcomm $line"; done
    tail -n 12 /tmp/rfcomm_a30m.log 2>/dev/null | while IFS= read -r line; do emit "vci bind $line"; done
    tail -n 8 /tmp/rfcomm_a30m_sdp.log 2>/dev/null | while IFS= read -r line; do emit "vci sdp $line"; done
    tail -n 8 /tmp/rfcomm_a30m_connect.log 2>/dev/null | while IFS= read -r line; do emit "vci connect $line"; done
}

emit_sta_status() {
    status="$(ubus call network.interface.wifi_sta status 2>/dev/null || true)"
    if [ -n "$status" ]; then
        printf '%s\n' "$status" | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g' | \
            while IFS= read -r line; do emit "sta status $line"; done
    else
        emit 'sta status unavailable'
    fi
}

snapshot() {
    emit '=== SVCI MSM8916 runtime debug ==='
    emit "time=$(date -Iseconds 2>/dev/null || date)"
    emit "kernel=$(uname -a)"
    emit "root=$(findmnt -n -o SOURCE / 2>/dev/null || true)"
    ip -br addr 2>/dev/null | while IFS= read -r line; do emit "ip $line"; done
    iw dev 2>/dev/null | while IFS= read -r line; do emit "iw $line"; done
    ubus call network.wireless status 2>/dev/null | tr '\n' ' ' | while IFS= read -r line; do emit "wireless $line"; done
    rfkill list 2>/dev/null | while IFS= read -r line; do emit "rfkill $line"; done
    emit_vci_status
    logread 2>/dev/null | grep -Ei 'wcnss|wlan|wifi|ath|qca|bluetooth|usb_acm|ttyGS' | tail -n 40 | while IFS= read -r line; do emit "log $line"; done
    emit '=== debug snapshot end ==='
}

snapshot
while sleep 30; do
    emit_sta_status
    emit_vci_status
    emit "heartbeat $(date -Iseconds 2>/dev/null || date)"
done
