# Security Policy

## Reporting a vulnerability

Please report security issues privately through GitHub Security Advisories when available. Do not open a public issue containing credentials, tokens, private IP inventories, packet captures, or authentication bypass details.

## Deployment boundaries

- The web panel is intended for a trusted LAN only.
- Do not create an Internet-facing port forward for the web port.
- HTTP Basic Authentication does not encrypt credentials. Use a TLS reverse proxy if the LAN is not trusted.
- Never commit `/etc/vpn-control-web.env`, `/var/lib/vpn-control/config.json`, NordVPN tokens, WireGuard private keys, or packet captures.
- Disable or separately control IPv6 on managed clients to avoid bypassing an IPv4-only gateway.
