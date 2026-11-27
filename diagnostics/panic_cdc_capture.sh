#!/bin/sh
# Diagnostic-only live panic capture; kernel and transport run on separate CPUs.
tty=/dev/ttyGS0
[ -c "$tty" ] || exit 0
[ -x /usr/bin/taskset ] || exit 0
grep -qE '(^|,)3($|,)|(^|-)3($|,)' /sys/devices/system/cpu/online || exit 0

irq=$(awk '/ci_hdrc_msm/ {sub(/:$/, "", $1); print $1; exit}' /proc/interrupts)
case "$irq" in
    ''|*[!0-9]*) exit 0 ;;
esac
[ -w "/proc/irq/$irq/smp_affinity_list" ] || exit 0
if ! printf '3\n' > "/proc/irq/$irq/smp_affinity_list"; then
    printf 'PANIC_CDC_CAPTURE_ERROR irq_affinity\r\n' > "$tty"
    exit 0
fi
affinity=$(cat "/proc/irq/$irq/smp_affinity_list")
printf 'PANIC_CDC_CAPTURE irq=%s cpu=%s reader_cpu=3\r\n' "$irq" "$affinity" > "$tty"

exec /usr/bin/taskset -c 3 /bin/sh -c '
    cat /dev/kmsg | while IFS= read -r line; do
        printf "KMSG %s\r\n" "$line"
    done
' > "$tty" 2>/dev/null
