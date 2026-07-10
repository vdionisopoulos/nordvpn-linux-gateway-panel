---
name: Bug report
about: Report a reproducible gateway, panel, DNS, routing, installer, updater, or service problem
title: "[Bug] "
labels: bug
assignees: ''
---

## Description

Describe the problem clearly and concisely.

## Expected behavior

What did you expect to happen?

## Actual behavior

What happened instead?

## Steps to reproduce

1.
2.
3.

## Environment

- Project version:
- Ubuntu version:
- Kernel version:
- Installation type: Physical host / Hyper-V / VMware / VirtualBox / Other
- NordVPN Linux client version:
- Browser and version, when applicable:

```bash
cat /opt/vpn-control/VERSION
lsb_release -a
uname -a
nordvpn version
```

## Network configuration

- Gateway LAN IPv4:
- LAN subnet:
- LAN interface:
- Managed device type and IPv4:
- Router/Gateway configured on the device:
- DNS configured on the device:

## Service status

```bash
sudo systemctl status tv-vpn-gateway.service --no-pager -l
sudo systemctl status vpn-control-dns.service --no-pager -l
sudo systemctl status vpn-control-web.service --no-pager -l
```

## Gateway health

```bash
sudo jq . /run/vpn-control/gateway-health.json
```

## Routing and nftables

```bash
ip -4 rule show
ip -4 route show table 200
sudo nft list table inet tv_vpn
sudo nft list table ip tv_vpn_nat
```

## Relevant logs

```bash
sudo journalctl -u tv-vpn-gateway.service -u vpn-control-dns.service -u vpn-control-web.service -n 150 --no-pager
```

## Smoke-test result

```bash
sudo bash scripts/smoke-test.sh
```

For failover-related issues:

```bash
sudo bash scripts/smoke-test.sh --with-failover
```

## Additional context

Add screenshots, timing details, and recent configuration changes.

Before submitting, redact passwords, tokens, public IP addresses, private device details, and other sensitive information. Report security vulnerabilities through the repository security policy rather than a public issue.
