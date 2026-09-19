#!/bin/bash
# prepare-pi-card.sh – writes a Raspberry Pi OS image to a card and prepares a headless first boot
# usage: sudo ./prepare-pi-card.sh <device> <image.img|image.img.xz> [deb-dir]
#   e.g. sudo ./prepare-pi-card.sh /dev/sdc 2026-09-15-raspios-trixie-armhf-lite.img.xz ./deb
#
# Sets up SSH, the first user, Wi-Fi and the wireless regulatory domain, and optionally copies a
# directory of .deb packages onto the card so the Pi can install them without internet access.
set -euo pipefail

DEVICE="${1:-}"
IMAGE="${2:-}"
DEB_DIR="${3:-}"

if [[ "$EUID" -ne 0 ]]; then
  echo "❌ Run as root (sudo)."
  exit 1
fi

if [[ -z "$DEVICE" || -z "$IMAGE" ]]; then
  echo "Usage: sudo $0 <device> <image.img|image.img.xz> [deb-dir]"
  exit 1
fi

if [[ ! -b "$DEVICE" ]]; then
  echo "❌ $DEVICE is not a block device."
  exit 1
fi

if [[ ! -r "$IMAGE" ]]; then
  echo "❌ Cannot read image $IMAGE"
  exit 1
fi

# Refuse a non-removable disk: the usual way to overwrite the wrong drive is a typo here.
if [[ "$(lsblk -dno RM "$DEVICE")" != "1" ]]; then
  echo "❌ $DEVICE is not removable. Refusing to write to it."
  exit 1
fi

echo "📝 Target disk:"
lsblk -o NAME,SIZE,TYPE,TRAN,RM,MOUNTPOINT,MODEL "$DEVICE"
echo
read -rp "This ERASES everything on $DEVICE. Type YES to continue: " confirm
if [[ "$confirm" != "YES" ]]; then
  echo "Aborted."
  exit 1
fi

read -rp  "Username for the Pi: " PI_USER
read -rsp "Password for $PI_USER: " PI_PASS; echo
read -rp  "Hostname [raspberrypi]: " PI_HOST
PI_HOST="${PI_HOST:-raspberrypi}"
read -rp  "Wi-Fi SSID (leave empty to skip Wi-Fi): " WIFI_SSID
WIFI_PSK=""
if [[ -n "$WIFI_SSID" ]]; then
  read -rsp "Wi-Fi password: " WIFI_PSK; echo
fi
read -rp  "Wireless country code [IT]: " WIFI_COUNTRY
WIFI_COUNTRY="${WIFI_COUNTRY:-IT}"

# mmcblk0/nvme0n1 number their partitions p1/p2, sdc does not.
PART_PREFIX="$DEVICE"
if [[ "$DEVICE" =~ [0-9]$ ]]; then
  PART_PREFIX="${DEVICE}p"
fi

echo "📝 Unmounting any mounted partition ..."
while read -r part; do
  [[ -n "$part" ]] || continue
  umount "$part" 2>/dev/null || true
done < <(lsblk -lno PATH,MOUNTPOINT "$DEVICE" | awk 'NF>1 {print $1}')

echo "📝 Writing the image ..."
case "$IMAGE" in
  *.xz) xz -dc "$IMAGE" | dd of="$DEVICE" bs=4M conv=fsync status=progress ;;
  *)    dd if="$IMAGE" of="$DEVICE" bs=4M conv=fsync status=progress ;;
esac
sync
partprobe "$DEVICE"
udevadm settle
sleep 2

BOOT_MNT="$(mktemp -d)"
ROOT_MNT="$(mktemp -d)"
mount "${PART_PREFIX}1" "$BOOT_MNT"
mount "${PART_PREFIX}2" "$ROOT_MNT"

