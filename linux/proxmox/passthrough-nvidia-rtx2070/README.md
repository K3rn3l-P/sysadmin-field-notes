# Proxmox NVIDIA RTX 2070 GPU passthrough – complete (tested) guide

> **Tested on Proxmox VE 6/7/8/9, kernel >=6.8, UEFI host, NVIDIA RTX 2070**
> Applies to all NVIDIA RTX/Ampere/Turing cards (see the "PCI IDs" section).

---

## Prerequisites

- Proxmox VE installed and up to date (tested on 6/7/8/9)
- Root access over SSH/shell
- A dedicated GPU (NOT the one driving the host's boot/console!)
- Motherboard and CPU *with VT-d/IOMMU support* (enable it in the BIOS)
- **Disable CSM/Legacy Boot** in UEFI/BIOS if present (CRITICAL for many NVIDIA cards)
- A backup of the VM data

---

## 📌 CSM/Legacy on the HP Z420 (in detail)

**To disable CSM (Compatibility Support Module) on an HP Z420:**
- Reboot the server and press **F10** repeatedly at startup to enter the BIOS.
- Go to:
  **Storage → Boot Order**
- Find and set:
    - **Legacy Support** (or "CSM"): **Disabled**
    - (Optional) make sure "UEFI Boot Order" is at the top / Enabled
- With CSM disabled the system uses UEFI only.
    - *Note*: Secure Boot may switch itself on; you can leave it enabled or set it to Disabled as
      you prefer, but CSM/legacy must stay off.
- **Save** the changes (F10 or ESC → Save) and reboot.

> _If Proxmox no longer boots:_ check that the boot disk is UEFI-compatible (converting from legacy
> to UEFI can require partition fixes; see the official Proxmox wiki).

---

## 📌 Local console on a host with a single passed-through GPU (HP Z420)

**Problem:** if the host has only one GPU and all of it goes to passthrough (`disable_vga=1` in
`vfio.conf`), the host loses its local video console. The framebuffer comes up at boot, but as soon
as `vfio-pci` claims the card (usually within the first ~10 seconds) the framebuffer is destroyed
and the screen goes black. No visible error, no login — so if something goes wrong and the network
is down, the host is unreachable even physically.

**Tested solution:** a cheap second GPU dedicated solely to the host console, kept out of
`vfio.conf`. On an HP Z420 with the RTX 2070 in passthrough and a GeForce GT 620 as console:

- **Slots:** GT 620 in slot 5 (bus `0000:04:00`), RTX 2070 left in slot 2 (bus `0000:05:00`). Full
  physical slot → PCI bus map on the Z420:

  | HP slot | Bus | Type | Notes |
  |---|---|---|---|
  | 1 (top) | 07 | PCIe Gen2 x4(x1) | closed-end connector, a GPU won't fit |
  | 2 | 05 | PCIe Gen3 x16 | the RTX 2070's slot |
  | 3 | 06 | PCIe Gen2 x8(x4) open-ended | usable but awkward |
  | 4 | 03 | PCIe Gen3 x8 open-ended | usable but awkward |
  | 5 | 04 | PCIe Gen3 x16 | the GT 620's slot |
  | 6 | 09 | PCI 32bit/33MHz | legacy |

  The RTX 2070 stayed in slot 2 rather than being moved: in slot 5 its fans would sit almost
  against the case, running hotter under sustained load.

- **BIOS — designating the console GPU as primary:** `F10 → Advanced → VGA Configuration`.
  The menu lists the GPUs by slot; select the one you want as primary with **F5**, then **F10** to
  confirm and *Save & Exit*. **This entry only appears when two graphics cards are installed** —
  which is why it's so easy never to find it. Don't confuse it with:
  - `Advanced → Bus Options`: despite what HP's Maintenance and Service Guide implies
    (*"designates one card as primary graphics"*), on the Z420/Z620/Z820 it only holds Numa, MMIO
    Assignment, PCI SERR#, VGA Palette Snooping and PCI Latency Timer — nothing about which card
    acts as boot device
  - `Advanced → Slot Settings`: enables or disables a whole PCIe slot, it doesn't pick the primary

- **Confirm the right GPU became the boot card:**
  ```bash
  cat /sys/bus/pci/devices/0000:04:00.0/boot_vga   # GT 620  → expected 1
  cat /sys/bus/pci/devices/0000:05:00.0/boot_vga   # RTX 2070 → expected 0
  cat /sys/class/vtconsole/*/name                   # expected: "(M) frame buffer device"
  ```
  Before the fix, `dmesg` showed `Console: switching to colour dummy device 80x25` a few seconds
  into the boot (`vfio-pci` grabbing the wrong card). Afterwards that line is gone and the
  framebuffer console stays active.

- **A useful side effect:** with the second GPU as primary, `video=efifb:off,vesafb:off` (see
  "Kernel cmdline and framebuffer" below) becomes unnecessary — there's no longer a framebuffer to
  hide from passthrough, because the active one isn't on the GPU handed to the VM. Remove it from
  the cmdline anyway: it's a parameter meant to switch off a framebuffer console, and there's no
  reason to keep it once that console has become the host's safety net.

- **Check passthrough still works:** changing the boot card did not alter the IOMMU group of the
  passed-through GPU (verified: identical before and after). Check case by case anyway with
  `find /sys/kernel/iommu_groups/ -type l | sort` before and after the change, and restart the VM
  with the passed-through GPU to confirm it still comes up.

---

## 1. Enable virtualisation in the BIOS

- Reboot and enter the BIOS/UEFI (F10 on HP)
- Enable:
    - **Intel VT-x** (CPU virtualisation)
    - **Intel VT-d** (PCIe/IOMMU passthrough)
- **Disable CSM/Compatibility Support Module** as above
- Save and reboot

---

## 2. Find your NVIDIA card and its IDs

```bash
lspci -nn | grep -i nvidia
# Or, to also see the GPU's audio/USB functions:
lspci -nn | egrep -i 'vga|audio|usb'
```

Example output:
```
05:00.0 VGA compatible controller [0300]: NVIDIA RTX 2070 [10de:1f02]
05:00.1 Audio device [0403]: NVIDIA HD Audio [10de:10f9]
05:00.2 USB controller [0c03]: NVIDIA USB 3.1 Host Controller [10de:1ada]
05:00.3 Serial bus controller [0c80]: NVIDIA USB Type-C UCSI [10de:1adb]
```
Note down all the IDs (here: **10de:1f02, 10de:10f9, 10de:1ada, 10de:1adb**).

---

## 3. Check how the system boots

```bash
[ -d /sys/firmware/efi ] && echo "UEFI" || echo "Legacy BIOS"
```
- **UEFI** → carry on with the "UEFI" section
- **Legacy BIOS** → see the "GRUB"/legacy section below

---

## 📌 Kernel cmdline and the framebuffer

Once UEFI is confirmed and CSM is disabled, **you can improve passthrough by clearing the system
framebuffers** that get in the way of detaching the GPU cleanly.

**What are they?**
- Framebuffers (efifb, vesafb) are drivers that let the kernel use the graphics card for the
  console.
- If the GPU is meant exclusively for VMs, you can disable them.

**How to do it on Proxmox UEFI:**
1. Edit the kernel cmdline:
   ```bash
   nano /etc/kernel/cmdline
   ```
   Append to the existing line:
   ```
   video=efifb:off,vesafb:off
   ```
   The result looks something like:
   ```
   quiet intel_iommu=on iommu=pt video=efifb:off,vesafb:off
   ```
2. Apply it:
   ```bash
   proxmox-boot-tool refresh
   reboot
   ```
3. (On legacy GRUB: edit the `GRUB_CMDLINE_LINUX_DEFAULT` line, then `update-grub` + reboot)

**What changes?**
- You no longer get a graphical console on the physical host (use SSH or the Proxmox web GUI)
- It improves the odds that the GPU is immediately "free" for the guest, without device busy/reset
  errors.

---

### **A) UEFI:**
Follow the procedure above for `/etc/kernel/cmdline` + refresh/reboot.

### **B) Legacy BIOS (GRUB):**
Edit `/etc/default/grub` like this:
```
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt video=efifb:off,vesafb:off"
```
Then:
```bash
update-grub
reboot
```
If the IOMMU groups aren't separated, you can also add `pcie_acs_override=downstream,multifunction`.

---

## 4. Load the VFIO modules and bind the GPU to vfio-pci

1. **Make sure the modules load at boot**
   (append to `/etc/modules` if not already there):
   ```
   vfio
   vfio_iommu_type1
   vfio_pci
   # vfio_virqfd (optional, if your kernel supports it)
   ```
   Note: `vfio_virqfd` is optional and a warning about it doesn't mean your configuration is wrong.
   It can be listed in `/etc/modules` yet be unavailable if the current kernel package doesn't ship
   that module. Only add it if the module actually exists in `/lib/modules/$(uname -r)` or shows up
   under `modinfo vfio_virqfd`.
2. **Create or edit `/etc/modprobe.d/vfio.conf`:**
   ```
   options vfio-pci ids=10de:1f02,10de:10f9,10de:1ada,10de:1adb disable_vga=1
   softdep xhci_hcd pre: vfio-pci
   softdep xhci_pci pre: vfio-pci
   softdep i2c_nvidia_gpu pre: vfio-pci
   ```

3. **Blacklist the host NVIDIA drivers**
   In `/etc/modprobe.d/blacklist-nvidia.conf`:
   ```
   blacklist nvidia
   blacklist nouveau
   blacklist nvidia_drm
   blacklist nvidia_uvm
   blacklist nvidia_modeset
   ```

4. **(Optional) Force the NVIDIA USB functions onto vfio-pci**
   Only if you see that 05:00.2/.3 aren't handled by vfio-pci after a reboot:
   ```
   nano /etc/modprobe.d/blacklist-nvidiausb.conf
   ```
   ```
   blacklist xhci_hcd
   blacklist xhci_pci
   blacklist i2c_nvidia_gpu
   ```
   ⚠️ _This can also kill all USB 3.0/3.1 on the host. Use it only if you really have to._

---

## 5. Update initramfs and reboot

```bash
update-initramfs -u -k all
reboot
```

---

## 📌 Checking for a separate IOMMU group

- Run:
  ```bash
  find /sys/kernel/iommu_groups/ -type l | sort
  ```
- Check that all four 05:00.x devices are **in the same group** (good) **and that no unrelated
  devices share that group**.
    - If that's the case → you can pass the whole group/PCI slot through without trouble.
    - If the GPU shares its group with devices you don't want to pass:
        - Add `pcie_acs_override=downstream,multifunction` to the kernel cmdline and check again.
        - Careful: this option weakens the host's DMA isolation (desktop boards and trusted VMs
          only).

