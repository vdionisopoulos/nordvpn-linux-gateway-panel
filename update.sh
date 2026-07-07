#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo: sudo ./update.sh"
    exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=installer-lib.sh
source "$SCRIPT_DIR/installer-lib.sh"

if [[ ! -d /opt/vpn-control || ! -f /etc/systemd/system/vpn-control-web.service ]]; then
    die "Existing installation not found. Run 'sudo ./install.sh' instead."
fi

if [[ -f "$STATE_FILE" ]]; then
    VPN_USER="$(jq -r '.vpn_user // empty' "$STATE_FILE")"
else
    VPN_USER="$(systemctl show vpn-control-web.service --property=User --value 2>/dev/null || true)"
fi
VPN_USER="${VPN_USER:-${SUDO_USER:-}}"
[[ -n "$VPN_USER" ]] || die "Could not determine the VPN service user."
id "$VPN_USER" >/dev/null 2>&1 || die "User not found: $VPN_USER"

LAN_IF="$(jq -r '.lan_if' "$RUNTIME_CONFIG")"
BIND_IP="$(jq -r '.lan_ip' "$RUNTIME_CONFIG")"
LAN_NET="$(jq -r '.lan_net' "$RUNTIME_CONFIG")"
COUNTRY="$(jq -r '.country // "gr"' "$RUNTIME_CONFIG")"

command -v nordvpn >/dev/null 2>&1 || die "NordVPN Linux CLI is not installed."

groupadd -f nordvpn
NORDVPN_GROUP_ADDED=false
if ! id -nG "$VPN_USER" | tr ' ' '\n' | grep -Fxq nordvpn; then
    usermod -aG nordvpn "$VPN_USER"
    NORDVPN_GROUP_ADDED=true
fi
ensure_nordvpn_settings "$LAN_NET"

log "Installing or updating Ubuntu packages..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 python3-venv python3-pip jq nftables curl dnsmasq-base
ensure_dns_user

python3 -m py_compile "$SCRIPT_DIR/app.py" "$SCRIPT_DIR/validation.py"
bash -n \
    "$SCRIPT_DIR/gateway.sh" \
    "$SCRIPT_DIR/install.sh" \
    "$SCRIPT_DIR/update.sh" \
    "$SCRIPT_DIR/uninstall.sh" \
    "$SCRIPT_DIR/installer-lib.sh"

stamp="$(date +%Y%m%d-%H%M%S)"
for path in \
    /opt/vpn-control/app.py \
    /opt/vpn-control/validation.py \
    /opt/vpn-control/requirements.txt \
    /usr/local/sbin/tv-vpn-gateway \
    /etc/systemd/system/tv-vpn-gateway.service \
    /etc/systemd/system/vpn-control-web.service \
    /etc/systemd/system/vpn-control-dns.service \
    "$DNS_CONFIG"; do
    backup_file "$path" "$stamp"
done

systemctl stop vpn-control-web.service tv-vpn-gateway.service 2>/dev/null || true
sysctl -q -w net.ipv4.ip_forward=0

install -d -m 0755 /opt/vpn-control
install -m 0644 "$SCRIPT_DIR/app.py" /opt/vpn-control/app.py
install -m 0644 "$SCRIPT_DIR/validation.py" /opt/vpn-control/validation.py
install -m 0644 "$SCRIPT_DIR/requirements.txt" /opt/vpn-control/requirements.txt
install -m 0755 "$SCRIPT_DIR/gateway.sh" /usr/local/sbin/tv-vpn-gateway
install -m 0644 "$SCRIPT_DIR/tv-vpn-gateway.service" \
    /etc/systemd/system/tv-vpn-gateway.service
install -m 0644 "$SCRIPT_DIR/vpn-control-dns.service" \
    /etc/systemd/system/vpn-control-dns.service
sed "s/__VPN_USER__/${VPN_USER}/g" "$SCRIPT_DIR/vpn-control-web.service" \
    > /etc/systemd/system/vpn-control-web.service
chmod 0644 /etc/systemd/system/vpn-control-web.service

migrate_runtime_config "$COUNTRY" "$LAN_IF" "$BIND_IP" "$LAN_NET" "$VPN_USER"
write_dns_config "$BIND_IP"

if [[ ! -d /opt/vpn-control/.venv ]]; then
    python3 -m venv /opt/vpn-control/.venv
fi
/opt/vpn-control/.venv/bin/pip install --upgrade pip
/opt/vpn-control/.venv/bin/pip install -r /opt/vpn-control/requirements.txt

if ! grep -q '^VPN_HEALTH_PATH=' /etc/vpn-control-web.env; then
    echo 'VPN_HEALTH_PATH=/run/vpn-control/gateway-health.json' >> /etc/vpn-control-web.env
fi
chmod 0600 /etc/vpn-control-web.env

rm -f /etc/sysctl.d/99-vpn-gateway.conf /etc/sysctl.d/99-tv-vpn-gateway.conf

if [[ -f "$STATE_FILE" ]]; then
    temp_state="$(mktemp /var/lib/vpn-control/.install-state.XXXXXX)"
    jq \
        --arg version "$PROJECT_VERSION" \
        --arg vpn_user "$VPN_USER" \
        --arg lan_net "$LAN_NET" \
        --argjson group_added "$NORDVPN_GROUP_ADDED" \
        --argjson allowlist_added "$NORDVPN_ALLOWLIST_ADDED" \
        --argjson dns_user_created "$VPN_DNS_USER_CREATED" \
        '.version = $version |
         .vpn_user = $vpn_user |
         .lan_net = $lan_net |
         .forwarding_was_enabled //= false |
         .nordvpn_group_added = ((.nordvpn_group_added // false) or $group_added) |
         .allowlist_added = ((.allowlist_added // false) or $allowlist_added) |
         .dns_user_created = ((.dns_user_created // false) or $dns_user_created)' \
        "$STATE_FILE" > "$temp_state"
    chmod 0600 "$temp_state"
    mv -f "$temp_state" "$STATE_FILE"
else
    write_install_state false "$NORDVPN_GROUP_ADDED" "$NORDVPN_ALLOWLIST_ADDED" "$VPN_DNS_USER_CREATED"
fi

systemctl daemon-reload
if command -v systemd-analyze >/dev/null 2>&1; then
    systemd-analyze verify \
        /etc/systemd/system/vpn-control-dns.service \
        /etc/systemd/system/tv-vpn-gateway.service \
        /etc/systemd/system/vpn-control-web.service
fi

systemctl enable vpn-control-dns.service tv-vpn-gateway.service vpn-control-web.service
systemctl restart vpn-control-dns.service
systemctl restart tv-vpn-gateway.service
systemctl restart vpn-control-web.service

nordvpn_as_user set autoconnect on "$COUNTRY"
nordvpn_as_user connect "$COUNTRY" || log "NordVPN is currently disconnected; managed devices remain fail-closed."

for path in \
    /opt/vpn-control/app.py \
    /opt/vpn-control/validation.py \
    /opt/vpn-control/requirements.txt \
    /usr/local/sbin/tv-vpn-gateway \
    /etc/systemd/system/tv-vpn-gateway.service \
    /etc/systemd/system/vpn-control-web.service \
    /etc/systemd/system/vpn-control-dns.service \
    "$DNS_CONFIG"; do
    rotate_backups "$path" 5
done

sleep 2
systemctl --no-pager --full status \
    vpn-control-dns.service tv-vpn-gateway.service vpn-control-web.service

echo
echo "Update to ${PROJECT_VERSION} completed."
echo "Managed-device DNS is now the gateway address: ${BIND_IP}"
