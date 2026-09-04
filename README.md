# sysadmin-field-notes

> Tested scripts, guides and configuration for administering, virtualising and tuning Linux
> systems (mainly Proxmox VE), Windows and GPU hardware.

Every folder stands on its own: it holds a `README.md` with the full guide and, where useful, the
scripts and config files ready to copy. The point is to have an archive to reach for quickly —
during a restore, a reinstall, or when re-applying a fix that was already solved once before.

---

## 🔎 Quick index

| Category | Guide | Contents |
|---|---|---|
| **Proxmox VE** | [NVIDIA RTX 2070 passthrough](linux/proxmox/passthrough-nvidia-rtx2070/README.md) | Full guide + vfio diagnostic script |
| | [e1000e NIC hang fix (82579LM)](linux/proxmox/e1000e-nic-hang-fix/README.md) | Diagnosis + watchdog + network/storage/smartd config |
| | [NVIDIA fix on the Proxmox host](linux/proxmox/old-proxmox-nvidia-host/README.md) | Driver blacklisting for GPU passthrough |
| | [Restoring a VM from external backup](linux/proxmox/proxmox-backup-restore/README.md) | Restore over Samba/NFS/SSH |
| | [Importing an OVF](linux/proxmox/import-ovf-proxmox/README.md) | `qm importovf` |
| | [Laying out disks](linux/proxmox/strutturazione-dischi/README.md) | LVM, LVM-Thin, Directory (no ZFS) ⚠️ CIFS-to-self warning |
| | [Resetting a stuck LVM disk](linux/proxmox/disco-lvm-reset/README.md) | Releasing and reusing an LVM disk |
| | [Email notifications via Postfix/Gmail relay](linux/proxmox/postfix-gmail-relay/README.md) | Why the notifications never arrive + automated script |
| **GPU / NVIDIA** | [Clean NVIDIA driver install](linux/gpu-nvidia-install-guide/README.md) | Debian 12 / VM / Proxmox |
| | [Safe NVIDIA driver upgrade](linux/gpu-nvidia-update/README.md) | Debian/Ubuntu, VMs, Proxmox, passthrough + automated script |
| | [VRAM per Docker container](linux/gpu-tools/README.md) | Maps `nvidia-smi` output to containers + script |
| **System & disks** | [Automatic swap for VMs](linux/create-swap/README.md) | Script + Proxmox/Linux guide |
| | [Hardware and disk commands](linux/disk-info-hw/README.md) | CPU, RAM, disks, buses, SMART |
| | [Disk usage analysis (ncdu)](linux/ncdu-disk-usage/README.md) | Interactive usage |
| | [Temperature and hardware sensors](linux/sensors-hw/README.md) | `lm-sensors` + monitor script + boot/hang logging |
| **Docker** | [Deep Docker cleanup](linux/docker-clean/README.md) | Cache, images, volumes |
| **Network** | [Samba share](linux/samba-share/README.md) | LAN share setup + ⚠️ how to wire it into Proxmox without CIFS-to-self |
| **Windows** | [Windows utilities](windows/README.md) | Placeholder, to be filled in |

---

## 🌳 Repository layout

```
sysadmin-field-notes/
├── linux/
│   ├── create-swap/                     📄 guide + 🔧 crea_swap.sh
│   ├── disk-info-hw/                    📄 guide
│   ├── docker-clean/                    📄 guide
│   ├── gpu-nvidia-install-guide/        📄 guide
│   ├── gpu-nvidia-update/               📄 guide + 🔧 nvidia_safe_upgrade.sh, nvidia_safe_upgrade_auto.sh
│   ├── gpu-tools/                       📄 guide + 🔧 gpu-vram-by-container.sh
│   ├── ncdu-disk-usage/                 📄 guide
│   ├── proxmox/
│   │   ├── disco-lvm-reset/             📄 guide
│   │   ├── e1000e-nic-hang-fix/         📄 guide + 🔧 watchdog + ⚙️ config (interfaces/storage/smartd)
│   │   ├── import-ovf-proxmox/          📄 guide
│   │   ├── old-proxmox-nvidia-host/     📄 guide
│   │   ├── passthrough-nvidia-rtx2070/  📄 guide + 🔧 check-vfio-bind.sh
│   │   ├── postfix-gmail-relay/         📄 guide + 🔧 script + ⚙️ credential/email templates
│   │   ├── proxmox-backup-restore/      📄 guide
│   │   └── strutturazione-dischi/       📄 guide
│   ├── samba-share/                     📄 guide
│   └── sensors-hw/                      📄 guide + 🔧 monitor-cpu-temp.sh
└── windows/                             📄 placeholder
```

**Legend:** 📄 guide (README.md) · 🔧 executable script · ⚙️ config file or snippet

---

## ✍️ Conventions

- One folder per topic, under `linux/<category>/` or `linux/proxmox/<topic>/`.
- Each folder has a `README.md` covering: purpose, prerequisites, steps with command blocks,
  troubleshooting (where relevant), a final checklist, and sources.
- Scripts need to be made executable before use: `chmod +x script-name.sh`.
- When adding a guide: create the folder, write its `README.md`, then **update the quick index
  table and the tree above** — that's the only thing that has to be kept in sync by hand.

Host addresses in these guides are placeholders (`10.0.0.10`, `10.0.0.20`), not real ones.

---

## 📚 Other pages

- [`INDEX.md`](INDEX.md) — alias, points back here.
