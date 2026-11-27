# WCN36xx scan RX NULL dereference

The reproduced failure is in the WCN36xx RX interrupt path on a 2.4 GHz-only
WCN3620 using backports 6.18.26 with Linux 6.12.85. A temporary exception
notifier captured a NULL read in `wcn36xx_rx_skb()` with the survey update
inlined. The active wiphy advertises only the 2.4 GHz band.

## Fault mechanism

In `drivers/net/wireless/ath/wcn36xx/txrx.c`, scan-learn descriptors are mapped
to 5 GHz when `rf_band != 1` and the encoded channel is within the 5 GHz map.
The condition does not check whether this radio supports 5 GHz. On WCN3620,
initialization leaves `wiphy->bands[NL80211_BAND_5GHZ]` NULL.

`wcn36xx_update_survey()` then executes:

```c
sband = wcn->hw->wiphy->bands[band];
channel = sband->channels;
```

The captured fault instruction is a read through the NULL `sband` pointer.
In the deployed stripped module it is `_25+0x308/0x5dc`, instruction
`ldr x1, [x2]`. The surrounding instructions load band 1 and index the wiphy
band array before reading its `channels` pointer. The instruction sequence and
mac80211 RX calls match the inlined survey update in `wcn36xx_rx_skb()`.
The ARM64 exception occurs in IRQ context and its normal die path calls panic.

This identifies the driver failure for the captured reboot. It does not prove
why the firmware descriptor reported that band, nor that every other possible
device reset has this cause. The scan sender was separately observed as
wpa_supplicant with a 300-second interval.

## Fix and validation status

`wcn36xx-scan-band-guard.patch` checks the registered 5 GHz capability before
using that channel map and rejects an unsupported band before the survey and
mac80211 RX handoff. The patch applies to the SHA-256-verified backports 6.18.26
archive. The workflow stages it only for the UFI003 ramoops diagnostic build.

The source patch check and repository preflight pass. A fixed firmware has not
yet been built or physically accepted: GitHub workflow dispatch is returning
HTTP422 stating that Actions is disabled despite enabled/active settings APIs.
This patch is not a claimed production fix until a successful diagnostic build
and physical scan/STA/Bluetooth acceptance establish that result.

Raw crash logs, module hashes and disassembly remain outside Git in the local
diagnostic evidence directory.
