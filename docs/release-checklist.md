# Stable release checklist

Use this checklist before publishing a stable version.

## Repository validation

- [ ] `VERSION`, application version, gateway heartbeat version, README, and CHANGELOG agree
- [ ] Pull-request CI is green
- [ ] Ruff, pytest, Bash syntax, ShellCheck, nftables validation, and systemd verification pass
- [ ] No credentials, real runtime configuration, tokens, private keys, or packet captures are committed
- [ ] Installation and update documentation matches the scripts
- [ ] Release notes contain upgrade and rollback implications

## Clean installation test

Test on a supported Ubuntu Server VM with a bridged/external NIC:

```bash
git clone --branch release/v1.0.0 \
  https://github.com/vdionisopoulos/nordvpn-linux-gateway-panel.git
cd nordvpn-linux-gateway-panel
sudo ./install.sh
sudo bash scripts/smoke-test.sh --with-failover
```

Confirm:

- [ ] All three systemd services are active
- [ ] SSH remains reachable after the first NordVPN connection
- [ ] The web panel remains reachable on the LAN
- [ ] A managed device reaches the Internet through the selected NordVPN country
- [ ] The managed device uses the Ubuntu gateway for DNS
- [ ] DNS fails closed when NordVPN disconnects
- [ ] DNS and application connectivity recover after reconnect
- [ ] Device add/remove and country change operations work from the panel

## Upgrade test

Test an upgrade from the latest previous public version:

```bash
git fetch origin
git switch release/v1.0.0
sudo ./update.sh
sudo bash scripts/smoke-test.sh --with-failover
```

Confirm:

- [ ] Managed-device inventory is preserved
- [ ] Web credentials are preserved
- [ ] Selected country is preserved
- [ ] Runtime configuration is migrated correctly
- [ ] systemd units are updated and reloaded
- [ ] Five-backup rotation is enforced
- [ ] A failed update restores the previous managed files and services

## Uninstall test

- [ ] `--panel-only` removes only the panel
- [ ] `--all` removes services, routing, nftables, and DNS while preserving runtime configuration
- [ ] `--purge` removes installer-owned runtime state and installer-created account/group changes
- [ ] The host's original IPv4 forwarding state is restored

## Documentation and presentation

- [ ] Add a current screenshot of the running panel under `docs/screenshots/`
- [ ] Verify English and Greek README instructions
- [ ] Verify the architecture and DNS diagrams render correctly
- [ ] Verify repository description and topics

## Publish

After the release pull request is approved and merged:

```bash
git switch main
git pull --ff-only
git tag -a v1.0.0 -m "NordVPN Linux Gateway Panel v1.0.0"
git push origin v1.0.0
```

Pushing the annotated tag runs the release workflow, validates the tagged source again, creates source archives and SHA-256 checksums, and publishes the GitHub Release.
