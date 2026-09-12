# Split-horizon LAN domain not resolving with two active connections – Linux

## Purpose
Fix the case where a machine has two active connections (e.g. a wired NIC into the LAN and a
Wi-Fi/hotspot link for internet), the LAN's own router provides local DNS answers for the site's
internal domain (a common split-horizon setup: same domain resolves to a LAN IP internally and to
a public IP or CDN from the outside), but a browser on that machine still can't resolve those
names — even though querying the LAN router directly works fine.

See [`dual-uplink-lan-route`](../dual-uplink-lan-route/README.md) first if the symptom is a LAN
*host* being unreachable rather than a name failing to resolve — this guide is the DNS-layer
counterpart of that one and the two are often needed together.

## Symptom

- `resolvectl query somehost.home.example` fails or returns nothing.
- Querying the LAN router's DNS service directly for the same name works
  (`resolvectl query --interface eth0 ...`, or a manual query to its IP) and returns the expected
  LAN address.
- The browser hangs or shows a DNS/name-resolution error for that domain, while unrelated internet
  domains resolve fine (through the other connection).

## Why it happens

`systemd-resolved` tracks one DNS server list per link. With two links up at once, it sends a
generic query (no interface pinned) to whichever link is treated as authoritative for that name —
by default, that's the link with the default route, not necessarily the one whose DNS server
actually knows the domain:

```bash
resolvectl status
# Link eth0  (LAN):     DNS Servers: 10.0.0.1        Default Route: no
# Link wlan0 (hotspot):  DNS Servers: 172.20.10.1     Default Route: yes
```

With no per-link routing domain configured, `resolvectl domain` shows both links empty, and every
plain query goes out over the default-route link (the hotspot here) — whose public resolver has no
idea about the LAN's internal domain, so it just returns nothing or NXDOMAIN.

## Diagnosis

```bash
resolvectl status                 # confirm both links are up, note which has "Default Route: yes"
resolvectl domain                 # any routing/search domain already set per link?
resolvectl query <name>           # what the system actually resolves right now
```

To check what each link's resolver *would* answer, query it directly and compare:

```bash
python3 - <<'PYEOF'
import socket, struct
def query(server, name, timeout=3):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(timeout)
    q = struct.pack(">HHHHHH", 1, 0x0100, 1, 0, 0, 0)
    for part in name.split("."):
        q += bytes([len(part)]) + part.encode()
    q += b"\x00" + struct.pack(">HH", 1, 1)
    s.sendto(q, (server, 53))
    data, _ = s.recvfrom(512)
    return struct.unpack(">H", data[6:8])[0]  # answer count
for server in ["10.0.0.1", "172.20.10.1"]:
    print(server, "-> answers:", query(server, "somehost.home.example"))
PYEOF
```

A non-zero answer count from the LAN router and zero from the other resolver confirms the query is
reaching the wrong server.

## Fix: route that domain's queries through the LAN link

A "routing-only" domain tells `systemd-resolved` to always ask a specific link's DNS server for
names under that domain, regardless of which link has the default route — without changing where
plain internet lookups go.

### Temporary check (no change persisted)

```bash
resolvectl query --interface eth0 somehost.home.example
```

### Persistent fix

```bash
sudo nmcli connection modify "<wired-connection-name>" +ipv4.dns-search "~home.example"
sudo nmcli connection up "<wired-connection-name>"
```

Or with the included script:

```bash
chmod +x set-dns-routing-domain.sh
sudo ./set-dns-routing-domain.sh "Wired connection 1" home.example
```

Verify:

```bash
resolvectl domain
# Link eth0: ~home.example
resolvectl query somehost.home.example
```

## Extra notes

- **Not a reverse-proxy or router problem:** a reverse proxy's per-path config (e.g. Nginx Proxy
  Manager's "Custom Locations") only applies to a request that already arrived there over HTTP(S)
  — it has no way to influence which DNS server a client asked to resolve the name in the first
  place. The LAN router can't fix a client's resolver choice either when the second uplink is
  external to it (e.g. a phone's hotspot): that link isn't part of the router's own network, so it
  has no visibility into it and no lever to pull. The fix belongs on the client, same as the
  routing case above.
- The `~` prefix marks it a *routing* domain (used only to pick which DNS server answers), not a
  *search* domain (used to expand bare hostnames) — it won't make `ping somehost` try
  `somehost.home.example` automatically.
- `+ipv4.dns-search` appends to the connection's existing list; dropping the `+` replaces it
  entirely, which can silently remove real search domains already configured on that connection.
- Any route added by hand with `sudo ip route add ...` (see
  [`dual-uplink-lan-route`](../dual-uplink-lan-route/README.md)) is **not persistent** and gets
  dropped the moment that connection is reactivated (`nmcli connection up`, a reconnect, a
  reboot) — if LAN hosts stop responding again right after a DNS fix like this one, check
  `ip route` first before assuming the DNS fix didn't work.

---

**Last updated:** September 2026
