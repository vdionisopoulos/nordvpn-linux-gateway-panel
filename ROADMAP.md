# Project roadmap

This document describes the **suggested direction** for future releases of NordVPN Linux Gateway Panel.

The roadmap is intentionally flexible. Version scope and ordering may change after testing, user feedback, security review, or changes in the NordVPN Linux client. A feature is not considered committed until it is tracked in an issue or included in an active release pull request.

Current stable release: **v1.0.3**

## Guiding principles

Every future change should preserve these guarantees:

- Managed devices must not silently fall back to the normal LAN router.
- DNS must remain fail-closed when the VPN tunnel is unavailable.
- Updates must remain transactional and recoverable.
- Runtime secrets and private configuration must stay outside the repository.
- New privileges, capabilities, listeners, and firewall exceptions must be minimized.
- Existing installations should remain upgradeable whenever practical.

---

## v1.0.3 — Maintenance and repository quality

**Status:** delivered.

Delivered scope:

- Completed the GitHub Community Profile templates.
- Removed the obsolete version-specific tag workflow.
- Added reusable version-aware release publishing.
- Improved English and Greek UI labels and operational errors.
- Updated development dependencies.
- Added automated release metadata synchronization checks.
- Added startup convergence handling to the installed-gateway smoke test.
- Expanded regression coverage and release documentation.

---

## v1.1.0 — Diagnostics and operations

**Goal:** make the gateway easier to operate, validate, and support.

Suggested scope:

- Add a **Run diagnostics** action to the web panel.
- Show smoke-test results in a safe, read-only diagnostics view.
- Add DNS resolution and tunnel connectivity checks.
- Show tunnel uptime, last reconnect time, and current server details.
- Add a sanitized support-bundle export containing:
  - installed version,
  - gateway health,
  - service status,
  - policy rules,
  - routing table `200`,
  - nftables rules,
  - recent redacted logs.
- Add an audit log for:
  - country changes,
  - connect/disconnect/reconnect actions,
  - device additions and removals,
  - configuration restore operations,
  - application updates.
- Add configuration backup and restore with validation before activation.

Security requirement: support bundles must exclude passwords, tokens, public IP addresses, and private device details unless the user explicitly chooses to include them.

---

## v1.2.0 — Device groups and routing policies

**Goal:** provide more flexible per-device operation while preserving explicit fail-closed behavior.

Suggested scope:

- Device groups such as TVs, tablets, consoles, and guests.
- Enable or pause VPN routing without deleting a device.
- Optional schedules per device or group.
- Online/offline visibility and last-seen timestamps.
- Notes and tags for managed devices.
- Import and export of the managed-device list.
- Explicit bypass policies with clear warnings and audit history.

Example policies:

```text
Living-room TV → VPN every day, 18:00–01:00
Console        → VPN on weekends
Tablet         → Always VPN
Guest device   → Temporarily paused
```

A bypass policy must never be created implicitly. The UI and configuration should distinguish clearly between **VPN**, **fail-closed**, **paused**, and **intentional bypass** states.

---

## v1.3.0 — Security and access control

**Goal:** strengthen panel access for less-trusted LAN environments.

Suggested scope:

- Optional HTTPS deployment using Caddy or Nginx.
- Form-based login instead of HTTP Basic Authentication.
- Session expiration and login rate limiting.
- Roles:
  - Administrator,
  - Operator,
  - Read-only.
- Optional TOTP multi-factor authentication.
- Panel access restrictions by subnet.
- Security-event audit records.
- Encrypted configuration backup export.
- Optional Unix-socket communication between reverse proxy and Gunicorn.

These features should remain optional so the basic LAN-only installation stays lightweight.

---

## v1.4.0 — Monitoring, metrics, and alerts

**Goal:** provide proactive visibility when the gateway or tunnel changes state.

Suggested scope:

- Prometheus-compatible metrics endpoint.
- Example Grafana dashboard.
- Historical health and reconnect data.
- Notifications through configurable channels:
  - email,
  - Telegram,
  - Discord,
  - generic webhook.
- Alerts when:
  - the VPN tunnel disconnects,
  - the DNS proxy is not protected,
  - the blackhole route disappears,
  - policy-rule counts differ from the expected state,
  - nftables protection is missing,
  - an update or rollback fails.

Possible metrics:

```text
vpn_gateway_healthy
vpn_tunnel_connected
vpn_policy_rules_expected
vpn_policy_rules_actual
vpn_dns_protected
vpn_managed_devices
vpn_reconnect_total
```

Metrics must not expose device names, private addresses, credentials, or public IP information by default.

---

## v2.0.0 — Multiple tunnels and per-device countries

**Goal:** support independent VPN profiles for different devices or groups.

Example target behavior:

```text
Living-room TV → United States
Bedroom TV     → Greece
Tablet          → Germany
Console         → United Kingdom
```

This is a major architectural change and requires research and prototyping. The current NordVPN CLI normally manages one active tunnel, so a possible design may require:

- Linux network namespaces,
- one tunnel process or profile per namespace,
- separate routing tables,
- nftables marks,
- device-to-profile mapping,
- independent DNS handling per tunnel,
- a fail-closed blackhole route for every profile,
- migration of the configuration schema and systemd service model.

Conceptual model:

```text
Device group US
  → fwmark 101
  → routing table 201
  → namespace vpn-us
  → US tunnel

Device group DE
  → fwmark 102
  → routing table 202
  → namespace vpn-de
  → DE tunnel
```

Release v2.0.0 should proceed only after the design proves that isolation, DNS routing, restart behavior, upgrades, and fail-closed guarantees remain reliable.

---

## Longer-term ideas

These items are candidates rather than scheduled releases:

- IPv6 fail-closed routing.
- ARM64 and Raspberry Pi validation.
- Debian support.
- Docker or Podman deployment where networking constraints allow it.
- Ansible role and cloud-init installation.
- Documented REST API.
- Home Assistant integration.
- OpenWrt companion integration.
- High availability with a second gateway.
- Provider abstraction for other WireGuard-compatible VPN services.

## Contributing to the roadmap

Feature requests should explain:

1. The problem being solved.
2. The expected operational behavior.
3. The effect on routing, DNS, nftables, privileges, and fail-closed guarantees.
4. Backward-compatibility and upgrade considerations.
5. Tests required to prove safe behavior.

Please open a GitHub issue before starting a large implementation so the architecture and release target can be discussed first.
