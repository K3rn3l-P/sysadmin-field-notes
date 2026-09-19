# Zigbee coordinator over the network with ser2net on a Raspberry Pi Zero W

## Purpose

Move a USB Zigbee coordinator off a host that can no longer see it — a dead USB controller, a
machine being retired, a stick that has to sit somewhere with better reception — onto a Raspberry
Pi Zero W, and expose it over TCP with `ser2net`. Home Assistant (ZHA or Zigbee2MQTT) then talks to
`socket://<pi>:20108` instead of `/dev/ttyUSB0`, and every paired device keeps working.

The guide prepares the card fully headless, with no monitor and **no internet access on the Pi
itself** — which matters when the network the Pi joins has no uplink.

Everything below was done on a Pi Zero W v1.1 with a Sonoff Zigbee 3.0 USB Dongle Plus V2, against
Raspberry Pi OS Lite (Trixie, armhf) and Home Assistant 2026.8.

## The two traps

These cost the whole morning. Both fail silently: no error, no warning, just a Pi that never
appears on the network or a package that dies the moment it runs.

### 1. The Wi-Fi radio ships blocked, and the country code does not unblock it

Raspberry Pi OS ships `/etc/modprobe.d/rfkill_default.conf` containing `options rfkill
default_state=0`, so the wireless radio comes up **soft-blocked**. Setting
`cfg80211.ieee80211_regdom=XX` in `cmdline.txt` tells the kernel which regulatory domain to use —
it does not lift the block. A headless Pi prepared that way boots perfectly, creates its user,
resizes its filesystem, and never joins any network.

`raspi-config`'s `do_wifi_country` unblocks it as a separate step. Offline, on a mounted card, the
equivalent is:

```bash
# systemd-rfkill restores this saved state at boot
echo 0 > /mnt/root/var/lib/systemd/rfkill/*:wlan

printf '[main]\nNetworkingEnabled=true\nWirelessEnabled=true\nWWANEnabled=true\n' \
  > /mnt/root/var/lib/NetworkManager/NetworkManager.state
```

`prepare-pi-card.sh` does both, and also installs a `wifi-unblock.service` that runs
`rfkill unblock all` before NetworkManager on every boot.

The confirmation that this is the cause is sitting on the card itself: the saved state file reads
`1`.

```bash
$ cat /mnt/root/var/lib/systemd/rfkill/platform-20300000.mmcnr:wlan
1
```

The OS even ships a login banner for this exact situation,
`/etc/profile.d/wifi-check.sh`, which prints *"Wi-Fi is currently blocked by rfkill"* — useless
when nothing can log in.

### 2. Debian `armhf` is ARMv7, Raspbian `armhf` is ARMv6

A Pi Zero W v1.1, a Pi Zero and a Pi 1 are **BCM2835, ARMv6**. A Pi Zero 2 W, a Pi 2 and everything
newer are ARMv7 or ARMv8.

Debian's own `armhf` port targets **ARMv7-A**. Raspberry Pi OS 32-bit is a separate rebuild
(Raspbian) targeting **ARMv6**. Same `armhf` label, same package names, same version numbers — so a
`.deb` taken from the wrong archive installs without complaint and then dies with `Illegal
instruction`.

Check before trusting a package:

```bash
ar x ser2net_4.6.4-1_armhf.deb && tar xf data.tar.*
readelf -A ./usr/sbin/ser2net | grep Tag_CPU_arch
```

- `Tag_CPU_arch: v6` → Raspbian, runs on a Zero W
- `Tag_CPU_arch: v7` → Debian, **will not run** on a Zero W

The right archive for an ARMv6 Pi is `http://raspbian.raspberrypi.com/raspbian/`, not
`http://deb.debian.org/debian/`. Confirm which one the image expects:

```bash
grep -r URIs /etc/apt/sources.list.d/
# URIs: http://raspbian.raspberrypi.com/raspbian/
```

## Prerequisites

