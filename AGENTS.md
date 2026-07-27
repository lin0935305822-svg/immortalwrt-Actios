# SVCI UFI003 Release Rules

These rules apply to every automated agent and human change in this repository.
They are release requirements, not suggestions.

1. The target board uses Qualcomm WCNSS SMD Bluetooth. Use `btqca` and
   `btqcomsmd`; do not add UART `hciattach` or USB Bluetooth fallback.
2. Wi-Fi STA and Bluetooth must coexist. Production code must not call
   `ifdown wifi_sta` for Bluetooth scanning, pairing, or testing.
3. The red LED is the STA communication indicator: 700 ms on/off while
   connected and 120 ms on/off while disconnected. The blue LED indicates
   traffic: 120 ms on/off active and 1000 ms on/off idle.
4. All custom init, UCI-default, hotplug, user-bin, user-sbin, and CGI scripts
   must be executable in the final rootfs. A source edit is not accepted until
   the Actions image gate proves this.
5. Do not publish or flash firmware until source checks, image checks, and
   physical acceptance pass. Physical acceptance requires CDC ACM diagnostics,
   STA connectivity, `hci0`, `bluetoothd`, A30M pairing, SDP, and RFCOMM.
6. Never erase or write EFS, calibration, `modemst1`, `modemst2`, `fsc`, or
   `fsg`. Normal firmware flashing writes only `boot` and `rootfs`.
7. Do not treat a successful compiler exit as a release result. The release
   commit, Actions run, artifact hashes, and acceptance report must match.
