#!/usr/bin/env bash

PROJECT_VERSION="$(tr -d '[:space:]' < "${SCRIPT_DIR}/VERSION")"
STATE_FILE="/var/lib/vpn-control/install-state.json"
RUNTIME_CONFIG="/var/lib/vpn-control/config.json"
DNS_CONFIG="/etc/vpn-control/dnsmasq.conf"

[[ -n "$PROJECT_VERSION" ]] || {
    echo "[vpn-control] ERROR: VERSION is empty." >&2
    exit 1
}

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

nordvpn_command_idempotent() {
    local output
    local exit_code

    if output="$(nordvpn_as_user "$@" 2>&1)"; then
        [[ -n "$output" ]] && printf '%s\n' "$output"
        return 0
    else
        exit_code=$?
    fi

    [[ -n "$output" ]] && printf '%s\n' "$output"

    # Some NordVPN Linux CLI versions return a non-zero exit code when a
    # requested setting is already in the desired state. Treat only that
    # explicit no-op response as success; propagate all other failures.
    if grep -qiE 'already (set|enabled|disabled|connected)' <<< "$output"; then
        return 0
    fi

    return "$exit_code"
}

nordvpn_set_idempotent() {
    nordvpn_command_idempotent set "$@"
}

nordvpn_is_authenticated() {
    nordvpn_as_user account >/dev/null 2>&1
}

nordvpn_allowlist_contains() {
    local subnet="$1"
    nordvpn_as_user settings 2>/dev/null | grep -Fq "$subnet"
}

transition_lan_discovery_to_allowlist() {
    local subnet="$1"
    local unit_name="vpn-control-lan-access-$(date +%s)-$$"

    command -v systemd-run >/dev/null 2>&1 || \
        die "systemd-run is required for the safe LAN allowlist transition."

    log "Switching NordVPN LAN access from discovery to exact allowlist: $subnet"
    log "A brief LAN interruption is possible; the transition continues locally even if SSH pauses."

    if ! systemd-run \
        --quiet \
        --collect \
        --wait \
        --unit "$unit_name" \
        --property=Type=oneshot \
        /usr/sbin/runuser -u "$VPN_USER" -- \
        /bin/bash -c '
            set -Eeuo pipefail
            subnet="$1"

            run_idempotent() {
                local output
                local exit_code

                if output="$("$@" 2>&1)"; then
                    [[ -n "$output" ]] && printf "%s\n" "$output"
                    return 0
                else
                    exit_code=$?
                fi

                [[ -n "$output" ]] && printf "%s\n" "$output"
                if grep -qiE "already (set|enabled|disabled|connected)" <<< "$output"; then
                    return 0
                fi
                return "$exit_code"
            }

            restore_discovery() {
                nordvpn set lan-discovery on >/dev/null 2>&1 || true
            }
            trap restore_discovery ERR

            run_idempotent nordvpn set lan-discovery off
            nordvpn allowlist add subnet "$subnet"

            trap - ERR
        ' vpn-control-lan-transition "$subnet"; then
        journalctl -u "$unit_name" --no-pager -n 50 2>/dev/null || true
        die "Could not replace LAN Discovery with the exact subnet allowlist. LAN Discovery was restored when possible."
    fi

    nordvpn_allowlist_contains "$subnet" || \
        die "NordVPN did not retain the expected LAN subnet allowlist: $subnet"
}

ensure_nordvpn_settings() {
    local subnet="$1"
    local allowlist_added=false

    nordvpn_is_authenticated || \
        die "NordVPN is not authenticated for user ${VPN_USER}. Run 'nordvpn login' first."

    nordvpn_set_idempotent technology nordlynx
    nordvpn_set_idempotent routing on
    nordvpn_set_idempotent firewall on
    nordvpn_set_idempotent killswitch off

    # NordVPN does not permit adding a private subnet while Local Network
    # Discovery is enabled. Run both operations in a local transient systemd
    # unit so the exact allowlist is still applied if the SSH connection pauses.
    if ! nordvpn_allowlist_contains "$subnet"; then
        transition_lan_discovery_to_allowlist "$subnet"
        allowlist_added=true
    else
        log "NordVPN allowlist already contains: $subnet"
        nordvpn_set_idempotent lan-discovery off
    fi

    NORDVPN_ALLOWLIST_ADDED="$allowlist_added"
}

backup_file() {
    local path="$1"
    local stamp="$2"

    if [[ -e "$path" ]]; then
        cp -a -- "$path" "${path}.backup.${stamp}"
    fi
}

restore_backup() {
    local path="$1"
    local stamp="$2"
    local backup="${path}.backup.${stamp}"

    if [[ -e "$backup" ]]; then
        cp -a -- "$backup" "$path"
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
    local upstream
    local -a upstreams=()

    mapfile -t upstreams < <(
        jq -er '
            .dns_upstreams
            | select(type == "array" and length > 0)
            | .[]
            | select(type == "string" and length > 0)
        ' "$RUNTIME_CONFIG"
    )

    ((${#upstreams[@]} > 0)) || die "At least one DNS upstream must be configured."

    for upstream in "${upstreams[@]}"; do
        [[ "$upstream" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || \
            die "DNS upstream must be an IPv4 address: $upstream"
    done

    install -d -m 0755 /etc/vpn-control
    {
        cat <<EOF
# Managed by nordvpn-linux-gateway-panel ${PROJECT_VERSION}
port=53
listen-address=${bind_ip}
bind-interfaces
pid-file=/run/vpn-control-dns/dnsmasq.pid
no-resolv
no-poll
EOF
        for upstream in "${upstreams[@]}"; do
            printf 'server=%s\n' "$upstream"
        done
        cat <<'EOF'
cache-size=1000
domain-needed
bogus-priv
stop-dns-rebind
dns-forward-max=150
EOF
    } > "$DNS_CONFIG"
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
             del(.dns_enabled) |
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
