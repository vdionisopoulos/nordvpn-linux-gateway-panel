---
name: Bug report
about: Report a reproducible problem in the VPN gateway, web panel, DNS, routing,
  installer, updater, or systemd services
title: Add screenshots, timing details, recent configuration changes, or anything
  else that may help.
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
- Browser and version, if the issue concerns the web panel:

Commands that may help:

```bash
cat /opt/vpn-control/VERSION
lsb_release -a
uname -a
nordvpn version

##Managed-device network configuration
- Gateway LAN IPv4:
- LAN subnet:
- LAN interface:
- Managed device type:
- Managed device IPv4:
- Router/Gateway configured on the device:
- DNS configured on the device:

##Service Status
sudo systemctl status tv-vpn-gateway.service --no-pager -l
sudo systemctl status vpn-control-dns.service --no-pager -l
sudo systemctl status vpn-control-web.service --no-pager -l
Paste the relevant output here:
