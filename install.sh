#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo: sudo ./install.sh"
    exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VPN_USER="${VPN_USER:-${SUDO_USER:-}}"
WEB_PORT="${WEB_PORT:-8080}"
WEB_USER="${WEB_USER:-admin}"
DEFAULT_COUNTRY="${DEFAULT_COUNTRY:-gr}"

if [[ -z "$VPN_USER" ]]; then
    echo "Could not determine the non-root account. Run with sudo or set VPN_USER explicitly."
    exit 1
fi

id "$VPN_USER" >/dev/null 2>&1 || {
    echo "User not found: $VPN_USER"
    exit 1
}

command -v nordvpn >/dev/null 2>&1 || {
    echo "NordVPN Linux CLI is not installed. Install it and log in before running this installer."
    exit 1
}

LAN_IF="${LAN_IF:-$(ip -4 route show default | awk 'NR==1 {print $5}')}"
if [[ -z "$LAN_IF" ]]; then
    echo "Could not detect the LAN interface. Set LAN_IF explicitly."
    exit 1
fi

BIND_IP="${BIND_IP:-$(ip -4 -o addr show dev "$LAN_IF" scope global | awk 'NR==1 {split($4,a,"/"); print a[1]}')}"
# Fallback kept separate to avoid obscure shell errors on unusual ip output.
if [[ -z "${BIND_IP:-}" ]]; then
    BIND_IP="$(ip -4 -o addr show dev "$LAN_IF" scope global | awk 'NR==1 {print $4}' | cut -d/ -f1)"
fi
LAN_NET="${LAN_NET:-$(ip -4 route show dev "$LAN_IF" proto kernel scope link | awk 'NR==1 {print $1}')}"

if [[ -z "$BIND_IP" || -z "$LAN_NET" ]]; then
    echo "Could not auto-detect BIND_IP or LAN_NET. Set them explicitly."
    exit 1
fi

echo "Installing packages..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 python3-venv python3-pip jq nftables curl

install -d -m 0755 /opt/vpn-control
install -m 0644 "$SCRIPT_DIR/app.py" /opt/vpn-control/app.py
install -m 0644 "$SCRIPT_DIR/requirements.txt" /opt/vpn-control/requirements.txt

python3 -m venv /opt/vpn-control/.venv
/opt/vpn-control/.venv/bin/pip install --upgrade pip
/opt/vpn-control/.venv/bin/pip install -r /opt/vpn-control/requirements.txt

install -d -o "$VPN_USER" -g "$VPN_USER" -m 0750 /var/lib/vpn-control

if [[ ! -f /var/lib/vpn-control/config.json ]]; then
    jq -n \
      --arg country "$DEFAULT_COUNTRY" \
      --arg lan_if "$LAN_IF" \
      --arg lan_ip "$BIND_IP" \
      --arg lan_net "$LAN_NET" \
      '{
        country: $country,
        devices: [],
        lan_if: $lan_if,
        lan_ip: $lan_ip,
        lan_net: $lan_net,
        vpn_if: "nordlynx",
        route_table: 200,
        rule_priority: 10000,
        check_interval: 5
      }' > /var/lib/vpn-control/config.json
    chown "$VPN_USER:$VPN_USER" /var/lib/vpn-control/config.json
    chmod 0640 /var/lib/vpn-control/config.json
else
    echo "Keeping existing /var/lib/vpn-control/config.json"
fi

if [[ -f /usr/local/sbin/tv-vpn-gateway ]]; then
    cp -a /usr/local/sbin/tv-vpn-gateway \
        "/usr/local/sbin/tv-vpn-gateway.backup.$(date +%Y%m%d-%H%M%S)"
fi
install -m 0755 "$SCRIPT_DIR/gateway.sh" /usr/local/sbin/tv-vpn-gateway

if [[ -f /etc/systemd/system/tv-vpn-gateway.service ]]; then
    cp -a /etc/systemd/system/tv-vpn-gateway.service \
        "/etc/systemd/system/tv-vpn-gateway.service.backup.$(date +%Y%m%d-%H%M%S)"
fi
install -m 0644 "$SCRIPT_DIR/tv-vpn-gateway.service" \
    /etc/systemd/system/tv-vpn-gateway.service

sed "s/__VPN_USER__/${VPN_USER}/g" \
    "$SCRIPT_DIR/vpn-control-web.service" \
    > /etc/systemd/system/vpn-control-web.service
chmod 0644 /etc/systemd/system/vpn-control-web.service

groupadd -f nordvpn
usermod -aG nordvpn "$VPN_USER"

if [[ -z "${WEB_PASSWORD:-}" ]]; then
    read -rsp "Web password for user '${WEB_USER}' (Enter = generate): " WEB_PASSWORD
    echo
fi
if [[ -z "${WEB_PASSWORD:-}" ]]; then
    WEB_PASSWORD="$(python3 -c 'import secrets; print(secrets.token_urlsafe(16))')"
    GENERATED_PASSWORD=1
else
    GENERATED_PASSWORD=0
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
VPN_COMMAND_TIMEOUT=90
ENVEOF
chmod 0600 /etc/vpn-control-web.env

cat > /etc/sysctl.d/99-vpn-gateway.conf <<'SYSCTLEOF'
net.ipv4.ip_forward = 1
SYSCTLEOF
sysctl --system >/dev/null

systemctl daemon-reload
systemctl enable tv-vpn-gateway.service vpn-control-web.service
systemctl restart tv-vpn-gateway.service
systemctl restart vpn-control-web.service

COUNTRY="$(jq -r '.country // "gr"' /var/lib/vpn-control/config.json)"
runuser -u "$VPN_USER" -- nordvpn set autoconnect on "$COUNTRY" || true

echo
echo "Installation complete."
echo "URL:      http://${BIND_IP}:${WEB_PORT}"
echo "Username: ${WEB_USER}"
if [[ "$GENERATED_PASSWORD" -eq 1 ]]; then
    echo "Password: ${WEB_PASSWORD}"
else
    echo "Password: the password you entered"
fi
echo
echo "Do not expose port ${WEB_PORT} to the Internet."
echo "Check services:"
echo "  systemctl status tv-vpn-gateway.service --no-pager"
echo "  systemctl status vpn-control-web.service --no-pager"
