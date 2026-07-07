#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo: sudo ./uninstall.sh [--panel-only|--all|--purge]"
    exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=installer-lib.sh
source "$SCRIPT_DIR/installer-lib.sh"

MODE="${1:---panel-only}"
case "$MODE" in
    --panel-only | --all | --purge) ;;
    *)
        echo "Usage: sudo ./uninstall.sh [--panel-only|--all|--purge]"
        exit 2
        ;;
esac

VPN_USER=""
LAN_NET=""
FORWARDING_WAS_ENABLED=false
NORDVPN_GROUP_ADDED=false
ALLOWLIST_ADDED=false
DNS_USER_CREATED=false

if [[ -f "$STATE_FILE" ]]; then
    VPN_USER="$(jq -r '.vpn_user // empty' "$STATE_FILE")"
    LAN_NET="$(jq -r '.lan_net // empty' "$STATE_FILE")"
    FORWARDING_WAS_ENABLED="$(jq -r '.forwarding_was_enabled // false' "$STATE_FILE")"
    NORDVPN_GROUP_ADDED="$(jq -r '.nordvpn_group_added // false' "$STATE_FILE")"
    ALLOWLIST_ADDED="$(jq -r '.allowlist_added // false' "$STATE_FILE")"
    DNS_USER_CREATED="$(jq -r '.dns_user_created // false' "$STATE_FILE")"
elif [[ -f "$RUNTIME_CONFIG" ]]; then
    LAN_NET="$(jq -r '.lan_net // empty' "$RUNTIME_CONFIG")"
    VPN_USER="$(systemctl show vpn-control-web.service --property=User --value 2>/dev/null || true)"
fi

remove_rule_priority() {
    local priority="$1"
    while ip -4 rule delete priority "$priority" 2>/dev/null; do
        :
    done
}

cleanup_gateway_state() {
    local route_table=200
    local rule_priority=10000
    local dns_rule_priority=9999
    local priority

    if [[ -f "$RUNTIME_CONFIG" ]]; then
        route_table="$(jq -r '.route_table // 200' "$RUNTIME_CONFIG")"
        rule_priority="$(jq -r '.rule_priority // 10000' "$RUNTIME_CONFIG")"
        dns_rule_priority="$(jq -r '.dns_rule_priority // 9999' "$RUNTIME_CONFIG")"
    fi

    sysctl -q -w net.ipv4.ip_forward=0
    remove_rule_priority "$dns_rule_priority"
    for ((priority = rule_priority; priority < rule_priority + 256; priority++)); do
        remove_rule_priority "$priority"
    done
    ip -4 route flush table "$route_table" 2>/dev/null || true
    nft delete table inet tv_vpn 2>/dev/null || true
    nft delete table ip tv_vpn_nat 2>/dev/null || true
}

systemctl disable --now vpn-control-web.service 2>/dev/null || true
rm -f /etc/systemd/system/vpn-control-web.service
rm -f /etc/vpn-control-web.env
rm -rf /opt/vpn-control

if [[ "$MODE" == "--panel-only" ]]; then
    systemctl daemon-reload
    echo "Web panel removed. Gateway routing, DNS proxy and runtime configuration were kept."
    exit 0
fi

systemctl disable --now tv-vpn-gateway.service vpn-control-dns.service 2>/dev/null || true
cleanup_gateway_state

rm -f /etc/systemd/system/tv-vpn-gateway.service
rm -f /etc/systemd/system/vpn-control-dns.service
rm -f /usr/local/sbin/tv-vpn-gateway
rm -f "$DNS_CONFIG"
rm -f /etc/sysctl.d/99-vpn-gateway.conf /etc/sysctl.d/99-tv-vpn-gateway.conf
rm -rf /run/vpn-control

if [[ "$ALLOWLIST_ADDED" == "true" && -n "$VPN_USER" && -n "$LAN_NET" ]] && \
   id "$VPN_USER" >/dev/null 2>&1 && command -v nordvpn >/dev/null 2>&1; then
    runuser -u "$VPN_USER" -- nordvpn allowlist remove subnet "$LAN_NET" || true
fi

if [[ "$FORWARDING_WAS_ENABLED" == "true" ]]; then
    sysctl -q -w net.ipv4.ip_forward=1
fi

if [[ "$MODE" == "--purge" ]]; then
    rm -rf /var/lib/vpn-control /etc/vpn-control

    if [[ "$NORDVPN_GROUP_ADDED" == "true" && -n "$VPN_USER" ]] && id "$VPN_USER" >/dev/null 2>&1; then
        gpasswd -d "$VPN_USER" nordvpn >/dev/null 2>&1 || true
    fi

    if [[ "$DNS_USER_CREATED" == "true" ]] && id vpn-dns >/dev/null 2>&1; then
        userdel vpn-dns
    fi

    rm -f \
        /usr/local/sbin/tv-vpn-gateway.backup.* \
        /etc/systemd/system/tv-vpn-gateway.service.backup.* \
        /etc/systemd/system/vpn-control-web.service.backup.* \
        /etc/systemd/system/vpn-control-dns.service.backup.* \
        /etc/vpn-control/dnsmasq.conf.backup.*
    echo "Full purge completed. Runtime configuration and installer state were removed."
else
    echo "Gateway, DNS proxy and web panel removed. Runtime configuration was kept in /var/lib/vpn-control."
fi

systemctl daemon-reload
systemctl reset-failed
