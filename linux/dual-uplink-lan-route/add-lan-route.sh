#!/bin/bash
# add-lan-route.sh – adds a route to a LAN subnet that the current default route can't reach
# usage: sudo ./add-lan-route.sh <subnet/CIDR> <gateway-ip> <interface>
#   e.g. sudo ./add-lan-route.sh 10.0.16.0/20 10.0.0.1 eth0
set -e

SUBNET="$1"
GATEWAY="$2"
IFACE="$3"

if [[ "$EUID" -ne 0 ]]; then
  echo "❌ Run as root (sudo)."
  exit 1
fi

if [[ -z "$SUBNET" || -z "$GATEWAY" || -z "$IFACE" ]]; then
  echo "Usage: sudo $0 <subnet/CIDR> <gateway-ip> <interface>"
  exit 1
fi

echo "📝 Adding route ${SUBNET} via ${GATEWAY} dev ${IFACE} ..."
ip route add "$SUBNET" via "$GATEWAY" dev "$IFACE"
echo "✅ Route added (until reboot). Verify with: ip route"
echo "ℹ️  To make it survive a reboot, see the 'Persistent route' section in the guide."
