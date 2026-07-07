# Security Policy

## Reporting a vulnerability

Report security issues privately through GitHub Security Advisories when available. Do not open a public issue containing credentials, tokens, private IP inventories, packet captures, or authentication-bypass details.

## Deployment boundaries

- The web panel is intended for a trusted LAN only.
- Do not create an Internet-facing port forward for the web port.
- HTTP Basic Authentication does not encrypt credentials. Use a TLS reverse proxy if the LAN is not trusted.
- Never commit NordVPN access tokens, Nord Account passwords, WireGuard/NordLynx private keys, OpenVPN service credentials, or real runtime files.
- Configure managed devices with the Ubuntu gateway as both Router and DNS.
- Disable or separately control IPv6 to prevent bypassing an IPv4-only gateway.

## Sensitive local files

```text
/etc/vpn-control-web.env
/var/lib/vpn-control/config.json
/var/lib/vpn-control/install-state.json
```

If a token or key is accidentally published, revoke or rotate it immediately and then remove it from Git history.
