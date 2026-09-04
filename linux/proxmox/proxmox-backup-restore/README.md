# Restoring a VM from an external backup on Proxmox VE – Linux

## Purpose
Step-by-step guide to fetching and restoring VM backups from external storage (Samba/NFS/SSH) onto
a Proxmox host.

## Prerequisites

- A Proxmox VE host with free space on the destination storage
- The VM backup already copied to the Proxmox server, or reachable over the network
- Root permissions to run `qmrestore`

## Full procedure

### 1. Copy the backup over SCP

```bash
mkdir -p /tmp/vm-backup
cd /tmp/vm-backup
scp root@10.0.0.20:/mnt/WD-P/dump/vzdump-qemu-100-*.vma.zst .
```

### 2. Check the file you received

```bash
ls -lh vzdump-qemu-*.vma.zst
```

Make sure the file is complete and the size is what you expected.

### 3. Restore the VM onto local storage

```bash
qm list
qmrestore vzdump-qemu-100-2026_03_22-03_00_09.vma.zst 101 --storage local-lvm
```

Storage alternatives:

```bash
qmrestore vzdump-qemu-100-2026_03_22-03_00_09.vma.zst 101 --storage local
qmrestore vzdump-qemu-100-2026_03_22-03_00_09.vma.zst 101 --storage SSD
```

### 4. Start the VM

```bash
qm list
qm start 101
qm status 101
```

### 5. Check in the GUI

```
Datacenter → 101 → Start → Console
```

## Useful `qmrestore` options

```bash
--force          # overwrite an existing VM
--storage XXX    # destination storage (pvesm status)
--rootfs local:4 # container rootfs (for CTs)
```

## Common problems

- Storage not found:
  ```bash
  pvesm status
  ```
- Corrupt or incomplete file:
  ```bash
  vzdump --restore vzdump-*.vma.zst --list
  ```
- Duplicate VM ID:
  ```bash
  qm destroy 101 && qmrestore ...
  ```

## Cleanup after the restore

```bash
rm -rf /tmp/vm-backup/*
```

---

## Tips

- Use `qm list` to find free IDs before restoring.
- On non-local storage, check there's enough space and that the pool is online.
- Keep the original backups until the VM has been properly tested.

---

**Last updated:** April 2026
