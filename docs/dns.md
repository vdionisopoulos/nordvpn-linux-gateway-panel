# Fail-closed DNS design

Version 0.3.0 adds a local dnsmasq proxy to reduce configuration mistakes and prevent fallback to the normal LAN resolver.

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

From another LAN host:

```bash
nslookup example.com GATEWAY-IP
dig @GATEWAY-IP example.com
```

On the gateway:

```bash
sudo systemctl status vpn-control-dns.service
ip -4 rule show | grep uidrange
sudo tcpdump -ni eth0 'port 53'
sudo tcpdump -ni nordlynx 'port 53'
```

Disconnect NordVPN and repeat the lookup. It should fail rather than use the normal LAN router.

## Limitations

The gateway cannot intercept DNS packets that a device sends directly to a resolver on the same Ethernet subnet, because those packets do not traverse the gateway. Configure the device DNS explicitly as the Ubuntu gateway address and reserve the device address in the router.

Encrypted DNS implemented inside an application, such as DoH or DoT, is ordinary application traffic. It is routed through the VPN when the application uses the Ubuntu gateway, but it does not use the local dnsmasq cache.
