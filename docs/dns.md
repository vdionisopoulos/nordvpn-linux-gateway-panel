# Fail-closed DNS design

Version 0.3.0 added a local dnsmasq proxy to reduce configuration mistakes and prevent fallback to the normal LAN resolver.

## Data path

```text
Managed device
  DNS = Ubuntu gateway
        |
        v
vpn-control-dns.service (dnsmasq, user vpn-dns)
        |
        v
ip rule uidrange <vpn-dns-uid> lookup 200
        |
        +--> nordlynx default route, when available
        |
        +--> blackhole default, when unavailable
```

The DNS proxy uses these upstream resolvers by default:

```text
103.86.96.100
103.86.99.100
```

The upstream addresses are stored in the runtime configuration and rendered into `/etc/vpn-control/dnsmasq.conf` by the installer/updater.

## Why a local proxy is needed

When a managed device uses the LAN router as DNS, its DNS packets remain inside the local subnet and can reach the router directly without using the Ubuntu default gateway. Routing application traffic through the VPN therefore does not by itself prevent a LAN DNS leak.

## Verification

The nftables input chain accepts gateway DNS requests only from addresses listed in `devices`. DNS requests from other LAN hosts are intentionally dropped.

From a **managed device**:

```bash
nslookup example.com GATEWAY-IP
dig @GATEWAY-IP example.com
```

From the gateway itself:

```bash
nslookup example.com GATEWAY-IP
dig @GATEWAY-IP example.com
sudo systemctl status vpn-control-dns.service
ip -4 rule show | grep uidrange
sudo tcpdump -ni eth0 'port 53'
sudo tcpdump -ni nordlynx 'port 53'
```

A lookup from an unregistered administrator laptop or another non-managed LAN host is expected to time out. Add that host temporarily as a managed device only when an end-to-end LAN test is required.

Disconnect NordVPN and repeat an uncached lookup from a managed device. It should fail closed rather than use the normal LAN router. The supplied smoke test performs this check with unique query names:

```bash
sudo bash scripts/smoke-test.sh --with-failover
```

## Limitations

The gateway cannot intercept DNS packets that a device sends directly to a resolver on the same Ethernet subnet, because those packets do not traverse the gateway. Configure the device DNS explicitly as the Ubuntu gateway address and reserve the device address in the router.

Encrypted DNS implemented inside an application, such as DoH or DoT, is ordinary application traffic. It is routed through the VPN when the application uses the Ubuntu gateway, but it does not use the local dnsmasq cache.
