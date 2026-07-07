#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="${VPN_CONFIG_PATH:-/var/lib/vpn-control/config.json}"
STATE_FILE="/var/lib/vpn-control/install-state.json"
VERSION_FILE="${VPN_VERSION_PATH:-/opt/vpn-control/VERSION}"
WITH_FAILOVER=false
ORIGINAL_CONNECTED=false
VPN_USER=""
COUNTRY=""

if [[ "${1:-}" == "--with-failover" ]]; then
    WITH_FAILOVER=true
elif [[ -n "${1:-}" ]]; then
    echo "Usage: sudo bash scripts/smoke-test.sh [--with-failover]" >&2
    exit 2
fi

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo: sudo bash scripts/smoke-test.sh [--with-failover]" >&2
    exit 1
fi

pass_count=0
fail_count=0

pass() {
    printf 'PASS  %s\n' "$*"
    pass_count=$((pass_count + 1))
}

fail() {
    printf 'FAIL  %s\n' "$*" >&2
    fail_count=$((fail_count + 1))
}

check() {
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        pass "$description"
    else
        fail "$description"
    fi
}

nordvpn_as_user() {
    runuser -u "$VPN_USER" -- nordvpn "$@"
}

dns_probe() {
    local server="$1"
    local timeout_seconds="${2:-4}"
    local query_name="${3:-example.com}"
    local mode="${4:-answer}"

    python3 - "$server" "$timeout_seconds" "$query_name" "$mode" <<'PY'
import random
import socket
import struct
import sys

server = sys.argv[1]
timeout = float(sys.argv[2])
query_name = sys.argv[3].rstrip(".")
mode = sys.argv[4]

labels = query_name.split(".")
encoded_labels = [label.encode("idna") for label in labels]
if not encoded_labels or any(not label or len(label) > 63 for label in encoded_labels):
    raise SystemExit(2)

transaction_id = random.randint(0, 65535)
header = struct.pack("!HHHHHH", transaction_id, 0x0100, 1, 0, 0, 0)
question = b"".join(bytes([len(label)]) + label for label in encoded_labels)
question += b"\x00" + struct.pack("!HH", 1, 1)
packet = header + question

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(timeout)
sock.sendto(packet, (server, 53))
response, _ = sock.recvfrom(4096)
if len(response) < 12:
    raise SystemExit(1)

response_id, flags, _, answers, _, _ = struct.unpack("!HHHHHH", response[:12])
is_response = bool(flags & 0x8000)
rcode = flags & 0x000F

if response_id != transaction_id or not is_response:
    raise SystemExit(1)

if mode == "upstream":
    # NOERROR (0) and NXDOMAIN (3) are normal authoritative/resolver results.
    # SERVFAIL (2), REFUSED (5), or a timeout are local failure outcomes and
    # therefore count as fail-closed rather than as evidence of DNS leakage.
    raise SystemExit(0 if rcode in {0, 3} else 1)

if mode == "answer" and rcode == 0 and answers >= 1:
    raise SystemExit(0)

raise SystemExit(1)
PY
}

restore_vpn() {
    if [[ "$WITH_FAILOVER" == "true" && "$ORIGINAL_CONNECTED" == "true" ]]; then
        printf '\nRestoring NordVPN connection to %s...\n' "$COUNTRY"
        nordvpn_as_user connect "$COUNTRY" >/dev/null 2>&1 || true
    fi
}
trap restore_vpn EXIT

for command_name in awk curl date grep ip jq nft python3 runuser sleep sysctl systemctl tr; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "Missing required command: $command_name" >&2
        exit 1
    }
done

[[ -r "$CONFIG_FILE" ]] || {
    echo "Runtime configuration not readable: $CONFIG_FILE" >&2
    exit 1
}
[[ -r "$VERSION_FILE" ]] || {
    echo "Installed VERSION file not readable: $VERSION_FILE" >&2
    exit 1
}

EXPECTED_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
[[ -n "$EXPECTED_VERSION" ]] || {
    echo "Installed VERSION file is empty: $VERSION_FILE" >&2
    exit 1
}

LAN_IP="$(jq -r '.lan_ip' "$CONFIG_FILE")"
LAN_IF="$(jq -r '.lan_if' "$CONFIG_FILE")"
VPN_IF="$(jq -r '.vpn_if // "nordlynx"' "$CONFIG_FILE")"
ROUTE_TABLE="$(jq -r '.route_table // 200' "$CONFIG_FILE")"
DNS_PRIORITY="$(jq -r '.dns_rule_priority // 9999' "$CONFIG_FILE")"
COUNTRY="$(jq -r '.country // "gr"' "$CONFIG_FILE")"
DEVICE_COUNT="$(jq '.devices | length' "$CONFIG_FILE")"
EXPECTED_RULES=$((DEVICE_COUNT + 1))

if [[ -r "$STATE_FILE" ]]; then
    VPN_USER="$(jq -r '.vpn_user // empty' "$STATE_FILE")"
fi
if [[ -z "$VPN_USER" ]]; then
    VPN_USER="$(systemctl show vpn-control-web.service --property=User --value)"
fi
[[ -n "$VPN_USER" ]] || {
    echo "Could not determine the NordVPN service user." >&2
    exit 1
}

printf 'VPN Control %s smoke test\n' "$EXPECTED_VERSION"
printf 'Gateway: %s (%s), devices: %s, country: %s\n\n' \
    "$LAN_IP" "$LAN_IF" "$DEVICE_COUNT" "$COUNTRY"

check "tv-vpn-gateway.service is active" systemctl is-active --quiet tv-vpn-gateway.service
check "vpn-control-dns.service is active" systemctl is-active --quiet vpn-control-dns.service
check "vpn-control-web.service is active" systemctl is-active --quiet vpn-control-web.service
check "NordVPN reports Connected" sh -c "runuser -u '$VPN_USER' -- nordvpn status | grep -q '^Status: Connected'"
check "$VPN_IF has an IPv4 address" sh -c "ip -4 address show dev '$VPN_IF' | grep -q '^[[:space:]]*inet '"
check "IPv4 forwarding is enabled" test "$(sysctl -n net.ipv4.ip_forward)" = "1"
check "Fail-closed blackhole route exists" sh -c "ip -4 route show table '$ROUTE_TABLE' | grep -q '^blackhole default'"
check "VPN default route exists" sh -c "ip -4 route show table '$ROUTE_TABLE' | grep -q '^default dev $VPN_IF'"
check "nftables forwarding table exists" nft list table inet tv_vpn
check "nftables NAT table exists" nft list table ip tv_vpn_nat
check "DNS UID policy rule exists" sh -c "ip -4 rule show | grep -q '^${DNS_PRIORITY}:.*uidrange.*lookup ${ROUTE_TABLE}'"

actual_rules="$(
    ip -4 rule show |
        awk -v table="$ROUTE_TABLE" '$0 ~ ("lookup " table "$") {count++} END {print count+0}'
)"
if [[ "$actual_rules" -eq "$EXPECTED_RULES" ]]; then
    pass "Policy-rule count is ${actual_rules}/${EXPECTED_RULES}"
else
    fail "Policy-rule count is ${actual_rules}/${EXPECTED_RULES}"
fi

if jq -e --arg version "$EXPECTED_VERSION" '
    .version == $version and
    (.status == "healthy" or .status == "fail-closed") and
    .fail_closed_present == true and
    .nft_filter_present == true and
    .nft_nat_present == true and
    .dns_service_active == true and
    .dns_rule_present == true
' /run/vpn-control/gateway-health.json >/dev/null 2>&1; then
    pass "Gateway heartbeat is current and protected"
else
    fail "Gateway heartbeat is missing or degraded"
fi

check "Local DNS proxy resolves through gateway" dns_probe "$LAN_IP" 5 example.com answer
check "Web panel responds with authentication challenge" \
    sh -c "test \"\$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 'http://${LAN_IP}:8080/')\" = 401"

if [[ "$WITH_FAILOVER" == "true" ]]; then
    if nordvpn_as_user status | grep -q '^Status: Connected'; then
        ORIGINAL_CONNECTED=true
    fi

    # Use unique names so dnsmasq cannot satisfy the checks from its cache.
    # A normal upstream result is NOERROR or NXDOMAIN. Local SERVFAIL/REFUSED
    # after disconnect is an expected fail-closed result.
    baseline_probe="vpn-control-before-$(date +%s%N)-$$.example.com"
    blocked_probe="vpn-control-after-$(date +%s%N)-$$.example.com"
    check "Uncached DNS probe reaches upstream before disconnect" \
        dns_probe "$LAN_IP" 5 "$baseline_probe" upstream

    printf '\nRunning failover test: disconnecting NordVPN...\n'
    nordvpn_as_user disconnect >/dev/null
    sleep 8

    if dns_probe "$LAN_IP" 3 "$blocked_probe" upstream >/dev/null 2>&1; then
        fail "Uncached DNS query reached an upstream resolver after VPN disconnect"
    else
        pass "Uncached DNS query is fail-closed after VPN disconnect"
    fi

    check "Blackhole route remains after disconnect" \
        sh -c "ip -4 route show table '$ROUTE_TABLE' | grep -q '^blackhole default'"
    if ip -4 route show table "$ROUTE_TABLE" | grep -q "^default dev ${VPN_IF}"; then
        fail "VPN default route remained after tunnel disconnect"
    else
        pass "VPN default route was removed after disconnect"
    fi

    printf 'Reconnecting NordVPN to %s...\n' "$COUNTRY"
    nordvpn_as_user connect "$COUNTRY" >/dev/null
    ORIGINAL_CONNECTED=false
    sleep 8

    check "NordVPN reconnects successfully" \
        sh -c "runuser -u '$VPN_USER' -- nordvpn status | grep -q '^Status: Connected'"
    check "DNS recovers after reconnect" dns_probe "$LAN_IP" 5 example.com answer
    check "VPN default route is restored" \
        sh -c "ip -4 route show table '$ROUTE_TABLE' | grep -q '^default dev $VPN_IF'"
fi

printf '\nResult: %s passed, %s failed\n' "$pass_count" "$fail_count"
[[ "$fail_count" -eq 0 ]]
