#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_file="${1:-$repo_dir/files/usr/bin/usb_console_debug.sh}"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
assert_contains() {
    grep -Fq "$1" "$2" || { echo "missing expected output: $1" >&2; exit 1; }
}
assert_absent() {
    if grep -Fq "$1" "$2"; then
        echo "syslog feedback found: $1" >&2
        exit 1
    fi
}

# Load only the functions; the service entry point requires a real CDC tty.
eval "$(awk '/^emit\(\)/ { in_functions=1 } /^snapshot$/ { in_functions=0 } in_functions { print }' "$source_file")"
TTY="$scratch/serial"
logger() { printf '%s\n' "$*" >> "$scratch/syslog"; }
logread() {
    printf '%s\n' \
        'daemon.info usb_console_debug: control log prior uhttpd line' \
        'daemon.info uhttpd: real control event' \
        'kernel.info wcnss: real radio event'
}

emit 'heartbeat probe'
emit_control_status
assert_contains 'heartbeat probe' "$scratch/syslog"
assert_contains 'control log daemon.info uhttpd: real control event' "$scratch/serial"
assert_absent 'control log prior' "$scratch/syslog"
assert_absent 'control log daemon.info uhttpd:' "$scratch/syslog"

emit_vci_status() { :; }
emit_control_status() { :; }
snapshot
assert_absent 'log kernel.info wcnss:' "$scratch/syslog"
assert_absent 'log daemon.info usb_console_debug:' "$scratch/syslog"
printf '%s\n' 'usb_console_debug syslog feedback regression passed'
