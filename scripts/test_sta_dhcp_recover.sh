#!/bin/sh
# Exercises the bounded STA DHCP recovery policy with fake OpenWrt commands.
set -eu

root="${1:-.}"
script="$root/files/usr/bin/sta_dhcp_recover.sh"
[ -x "$script" ] || { echo "STA recovery script is not executable" >&2; exit 1; }

temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
mkdir -p "$temp/bin"

cat > "$temp/bin/logger" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$TEST_LOG"
EOF
cat > "$temp/bin/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$temp/bin/iw" <<'EOF'
#!/bin/sh
[ "$TEST_ASSOCIATED" = 1 ] && printf '%s\n' 'Connected to 34:ce:00:10:9f:03 (on phy0-sta0)'
EOF
cat > "$temp/bin/ubus" <<'EOF'
#!/bin/sh
if [ "$1" = call ] && [ "$2" = network.interface.wifi_sta ] && [ "$3" = renew ]; then
    printf 'ubus %s\n' "$*" >> "$TEST_LOG"
    [ "$TEST_RENEW_SUCCEEDS" = 1 ] && : > "$TEST_LEASE"
    exit 0
fi
if [ -f "$TEST_LEASE" ]; then
    printf '%s\n' '{"ipv4-address":[{"address":"192.168.0.200"}]}'
else
    printf '%s\n' '{"ipv4-address":[]}'
fi
EOF
chmod +x "$temp/bin"/*

run_case() {
    name="$1"
    associated="$2"
    leased="$3"
    renew_succeeds="$4"
    expected="$5"
    log="$temp/$name.log"
    lease="$temp/$name.lease"
    rm -f "$lease"
    [ "$leased" = 1 ] && : > "$lease"
    TEST_LOG="$log" TEST_LEASE="$lease" TEST_ASSOCIATED="$associated" TEST_RENEW_SUCCEEDS="$renew_succeeds" PATH="$temp/bin:$PATH" /bin/sh "$script"
    actual="$(grep -E '^ubus ' "$log" 2>/dev/null || true)"
    [ "$actual" = "$expected" ] || { echo "$name: unexpected recovery commands: $actual" >&2; exit 1; }
}

run_case associated_without_lease 1 0 1 'ubus call network.interface.wifi_sta renew'
run_case associated_renew_without_lease 1 0 0 'ubus call network.interface.wifi_sta renew'
run_case associated_with_lease 1 1 1 ''
run_case unassociated 0 0 1 ''

init_script="$root/files/etc/init.d/sta_dhcp_recover"
[ -x "$init_script" ] || { echo "STA recovery init script is not executable" >&2; exit 1; }
grep -Fq '/bin/sh /usr/bin/sta_dhcp_recover.sh' "$init_script"
if grep -Eq 'respawn|procd_' "$init_script"; then
    echo 'STA recovery init script must be one-shot and must not respawn' >&2
    exit 1
fi

echo 'STA DHCP recovery tests passed.'
