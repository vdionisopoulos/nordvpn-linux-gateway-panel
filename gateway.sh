#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="${VPN_CONFIG_PATH:-/var/lib/vpn-control/config.json}"
LAST_CONFIG_HASH=""

log() {
    echo "[tv-vpn-gateway] $*"
}

require_commands() {
    local command_name
    for command_name in ip nft sysctl jq sha256sum sleep; do
        command -v "$command_name" >/dev/null 2>&1 || {
            log "Missing command: $command_name"
            exit 1
        }
    done
}

load_config() {
    jq -e '
      (.devices | type == "array") and
      (.lan_if | type == "string") and
      (.lan_ip | type == "string") and
      (.lan_net | type == "string") and
      (.vpn_if | type == "string") and
      (.route_table | type == "number") and
      (.rule_priority | type == "number")
    ' "$CONFIG_FILE" >/dev/null

    LAN_IF="$(jq -r '.lan_if' "$CONFIG_FILE")"
    LAN_IP="$(jq -r '.lan_ip' "$CONFIG_FILE")"
    LAN_NET="$(jq -r '.lan_net' "$CONFIG_FILE")"
    VPN_IF="$(jq -r '.vpn_if' "$CONFIG_FILE")"
    ROUTE_TABLE="$(jq -r '.route_table' "$CONFIG_FILE")"
    RULE_PRIORITY="$(jq -r '.rule_priority' "$CONFIG_FILE")"
    CHECK_INTERVAL="$(jq -r '.check_interval // 5' "$CONFIG_FILE")"

    mapfile -t VPN_CLIENTS < <(jq -r '.devices[].ip' "$CONFIG_FILE")
}

vpn_is_ready() {
    ip link show dev "$VPN_IF" >/dev/null 2>&1 &&
    ip -4 address show dev "$VPN_IF" | grep -qE '^[[:space:]]+inet[[:space:]]'
}

ensure_forwarding() {
    if [[ "$(sysctl -n net.ipv4.ip_forward)" != "1" ]]; then
        sysctl -q -w net.ipv4.ip_forward=1
        log "IPv4 forwarding enabled."
    fi
}

clear_managed_rules() {
    local priority
    for ((priority = RULE_PRIORITY; priority < RULE_PRIORITY + 256; priority++)); do
        while ip -4 rule delete priority "$priority" 2>/dev/null; do
            :
        done
    done
}

install_policy_rules() {
    local index=0
    local client_ip
    for client_ip in "${VPN_CLIENTS[@]}"; do
        ip -4 rule add \
            priority "$((RULE_PRIORITY + index))" \
            from "${client_ip}/32" \
            table "$ROUTE_TABLE"
        index=$((index + 1))
    done
    log "Policy rules installed for ${#VPN_CLIENTS[@]} device(s)."
}

reset_routes() {
    ip -4 route flush table "$ROUTE_TABLE" 2>/dev/null || true
    ip -4 route add "$LAN_NET" dev "$LAN_IF" src "$LAN_IP" table "$ROUTE_TABLE"
    ip -4 route add blackhole default metric 32767 table "$ROUTE_TABLE"

    if vpn_is_ready; then
        ip -4 route add default dev "$VPN_IF" metric 10 table "$ROUTE_TABLE"
        log "VPN route active through $VPN_IF."
    else
        log "VPN not ready; managed devices remain fail-closed."
    fi
}

ensure_routes() {
    ip -4 route replace "$LAN_NET" dev "$LAN_IF" src "$LAN_IP" table "$ROUTE_TABLE"

    if ! ip -4 route show table "$ROUTE_TABLE" | grep -qE '^blackhole default([[:space:]]|$)'; then
        ip -4 route add blackhole default metric 32767 table "$ROUTE_TABLE"
    fi

    if vpn_is_ready; then
        if ! ip -4 route show table "$ROUTE_TABLE" | grep -qE "^default dev ${VPN_IF}([[:space:]]|$)"; then
            ip -4 route replace default dev "$VPN_IF" metric 10 table "$ROUTE_TABLE"
            log "VPN default route restored."
        fi
    else
        ip -4 route delete default dev "$VPN_IF" table "$ROUTE_TABLE" 2>/dev/null || true
    fi
}

install_nftables_rules() {
    local client_list=""
    local set_definition=""
    local client_ip

    for client_ip in "${VPN_CLIENTS[@]}"; do
        [[ -n "$client_list" ]] && client_list+=", "
        client_list+="$client_ip"
    done

    if [[ -n "$client_list" ]]; then
        set_definition="elements = { $client_list }"
    fi

    nft delete table inet tv_vpn 2>/dev/null || true
    nft delete table ip tv_vpn_nat 2>/dev/null || true

    nft -f - <<EOF
table inet tv_vpn {
    set vpn_clients {
        type ipv4_addr;
        $set_definition
    }

    chain forward {
        type filter hook forward priority -10; policy accept;

        iifname "$LAN_IF" oifname "$VPN_IF" \
            ip saddr @vpn_clients counter accept

        iifname "$VPN_IF" oifname "$LAN_IF" \
            ip daddr @vpn_clients ct state established,related counter accept

        # Any LAN device still pointing to this VM but not present in
        # vpn_clients is also blocked. This prevents accidental clear-net fallback.
        iifname "$LAN_IF" counter drop
    }
}

table ip tv_vpn_nat {
    set vpn_clients {
        type ipv4_addr;
        $set_definition
    }

    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;

        oifname "$VPN_IF" ip saddr @vpn_clients counter masquerade
    }
}
EOF

    log "nftables rules installed for: ${VPN_CLIENTS[*]:-(none)}"
}

rules_are_present() {
    nft list table inet tv_vpn >/dev/null 2>&1 &&
    nft list table ip tv_vpn_nat >/dev/null 2>&1
}

apply_config() {
    load_config
    ensure_forwarding
    clear_managed_rules
    install_policy_rules
    reset_routes
    install_nftables_rules
}

main() {
    require_commands
    [[ -r "$CONFIG_FILE" ]] || {
        log "Config not readable: $CONFIG_FILE"
        exit 1
    }

    apply_config
    LAST_CONFIG_HASH="$(sha256sum "$CONFIG_FILE" | awk '{print $1}')"

    while true; do
        current_hash="$(sha256sum "$CONFIG_FILE" | awk '{print $1}')"

        if [[ "$current_hash" != "$LAST_CONFIG_HASH" ]]; then
            log "Configuration change detected."
            apply_config
            LAST_CONFIG_HASH="$current_hash"
        else
            ensure_forwarding
            ensure_routes
            rules_are_present || install_nftables_rules
        fi

        sleep "$CHECK_INTERVAL"
    done
}

main "$@"
