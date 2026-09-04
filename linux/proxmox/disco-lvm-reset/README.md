# Full guide – releasing, wiping and reusing an LVM disk in Proxmox VE

## Purpose
Sometimes a disk or partition in Proxmox is "stuck" or unusable because LVM (Logical Volume
Manager) still holds it, even though no VM is using it any more. This guide covers how to identify
the cause, release the disk and zero it so Proxmox can use it again — the way it played out in
practice.

---

## Prerequisites and safety notes

- **Warning:** every byte on the chosen disk will be lost, irreversibly.
- Only do this **if you're certain you're working on the right disk** (typically `/dev/sdb`, but
  check!).
- Run everything as `root` on the Proxmox node (terminal/shell).

---

## 1. First diagnosis: find out what is holding the disk

**You may run into errors like:**
- `disk/partition '/dev/sdb3' has a holder (500)`
- `error wiping '/dev/sdb1': dd: invalid number: '0.9833984375'`

> These mean something — usually LVM — is still using the disk or partition.

### 1.1 Show the disk and LVM layout

```bash
# Show disks and the LVM structures attached to them
lsblk
lvs
pvs
vgs
```

**Typical output:**
```
sdb                                   8:16   0 223.6G  0 disk
├─sdb1                                8:17   0  1007K  0 part
├─sdb2                                8:18   0     1G  0 part
└─sdb3                                8:19   0 222.6G  0 part
  ├─pve--OLD--xxxx-root        252:3    0  65.6G  0 lvm
  ... (other LVs)
```
Note how *partition sdb3 has Logical Volumes (LVs) belonging to a Volume Group (VG) such as
`pve-OLD-...`*.

---

## 2. Deactivate everything using the disk (umount, lvchange, vgchange)

You have to deactivate every Logical Volume and the Volume Group attached to the disk:

```bash
# Try to unmount any mounted filesystems (many LVs may not be mounted at all)
umount /dev/mapper/pve--OLD--xxxx-root   # (if mounted)
umount /dev/mapper/pve--OLD--xxxx-data   # (if mounted)
# Don't worry if they aren't mounted.

# Deactivate all LVs in the VG
lvchange -an pve-OLD-xxxx/swap
lvchange -an pve-OLD-xxxx/root
lvchange -an pve-OLD-xxxx/data
lvchange -an pve-OLD-xxxx/data_tmeta
lvchange -an pve-OLD-xxxx/data_tdata
lvchange -an pve-OLD-xxxx/data-tpool
# List them all with: lvs

# Deactivate the whole Volume Group
vgchange -an pve-OLD-xxxx
```
(Replace `xxxx` with whatever `lsblk`/`vgs` showed you.)

---

## 3. Remove the Volume Group and Physical Volume

```bash
# Delete the Volume Group (it will ask for confirmation)
vgremove pve-OLD-xxxx

# Remove the LVM signature from the partition
pvremove /dev/sdb3
```

If you still get "holder" errors, make sure no process is using the disk any more:
```bash
lsof | grep /dev/sdb
cat /proc/swaps          # if it's in use as swap, run swapoff /dev/sdbX
```

---

## 4. Wipe every signature from the disk
Now you can clear the LVM signatures and the old partition table from the whole disk, not just the
partition:

```bash
wipefs -a /dev/sdb      # removes all known signatures
sgdisk --zap-all /dev/sdb  # wipes the GPT and PMBR

# (Extra safety: zero the first few MB of the disk)
dd if=/dev/zero of=/dev/sdb bs=1M count=10

# (Optional) turn off any swap still active
swapoff /dev/sdb2
```

---

## 5. (Optional) Create a fresh partition table

To prepare the disk for reuse straight away:
```bash
parted /dev/sdb mklabel gpt
```
Or leave it empty and do everything from the Proxmox GUI.

---

## 6. Rescan from the Proxmox GUI

You can now add the disk as storage, or use it for new VMs and containers in Proxmox VE from the
GUI, without errors.

---

## FAQ and common errors

**Q: I still get "has a holder" messages.**
A: Something is still using the disk: check with `lsof | grep /dev/sdb` and make sure no Logical
Volume is still active (`lvs`, `vgdisplay`).

**Q: I'm afraid of wiping the wrong disk!**
A: Read the `lsblk` output carefully and confirm size and device before going ahead. Better to
check one time too many than one too few.

---

## Useful resources

- [Proxmox Wiki - LVM](https://pve.proxmox.com/wiki/LVM)
- [LVM commands](https://wiki.archlinux.org/title/LVM)
- [wipefs man page](https://man7.org/linux/man-pages/man8/wipefs.8.html)

---

*Tested on Proxmox VE 8.x with a 6.x kernel, based on real troubleshooting.*
