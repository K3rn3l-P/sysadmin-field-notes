# Swap utility for Proxmox VMs – quick guide

Utilities and best practice for managing RAM and enabling swap **inside Proxmox/Linux VMs**.
Written for Debian/Ubuntu but easy to adapt.

---

## Why does a VM need swap?

- Avoids sudden crashes and OOM-killer kicks when RAM fills up (Docker, LLMs, AI, heavy services)
- Improves stability on VMs with variable or bursty workloads
- Essential where the RAM the VM actually "sees" is inherently less than what's assigned in the GUI

---

## RAM & swap best practice on Proxmox VMs

- RAM: assign it under Hardware → Memory in the Proxmox GUI (e.g. 8–32 GiB depending on load)
- **Ballooning:** off, unless you specifically need it
- **Swap:** always on, at least 4–8 GiB (even on SSD — better swap than a crash)

---

## Creating swap automatically (script included)

### 1. Copy `crea_swap.sh` into the VM
### 2. Make it executable
```bash
chmod +x crea_swap.sh
```
### 3. Run it with the size you want (in GiB, default 4 GB):
```bash
sudo ./crea_swap.sh 8   # creates an 8 GB swapfile
```

### 4. Check that swap is active:
```bash
free -h
swapon --show
```

---

## Script: crea_swap.sh

```bash
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
  swapon --show; exit 0
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
```

---

## FAQ

- **Does swap on an SSD wear the disk out?**
  **No, as long as it isn't swapping heavily and continuously. In normal use the lifespan is fine,
  and swap protects your data from crashes and OOM kills.**

- **Do I need to reboot after adding swap?**
  **No.** Swap is active immediately. A reboot is only needed if you want to confirm it persists.

- **The VM sees less RAM than Proxmox assigned it?**
  A few hundred MB less is normal (reserved for firmware and the hypervisor). If the gap is large,
  check ballooning and the VM config.

---

## Troubleshooting

- **free -h** should show a "Swap" row with a value greater than 0
- **swapon --show** should list `/swapfile`
- **If you still see OOM errors in dmesg** despite swap, add RAM/swap or rein in the processes
  using the most memory (`ps aux --sort=-%mem | head`)
- **Ballooning still on?** Turn it off in the Proxmox GUI → Hardware → Memory.
