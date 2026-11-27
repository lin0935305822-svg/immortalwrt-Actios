#!/bin/sh
# Inspect the taskset entry inside an unmounted ext4 image. BusyBox applet
# links are normally mode 0777; only their final regular target is executable.
set -eu
image="${1:?usage: verify_ufi003_taskset_image.sh <raw ext4 image>}"
test -f "$image"
fail() { echo "::error::$*" >&2; exit 1; }
stat_inode() { debugfs -R "stat $1" "$image" 2>&1; }
inode_type() { sed -n 's/.*Type: *\([^ ]*\).*/\1/p'; }
inode_mode() { sed -n 's/.*Mode: *\([0-7]*\).*/\1/p'; }
require_regular_exec() {
    details="$(stat_inode "$1")" || fail "Cannot inspect $1"
    type="$(printf '%s\n' "$details" | inode_type)"
    mode="$(printf '%s\n' "$details" | inode_mode)"
    test "$type" = regular || fail "$1 must be a regular executable (type=${type:-missing})"
    case "$mode" in
        0755|0100755) ;;
        *) fail "$1 must have mode 0755 (mode=${mode:-missing})" ;;
    esac
}
details="$(stat_inode /usr/bin/taskset)" || fail 'Cannot inspect /usr/bin/taskset'
type="$(printf '%s\n' "$details" | inode_type)"
case "$type" in
    regular) require_regular_exec /usr/bin/taskset ;;
    symlink)
        target="$(printf '%s\n' "$details" | sed -n 's/^Fast link dest: "\(.*\)"$/\1/p')"
        case "$target" in
            ../../bin/busybox|/bin/busybox) ;;
            *) fail "Unexpected taskset symlink target: ${target:-unreadable}" ;;
        esac
        require_regular_exec /bin/busybox
        ;;
    *) fail "Missing or unsupported /usr/bin/taskset inode: ${type:-missing}" ;;
esac
echo 'rootfs executable verified: /usr/bin/taskset (regular 0755 or verified BusyBox link)'
