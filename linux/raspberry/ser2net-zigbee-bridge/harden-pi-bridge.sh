#!/bin/bash
# harden-pi-bridge.sh – keeps a ser2net serial bridge alive without anyone watching it
# usage: sudo ./harden-pi-bridge.sh [tcp-port]
#
# Applies four things, all idempotent and all working offline:
#   1. ser2net restarts itself if it dies
#   2. the hardware watchdog reboots the board if the kernel hangs
#   3. a timer restarts ser2net if the serial device or the listening port disappears
#   4. unattended-upgrades limited to security, with the kernel held back and no reboot
set -euo pipefail

PORT="${1:-20108}"
SER2NET_YAML=/etc/ser2net.yaml

if [[ "$EUID" -ne 0 ]]; then
  echo "❌ Run as root (sudo)."
  exit 1
fi

if [[ ! -r "$SER2NET_YAML" ]]; then
  echo "❌ $SER2NET_YAML not found — configure ser2net first."
  exit 1
fi

# The connector line looks like: connector: serialdev,/dev/serial/by-id/usb-…,115200n81,local
DEVICE=$(awk -F, '/connector:[[:space:]]*serialdev/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}' \
  "$SER2NET_YAML")

if [[ -z "$DEVICE" ]]; then
  echo "❌ Could not read the serial device out of $SER2NET_YAML"
  exit 1
fi

echo "📝 Serial device: $DEVICE"
echo "📝 TCP port: $PORT"

echo "📝 1/4 — ser2net restarts on failure ..."
install -d -m 755 /etc/systemd/system/ser2net.service.d
cat > /etc/systemd/system/ser2net.service.d/restart.conf <<'UNIT'
[Service]
Restart=always
RestartSec=5
UNIT

echo "📝 2/4 — hardware watchdog ..."
# Raspberry Pi OS already enables it in /usr/lib/systemd/system.conf.d/40-rpi-enable-watchdog.conf,
# and a drop-in there beats anything written into system.conf itself. Check what is in effect
# before touching anything, or you end up with inert settings that read as if they work.
WATCHDOG_USEC=$(systemctl show -p RuntimeWatchdogUSec --value)
if [[ ! -e /dev/watchdog ]]; then
  echo "⚠️  No /dev/watchdog on this board, skipping."
elif [[ -n "$WATCHDOG_USEC" && "$WATCHDOG_USEC" != "0" ]]; then
  echo "   Already enabled ($WATCHDOG_USEC), leaving it alone."
else
  install -d -m 755 /etc/systemd/system.conf.d
  cat > /etc/systemd/system.conf.d/50-watchdog.conf <<'UNIT'
[Manager]
RuntimeWatchdogSec=1min
RebootWatchdogSec=2min
UNIT
  echo "   Enabled; takes effect after a reboot."
fi

echo "📝 3/4 — health check every 5 minutes ..."
cat > /usr/local/sbin/ser2net-healthcheck.sh <<CHECK
#!/bin/bash
# Restarts ser2net when the bridge is up but useless: the adapter has gone, or nothing is
# listening any more. It deliberately never connects to the port — with kickolduser the probe
# would evict the real client on every run.
set -u

DEVICE="$DEVICE"
PORT="$PORT"

if [ ! -e "\$DEVICE" ]; then
  logger -t ser2net-healthcheck "serial device \$DEVICE is gone, restarting ser2net"
  systemctl restart ser2net
  exit 0
fi

if ! ss -lnt "sport = :\$PORT" | grep -q LISTEN; then
  logger -t ser2net-healthcheck "nothing listening on \$PORT, restarting ser2net"
  systemctl restart ser2net
fi
CHECK
chmod 755 /usr/local/sbin/ser2net-healthcheck.sh

cat > /etc/systemd/system/ser2net-healthcheck.service <<'UNIT'
[Unit]
Description=Check that the ser2net bridge is usable
After=ser2net.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/ser2net-healthcheck.sh
UNIT

cat > /etc/systemd/system/ser2net-healthcheck.timer <<'UNIT'
[Unit]
Description=Run the ser2net bridge check every 5 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
AccuracySec=30s

[Install]
WantedBy=timers.target
UNIT

echo "📝 4/4 — security updates only, no automatic reboot ..."
cat > /etc/apt/apt.conf.d/52unattended-upgrades-bridge <<'APT'
// A headless board with no screen: a bad kernel or bootloader update means pulling the card out
// to find out why it stopped booting. Security updates carry no such risk.
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Package-Blacklist {
    "raspberrypi-kernel";
    "raspberrypi-bootloader";
    "raspberrypi-sys-mods";
    "linux-image-.*";
    "linux-headers-.*";
};
APT

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'APT'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT

systemctl daemon-reload
systemctl enable --now ser2net-healthcheck.timer
systemctl restart ser2net

echo
echo "✅ Done."
systemctl show ser2net -p Restart --value | sed 's/^/   ser2net Restart=/'
systemctl list-timers ser2net-healthcheck.timer --no-pager | sed -n '2p'
if ! dpkg -s unattended-upgrades >/dev/null 2>&1; then
  echo "   ⚠️  unattended-upgrades is not installed; the config above starts working once it is."
fi
echo "   The watchdog setting needs a reboot to take effect."
