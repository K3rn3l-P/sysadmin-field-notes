#!/bin/bash
# crea_swap.sh – creates a swap file automatically inside a VM
# usage: sudo ./crea_swap.sh [GB]   (e.g. sudo ./crea_swap.sh 8)
SIZE="${1:-4}" # defaults to 4GB if not given

set -e

if [[ "$EUID" -ne 0 ]]; then
  echo "❌ You must run this as root (use sudo)!"
  exit 1
fi

if swapon --noheadings --show=NAME | grep -q '/swapfile'; then
  echo "⚠️  Swapfile already present. Exiting without changing anything."
  swapon --show
  exit 0
fi

echo "📝 Creating a ${SIZE} GB swapfile at /swapfile ..."
fallocate -l "${SIZE}G" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count="$((SIZE*1024))"
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
if ! grep -q '/swapfile' /etc/fstab; then
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
echo "✅ ${SIZE}GB of swap created and active!"
swapon --show
