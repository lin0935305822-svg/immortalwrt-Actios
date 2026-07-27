#!/bin/sh

TTY=/dev/ttyGS0

[ -c "$TTY" ] || exit 1
stty -F "$TTY" 115200 cs8 -cstopb -parenb -echo 2>/dev/null || true

emit() {
    printf '%s\r\n' "$*" > "$TTY"
    logger -t usb_console_debug "$*"
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
    logread 2>/dev/null | grep -Ei 'wcnss|wlan|wifi|ath|qca|bluetooth|usb_acm|ttyGS' | tail -n 40 | while IFS= read -r line; do emit "log $line"; done
    emit '=== debug snapshot end ==='
}

snapshot
while sleep 30; do
    emit "heartbeat $(date -Iseconds 2>/dev/null || date)"
done
