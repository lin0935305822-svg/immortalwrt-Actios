#!/bin/sh
# Diagnostic build only: export retained pstore records on the existing CDC ACM stream.

tty=/dev/ttyGS0
store=/sys/fs/pstore
[ -c "$tty" ] || exit 0

# Windows may enumerate COM6 after the gadget node appears. The host collector
# is already running before reboot and opens the port as soon as it appears.
sleep 20

printf 'PSTORE_EXPORT_BEGIN version=1\r\n' > "$tty"
if ! grep -q " $store " /proc/mounts; then
    mount -t pstore -o ro pstore "$store" 2>/dev/null || true
fi
if ! grep -q " $store " /proc/mounts; then
    printf 'PSTORE_EXPORT_ERROR mount_failed\r\n' > "$tty"
    exit 0
fi

dmesg 2>/dev/null | grep -Ei 'ramoops|pstore' | tail -n 20 | while IFS= read -r line; do
    printf 'PSTORE_INIT %s\r\n' "$line" > "$tty"
done

found=0
for file in "$store"/*; do
    [ -f "$file" ] || continue
    found=1
    name=${file##*/}
    bytes=$(wc -c < "$file" | tr -d ' ')
    printf 'PSTORE_FILE_BEGIN name=%s bytes=%s encoding=base64\r\n' "$name" "$bytes" > "$tty"
    if /usr/bin/openssl base64 -A -in "$file" > "$tty" 2>/dev/null; then
        printf '\r\nPSTORE_FILE_END name=%s status=ok\r\n' "$name" > "$tty"
    else
        printf '\r\nPSTORE_FILE_END name=%s status=error\r\n' "$name" > "$tty"
    fi
done
[ "$found" -eq 1 ] || printf 'PSTORE_EMPTY\r\n' > "$tty"
printf 'PSTORE_EXPORT_END\r\n' > "$tty"
