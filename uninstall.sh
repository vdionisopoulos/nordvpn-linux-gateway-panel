#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo: sudo ./uninstall.sh"
    exit 1
fi

systemctl disable --now vpn-control-web.service 2>/dev/null || true
rm -f /etc/systemd/system/vpn-control-web.service
rm -f /etc/vpn-control-web.env
rm -rf /opt/vpn-control
systemctl daemon-reload

echo "Web panel removed."
echo "The gateway service and /var/lib/vpn-control/config.json were kept."