- A Raspberry Pi Zero W and a micro-USB **OTG** adapter for the Zigbee stick (the port marked
  `USB`, not `PWR`).
- A microSD card, and a Linux machine with `xz`, `openssl` and `readelf` to prepare it.
- Raspberry Pi OS **Lite, 32-bit (armhf)** — the desktop is useless here and the 64-bit image does
  not boot on ARMv6 hardware.
- The Wi-Fi network must offer **2.4 GHz**: a Zero W has no 5 GHz radio.

## 1. Download and verify the image

```bash
BASE=https://downloads.raspberrypi.com/raspios_lite_armhf/images
DIR=raspios_lite_armhf-2026-09-15
IMG=2026-09-15-raspios-trixie-armhf-lite.img.xz

curl -LO "$BASE/$DIR/$IMG"
curl -LO "$BASE/$DIR/$IMG.sha256"
sha256sum -c "$IMG.sha256"
```

Confirm it really targets ARMv6 before writing it, straight out of the image. No mounting and no
root needed, because `debugfs` opens an image file at an offset:

```bash
xz -dc "$IMG" > lite.img
fdisk -l -o Device,Start,Sectors,Type lite.img     # note the start sector of partition 2

OFFSET=$(( 1064960 * 512 ))
debugfs -R "dump /bin/bash ./bash_img" "lite.img?offset=$OFFSET"
readelf -A ./bash_img | grep Tag_CPU_arch          # expect v6
```

The same trick answers which archive the image uses and which package versions it ships:

```bash
debugfs -R "cat /etc/apt/sources.list.d/raspbian.sources" "lite.img?offset=$OFFSET"
debugfs -R "dump /var/lib/dpkg/status ./dpkgstatus" "lite.img?offset=$OFFSET"
```

## 2. Collect the packages the Pi cannot download itself

If the Pi will land on a network without internet, fetch `ser2net` and its dependencies on the
machine preparing the card.

```bash
mkdir -p deb
curl -s http://raspbian.raspberrypi.com/raspbian/dists/trixie/main/binary-armhf/Packages.gz \
  | zcat > Packages

fetch() {
  path=$(awk -v p="$1" '$1=="Package:"{c=$2} c==p && $1=="Filename:"{print $2; exit}' Packages)
  curl -sL -o "deb/$(basename "$path")" "http://raspbian.raspberrypi.com/raspbian/$path"
}

for pkg in ser2net libgensio6t64 libyaml-0-2; do fetch "$pkg"; done
```

**That set is not enough on a Lite image.** `libgensio6t64` pulls in a dozen libraries, and on
Raspberry Pi OS Lite four of them are missing. Read the dependencies rather than copying a list —
they change between releases:

```bash
awk '$1=="Package:"{c=$2} c=="libgensio6t64" && $1=="Depends:"' Packages
```

then ask the Pi itself which of them it does not already have:

```bash
for p in libasound2t64 libavahi-client3 libavahi-common3 libopenipmi0t64 \
         libpython3.13 libsctp1 libssl3t64 libwrap0; do
  printf '%-22s ' "$p"; dpkg-query -W -f='${Version}\n' "$p" 2>/dev/null || echo MISSING
done
```

On Trixie Lite that came back as `libavahi-client3`, `libopenipmi0t64` and `libsctp1` — which in
turn need `libncurses6`. Fetch those too, and repeat the check once after installing: a dependency
of a dependency only shows up on the second pass.

Installing all the `.deb` files in **one** `dpkg -i` call lets dpkg sort out their order itself.

## 3. Write and prepare the card

[`prepare-pi-card.sh`](prepare-pi-card.sh) writes the image and configures the first boot. It
refuses any disk that is not removable, and asks for confirmation before erasing anything.

```bash
chmod +x prepare-pi-card.sh
sudo ./prepare-pi-card.sh /dev/sdc 2026-09-15-raspios-trixie-armhf-lite.img.xz ./deb
```

It asks for the username, the password, the hostname, the Wi-Fi network and the country code, and
then:

