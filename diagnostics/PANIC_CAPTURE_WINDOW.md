# Live panic capture for the UFI003 diagnostic image

The verified ramoops backend registers successfully, but both a scan-adjacent
reboot and a controlled warm reboot left pstore empty. Persistent DDR capture
has not been established on this boot chain. Live SSH diagnostics also showed
USB IRQ 38 and WCN36xx IRQs 54/55 all executing on CPU0.

When `ramoops_diag=true`, the build now applies a kernel patch to wait 10 seconds
after printing the panic message/initial stack and before stopping the other
CPUs. The faulting CPU keeps IRQs and preemption disabled. A rootfs helper puts
the `ci_hdrc_msm` USB IRQ and the `/dev/kmsg` to CDC reader on CPU3, so another CPU
has a chance to send the log while the faulting CPU waits. The standard panic
shutdown then resumes. The marker is `UFI003_DIAG_CAPTURE`.

This deliberately changes panic shutdown timing. It is a diagnostic experiment,
not a driver fix or a production configuration. It may fail if the fault stops
the bus, the USB CPU also panics, or locks prevent the reader from progressing.
Only a captured stack will establish the failing path. The boot/rootfs pair
must come from this successful diagnostic run; its vmlinux must contain the
capture marker, and the rootfs must contain executable helper and taskset.

Ordinary builds do not install this kernel patch or helper. Revoke the temporary
workstation SSH key when the investigation ends as described in
`SSH_DIAGNOSTIC_ACCESS.md`.
