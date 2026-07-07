#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo: sudo ./update.sh"
    exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -d /opt/vpn-control || ! -f /etc/systemd/system/vpn-control-web.service ]]; then
    echo "Existing installation not found. Run sudo ./install.sh instead."
    exit 1
fi

python3 -m py_compile "$SCRIPT_DIR/app.py"
bash -n "$SCRIPT_DIR/gateway.sh"

stamp="$(date +%Y%m%d-%H%M%S)"
cp -a /opt/vpn-control/app.py "/opt/vpn-control/app.py.backup.${stamp}"
cp -a /usr/local/sbin/tv-vpn-gateway "/usr/local/sbin/tv-vpn-gateway.backup.${stamp}"

install -m 0644 "$SCRIPT_DIR/app.py" /opt/vpn-control/app.py
install -m 0644 "$SCRIPT_DIR/requirements.txt" /opt/vpn-control/requirements.txt
install -m 0755 "$SCRIPT_DIR/gateway.sh" /usr/local/sbin/tv-vpn-gateway

/opt/vpn-control/.venv/bin/pip install -r /opt/vpn-control/requirements.txt

systemctl restart tv-vpn-gateway.service vpn-control-web.service
sleep 2
systemctl --no-pager --full status tv-vpn-gateway.service vpn-control-web.service

echo
echo "Update completed. Runtime configuration and credentials were preserved."
