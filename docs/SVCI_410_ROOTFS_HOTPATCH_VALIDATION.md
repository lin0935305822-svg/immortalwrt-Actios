# SVCI 410 Rootfs Hot-Patch Validation

Use this procedure before an expensive cloud firmware build when a change is
limited to files under `files/` and does not change the kernel, boot image,
partition table, Wi-Fi firmware, Bluetooth firmware, or boot chain.

The procedure creates a disposable test rootfs from a previously successful
UFI003 release image, applies the reviewed rootfs overlay, and flashes only
the `rootfs` partition. It is a development validation path, not a production
release artifact.

## Preconditions

1. Start from a release ZIP whose SHA-256 has been verified.
2. Run source gates before making a hot-patch image:

```sh
scripts/run_ufi003_preflight.sh .
```

3. Record the source commit and the base release artifact digest.
4. Do not use this path for boot, kernel, firmware, package-selection, or
   partition changes. Those require a cloud build.

## Image Construction

On the local Linux/WSL image toolchain, use the checked-in builder; it runs
all source gates, rejects an overlay that enables HTTP port 80, converts the
base `system.img` to raw ext4, overlays `files/` while preserving modes, runs
`e2fsck`, then creates a new Android sparse image and provenance manifest.

```sh
sudo scripts/build_ufi003_rootfs_hotpatch.sh \
  /path/to/verified/system.img \
  /path/to/new-directory/system-hotpatch.img
```

The output directory must be new. Never overwrite a verified release image.

## Device Validation

1. Put UFI003 in Fastboot using the canonical 9008 recovery path if needed.
2. Verify `fastboot getvar product` returns `LK1ST_MSM8916`.
3. Flash only the patched rootfs:

```powershell
fastboot erase rootfs
fastboot flash rootfs system-hotpatch.img
fastboot reboot
```

Never use `-S 64m`: the UFI003 target resets after the third sparse fragment.
Never write `boot`, EFS, modemst1, modemst2, fsc, fsg, calibration, or
userdata in this validation path.

## Acceptance

Capture COM12 for at least 60 seconds and require all of the following:

- TP-LINK STA has a DHCP lease;
- WCNSS `hci0` is `UP RUNNING`;
- `/dev/rfcomm0` is connected to the configured VCI;
- the HTTPS device identity endpoint responds from a non-isolated client;
- HTTP port 80 is unavailable.

Only after this acceptance passes may the same commit trigger one final cloud
UFI003 build. Download and flash only artifacts from that final successful run.
