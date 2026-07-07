# Changelog

All notable changes to this project are documented here.

## [1.0.1] - 2026-07-07

### Changed

- Protected DNS is now an explicit mandatory component rather than a misleading optional runtime toggle
- Runtime configuration migration removes the obsolete `dns_enabled` key
- DNS verification documentation now distinguishes managed-device tests from intentionally blocked non-managed LAN hosts

### Fixed

- Prevented disabled-looking DNS configuration from producing permanently degraded health and failed updates
- Added a configuration contract test to prevent the obsolete DNS toggle from returning

## [1.0.0] - 2026-07-07

First stable release of the NordVPN Linux Gateway Panel.

### Added

- Installed-gateway smoke test with optional VPN disconnect/reconnect validation
- Stable release checklist covering clean install, upgrade, failover, and uninstall
- Automated tagged-release workflow producing ZIP, tar.gz, and SHA-256 checksum files
- Transactional updater rollback for managed files and systemd units
- Packaged `VERSION` file used by the application, installer, updater, and health heartbeat

### Changed

- Gateway protection now starts before the local DNS proxy and web panel
- The DNS proxy requires the gateway service and is started in the same ordered systemd transaction
- The updater validates all services and the protected health state before declaring success
- The web service tolerates a temporarily absent runtime health directory during startup
- Installation and update output now includes the installed version and smoke-test command
- LAN Discovery is replaced with the exact subnet allowlist through a local transient systemd unit
- DNS failover validation now uses unique uncached query names and accepts only normal upstream results (`NOERROR` or `NXDOMAIN`) as evidence that a resolver was reached

### Fixed

- Removed the brief startup interval in which the DNS proxy could be available before gateway nftables protection
- Added automatic restoration of previous managed files if an update fails
- Rollback now terminates the failed update instead of allowing a misleading success message
- Removed stale DNS enablement links when rolling back an upgrade from a version without the DNS service
- Prevented DNS restart jobs from being canceled during ordered service startup
- Allowed the hardened gateway service to read the protected runtime configuration without restoring broad root capabilities
- Allowed dnsmasq to open the required netlink socket while retaining systemd address-family restrictions
- Prevented cached answers and locally generated `SERVFAIL` responses from causing false DNS failover failures in the smoke test
- Centralized release-version handling to prevent application, installer, and heartbeat version drift

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