---

## 6. Verify the vfio bindings are active

Check that every function of the GPU shows "in use: vfio-pci":

```bash
lspci -nnk -s 05:00.0
lspci -nnk -s 05:00.1
lspci -nnk -s 05:00.2
lspci -nnk -s 05:00.3
```
All of them must report:
**Kernel driver in use: vfio-pci**

---

## 7. Assign the PCI functions to the VM

**In the GUI:**
- VM → Hardware → Add → PCI Device
    - Include at least 05:00.0 and 05:00.1 (add .2 and .3 as well for full passthrough)
    - Tick "All Functions" if present, or add every function by hand
- VM Options:
    - Machine: q35
    - BIOS: OVMF (UEFI)
    - PCI Express: ON

**From the CLI:**
Configure `/etc/pve/qemu-server/<VMID>.conf`:
```
machine: q35
hostpci0: 0000:05:00,pcie=1,multifunction=on
```

---

## 8. Guest OS and drivers

### Windows 10/11
1. Connect a monitor to the GPU
2. Install the NVIDIA driver from the official site
3. Check Device Manager
4. On "Code 43", add to the VM config:
   ```
   args: -cpu 'host,kvm=on'
   ```
   or
   ```
   hostpci0: ...,hidden=1
   ```
   *(Often unnecessary on Proxmox 7+; on legacy setups or recent GeForce cards → see
   troubleshooting)*

