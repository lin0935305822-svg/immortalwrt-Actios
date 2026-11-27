# Pinned WCN36xx regression input

`drivers/net/wireless/ath/wcn36xx/txrx.c` is the unmodified file from OpenWrt
backports 6.18.26. Its original copyright and permission notice are retained.

- Archive SHA-256: `2ad578c6cae22f192fefd44e1449725228d4109ee781998b41dcbae872554968`.
- File SHA-256: `5749ed7fdc588e398e040f99b28b2ec995a363bd4a7e76ed5c89b18876236bd7`.

The regression gate applies the real source patch to this file, extracts the
actual band-selection and survey code, and supplies small userspace substitutes
for kernel types and unrelated helpers. It reproduces the old NULL dereference
in an isolated userspace child, then checks the fixed 2.4 GHz cases, retained
5 GHz mapping, and unsupported-band rejection. It does not replace firmware
compilation or physical STA/Bluetooth acceptance. Run it in Linux or WSL with
Python 3, a C compiler and `patch`.
