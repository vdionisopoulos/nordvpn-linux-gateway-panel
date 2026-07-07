#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo: sudo ./install.sh"
    exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=installer-lib.sh
source "$SCRIPT_DIR/installer-lib.sh"

VPN_USER="${VPN_USER:-${SUDO_USER:-}}"
WEB_PORT="${WEB_PORT:-8080}"
WEB_USER="${WEB_USER:-admin}"
DEFAULT_COUNTRY="${DEFAULT_COUNTRY:-gr}"

[[ -n "$VPN_USER" ]] || die "Could not determine the non-root account. Set VPN_USER explicitly."
id "$VPN_USER" >/dev/null 2>&1 || die "User not found: $VPN_USER"

if [[ -e /etc/systemd/system/vpn-control-web.service || -e /opt/vpn-control/app.py ]]; then
    die "An existing installation was detected. Use 'sudo ./update.sh' instead."
fi

command -v nordvpn >/dev/null 2>&1 || die "NordVPN Linux CLI is not installed."

LAN_IF="${LAN_IF:-$(ip -4 route show default | awk 'NR==1 {print $5}')}"
[[ -n "$LAN_IF" ]] || die "Could not detect the LAN interface. Set LAN_IF explicitly."

BIND_IP="${BIND_IP:-$(ip -4 -o addr show dev "$LAN_IF" scope global | awk 'NR==1 {split($4,a,"/"); print a[1]}')}"
LAN_NET="${LAN_NET:-$(ip -4 route show dev "$LAN_IF" proto kernel scope link | awk 'NR==1 {print $1}')}"
[[ -n "$BIND_IP" && -n "$LAN_NET" ]] || die "Could not detect BIND_IP or LAN_NET."

FORWARDING_WAS_ENABLED=false
[[ "$(sysctl -n net.ipv4.ip_forward)" == "1" ]] && FORWARDING_WAS_ENABLED=true

NORDVPN_GROUP_ADDED=false
groupadd -f nordvpn
if ! id -nG "$VPN_USER" | tr ' ' '\n' | grep -Fxq nordvpn; then
    usermod -aG nordvpn "$VPN_USER"
    NORDVPN_GROUP_ADDED=true
fi

ensure_nordvpn_settings "$LAN_NET"

log "Installing Ubuntu packages..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 python3-venv python3-pip jq nftables curl dnsmasq-base

ensure_dns_user

install -d -m 0755 /opt/vpn-control
install -m 0644 "$SCRIPT_DIR/app.py" /opt/vpn-control/app.py
install -m 0644 "$SCRIPT_DIR/validation.py" /opt/vpn-control/validation.py
install -m 0644 "$SCRIPT_DIR/requirements.txt" /opt/vpn-control/requirements.txt
install -m 0644 "$SCRIPT_DIR/VERSION" /opt/vpn-control/VERSION

python3 -m venv /opt/vpn-control/.venv
/opt/vpn-control/.venv/bin/pip install --upgrade pip
/opt/vpn-control/.venv/bin/pip install -r /opt/vpn-control/requirements.txt

migrate_runtime_config "$DEFAULT_COUNTRY" "$LAN_IF" "$BIND_IP" "$LAN_NET" "$VPN_USER"
write_dns_config "$BIND_IP"

install -m 0755 "$SCRIPT_DIR/gateway.sh" /usr/local/sbin/tv-vpn-gateway
install -m 0644 "$SCRIPT_DIR/tv-vpn-gateway.service" \
    /etc/systemd/system/tv-vpn-gateway.service
install -m 0644 "$SCRIPT_DIR/vpn-control-dns.service" \
    /etc/systemd/system/vpn-control-dns.service
sed "s/__VPN_USER__/${VPN_USER}/g" "$SCRIPT_DIR/vpn-control-web.service" \
    > /etc/systemd/system/vpn-control-web.service
chmod 0644 /etc/systemd/system/vpn-control-web.service

if [[ -z "${WEB_PASSWORD:-}" ]]; then
    read -rsp "Web password for user '${WEB_USER}' (Enter = generate): " WEB_PASSWORD
    echo
fi
if [[ -z "${WEB_PASSWORD:-}" ]]; then
    WEB_PASSWORD="$(python3 -c 'import secrets; print(secrets.token_urlsafe(16))')"
    GENERATED_PASSWORD=true
