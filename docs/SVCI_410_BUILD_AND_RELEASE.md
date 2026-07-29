# SVCI 410 Build And Release Procedure

## Authority

This is the source-controlled procedure for MSM8916 / UFI003 SVCI 410 builds.
The release repository is:

```text
https://github.com/lin0935305822-svg/immortalwrt-Actios.git
```

Build only the `ufi003` profile. GitHub Actions is the authoritative release
build. Local Windows/WSL work is limited to review, focused validation,
artifact handling, and device flashing.

## Network

The workstation and production 410 connect to the TP-Link LAN. GitHub traffic
must leave the workstation through `WLAN`; Android USB/RNDIS is not a release
network dependency and must not be used for publishing.

Before publishing, verify the active route:

```powershell
Test-NetConnection github.com -Port 443 -InformationLevel Detailed
```

The result must show `InterfaceAlias : WLAN` and the TP-Link gateway
`192.168.0.1`. If RNDIS is selected, an administrator must give `WLAN` a lower
interface metric. Do not disable the CDC ACM COM device while changing routes.

If direct Git smart-HTTP is unstable but an approved local SOCKS5 service is
already listening on `127.0.0.1:2801`, use it per command only:

```powershell
$env:ALL_PROXY = 'socks5h://127.0.0.1:2801'
git -C D:\SVCI\410\immortalwrt-Actios ls-remote origin
git -C D:\SVCI\410\immortalwrt-Actios push origin main
Remove-Item Env:ALL_PROXY
```

Never save a proxy in Git configuration, the repository, firmware, or Wi-Fi
settings. Do not switch to phone tethering for releases.

## Review And Publish

```powershell
$repo = 'D:\SVCI\410\immortalwrt-Actios'
git -C $repo remote -v
git -C $repo fetch origin main
git -C $repo status --short --branch
git -C $repo diff --check
git -C $repo diff --stat
& 'C:\Program Files\Git\bin\bash.exe' scripts/run_ufi003_preflight.sh .
```

`origin` must be `lin0935305822-svg/immortalwrt-Actios.git`, never the `x7780`
fork. Review intended files before staging; run focused tests; make small,
coherent commits. Publish and verify synchronization:

```powershell
git -C $repo push origin main
git -C $repo fetch origin main
git -C $repo status --short --branch
```

A release starts only from a clean working tree with local `main` synchronized
to `origin/main`.

## Cloud Build

The 410 workflow is manual (`workflow_dispatch`), so a push does not build
firmware by itself. In GitHub Actions choose the 410 build workflow and use:

| Input | Value |
| --- | --- |
| Branch | `main` at the published release commit |
| Profile | `ufi003` |
| Upstream | `lkiuyu/immortalwrt` |
| SSH debug | `false` |
| Custom hash | empty, unless reviewed |
| Extra packages | empty, unless reviewed |

The newest Actions run must report a `head_sha` equal to the release commit.
If a newer commit is pushed, cancel the older queued/running build and dispatch
a new UFI003 run. Accept only `completed/success`; normal duration is 45 to
120 minutes.

## Artifacts And Flash Gate

Download `boot.img` and rootfs/system image from the same successful run.
Record run URL, full commit SHA, file names, download time, and SHA-256 in the
release manifest. Never combine artifacts from different runs or flash a
failed/cancelled/outdated build.

For flashing and recovery, follow the repository-independent local runbook at
`D:\SVCI\410\SVCI_410_CANONICAL_RUNBOOK.md`. The mandatory rules are:

1. The device partitions are `boot` and `rootfs`, not `rootfs_data`.
2. Flash rootfs as one Fastboot transaction: `fastboot flash rootfs system.img`.
3. Never erase/write EFS, calibration, `modemst1`, `modemst2`, or `fsg`.
4. Production is TP-Link STA; `RECOVERY_AP=1` is recovery-only.
5. CDC ACM diagnostics stay enabled; COM number is assigned by Windows.
6. Accept a Bluetooth build only after STA DHCP, WCNSS `hci0`, `bluetoothd`,
   and RFCOMM/SPP checks pass.

The production profile disables Dropbear and Android adb. It enables the
HTTPS-only uhttpd listener on port 8443 for the authenticated mobile-control
API. Do not add HTTP, network shell, web script upload, or unauthenticated
maintenance paths as a release shortcut.

## Verified Core Freeze

Once a core path has passed physical acceptance, it is frozen by default.
Core paths are boot/rootfs flashing, protected partition exclusions, Wi-Fi STA,
LED status, CDC ACM diagnostics, WCNSS Bluetooth, and A30M RFCOMM pairing. A
change requires a concrete defect or requirement change, documented affected
invariants, focused source/image checks, and a new physical acceptance record.
Do not replace a proven path with a cleanup, refactor, generic fallback, or
unverified alternative.

## LED Contract

The red LED is the communication-status indicator, not a normally-off fault
lamp. With `wifi_sta` connected it must use a 700 ms on/off cadence; when the
station is disconnected it must use a 120 ms on/off cadence. The blue LED
indicates Wi-Fi activity: 120 ms on/off while traffic changes and 1000 ms
on/off while idle. A release fails acceptance if the LED daemon is absent or
not executable.

## Final Checklist

```text
[ ] GitHub route is TP-Link WLAN, not phone RNDIS.
[ ] origin is the specified SVCI repository.
[ ] Intended changes are reviewed, tested, committed, pushed, and clean.
[ ] Workflow policy and all three source gates pass before cloud dispatch.
[ ] UFI003 Actions head SHA equals the release commit.
[ ] UFI003 Actions is completed/success.
[ ] boot and rootfs/system images are from that same run and hash-verified.
[ ] Only boot/rootfs are flashed; rootfs is written as one Fastboot transaction
    (`fastboot flash rootfs system.img`), never with `-S 64m`.
[ ] COM, STA DHCP, WCNSS Bluetooth, and SPP acceptance pass.
```
