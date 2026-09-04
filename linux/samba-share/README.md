# Sharing a disk over the network with Samba – Linux

## Purpose
How to create a Samba share on Linux and let other hosts on the network reach it.

## Prerequisites

- A Linux system with `sudo` access
- A working local network
- The disk or directory to be shared already mounted on the server

## Installation

```bash
sudo apt update
sudo apt install samba
```

## Creating the Samba user

```bash
sudo adduser condiviso
sudo smbpasswd -a condiviso
```

## Configuring the share

Add the following section to `/etc/samba/smb.conf`:

```ini
[4TB]
   path = /mnt/4TB
   browseable = yes
   writable = yes
   valid users = condiviso
   create mask = 0770
   directory mask = 0770
```

## Directory permissions

```bash
sudo chown -R condiviso:condiviso /mnt/4TB
sudo chmod -R 770 /mnt/4TB
```

## Restarting the Samba service

```bash
sudo systemctl restart smbd
```

## Access from Windows

- Network path: `\\PROXMOX_SERVER_IP\4TB`
- User: `condiviso`
- Password: the one set with `smbpasswd`

---

## ⚠️ If the shared disk is ALSO a storage on this same Proxmox host

A mistake made twice, on two different hosts, before it was diagnosed: if you add this same disk as
a Proxmox **CIFS storage pointing at this host's own IP**, you create a network loop back to
yourself — Proxmox mounts over the network a disk that is already local.

```
❌ WRONG — storage.cfg with CIFS pointing at this host's own IP:

cifs: StorageName
	path /mnt/pve/StorageName
	server <IP OF THIS VERY HOST>   ← the problem is here
	share 4TB
	...
```

Consequences seen in production: pointless network traffic (which on a NIC with a known bug like
the Intel 82579LM can trigger a hardware hang — see
[`e1000e-nic-hang-fix`](../proxmox/e1000e-nic-hang-fix/README.md)), extra latency, and above all
**failed backup jobs**: vzdump's final `rename()` (from `.vma.dat` to `.vma.zst`) turned out to be
unreliable across a CIFS mount pointing at itself, failing with
`unable to rename ... .vma.dat to ....vma.zst` — backups that looked complete but were in fact
scrap, after 12+ hours of work lost.

```
✅ RIGHT — a Directory storage on the local mountpoint, no network involved:

dir: StorageName
	path /mnt/4TB
	content backup,iso,vztmpl,import,snippets
```

**A note on `content`:** if the disk is NTFS (via ntfs-3g, as in this guide), keep `images` and
`rootdir` out of the content list — NTFS doesn't handle Unix permissions and symlinks the way
VM/CT disks need.

**Rule of thumb:** CIFS in `storage.cfg` only makes sense when `server` is the IP of **another
machine**. If `server` is this host's own IP, always use `dir` against the local mount path.

## Extra notes

- Firewall: allow TCP `445/139`, UDP `137/138`
- To add more users:
  ```bash
  sudo smbpasswd -a username
  ```
- To work with groups, add the users to the `condiviso` group.

---

**Last updated:** April 2026