| What | Where | Why |
|---|---|---|
| empty `ssh` file | boot partition | `sshswitch.service` finds it and enables `ssh` |
| `userconf.txt` as `user:hash` | boot partition | `userconf-service` renames the default user and sets its password |
| `cfg80211.ieee80211_regdom=XX` | `cmdline.txt` | picks the regulatory domain |
| `0` in `/var/lib/systemd/rfkill/*:wlan` | root partition | **unblocks the radio** — see trap 1 |
| `WirelessEnabled=true` in `NetworkManager.state` | root partition | NetworkManager starts with the radio on |
| `wifi-unblock.service` | root partition | `rfkill unblock all` before NetworkManager, every boot |
| `wifi.nmconnection`, mode `600` | `/etc/NetworkManager/system-connections/` | NetworkManager ignores a file others can read |
| the `.deb` files | `/root/packages/` | so the Pi never needs an uplink |

Three details worth keeping:

- The password hash comes from `openssl passwd -6 -stdin`. Passing the password as an argument
  would expose it in the process list to every user on the machine.
- The connection file deliberately has **no `interface-name=`**. Pinning it to `wlan0` buys
  nothing on a Pi with one radio and silently prevents the connection from matching if the
  interface is named anything else.
- Which first-boot mechanism an image supports is written in the image itself. Rather than guessing
  between `ssh`, `userconf.txt`, `firstrun.sh` and `custom.toml`, read the scripts that look for
  them: `/usr/lib/raspberrypi-sys-mods/sshswitch` and `/usr/lib/userconf-pi/userconf-service`.

## 4. First boot

Insert the card, connect the Zigbee stick through the OTG adapter, power the Pi and wait about 90
seconds — the first boot resizes the filesystem and reboots once.

NetworkManager sends the hostname as the DHCP client name, so **the router's client list is the
fastest way to find the Pi**. Failing that, its SSH banner identifies it: Raspberry Pi OS builds
say `Raspbian`, ordinary Debian machines say `Debian`.

```bash
$ ssh <user>@<hostname>.local
# or, from another subnet where mDNS does not reach:
$ ssh <user>@<ip>
```

Find the stick and, above all, its stable path. Device names like `/dev/ttyUSB0` move between
reboots; the `by-id` symlink does not.

```bash
ls -l /dev/serial/by-id/
dmesg | grep -iE "ttyUSB|ttyACM|cp210x|ch341|ftdi"
```

## 5. Install and configure ser2net

```bash
sudo dpkg -i /root/packages/*.deb
```

The glob needs to expand as root, since `/root` is not readable by the login user — run it as
`sudo bash -c 'dpkg -i /root/packages/*.deb'` if the shell reports *No such file or directory*.

Write `/etc/ser2net.yaml`. ser2net 4.x reads YAML; the single-line `ser2net.conf` format belongs to
3.x and is ignored.

```yaml
%YAML 1.1
---
connection: &zigbee
  accepter: tcp,20108
  connector: serialdev,/dev/serial/by-id/usb-XXXX-if00-port0,115200n81,local
  options:
    kickolduser: true
```

Replace the `by-id` path with the real one, and the baud rate with the coordinator's — 115200 for
Sonoff, most Texas Instruments and most Silicon Labs sticks. `kickolduser` lets a reconnecting
client take over from a session the server still believes is alive, which is what happens every
time Home Assistant restarts.

```bash
sudo systemctl enable --now ser2net
systemctl is-active ser2net
ss -lntp | grep 20108
```

Check reachability **from the machine that will actually use it**, not only from your desk:

```bash
nc -w 3 -z <pi-ip> 20108 && echo reachable
```

## 6. Point Home Assistant at it

ZHA does not implement a reconfigure flow, so the path change goes through its options flow:

1. **Settings → Devices & services → ZHA → Configure**.
2. *"A backup will be performed and ZHA will be stopped. Do you wish to continue?"* → continue.
3. *"Migrate or change adapter settings"* → **change the settings of the current adapter**.
4. *"Select a serial port"* → the dropdown still shows the old `usb-…` path, now marked as unknown.
   Do not submit it: pick the **manual entry** option, submit, and only then does an empty
   *Serial device path* field appear.