### Linux (Ubuntu/Debian)
1. Connect a monitor
2. Install the proprietary NVIDIA driver
3. Check the output of
   ```bash
   nvidia-smi
   ```

---

## 9. Troubleshooting / quick fixes

| Problem | Likely cause | Fix |
|---|---|---|
| VM won't start | Host driver still holding the card | Check for "in use: vfio-pci", remove/blacklist nvidia |
| Black screen in the VM, no output | No OVMF/q35, or no monitor | Use OVMF/q35, connect a physical monitor |
| GPU doesn't appear in the guest | Wrong IDs, wrong PCI slot | Re-check `ids=` in vfio.conf and the IOMMU group |
| HDMI audio doesn't work | Function 05:00.1 not passed through | Add 05:00.1 to the VM as well |
| USB not bound to vfio-pci | xhci_hcd/i2c_nvidia_gpu on the host | Use softdep, or a targeted blacklist |
| Host loses USB 3 | Global xhci blacklist | Drop the blacklist, use only the softdep above |
| VM works once then fails | GPU reset bug (NV/AMD) | Stop/start the VM; see the vendor-reset module if it recurs |
| VM fails with IOMMU | Missing BIOS or kernel flags | Check VT-d/CSM, re-check the kernel cmdline |
| Error 43 (NVIDIA on Windows) | Missing anti-detection patch | Use `args kvm=on`, `hidden=1`, see advanced options |
| Device shares an IOMMU group | Hardware, no ACS | Use pcie_acs_override (only if necessary) |
| GPU boot/ROM problems | Recent GPU or custom ROM | Try `romfile=...`, `rombar=0` in the VM config |
| noVNC shows nothing | GPU is passed through | You need a physical monitor |

