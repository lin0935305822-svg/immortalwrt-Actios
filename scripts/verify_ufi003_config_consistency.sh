#!/bin/sh
# Reject contradictory package choices before an expensive firmware build.
set -eu

config_file="${1:?usage: verify_ufi003_config_consistency.sh <.config>}"
[ -f "$config_file" ] || { echo "missing config: $config_file" >&2; exit 1; }

awk '
  { sub(/\r$/, "") }
  /^CONFIG_PACKAGE_/ && index($0, "=") {
    split($0, fields, "=")
    symbol = fields[1]
    state = "set=" fields[2]
  }
  $1 == "#" && $2 ~ /^CONFIG_PACKAGE_/ && $3 == "is" && $4 == "not" && $5 == "set" {
    symbol = $2
    state = "unset"
  }
  symbol != "" {
    if (states[symbol] != "" && states[symbol] != state) {
      printf "conflicting package config: %s (%s, %s)\n", symbol, states[symbol], state > "/dev/stderr"
      failed = 1
    }
    states[symbol] = state
    symbol = ""
  }
  END { exit failed }
' "$config_file"

grep -Fx 'CONFIG_PACKAGE_dropbear=y' "$config_file"
