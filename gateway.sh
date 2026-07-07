#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="${VPN_CONFIG_PATH:-/var/lib/vpn-control/config.json}"
HEALTH_FILE="${VPN_HEALTH_PATH:-/run/vpn-control/gateway-health.json}"
VERSION_FILE="${VPN_VERSION_PATH:-/opt/vpn-control/VERSION}"
PROJECT_VERSION="development"
LAST_CONFIG_HASH=""

if [[ -r "$VERSION_FILE" ]]; then
    PROJECT_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
fi

log() {
    echo "[tv-vpn-gateway] $*"
}

bool_json() {
    if "$@" >/dev/null 2>&1; then
        printf 'true'
    else
        printf 'false'
    fi
}

require_commands() {
    local command_name
    for command_name in chmod date dirname grep id install ip jq mktemp mv nft sha256sum sleep sysctl systemctl tr; do
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
    DNS_USER="$(jq -r '.dns_user // "vpn-dns"' "$CONFIG_FILE")"
    DNS_RULE_PRIORITY="$(jq -r '.dns_rule_priority // 9999' "$CONFIG_FILE")"

    mapfile -t VPN_CLIENTS < <(jq -r '.devices[].ip' "$CONFIG_FILE")
}

vpn_is_ready() {
    ip link show dev "$VPN_IF" >/dev/null 2>&1 &&
        ip -4 address show dev "$VPN_IF" | grep -qE '^[[:space:]]+inet[[:space:]]'
}

set_forwarding() {
    local value="$1"
    if [[ "$(sysctl -n net.ipv4.ip_forward)" != "$value" ]]; then
        sysctl -q -w "net.ipv4.ip_forward=${value}"
        log "IPv4 forwarding set to ${value}."
    fi
}

clear_priority() {
    local priority="$1"
    while ip -4 rule delete priority "$priority" 2>/dev/null; do
        :
    done
}

clear_managed_rules() {
    local priority
    clear_priority "$DNS_RULE_PRIORITY"
    for ((priority = RULE_PRIORITY; priority < RULE_PRIORITY + 256; priority++)); do
        clear_priority "$priority"
    done
}

install_policy_rules() {
    local index=0
    local client_ip

    if ! id "$DNS_USER" >/dev/null 2>&1; then
        log "DNS user does not exist: $DNS_USER"
        return 1
    fi

    DNS_UID="$(id -u "$DNS_USER")"
    ip -4 rule add \
        priority "$DNS_RULE_PRIORITY" \
        uidrange "${DNS_UID}-${DNS_UID}" \
        table "$ROUTE_TABLE"
    log "DNS policy rule installed for UID ${DNS_UID}, priority ${DNS_RULE_PRIORITY}."

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
}

ensure_routes() {
    ip -4 route replace "$LAN_NET" dev "$LAN_IF" src "$LAN_IP" table "$ROUTE_TABLE"

    if ! ip -4 route show table "$ROUTE_TABLE" | grep -qE '^blackhole default([[:space:]]|$)'; then
        ip -4 route add blackhole default metric 32767 table "$ROUTE_TABLE"
        log "Fail-closed blackhole route restored."
    fi

    if vpn_is_ready; then
        if ! ip -4 route show table "$ROUTE_TABLE" | grep -qE "^default dev ${VPN_IF}([[:space:]]|$)"; then
            ip -4 route replace default dev "$VPN_IF" metric 10 table "$ROUTE_TABLE"
            log "VPN default route restored through $VPN_IF."
        fi
    else
        ip -4 route delete default dev "$VPN_IF" table "$ROUTE_TABLE" 2>/dev/null || true
    fi
}

