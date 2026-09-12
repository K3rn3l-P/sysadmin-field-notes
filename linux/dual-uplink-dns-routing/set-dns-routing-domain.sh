#!/bin/bash
# set-dns-routing-domain.sh – makes NetworkManager/systemd-resolved always query one
# connection's DNS server for a given domain, instead of the default-route link's resolver
# usage: sudo ./set-dns-routing-domain.sh <connection-name> <domain>
#   e.g. sudo ./set-dns-routing-domain.sh "Wired connection 1" home.example
set -e

CONN="$1"
DOMAIN="$2"

if [[ "$EUID" -ne 0 ]]; then
  echo "❌ Run as root (sudo)."
  exit 1
fi

if [[ -z "$CONN" || -z "$DOMAIN" ]]; then
  echo "Usage: sudo $0 <connection-name> <domain>"
  exit 1
fi

echo "📝 Adding routing-only DNS domain ~${DOMAIN} to \"${CONN}\" ..."
nmcli connection modify "$CONN" +ipv4.dns-search "~${DOMAIN}"
nmcli connection up "$CONN" >/dev/null
echo "✅ Done. Verify with:"
echo "   resolvectl domain"
echo "   resolvectl query somehost.${DOMAIN}"
