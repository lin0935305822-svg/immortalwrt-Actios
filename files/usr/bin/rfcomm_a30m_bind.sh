#!/bin/sh
# Discover, pair, and connect an A30M Classic SPP device.

LOG_TAG='rfcomm_a30m'

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$LOG_TAG] $*" | tee -a /tmp/rfcomm_a30m.log >&2
}

get_config() {
    uci get bluetooth_a30m.settings."$1" 2>/dev/null || echo "$2"
}

[ "$(get_config enabled 1)" = 1 ] || exit 0

TARGET_MAC="$(get_config target_mac '')"
RFCOMM_DEV_INDEX="$(get_config rfcomm_dev 0)"
RFCOMM_NODE="/dev/rfcomm${RFCOMM_DEV_INDEX}"
SCAN_TRANSPORT="$(get_config scan_transport bredr)"
SPP_UUID='00001101-0000-1000-8000-00805f9b34fb'

while ! hciconfig hci0 2>/dev/null | grep -q 'UP RUNNING'; do
    log 'Waiting for Bluetooth adapter hci0 to be UP.'
    sleep 3
done

scan_for_a30m() {
    hcitool scan 2>/dev/null | awk '/A30M/ {print $1; exit}'
}

is_connected() {
    rfcomm -a 2>/dev/null | grep -q "rfcomm${RFCOMM_DEV_INDEX}.*connected"
}

is_paired() {
    bluetoothctl info "$1" 2>/dev/null | grep -Eq 'Paired:[[:space:]]+yes'
}

is_trusted() {
    bluetoothctl info "$1" 2>/dev/null | grep -Eq 'Trusted:[[:space:]]+yes'
}

trust_device() {
    mac="$1"
    is_trusted "$mac" && return 0
    printf 'trust %s\nquit\n' "$mac" | bluetoothctl >/tmp/rfcomm_a30m_trust.log 2>&1
    is_trusted "$mac"
}

pair_device() {
    mac="$1"
    if is_paired "$mac"; then
        trust_device "$mac" || log "Could not mark paired device $mac as trusted."
        log "$mac has a confirmed BlueZ bond."
        return 0
    fi

    log "Pairing $mac with SSP Just Works over $SCAN_TRANSPORT."
    pair_output="$(
        {
            printf 'power on\n'
            printf 'agent NoInputNoOutput\n'
            printf 'default-agent\n'
            # BlueZ only accepts a pairing request for a current device
            # object. Discover and pair in the same bluetoothctl session.
            printf 'scan on\n'
            sleep 10
            printf 'pair %s\n' "$mac"
            # Some A30M units finish pairing after discovery has stopped;
            # give bluetoothd enough time to complete the BR/EDR transaction.
            sleep 20
            printf 'trust %s\n' "$mac"
            sleep 2
            printf 'scan off\n'
            printf 'quit\n'
        } | bluetoothctl 2>&1
    )"
    printf '%s\n' "$pair_output" > /tmp/rfcomm_a30m_pair.log
    log "Pair transcript: $(printf '%s' "$pair_output" | tr '\n' ' ' | cut -c1-320)"

    # The scan transcript can contain LE events for unrelated devices. A
    # successful pairing response for this target is authoritative, even if
    # BlueZ drops the transient device object before a second info query.
    if printf '%s\n' "$pair_output" | grep -q 'Pairing successful'; then
        trust_device "$mac" || log "Could not mark newly paired device $mac as trusted."
        log "$mac pairing completed during the discovery session."
        return 0
    fi

    # BlueZ can omit the asynchronous pairing completion line when the peer
    # stops discovery, while still accepting trust for the current device.
    # A successful trust operation proves that BlueZ has retained this target
    # and is sufficient to continue with SDP/RFCOMM.
    if printf '%s\n' "$pair_output" | grep -Fq "Changing $mac trust succeeded"; then
        log "$mac accepted trust during the discovery session; attempting SPP."
        return 0
    fi

    if is_paired "$mac"; then
        trust_device "$mac" || log "Could not mark newly paired device $mac as trusted."
        log "$mac pairing confirmed by BlueZ."
        return 0
    fi

    if printf '%s\n' "$pair_output" | grep -qi 'AlreadyExists'; then
        # This target can drop its transient device object between daemon
        # cycles even though the BR/EDR bond is valid. Try SPP before making
        # any destructive change to the local pairing state.
        log "BlueZ reported an existing pairing for $mac; attempting SPP with it."
        return 0
    fi

    log "Pairing was not confirmed for $mac."
    return 1
}

connect_spp() {
    mac="$1"
    sdp_output="$(sdptool browse "$mac" 2>&1 || true)"
    printf '%s\n' "$sdp_output" > /tmp/rfcomm_a30m_sdp.log
    rfcomm_channel="$(printf '%s\n' "$sdp_output" | awk '
        /Service Name:/ { serial_port=0; class_list=0 }
        /Service Class ID List:/ { class_list=1; next }
        /Protocol Descriptor List:/ { class_list=0 }
        class_list && /0x1101/ { serial_port=1 }
        serial_port && /Channel:[[:space:]]*[0-9]+/ { print $2; exit }
    ')"
    case "$rfcomm_channel" in
        ''|*[!0-9]*)
            log "SPP SDP lookup did not return an RFCOMM channel for $mac."
            return 1
            ;;
    esac

    : > /tmp/rfcomm_a30m_connect.log
    log "Opening insecure RFCOMM SPP connection $RFCOMM_NODE -> $mac (SDP channel $rfcomm_channel)."
    rfcomm release "$RFCOMM_DEV_INDEX" >/dev/null 2>&1 || true
    sleep 1
    # Match CloudDiag's createInsecureRfcommSocketToServiceRecord path.
    rfcomm -i hci0 connect "$RFCOMM_NODE" "$mac" "$rfcomm_channel" >>/tmp/rfcomm_a30m_connect.log 2>&1 &
    connect_pid=$!
    sleep 5

    if is_connected; then
        log "SPP connection verified: $mac is connected on $RFCOMM_NODE."
        return 0
    fi

    # rfcomm connect remains in the foreground while it owns a transport.
    # A failed pending attempt must be stopped before the next daemon cycle.
    if kill -0 "$connect_pid" 2>/dev/null; then
        log "RFCOMM is still pending after 5 seconds; stopping stale attempt."
        kill "$connect_pid" 2>/dev/null || true
        wait "$connect_pid" 2>/dev/null || true
    fi

    log "RFCOMM connection was not established for $mac on SDP channel $rfcomm_channel."
    return 1
}

log 'Starting A30M RFCOMM daemon.'
while true; do
    CURRENT_MAC="$TARGET_MAC"
    [ -n "$CURRENT_MAC" ] || CURRENT_MAC="$(scan_for_a30m)"

    if [ -z "$CURRENT_MAC" ]; then
        log 'No A30M device address is available. Retrying later.'
    elif is_connected; then
        log "$RFCOMM_NODE is already connected."
    elif pair_device "$CURRENT_MAC"; then
        connect_spp "$CURRENT_MAC" || true
    fi

    sleep 30
done
