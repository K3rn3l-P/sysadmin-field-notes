# NVIDIA fix on the Proxmox host – Linux

## Purpose
How to blacklist the NVIDIA/Nouveau drivers on a Proxmox host when the GPU has to be passed
through to a VM or a container.

## Prerequisites

- A Proxmox VE host
- Root shell access
- A GPU dedicated to passthrough towards a VM or LXC

## Check the GPU

```bash
lspci | grep -i nvidia
```

Or:

```bash
lspci | grep -i vga
lspci -nnk | grep -A 10 '05:00'
```

## Check the blacklist files

```bash
cat /etc/modprobe.d/vfio.conf
cat /etc/modprobe.d/blacklist-nvidia2070.conf
```

Example files for passthrough:

`/etc/modprobe.d/vfio.conf`

```text
options vfio-pci ids=10de:1f02,10de:10f9,10de:1ada,10de:1adb
```

`/etc/modprobe.d/blacklist-nvidia2070.conf`

```text
blacklist nvidia
blacklist nouveau
blacklist nvidia_drm
blacklist nvidia_uvm
blacklist nvidia_modeset
```

## Update initramfs and GRUB

```bash
update-initramfs -u && update-grub && reboot
```

## Verify after reboot

```bash
lspci -nnk | grep -A 10 '05:00'
```

---

## Notes

- Make sure the GPU really is destined for a VM or container before blacklisting the drivers on
  the host.
- After the reboot, check that the host no longer loads the NVIDIA/Nouveau drivers for that device.

---

**Last updated:** April 2026
