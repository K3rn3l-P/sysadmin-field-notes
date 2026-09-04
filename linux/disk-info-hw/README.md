# Hardware and disk commands – Linux

## Purpose
A collection of useful commands for pulling information about CPU, RAM, disks, partitions and
hardware buses on Linux.

## Prerequisites

- A Linux system with `sudo` access

## CPU info

```bash
lscpu
```

## RAM info

```bash
free -h
```

## Disks and partitions

```bash
lsblk
fdisk -l
df -h
cat /proc/partitions
```

## PCI and USB buses and devices

```bash
lspci
lsusb
```

## Filesystem mounts

```bash
mount
cat /proc/mounts
```

## Identify disk models

```bash
cat /sys/block/sd*/device/model
cat /sys/block/sd*/device/vendor
```

## Extended inventory (dmidecode)

```bash
dmidecode -t system -t baseboard   # motherboard vendor/model
dmidecode -t bios                  # BIOS version
dmidecode -t slot                  # free/occupied PCIe slots
```

## SMART (disk health)

```bash
smartctl -i /dev/sdX      # model — often tells you whether the disk is SMR or CMR
smartctl -H /dev/sdX      # overall health PASSED/FAILED
smartctl -A /dev/sdX      # all attributes
smartctl -l error /dev/sdX     # error log
smartctl -l selftest /dev/sdX  # self-test history
smartctl -t long /dev/sdX      # start an extended self-test in the background (read-only, safe on a disk in use)
```

> Careful: attributes with the same name mean slightly different things across vendors — e.g.
> `188 Command_Timeout` on a Seagate SMR drive indicates stress, while `235 POR_Recovery_Count`
> (Samsung) and `174 Unexpect_Power_Loss_Ct` (Crucial) count unclean shutdowns: if they climb over
> time, the system is taking hangs or forced reboots even if you never noticed any.

---

## Tips

- Use `lsblk` for a quick view of disks, partitions and mountpoints.
- Check `df -h` for used capacity on mounted filesystems.
- Use `lspci` and `lsusb` to find graphics cards, adapters and controllers.

---

**Last updated:** August 2026