cleanup() {
  sync
  umount "$BOOT_MNT" 2>/dev/null || true
  umount "$ROOT_MNT" 2>/dev/null || true
  rmdir "$BOOT_MNT" "$ROOT_MNT" 2>/dev/null || true
}
trap cleanup EXIT

echo "📝 Enabling SSH and creating the first user ..."
touch "$BOOT_MNT/ssh"
# -stdin keeps the plaintext password out of the process list.
PI_HASH="$(printf '%s' "$PI_PASS" | openssl passwd -6 -stdin)"
printf '%s:%s\n' "$PI_USER" "$PI_HASH" > "$BOOT_MNT/userconf.txt"

echo "📝 Setting the wireless regulatory domain to $WIFI_COUNTRY ..."
if ! grep -q ieee80211_regdom "$BOOT_MNT/cmdline.txt"; then
  sed -i "1s/\$/ cfg80211.ieee80211_regdom=${WIFI_COUNTRY}/" "$BOOT_MNT/cmdline.txt"
fi

# The radio ships soft-blocked (/etc/modprobe.d/rfkill_default.conf sets default_state=0) and the
# country on the kernel command line does not lift that block, so a headless Pi never joins a
# network. raspi-config's do_wifi_country unblocks it as a separate step; these three do the same
# offline.
echo "📝 Unblocking the Wi-Fi radio ..."
for state in "$ROOT_MNT"/var/lib/systemd/rfkill/*:wlan; do
  [ -e "$state" ] || continue
  echo 0 > "$state"
done

install -d -m 755 "$ROOT_MNT/var/lib/NetworkManager"
printf '[main]\nNetworkingEnabled=true\nWirelessEnabled=true\nWWANEnabled=true\n' \
  > "$ROOT_MNT/var/lib/NetworkManager/NetworkManager.state"

cat > "$ROOT_MNT/etc/systemd/system/wifi-unblock.service" <<'UNIT'
[Unit]
Description=Unblock the Wi-Fi radio before NetworkManager starts
DefaultDependencies=no
After=systemd-modules-load.service
Before=NetworkManager.service network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/rfkill unblock all

[Install]
WantedBy=multi-user.target
UNIT
ln -sf ../wifi-unblock.service \
  "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/wifi-unblock.service"

if [[ -n "$WIFI_SSID" ]]; then
  echo "📝 Writing the Wi-Fi connection ..."
  WIFI_FILE="$ROOT_MNT/etc/NetworkManager/system-connections/wifi.nmconnection"
  cat > "$WIFI_FILE" <<NM
[connection]
id=wifi
uuid=$(cat /proc/sys/kernel/random/uuid)
type=wifi
autoconnect=true

[wifi]
mode=infrastructure
ssid=${WIFI_SSID}

[wifi-security]
key-mgmt=wpa-psk
psk=${WIFI_PSK}

[ipv4]
method=auto

[ipv6]
method=auto
NM
  # NetworkManager ignores a connection file that anyone but root can read.
  chmod 600 "$WIFI_FILE"
  chown 0:0 "$WIFI_FILE"
fi

echo "📝 Setting the hostname to $PI_HOST ..."
echo "$PI_HOST" > "$ROOT_MNT/etc/hostname"
sed -i "s/raspberrypi/${PI_HOST}/g" "$ROOT_MNT/etc/hosts"

if [[ -n "$DEB_DIR" ]]; then
  if compgen -G "$DEB_DIR/*.deb" > /dev/null; then
    echo "📝 Staging .deb packages in /root/packages ..."
    install -d -m 755 "$ROOT_MNT/root/packages"
    cp "$DEB_DIR"/*.deb "$ROOT_MNT/root/packages/"
    ls -1 "$ROOT_MNT/root/packages/"
  else
    echo "⚠️  No .deb found in $DEB_DIR, skipping."
  fi
fi

echo "✅ Card ready. Boot the Pi and wait about 90 seconds, then:"
echo "   ssh ${PI_USER}@${PI_HOST}.local"
