# Changelog

All notable changes to this project are documented here.

## [0.3.0] - 2026-07-07

### Added

- Dedicated dnsmasq-based DNS proxy bound to the gateway LAN address
- UID-based policy routing for DNS traffic through the fail-closed VPN table
- DNS service health in the gateway heartbeat and web panel
- DNS leak verification documentation
- `vpn-control-dns.service`

### Changed

- Managed devices now use the Ubuntu gateway address for both Router and DNS
- Runtime configuration schema now includes DNS service settings
- Installer and updater install `dnsmasq-base`

## [0.2.0] - 2026-07-07

### Added

- Exact NordVPN LAN subnet allowlist configuration
- Required NordVPN settings preflight
- Gateway heartbeat with policy-rule, route, nftables, and service checks
- Health status in the web panel
- Safer startup ordering that enables forwarding only after fail-closed controls
- Complete uninstall modes: `--panel-only`, `--all`, and `--purge`
- ShellCheck, Ruff, pytest, nftables validation, and systemd unit validation in CI
- systemd service hardening
- Backup rotation

### Fixed

- `update.sh` now updates all systemd units and runs `systemctl daemon-reload`
- Existing installs no longer remain on stale unit files after an update

## [0.1.0] - 2026-07-07

### Added

- Initial multi-device NordVPN gateway
- LAN web panel
- Per-device source policy routing
- nftables NAT and fail-closed routing
