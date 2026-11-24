#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
service="$repo_dir/files/etc/init.d/obdclaw_bt_coex_test"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT HUP INT TERM

. "$service"
uci() { printf '%s\n' "$coexistence_test"; }
procd_open_instance() { printf 'open %s\n' "$*" >> "$scratch/calls"; }
procd_set_param() { printf 'param %s\n' "$*" >> "$scratch/calls"; }
procd_close_instance() { printf 'close\n' >> "$scratch/calls"; }

coexistence_test=0
start_service
[ ! -e "$scratch/calls" ] || { echo 'disabled test spawned' >&2; exit 1; }

coexistence_test=1
start_service
grep -Fxq 'open obdclaw_bt_coex_test' "$scratch/calls"
grep -Fxq 'param command /bin/sh /usr/bin/obdclaw_bt_coex_test.sh' "$scratch/calls"
grep -Fxq 'close' "$scratch/calls"
if grep -Fq 'param respawn' "$scratch/calls"; then
    echo 'one-shot test configured to respawn' >&2
    exit 1
fi

printf '%s\n' 'Bluetooth coexistence one-shot service regression passed'
