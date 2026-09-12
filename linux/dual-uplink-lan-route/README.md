# Reaching LAN hosts on another subnet while the default route goes out a second uplink – Linux

## Purpose
Fix the case where a machine has two active connections at once (e.g. a wired NIC into the LAN and
a Wi-Fi/hotspot link used for internet), internet works fine, but hosts on a *different* subnet of
that same LAN become unreachable — even though the LAN's own router/gateway is still reachable.

## Symptom

- The LAN gateway (e.g. `10.0.0.1`) answers pings and its web UI loads fine.
- Other LAN hosts on a different subnet/VLAN (e.g. `10.0.16.20`, a NAS or home-automation box) time
  out completely.
- Both the wired and the wireless interface are up, and internet access works.

## Why it happens

With two active connections you end up with two default routes, one per interface, each with its
own metric (lower metric wins):

```
default via 172.20.10.1 dev wlan0 metric 600     ← hotspot, wins the default route
default via 10.0.0.1    dev eth0  metric 20100   ← wired LAN, loses
```

The LAN's gateway is reachable regardless, because it sits inside the wired NIC's *own* subnet
(e.g. `eth0` has `10.0.0.10/20`, which already covers `10.0.0.1` — no routing needed, just a local
network-adjacency lookup).

Any other LAN subnet (e.g. `10.0.16.0/20`, a separate VLAN) needs actual IP routing through that
gateway. With no specific route for it, the kernel falls back to the default route — and since the
hotspot's default route has the lower metric, it wins, so those packets go out over the phone
instead of the cable and get dropped there.

## Diagnosis

```bash
ip -br addr          # confirm both interfaces are up and note their subnets
ip route              # look for two "default via ..." lines with different metrics
ping -c1 <lan-gateway-ip>     # works: same-subnet, no routing involved
ping -c1 <other-lan-host-ip>  # fails: needs routing through the gateway
```

## Fix: add a specific route for the other subnet

A route matching a specific subnet is always preferred over a default route, regardless of metric —
so this fixes LAN access without touching how internet traffic is routed.

### Temporary (until reboot)

```bash
sudo ip route add <other-subnet>/<mask> via <lan-gateway-ip> dev <wired-interface>
# example:
sudo ip route add 10.0.16.0/20 via 10.0.0.1 dev eth0
```

Or with the included script:

```bash
chmod +x add-lan-route.sh
sudo ./add-lan-route.sh 10.0.16.0/20 10.0.0.1 eth0
```

Verify:

```bash
ip route
ping -c1 <other-lan-host-ip>
```

### Persistent route (NetworkManager)

Find the wired connection's profile name, then attach the route to it:

```bash
nmcli connection show                                    # find the profile name for the wired NIC
nmcli connection modify "Wired connection 1" +ipv4.routes "10.0.16.0/20 10.0.0.1"
nmcli connection up "Wired connection 1"
```

The route now survives reboots and reconnects, and only applies while that profile is active.

## Extra notes

- If the "other subnet" is actually a separate VLAN behind a router with inter-VLAN firewall
  rules, adding the route only gets the packets there — the router still has to be configured to
  allow traffic between the VLANs. Test with a device already known to work cross-VLAN before
  assuming the route alone is the fix.
- To remove a temporary route: `sudo ip route del <subnet>/<mask> via <gateway-ip> dev <interface>`.
- Finding the right subnet mask: `ip -br addr` shows each interface's own CIDR (e.g. `/20`); the
  unreachable host's subnet is often the same size on the same LAN, but confirm with whoever runs
  the router/VLANs if unsure.

---

**Last updated:** September 2026
