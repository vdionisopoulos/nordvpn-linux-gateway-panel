# Contributing

1. Fork the repository and create a focused branch.
2. Never commit runtime credentials, NordVPN tokens, private keys, packet captures, or real device inventories.
3. Preserve the fail-closed behavior for both managed-device traffic and DNS.
4. Run the complete local checks:

```bash
python3 -m pip install -r requirements.txt -r requirements-dev.txt
ruff check .
pytest
bash -n gateway.sh install.sh update.sh uninstall.sh installer-lib.sh
shellcheck -x gateway.sh install.sh update.sh uninstall.sh
VPN_CONFIG_PATH=config.example.json ./gateway.sh --render-nft > /tmp/vpn-control.nft
sudo nft -c -f /tmp/vpn-control.nft
```

5. Describe the Ubuntu version, hypervisor or physical host, LAN topology, and NordVPN client version in the pull request.
6. Include upgrade and uninstall implications for changes to units, routes, nftables, dnsmasq, or runtime configuration.
