#!/bin/bash
# crea_swap.sh – crea file swap in automatico in una VM
# usage: sudo ./crea_swap.sh [GB]   (es: sudo ./crea_swap.sh 8)
SIZE="${1:-4}" # default a 4GB se non specificato

set -e

if [[ "$EUID" -ne 0 ]]; then
  echo "❌ Devi eseguire come root (usa sudo)!"
  exit 1
fi

if swapon --noheadings --show=NAME | grep -q '/swapfile'; then
  echo "⚠️  Swapfile già presente. Esci senza modificare nulla."
  swapon --show
  exit 0
fi

echo "📝 Creo swapfile da ${SIZE} GB in /swapfile ..."
fallocate -l "${SIZE}G" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count="$((SIZE*1024))"
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
if ! grep -q '/swapfile' /etc/fstab; then
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
echo "✅ Swap di ${SIZE}GB creato e attivo!"
swapon --show
