#!/bin/sh
# Recover the STA DHCP client once per boot only after Layer-2 association.
set -u

INTERFACE='wifi_sta'
WIRELESS_DEVICE='phy0-sta0'
MAX_WAIT_SECONDS=45
POLL_SECONDS=3
LOG_TAG='sta_dhcp_recover'

log() {
    logger -t "$LOG_TAG" "$*"
}

status_json() {
    ubus call "network.interface.$INTERFACE" status 2>/dev/null || true
}

has_ipv4() {
    status_json | grep -q '"ipv4-address"[[:space:]]*:[[:space:]]*\[[[:space:]]*{'
}

is_associated() {
    iw dev "$WIRELESS_DEVICE" link 2>/dev/null | grep -q '^Connected to '
}

elapsed=0
while [ "$elapsed" -lt "$MAX_WAIT_SECONDS" ]; do
    if is_associated; then
        if has_ipv4; then
            log 'STA is associated and has an IPv4 lease; recovery not needed.'
            exit 0
        fi
        break
    fi

    sleep "$POLL_SECONDS"
    elapsed=$((elapsed + POLL_SECONDS))
done

if ! is_associated; then
    log "STA was not associated after ${MAX_WAIT_SECONDS}s; no recovery attempted."
    exit 0
fi

if has_ipv4; then
    log 'STA acquired an IPv4 lease before recovery; recovery not needed.'
    exit 0
fi

log 'STA is associated but has no IPv4 lease; performing one interface DHCP recovery.'
ifdown "$INTERFACE"
sleep 2
ifup "$INTERFACE"
sleep "$POLL_SECONDS"

if has_ipv4; then
    log 'STA DHCP recovery obtained an IPv4 lease.'
else
    log 'STA DHCP recovery completed without an IPv4 lease; no further retries this boot.'
fi