render_nftables() {
    local client_list=""
    local set_definition=""
    local client_ip

    for client_ip in "${VPN_CLIENTS[@]}"; do
        [[ -n "$client_list" ]] && client_list+=", "
        client_list+="$client_ip"
    done

    if [[ -n "$client_list" ]]; then
        set_definition="elements = { $client_list };"
    fi

    cat <<EOF
table inet tv_vpn {
    set vpn_clients {
        type ipv4_addr;
        $set_definition
    }

    chain input {
        type filter hook input priority -10; policy accept;

        iifname "$LAN_IF" ip saddr @vpn_clients ip daddr $LAN_IP \
            udp dport 53 counter accept
        iifname "$LAN_IF" ip saddr @vpn_clients ip daddr $LAN_IP \
            tcp dport 53 counter accept
        iifname "$LAN_IF" ip daddr $LAN_IP udp dport 53 counter drop
        iifname "$LAN_IF" ip daddr $LAN_IP tcp dport 53 counter drop
    }

    chain forward {
        type filter hook forward priority -10; policy accept;

        iifname "$LAN_IF" oifname "$VPN_IF" \
            ip saddr @vpn_clients counter accept

        iifname "$VPN_IF" oifname "$LAN_IF" \
            ip daddr @vpn_clients ct state established,related counter accept

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
}

install_nftables_rules() {
    nft delete table inet tv_vpn 2>/dev/null || true
    nft delete table ip tv_vpn_nat 2>/dev/null || true
    render_nftables | nft -f -
    log "nftables rules installed for: ${VPN_CLIENTS[*]:-(none)}"
}

rules_are_present() {
    nft list table inet tv_vpn >/dev/null 2>&1 &&
        nft list table ip tv_vpn_nat >/dev/null 2>&1
}

policy_rule_present() {
    local priority="$1"
    local pattern="$2"
    ip -4 rule show | grep -qE "^${priority}:.*${pattern}.*lookup ${ROUTE_TABLE}([[:space:]]|$)"
}

count_policy_rules() {
    local count=0
    local index=0
    local client_ip

    if id "$DNS_USER" >/dev/null 2>&1; then
        local dns_uid
        dns_uid="$(id -u "$DNS_USER")"
        if policy_rule_present "$DNS_RULE_PRIORITY" "uidrange ${dns_uid}-${dns_uid}"; then
            count=$((count + 1))
        fi
    fi

    for client_ip in "${VPN_CLIENTS[@]}"; do
        if policy_rule_present "$((RULE_PRIORITY + index))" "from ${client_ip}(/32)?"; then
            count=$((count + 1))
        fi
        index=$((index + 1))
    done

    printf '%s' "$count"
}

write_health() {
    local updated_epoch
    local updated_at
    local vpn_ready
    local forwarding_enabled
    local fail_closed_present
    local vpn_default_present
    local nft_filter_present
    local nft_nat_present
    local dns_service_active
    local dns_rule_present=false
    local policy_rules_actual
    local policy_rules_expected
    local status
    local temp_file

    updated_epoch="$(date +%s)"
    updated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    vpn_ready="$(bool_json vpn_is_ready)"
    forwarding_enabled="$(bool_json test "$(sysctl -n net.ipv4.ip_forward)" = "1")"
    fail_closed_present="$(bool_json sh -c "ip -4 route show table '$ROUTE_TABLE' | grep -qE '^blackhole default([[:space:]]|$)'")"
    vpn_default_present="$(bool_json sh -c "ip -4 route show table '$ROUTE_TABLE' | grep -qE '^default dev $VPN_IF([[:space:]]|$)'")"
    nft_filter_present="$(bool_json nft list table inet tv_vpn)"
    nft_nat_present="$(bool_json nft list table ip tv_vpn_nat)"
    dns_service_active="$(bool_json systemctl is-active --quiet vpn-control-dns.service)"

    if id "$DNS_USER" >/dev/null 2>&1; then
        local dns_uid
        dns_uid="$(id -u "$DNS_USER")"
        dns_rule_present="$(bool_json policy_rule_present "$DNS_RULE_PRIORITY" "uidrange ${dns_uid}-${dns_uid}")"
    fi

    policy_rules_actual="$(count_policy_rules)"
    policy_rules_expected=$((${#VPN_CLIENTS[@]} + 1))

    if [[ "$forwarding_enabled" == "true" && "$fail_closed_present" == "true" && \
          "$nft_filter_present" == "true" && "$nft_nat_present" == "true" && \
          "$policy_rules_actual" -eq "$policy_rules_expected" && \
          "$dns_service_active" == "true" && "$dns_rule_present" == "true" ]]; then
        if [[ "$vpn_ready" == "true" && "$vpn_default_present" == "true" ]]; then
            status="healthy"
        else
            status="fail-closed"
        fi
    else
        status="degraded"
    fi

    install -d -m 0755 "$(dirname "$HEALTH_FILE")"
    temp_file="$(mktemp "${HEALTH_FILE}.tmp.XXXXXX")"
    jq -n \
        --arg version "$PROJECT_VERSION" \
        --arg status "$status" \
        --arg updated_at "$updated_at" \
        --argjson updated_epoch "$updated_epoch" \
        --argjson vpn_ready "$vpn_ready" \
        --argjson forwarding_enabled "$forwarding_enabled" \
        --argjson fail_closed_present "$fail_closed_present" \
        --argjson vpn_default_present "$vpn_default_present" \
        --argjson nft_filter_present "$nft_filter_present" \
        --argjson nft_nat_present "$nft_nat_present" \
        --argjson dns_service_active "$dns_service_active" \
        --argjson dns_rule_present "$dns_rule_present" \
        --argjson policy_rules_actual "$policy_rules_actual" \
        --argjson policy_rules_expected "$policy_rules_expected" \
        --argjson managed_devices "${#VPN_CLIENTS[@]}" \
        '{
            version: $version,
            status: $status,
            updated_at: $updated_at,
            updated_epoch: $updated_epoch,
            vpn_ready: $vpn_ready,
            forwarding_enabled: $forwarding_enabled,
            fail_closed_present: $fail_closed_present,
            vpn_default_present: $vpn_default_present,
            nft_filter_present: $nft_filter_present,
            nft_nat_present: $nft_nat_present,
            dns_service_active: $dns_service_active,
            dns_rule_present: $dns_rule_present,
            policy_rules_actual: $policy_rules_actual,
            policy_rules_expected: $policy_rules_expected,
            managed_devices: $managed_devices
        }' > "$temp_file"
    chmod 0644 "$temp_file"
    mv -f "$temp_file" "$HEALTH_FILE"
}

apply_config() {
    load_config

    # Disable forwarding while the fail-closed state is rebuilt. This prevents
    # a transient fallback through the host's main routing table.
    set_forwarding 0
    reset_routes
    clear_managed_rules
    install_policy_rules
    install_nftables_rules
    ensure_routes
    set_forwarding 1
    write_health
}

main() {
    require_commands
    [[ -r "$CONFIG_FILE" ]] || {
        log "Config not readable: $CONFIG_FILE"
        exit 1
    }

    if [[ "${1:-}" == "--render-nft" ]]; then
        load_config
        render_nftables
        exit 0
    fi

    apply_config
    LAST_CONFIG_HASH="$(sha256sum "$CONFIG_FILE" | awk '{print $1}')"

    while true; do
        local current_hash
        current_hash="$(sha256sum "$CONFIG_FILE" | awk '{print $1}')"

        if [[ "$current_hash" != "$LAST_CONFIG_HASH" ]]; then
            log "Configuration change detected."
            apply_config
            LAST_CONFIG_HASH="$current_hash"
        else
            ensure_routes
            rules_are_present || install_nftables_rules
            set_forwarding 1
            write_health
        fi

        sleep "$CHECK_INTERVAL"
    done
}

main "$@"
