#!/bin/sh
set -eu
root="${1:-.}"
cd "$root"
exec python3 scripts/test_wcn36xx_scan_band_guard.py --root .
