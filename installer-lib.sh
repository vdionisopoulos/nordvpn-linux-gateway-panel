#!/usr/bin/env bash

PROJECT_VERSION="0.3.0"
STATE_FILE="/var/lib/vpn-control/install-state.json"
RUNTIME_CONFIG="/var/lib/vpn-control/config.json"
DNS_CONFIG="/etc/vpn-control/dnsmasq.conf"

log() {
    printf '[vpn-control] %s\n' "$*"
}

die() {
    printf '[vpn-control] ERROR: %s\n' "$*" >&2
    exit 1
}

nordvpn_as_user() {
    runuser -u "$VPN_USER" -- nordvpn "$@"
}

nordvpn_is_authenticated() {
    nordvpn_as_user account >/dev/null 2>&1
}

nordvpn_allowlist_contains() {
    local subnet="$1"
    nordvpn_as_user settings 2>/dev/null | grep -Fq "$subnet"
}

ensure_nordvpn_settings() {
    local subnet="$1"
    local allowlist_added=false

    nordvpn_is_authenticated || die "NordVPN is not authenticated for user ${VPN_USER}. Run 'nordvpn login' first."

    # Add the exact LAN subnet before disabling broad LAN discovery so an
    # existing SSH session and the web panel cannot be locked out.
    if ! nordvpn_allowlist_contains "$subnet"; then
        log "Adding NordVPN allowlist subnet: $subnet"
        nordvpn_as_user allowlist add subnet "$subnet"
        allowlist_added=true
    else
        log "NordVPN allowlist already contains: $subnet"
    fi

    nordvpn_as_user set technology nordlynx
    nordvpn_as_user set routing on
    nordvpn_as_user set firewall on
    nordvpn_as_user set killswitch off
    nordvpn_as_user set lan-discovery off

    NORDVPN_ALLOWLIST_ADDED="$allowlist_added"
}

backup_file() {
    local path="$1"
    local stamp="$2"

    if [[ -e "$path" ]]; then
        cp -a -- "$path" "${path}.backup.${stamp}"
    fi
}

rotate_backups() {
    local path="$1"
    local keep="${2:-5}"
    local directory
    local base
    local backup
    local index=0

    directory="$(dirname "$path")"
    base="$(basename "$path")"

    while IFS= read -r backup; do
        index=$((index + 1))
        if ((index > keep)); then
            rm -f -- "$backup"
        fi
    done < <(
        find "$directory" -maxdepth 1 -type f -name "${base}.backup.*" \
            -printf '%T@ %p\n' 2>/dev/null | sort -nr | sed 's/^[^ ]* //'
    )
}

ensure_dns_user() {
    if id vpn-dns >/dev/null 2>&1; then
        VPN_DNS_USER_CREATED=false
    else
        useradd --system --no-create-home --shell /usr/sbin/nologin vpn-dns
        VPN_DNS_USER_CREATED=true
    fi
}

write_dns_config() {
    local bind_ip="$1"
    local upstream_1="${2:-103.86.96.100}"
    local upstream_2="${3:-103.86.99.100}"

    install -d -m 0755 /etc/vpn-control
    cat > "$DNS_CONFIG" <<EOF
# Managed by nordvpn-linux-gateway-panel ${PROJECT_VERSION}
port=53
listen-address=${bind_ip}
bind-interfaces
pid-file=/run/vpn-control-dns/dnsmasq.pid
no-resolv
no-poll
server=${upstream_1}
server=${upstream_2}
cache-size=1000
domain-needed
bogus-priv
stop-dns-rebind
dns-forward-max=150
EOF
    chmod 0644 "$DNS_CONFIG"
}

migrate_runtime_config() {
    local country="$1"
    local lan_if="$2"
    local lan_ip="$3"
    local lan_net="$4"
    local owner="$5"
    local temp_file

    install -d -o "$owner" -g "$owner" -m 0750 /var/lib/vpn-control

    if [[ -f "$RUNTIME_CONFIG" ]]; then
        temp_file="$(mktemp /var/lib/vpn-control/.config-migrate.XXXXXX)"
        jq \
            --arg country "$country" \
            --arg lan_if "$lan_if" \
            --arg lan_ip "$lan_ip" \
            --arg lan_net "$lan_net" \
            '.country //= $country |
             .devices //= [] |
             .lan_if = $lan_if |
             .lan_ip = $lan_ip |
             .lan_net = $lan_net |
             .vpn_if //= "nordlynx" |
             .route_table //= 200 |
             .rule_priority //= 10000 |
             .check_interval //= 5 |
             .dns_enabled = true |
             .dns_user = "vpn-dns" |
             .dns_rule_priority //= 9999 |
             .dns_upstreams //= ["103.86.96.100", "103.86.99.100"]' \
            "$RUNTIME_CONFIG" > "$temp_file"
        chown "$owner:$owner" "$temp_file"
        chmod 0640 "$temp_file"
        mv -f "$temp_file" "$RUNTIME_CONFIG"
    else
        jq -n \
            --arg country "$country" \
            --arg lan_if "$lan_if" \
            --arg lan_ip "$lan_ip" \
            --arg lan_net "$lan_net" \
            '{
                country: $country,
                devices: [],
                lan_if: $lan_if,
                lan_ip: $lan_ip,
                lan_net: $lan_net,
                vpn_if: "nordlynx",
                route_table: 200,
                rule_priority: 10000,
                check_interval: 5,
                dns_enabled: true,
                dns_user: "vpn-dns",
                dns_rule_priority: 9999,
                dns_upstreams: ["103.86.96.100", "103.86.99.100"]
            }' > "$RUNTIME_CONFIG"
        chown "$owner:$owner" "$RUNTIME_CONFIG"
        chmod 0640 "$RUNTIME_CONFIG"
    fi
}

write_install_state() {
    local forwarding_was_enabled="$1"
    local nordvpn_group_added="$2"
    local allowlist_added="$3"
    local dns_user_created="$4"
    local temp_file

    temp_file="$(mktemp /var/lib/vpn-control/.install-state.XXXXXX)"
    jq -n \
        --arg version "$PROJECT_VERSION" \
        --arg vpn_user "$VPN_USER" \
        --arg lan_net "$LAN_NET" \
        --argjson forwarding_was_enabled "$forwarding_was_enabled" \
        --argjson nordvpn_group_added "$nordvpn_group_added" \
        --argjson allowlist_added "$allowlist_added" \
        --argjson dns_user_created "$dns_user_created" \
        '{
            version: $version,
            vpn_user: $vpn_user,
            lan_net: $lan_net,
            forwarding_was_enabled: $forwarding_was_enabled,
            nordvpn_group_added: $nordvpn_group_added,
            allowlist_added: $allowlist_added,
            dns_user_created: $dns_user_created
        }' > "$temp_file"
    chmod 0600 "$temp_file"
    mv -f "$temp_file" "$STATE_FILE"
}

update_install_state_version() {
    local temp_file

    [[ -f "$STATE_FILE" ]] || return 0
    temp_file="$(mktemp /var/lib/vpn-control/.install-state.XXXXXX)"
    jq --arg version "$PROJECT_VERSION" '.version = $version' "$STATE_FILE" > "$temp_file"
    chmod 0600 "$temp_file"
    mv -f "$temp_file" "$STATE_FILE"
}
