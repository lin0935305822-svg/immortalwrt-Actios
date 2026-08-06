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
if [ -f "$TEST_LEASE" ]; then
    printf '%s\n' '{"ipv4-address":[{"address":"192.168.0.200"}]}'
else
    printf '%s\n' '{"ipv4-address":[]}'
fi
EOF
cat > "$temp/bin/ifdown" <<'EOF'
#!/bin/sh
printf 'ifdown %s\n' "$1" >> "$TEST_LOG"
EOF
cat > "$temp/bin/ifup" <<'EOF'
#!/bin/sh
printf 'ifup %s\n' "$1" >> "$TEST_LOG"
: > "$TEST_LEASE"
EOF
chmod +x "$temp/bin"/*

run_case() {
    name="$1"
    associated="$2"
    leased="$3"
    expected="$4"
    log="$temp/$name.log"
    lease="$temp/$name.lease"
    rm -f "$lease"
    [ "$leased" = 1 ] && : > "$lease"
    TEST_LOG="$log" TEST_LEASE="$lease" TEST_ASSOCIATED="$associated" PATH="$temp/bin:$PATH" /bin/sh "$script"
    actual="$(grep -E '^(ifdown|ifup) ' "$log" 2>/dev/null || true)"
    [ "$actual" = "$expected" ] || { echo "$name: unexpected recovery commands: $actual" >&2; exit 1; }
}

run_case associated_without_lease 1 0 'ifup wifi_sta'
run_case associated_with_lease 1 1 ''
run_case unassociated 0 0 ''

init_script="$root/files/etc/init.d/sta_dhcp_recover"
[ -x "$init_script" ] || { echo "STA recovery init script is not executable" >&2; exit 1; }
grep -Fq '/bin/sh /usr/bin/sta_dhcp_recover.sh' "$init_script"
if grep -Eq 'respawn|procd_' "$init_script"; then
    echo 'STA recovery init script must be one-shot and must not respawn' >&2
    exit 1
fi

echo 'STA DHCP recovery tests passed.'