5. Enter `socket://<pi-ip>:20108`. Port speed `115200`, no flow control — on a socket the speed is
   not used, and ZHA's own documentation lists these fields as *"not applicable for all radios"*.
6. ZHA takes a backup, reconnects over TCP and reports the adapter change as done. Paired devices
   are preserved: it is the same radio, with the same EUI64 and the same network keys, reached down
   a different cable.

The radio type must match what the entry already used. It is readable without guessing:

```bash
python3 -c 'import json;print([e["data"] for e in
  json.load(open("/config/.storage/core.config_entries"))["data"]["entries"]
  if e["domain"]=="zha"])'
# {'device': {'baudrate': 115200, ...}, 'radio_type': 'ezsp'}
```

Use the Pi's IP address rather than its `.local` name: mDNS from inside a container is one more
thing that can fail at boot, and a Zigbee coordinator that comes up late leaves every device
unavailable. Give the Pi a DHCP reservation.

### What ZHA's own documentation says about this

> It is *not recommended* to run a coordinator via Serial-Proxy-Server (also called Serial-to-IP
> bridge or Ser2Net remote adapter) over: Wi-Fi, WAN, or VPN

The reason given is that serial protocols have no tolerance for packet loss and latency spikes.
A Pi Zero W is Wi-Fi only, so this setup is squarely in that warning. It works, and it is a
legitimate way to keep a network alive while waiting for a proper Ethernet coordinator — but expect
occasional drops, and treat it as temporary.

## 7. Keep it running unattended

A bridge nobody looks at needs to come back on its own. [`harden-pi-bridge.sh`](harden-pi-bridge.sh)
applies four things, all idempotent and all working without internet access:

```bash
sudo ./harden-pi-bridge.sh 20108
```

It reads the serial device straight out of `/etc/ser2net.yaml`, so there is no path to keep in sync.

**1. ser2net restarts itself.** The Debian unit ships with `Restart=no`: if the process dies it
stays dead, and the Zigbee network is gone until somebody notices. A drop-in sets `Restart=always`
with `RestartSec=5`. Check what yours has before assuming:

```bash
systemctl show ser2net -p Restart --value
```

**2. The hardware watchdog.** Raspberry Pi boards expose `/dev/watchdog`, and systemd keeps feeding
it so that a genuinely hung kernel reboots the board. This is the only automatic reboot worth
having: it fires only when the machine is already lost.

On Raspberry Pi OS this is **already enabled out of the box**, by
`/usr/lib/systemd/system.conf.d/40-rpi-enable-watchdog.conf` (`RuntimeWatchdogSec=1m`). Check
before changing anything:

```bash
systemctl show -p RuntimeWatchdogUSec --value    # "0" means off, anything else means on
```

A drop-in under `system.conf.d` **overrides** `/etc/systemd/system.conf`, so editing that file
while the drop-in exists changes nothing while looking like it worked. The script only writes
`/etc/systemd/system.conf.d/50-watchdog.conf`, and only when the watchdog is actually off.

**3. A health check every five minutes.** ser2net can be alive while the adapter has vanished — a
USB glitch is enough. A timer checks that the `by-id` symlink still exists and that the port is
still listening, and restarts ser2net if either is false.

The check deliberately never opens a TCP connection to the port. With `kickolduser: true` that
probe would evict the real client on every run.

**4. Security updates only.** On a board with no screen, a kernel or bootloader update that goes
wrong leaves you with something that does not boot and no way to see why — the fix is pulling the
card and reading it on another machine. So `unattended-upgrades` runs with the kernel, the
bootloader and `raspberrypi-sys-mods` blacklisted, and `Automatic-Reboot "false"`. Run
`apt full-upgrade` by hand, when you are there to watch it.

### What it deliberately does not do