else
    GENERATED_PASSWORD=false
fi
SECRET_KEY="$(python3 -c 'import secrets; print(secrets.token_urlsafe(48))')"

umask 077
cat > /etc/vpn-control-web.env <<ENVEOF
VPN_WEB_BIND=${BIND_IP}
VPN_WEB_PORT=${WEB_PORT}
VPN_WEB_USER=${WEB_USER}
VPN_WEB_PASSWORD=${WEB_PASSWORD}
VPN_WEB_SECRET_KEY=${SECRET_KEY}
VPN_CONFIG_PATH=/var/lib/vpn-control/config.json
VPN_HEALTH_PATH=/run/vpn-control/gateway-health.json
VPN_COMMAND_TIMEOUT=90
ENVEOF
chmod 0600 /etc/vpn-control-web.env

# Forwarding is enabled by the gateway service only after policy rules,
# the blackhole route, and nftables protection are in place.
rm -f /etc/sysctl.d/99-vpn-gateway.conf /etc/sysctl.d/99-tv-vpn-gateway.conf
sysctl -q -w net.ipv4.ip_forward=0

write_install_state \
    "$FORWARDING_WAS_ENABLED" \
    "$NORDVPN_GROUP_ADDED" \
    "$NORDVPN_ALLOWLIST_ADDED" \
    "$VPN_DNS_USER_CREATED"

systemctl daemon-reload
if command -v systemd-analyze >/dev/null 2>&1; then
    systemd-analyze verify \
        /etc/systemd/system/vpn-control-dns.service \
        /etc/systemd/system/tv-vpn-gateway.service \
        /etc/systemd/system/vpn-control-web.service
fi

systemctl enable tv-vpn-gateway.service vpn-control-dns.service vpn-control-web.service
systemctl reset-failed tv-vpn-gateway.service vpn-control-dns.service vpn-control-web.service 2>/dev/null || true
systemctl restart tv-vpn-gateway.service vpn-control-dns.service vpn-control-web.service

COUNTRY="$(jq -r '.country // "gr"' "$RUNTIME_CONFIG")"
nordvpn_set_idempotent autoconnect on "$COUNTRY"
nordvpn_as_user connect "$COUNTRY" || log "NordVPN connection was not established automatically; fail-closed protection remains active."

HEALTH_READY=false
for _ in $(seq 1 20); do
    if systemctl is-active --quiet tv-vpn-gateway.service && \
       systemctl is-active --quiet vpn-control-dns.service && \
       systemctl is-active --quiet vpn-control-web.service && \
       [[ -s /run/vpn-control/gateway-health.json ]] && \
       jq -e --arg version "$PROJECT_VERSION" '
            .version == $version and
            (.status == "healthy" or .status == "fail-closed") and
            .fail_closed_present == true and
            .nft_filter_present == true and
            .nft_nat_present == true and
            .dns_service_active == true and
            .dns_rule_present == true
       ' /run/vpn-control/gateway-health.json >/dev/null 2>&1; then
        HEALTH_READY=true
        break
    fi
    sleep 2
done

if [[ "$HEALTH_READY" != "true" ]]; then
    journalctl -u tv-vpn-gateway.service -u vpn-control-dns.service -u vpn-control-web.service \
        -n 100 --no-pager || true
    die "The installed services did not reach a protected healthy state."
fi

systemctl --no-pager --full status \
    tv-vpn-gateway.service vpn-control-dns.service vpn-control-web.service

cat <<EOF

Installation of ${PROJECT_VERSION} complete.
URL:      http://${BIND_IP}:${WEB_PORT}
Username: ${WEB_USER}
DNS:      ${BIND_IP}
EOF
if [[ "$GENERATED_PASSWORD" == "true" ]]; then
    echo "Password: ${WEB_PASSWORD}"
else
    echo "Password: the password you entered"
fi
cat <<EOF

Configure every managed device with:
  Gateway: ${BIND_IP}
  DNS:     ${BIND_IP}

Validate the installation with:
  sudo bash scripts/smoke-test.sh --with-failover

Do not expose port ${WEB_PORT} to the Internet.
EOF
