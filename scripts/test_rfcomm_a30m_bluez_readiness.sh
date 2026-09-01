#!/bin/sh
# Exercises the BlueZ D-Bus readiness barrier before an A30M pairing attempt.
set -eu

root="${1:-.}"
script="$root/files/usr/bin/rfcomm_a30m_bind.sh"
manager="$root/files/usr/bin/bluetooth_spp_manager.sh"
[ -x "$script" ] || { echo "RFCOMM manager is not executable: $script" >&2; exit 1; }
[ -x "$manager" ] || { echo "Bluetooth SPP manager is not executable: $manager" >&2; exit 1; }

# BlueZ discovers adapters when it starts. WCNSS hci0 must therefore be
# initialized before the first service launch, not only in the later loop.
hci_setup_line="$(grep -n '^setup_wcnss_hci || true$' "$manager" | head -n 1 | cut -d: -f1)"
bluez_start_line="$(grep -n '^start_bluez || true$' "$manager" | head -n 1 | cut -d: -f1)"
case "$hci_setup_line:$bluez_start_line" in
    *[!0-9:]*|:*|*:) echo 'Bluetooth startup ordering markers are missing' >&2; exit 1 ;;
esac
[ "$hci_setup_line" -lt "$bluez_start_line" ] || {
    echo 'BlueZ must start after WCNSS hci0 initialization' >&2
    exit 1
}

temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT HUP INT TERM
mkdir -p "$temp/bin"

cat > "$temp/bin/bluetoothctl" <<'EOF'
#!/bin/sh
if [ "${1:-}" = show ]; then
    previous="$(cat "$TEST_SHOW_COUNT" 2>/dev/null || printf '0')"
    current=$((previous + 1))
    printf '%s\n' "$current" > "$TEST_SHOW_COUNT"
    if [ "$current" -ge "$TEST_READY_AFTER" ]; then
        printf '%s\n' 'Controller 00:11:22:33:44:55 OBDclaw-410'
        exit 0
    fi
    printf '%s\n' 'Waiting to connect to bluetoothd...' >&2
    exit 1
fi
printf '%s\n' "$*" >> "$TEST_COMMAND_LOG"
EOF

cat > "$temp/bin/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$temp/bin"/*

RFCOMM_A30M_LIBRARY_ONLY=1 . "$script"
log() {
    printf '%s\n' "$*" >> "$TEST_LOG"
}

show_count="$temp/show-count"
command_log="$temp/commands"
test_log="$temp/test.log"
: > "$command_log"
: > "$test_log"
TEST_SHOW_COUNT="$show_count"
TEST_COMMAND_LOG="$command_log"
TEST_LOG="$test_log"
PATH="$temp/bin:$PATH"
export TEST_SHOW_COUNT TEST_COMMAND_LOG TEST_LOG PATH

TEST_READY_AFTER=3
BLUEZ_READY_TIMEOUT_SECONDS=5
export TEST_READY_AFTER
bluez_control_ready
[ "$(cat "$show_count")" = 3 ] || { echo 'BlueZ readiness did not wait for the controller' >&2; exit 1; }
grep -Fq 'BlueZ control interface became ready after 2s.' "$test_log"

rm -f "$show_count"
TEST_READY_AFTER=99
BLUEZ_READY_TIMEOUT_SECONDS=2
export TEST_READY_AFTER
if bluez_control_ready; then
    echo 'BlueZ readiness accepted an unavailable controller' >&2
    exit 1
fi
grep -Fq 'did not become ready within 2s.' "$test_log"

bluez_control_ready() { return 1; }
is_paired() { echo 'is_paired reached before BlueZ readiness' >&2; return 1; }
: > "$command_log"
if pair_device 'C4:65:4D:9D:09:34'; then
    echo 'pair_device proceeded without BlueZ readiness' >&2
    exit 1
fi
[ ! -s "$command_log" ] || { echo 'pair_device issued bluetoothctl commands before BlueZ readiness' >&2; exit 1; }

echo 'RFCOMM BlueZ readiness tests passed.'