---

## 10. Checklist

- [ ] BIOS: VT-x (CPU virtualisation) and VT-d enabled, CSM/Legacy **DISABLED**
- [ ] Kernel flags: `intel_iommu=on iommu=pt` (plus pcie_acs_override / video=efifb:off if needed) in `/proc/cmdline`
- [ ] /etc/modules contains the VFIO modules (see above)
- [ ] `/etc/modprobe.d/vfio.conf` has all the right device IDs
- [ ] Host NVIDIA/Nouveau drivers blacklisted
- [ ] The GPU and its functions are bound to vfio-pci in `lspci -nnk`
- [ ] IOMMU group is separate, or overridden where needed
- [ ] VM configured with q35 + OVMF and every required function passed through
- [ ] Guest drivers installed and acceleration working
- [ ] NVIDIA Windows guest: no Code 43 or other known errors (patched if needed)

---

## 11. Utility: automated NVIDIA passthrough diagnostic script

This bash utility checks **every NVIDIA GPU present**, verifies each PCIe function is bound to
vfio-pci, **auto-detects slots and IOMMU groups**, suggests fixes, and shows the state of the key
kernel cmdline parameters, flagging anything that contradicts this guide.

See [`check-vfio-bind.sh`](./check-vfio-bind.sh) in this folder.

### 📦 Usage

```bash
# Make the script executable (once)
chmod +x check-vfio-bind.sh

# Run the diagnostic
./check-vfio-bind.sh
```

**✅ The script detects everything automatically (PCI slots, groups, NVIDIA functions, kernel
parameters), flags problems and warnings with colour and emoji, and suggests the matching actions
from this guide — ready for troubleshooting multi-GPU setups too.**

---

## 12. Advanced options and tricks

- **`video=efifb:off,vesafb:off`** – frees the GPU from the host framebuffers.
- **`pcie_acs_override=downstream,multifunction`** – splits up "mixed" IOMMU groups: ONLY when the
  group isn't isolated.
- **Multifunction option (multifunction=on):**
  ```
  hostpci0: 0000:05:00,pcie=1,multifunction=on
  ```
  Useful for GPUs with several PCIe functions (audio, USB, etc.).
- **ROM bar / ROM file:**
  ```
  hostpci0: 0000:05:00,pcie=1,rombar=0
  hostpci0: ... ,romfile=/path/to/dump.rom
  ```
- **Error 43 patch:**
  ```
  args: -cpu 'host,kvm=on'
  ```
  or
  ```
  hostpci0: ...,hidden=1
  ```
  (For Code 43 on a GeForce card in a Windows guest)

- **vendor-reset (when the VM only starts once):**
  - [vendor-reset kernel module](https://github.com/gnif/vendor-reset)

- **Installing custom kernel headers:**
  ```
  apt install pve-headers-$(uname -r)
  ```

---

## 13. Sources and references

- [Proxmox PCI Passthrough Wiki](https://pve.proxmox.com/wiki/PCI_Passthrough)
- [ArchWiki PCI/VFIO](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF)
- [NVIDIA Docs](https://docs.nvidia.com/)
- [K3rn3l-P/sysadmin-field-notes](https://github.com/K3rn3l-P/sysadmin-field-notes)

---

> **Guide written and maintained by [K3rn3l-P](https://github.com/K3rn3l-P) — questions or
> additions welcome as issues on the repo.**