**No scheduled reboots.** Linux does not need them, and every reboot of the bridge takes the Zigbee
network down for a minute. A nightly reboot only papers over the failures that a service restart
already handles, at the cost of a guaranteed outage.

**No unattended full upgrades.** See point 4.

## Troubleshooting

**The Pi boots but never appears on the network.** Almost always trap 1. Power it off, put the card
back in a PC and read `/var/lib/systemd/rfkill/*:wlan`: a `1` means the radio was blocked.

**Deciding whether it booted at all.** A Pi Zero W has **no real-time clock**. With no network time
it restarts from the timestamp baked into the image, so files written during the first boot carry
the image's build date and look untouched. Judging by `find -newermt` gives the wrong answer. Use
facts that do not depend on the clock:

- the root partition grew to the size of the card (the first boot resized it);
- `/etc/passwd` holds your username instead of the image's default `pi` (`userconf-service`
  renames it);
- `ssh` and `userconf.txt` are gone from the boot partition (they are consumed once).

**No logs survive a power cut.** `/var/log/journal/` exists but stays empty until journald is told
to keep logs. Set `Storage=persistent` in `/etc/systemd/journald.conf` before you need it.

**`Illegal instruction` after installing a package.** Wrong architecture — the `.deb` came from
Debian rather than Raspbian. See trap 2.

**The Pi never joins the Wi-Fi.** Check the country code reached `cmdline.txt`, that the SSID is on
2.4 GHz, and that the connection file is mode `600` and owned by root.

**`rpi-imager` does not start on a Wayland session.** It elevates itself to root and then asks for
an X11 display, dies with `Authorization required, but no authorization protocol specified`, and no
window appears. Force the Qt backend:

```bash
QT_QPA_PLATFORM=wayland rpi-imager
```

**Zigbee range collapses once the Pi is in place.** The Zero W's Wi-Fi and the Zigbee radio share
the 2.4 GHz band, and the two antennas end up centimetres apart. Put the stick on a USB extension
cable, and keep the Wi-Fi channel far from the Zigbee one (Wi-Fi 1 with Zigbee 25/26, for example).

**Reading an image or a card without root.** `fdisk -l` works on a plain file, and `debugfs`
accepts an offset, so an ext4 partition inside an image can be inspected with no loop device and no
`sudo`:

```bash
debugfs -R "ls -l /etc" "lite.img?offset=545259520"
```

## Checklist

- [ ] Image is `armhf` Lite and `/bin/bash` inside it reports `Tag_CPU_arch: v6`
- [ ] Checksum verified
- [ ] Every staged `.deb` reports `Tag_CPU_arch: v6`
- [ ] Card written; `ssh` and `userconf.txt` present in the boot partition
- [ ] Country code in `cmdline.txt` **and** the rfkill state set to `0`
- [ ] Wi-Fi connection file mode `600`, no `interface-name=`
- [ ] Pi reachable over SSH
- [ ] `ser2net` enabled and listening on 20108, reachable from the Home Assistant host
- [ ] Coordinator addressed by its `by-id` path, not `/dev/ttyUSB0`
- [ ] DHCP reservation for the Pi
- [ ] ZHA reconnected through `socket://` and the paired devices are back
- [ ] `systemctl show ser2net -p Restart --value` reports `always`
- [ ] `ser2net-healthcheck.timer` is active
- [ ] `unattended-upgrades` installed, kernel blacklisted, automatic reboot off
- [ ] `systemctl show -p RuntimeWatchdogUSec --value` is not `0`
- [ ] After a reboot: the radio comes back unblocked, ser2net starts, and the Zigbee entities
      recover without anyone touching them

## Sources

- Raspberry Pi OS images — <https://downloads.raspberrypi.com/raspios_lite_armhf/images/>
- Raspbian archive (ARMv6) — <http://raspbian.raspberrypi.com/raspbian/>
- ser2net — <https://github.com/cminyard/ser2net>
- ZHA, including the warning about serial-to-IP bridges —
  <https://www.home-assistant.io/integrations/zha/>
