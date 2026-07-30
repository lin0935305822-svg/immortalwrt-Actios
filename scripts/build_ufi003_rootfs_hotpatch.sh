#!/usr/bin/env bash
# Build a disposable UFI003 rootfs test image from a verified release image.
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage: build_ufi003_rootfs_hotpatch.sh <verified-system.img> <output-system.img>

The input image is never modified. Run this only in Linux/WSL with loop-mount
permission. The result is for physical validation only, not release upload.
EOF
    exit 2
}

[[ $# -eq 2 ]] || usage

input_image="$1"
output_image="$2"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
overlay="$repo_root/files"

[[ -f "$input_image" ]] || { echo "input image does not exist: $input_image" >&2; exit 1; }
[[ -d "$overlay" ]] || { echo "missing rootfs overlay: $overlay" >&2; exit 1; }
[[ "$(realpath "$input_image")" != "$(realpath -m "$output_image")" ]] || {
    echo 'input and output image must differ' >&2; exit 1;
}

for command in simg2img img2simg e2fsck mount umount sha256sum realpath tar; do
    command -v "$command" >/dev/null || { echo "missing required command: $command" >&2; exit 1; }
done

if [[ $EUID -eq 0 ]]; then
    SUDO=()
else
    command -v sudo >/dev/null || { echo 'root or sudo is required for loop mount' >&2; exit 1; }
    sudo -v
    SUDO=(sudo)
fi

bash "$repo_root/scripts/run_ufi003_preflight.sh" "$repo_root"

# Do not let a development patch reopen a management path excluded by release policy.
if grep -R -n -E "^[[:space:]]*(list|option)[[:space:]]+listen_http[[:space:]]|^[[:space:]]*option[[:space:]]+dest_port[[:space:]]+'?80'?([[:space:]]|$)" "$overlay"; then
    echo 'refusing hot-patch overlay that enables HTTP port 80' >&2
    exit 1
fi

output_dir="$(dirname "$(realpath -m "$output_image")")"
mkdir -p "$output_dir"
output_image="$(realpath -m "$output_image")"
[[ ! -e "$output_image" ]] || { echo "refusing to overwrite existing output: $output_image" >&2; exit 1; }
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/svci-ufi003-hotpatch.XXXXXX")"
raw_image="$work_dir/system.raw.img"
mount_dir="$work_dir/rootfs"
manifest="$output_image.manifest"
mounted=0

cleanup() {
    if [[ $mounted -eq 1 ]]; then
        "${SUDO[@]}" umount "$mount_dir" || true
    fi
    rm -rf "$work_dir"
}
trap cleanup EXIT

echo '[1/5] Convert verified sparse image to raw ext4'
simg2img "$input_image" "$raw_image"

mkdir -p "$mount_dir"
echo '[2/5] Mount temporary rootfs image'
"${SUDO[@]}" mount -o loop,rw "$raw_image" "$mount_dir"
mounted=1

echo '[3/5] Apply checked-in rootfs overlay'
# -a preserves the explicit executable bits that OpenWrt copies into rootfs.
"${SUDO[@]}" cp -a "$overlay/." "$mount_dir/"
sync
"${SUDO[@]}" umount "$mount_dir"
mounted=0

echo '[4/5] Check ext4 and create sparse output'
set +e
"${SUDO[@]}" e2fsck -fy "$raw_image"
fsck_status=$?
set -e
[[ $fsck_status -le 2 ]] || { echo "e2fsck failed: $fsck_status" >&2; exit "$fsck_status"; }

echo '[4.5/5] Verify the patched rootfs contract'
"${SUDO[@]}" mount -o loop,ro "$raw_image" "$mount_dir"
mounted=1
for required_path in \
    etc/init.d/obdclaw_local_control \
    etc/init.d/obdclaw_uhttpd_watchdog \
    usr/bin/obdclaw_local_control_setup.sh \
    www/cgi-bin/obdclaw-device-identity.cgi \
    www/cgi-bin/obdclaw-control.cgi \
    www/cgi-bin/obdclaw-runner.cgi; do
    [[ -x "$mount_dir/$required_path" ]] || { echo "rootfs executable missing: $required_path" >&2; exit 1; }
done
grep -Fq "list listen_https '0.0.0.0:8443'" "$mount_dir/etc/config/uhttpd"
if grep -Eq '^[[:space:]]*(list|option)[[:space:]]+listen_http[[:space:]]' "$mount_dir/etc/config/uhttpd"; then
    echo 'patched rootfs contains an HTTP listener' >&2
    exit 1
fi
if grep -Eq "^[[:space:]]*option[[:space:]]+dest_port[[:space:]]+'?80'?([[:space:]]|$)" "$mount_dir/etc/config/firewall"; then
    echo 'patched rootfs exposes HTTP port 80 through firewall' >&2
    exit 1
fi
"${SUDO[@]}" umount "$mount_dir"
mounted=0
img2simg "$raw_image" "$output_image"

echo '[5/5] Record immutable test-image provenance'
{
    printf 'base_image_sha256='
    sha256sum "$input_image" | awk '{print $1}'
    printf 'hotpatch_image_sha256='
    sha256sum "$output_image" | awk '{print $1}'
    printf 'source_commit='
    git -C "$repo_root" rev-parse HEAD
    printf 'overlay_sha256='
    tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -C "$overlay" -cf - . | sha256sum | awk '{print $1}'
    if test -n "$(git -C "$repo_root" status --porcelain)"; then
        printf 'source_tree=dirty\n'
    else
        printf 'source_tree=clean\n'
    fi
    printf 'created_utc='
    date -u +%Y-%m-%dT%H:%M:%SZ
} > "$manifest"

echo "hot-patch image: $output_image"
echo "provenance: $manifest"
