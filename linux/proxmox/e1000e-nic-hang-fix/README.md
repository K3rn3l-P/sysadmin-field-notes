# Total Proxmox lockup — e1000e "Detected Hardware Unit Hang" (Intel 82579LM)

> **Diagnosed and fixed on an HP Z420 Workstation, Proxmox VE 8.4.18, kernel 6.8.12-20-pve, 1 August 2026.**
> Applies to any host with an Intel e1000e-series NIC (82579LM and similar) that locks up under sustained network load.

---

## Symptom

With every VM/CT shut down except one generating sustained, prolonged network traffic (an Ubuntu
Server VM, in this case), after a few hours the server became **completely unreachable**: Proxmox
GUI, SSH, websites on the VMs, the whole LAN — all dead. The only way out was a physical power-off
with the power button, followed by a normal boot.

It looked like heat, the PSU, or a kernel crash. **It was none of the three.**

## Diagnosis

```bash
# List boots with their start/end times
journalctl --list-boots

# For each suspicious boot, count the NIC hangs
journalctl -b -N -k | grep -c 'Detected Hardware Unit Hang'
```

Result: **hundreds of occurrences per boot**, and **zero** `Reset adapter` entries in the logs —
the driver detected the hang but never recovered on its own. The card's TX queue jammed and stayed
that way forever, while the rest of the host was perfectly alive (just mute on the network).

**What ruled out heat and the PSU:**
- CPU always 43-52°C (critical threshold 89°C), no throttling, no MCEs
  (`sensors`, `journalctl -k | grep -iE 'thermal|throttl|mce'`)
- The power-button shutdowns showed up in the journal as **clean shutdowns**
  (`poweroff.target` reached, journald closed in an orderly fashion) — a kernel panic or a PSU in
  protection doesn't produce that pattern
- The PSU (EVGA G3 750W) is far oversized for the actual load

**The real cause:** a known driver/firmware bug on the Intel 82579LM (and other e1000e parts) when
**TSO/GSO** (TCP/Generic Segmentation Offload) and/or **EEE** (Energy Efficient Ethernet) are
enabled. Confirmed across several Proxmox forum threads and public gists (see Sources).

```bash
ethtool -k eno1 | grep -E 'tcp-segmentation|generic-segmentation|generic-receive'
ethtool --show-eee eno1
```

**Also checked in the HP F10 BIOS Setup** (official HP Z220/Z420/Z620/Z820 Maintenance and Service
Guide, Table 2-2): there is no EEE or offload option in firmware on this generation of HP
workstation — only S5 Wake-on-LAN, NIC Option ROM Download, NIC Controller (Available/Hidden). The
fix is possible **only at the OS/driver level**.

**A compounding problem found along the way:** the Proxmox storage `TB4` was a CIFS mount pointing
at this host's own IP (`//10.0.0.10/4TB`) — Proxmox was mounting over the network a disk that was
already local. It generated pointless traffic on the very NIC that was faulty and, when the NIC
hung, the CIFS mount went into D-state and dragged `pvestatd`/`pveproxy` down with it (symptom: the
GUI freezes first, then everything dies).

---

## Fix 1 — Turn off TSO/GSO/GRO/EEE on the NIC (primary cause)

File: [`post-up-vmbr0.conf`](./post-up-vmbr0.conf) — a snippet to paste into
`/etc/network/interfaces`, inside the `iface vmbr0 inet static` stanza:

```bash
	post-up /usr/sbin/ethtool -K eno1 tso off gso off gro off sg off
	post-up /usr/sbin/ethtool --set-eee eno1 eee off
	post-up /usr/sbin/ethtool -G eno1 rx 4096 tx 4096
```

Apply it live too (without restarting networking), to check straight away:

```bash
ethtool -K eno1 tso off gso off gro off sg off
ethtool --set-eee eno1 eee off
ethtool -G eno1 rx 4096 tx 4096
```

The performance cost is negligible at gigabit: the CPU absorbs the extra work without trouble on
any modern Xeon/Core workstation.

## Fix 2 — Auto-recovery watchdog (safety net)

Even with Fix 1 in place, keep a watchdog that repairs any residual hang by itself, rather than
having to run for the power button.

Files: [`e1000e-watchdog.sh`](./e1000e-watchdog.sh) +
[`e1000e-watchdog.service`](./e1000e-watchdog.service)

```bash
# Copy the script
cp e1000e-watchdog.sh /usr/local/sbin/e1000e-watchdog.sh
chmod +x /usr/local/sbin/e1000e-watchdog.sh

# Copy the systemd unit
cp e1000e-watchdog.service /etc/systemd/system/e1000e-watchdog.service

# Enable and start it
systemctl daemon-reload
systemctl enable --now e1000e-watchdog.service
```

It follows `journalctl -kf` in real time; when `Detected Hardware Unit Hang` appears it brings the
interface down and up (falling back to reloading the `e1000e` module if that isn't enough),
re-applies the ethtool fixes, and logs everything through `logger` (visible in
`journalctl -u e1000e-watchdog`).

**Tested** by injecting a fake hang into the kernel log:
```bash
echo "<3>e1000e 0000:00:19.0 eno1: Detected Hardware Unit Hang: TEST" > /dev/kmsg
journalctl -u e1000e-watchdog -f   # watch the recovery, ~6 seconds
```

## Fix 3 — Get rid of the CIFS storage that points at itself

File: [`storage-cfg-TB4.snippet`](./storage-cfg-TB4.snippet) — shows the before/after for
`/etc/pve/storage.cfg`: from `cifs` (towards the host's own IP) to `dir` (on the local mount that
already exists). No data moves, and the vzdump backups stay visible in the same folder.

```bash
# Unmount the old CIFS
systemctl stop mnt-pve-TB4.mount

# Edit /etc/pve/storage.cfg per the snippet
nano /etc/pve/storage.cfg

# Remove the credential that's no longer used, and reload
rm -f /etc/pve/priv/storage/TB4.pw
systemctl restart pvestatd
pvesm status   # TB4 should now show as "dir" and "active"
mount | grep "<THIS-HOST-IP>" || echo "OK: no leftover CIFS mount pointing at itself"
```

If the underlying disk is NTFS via ntfs-3g, also add `noatime,big_writes` in `/etc/fstab` to cut
down metadata writes:

```
UUID=... /mnt/... ntfs-3g defaults,noatime,big_writes,uid=...,gid=...,umask=007 0 0
```

> **Hit twice, on two different Proxmox hosts.** If you're setting up a Samba share on a Proxmox
> disk from scratch, the [`samba-share`](../../samba-share/README.md) guide now carries a warning
> about this exact mistake — so you don't have to find it out the hard way, as happened here.

## Fix 4 — Per-disk smartd (monitoring, not the cause of the problem)

File: [`smartd.conf`](./smartd.conf) — a per-disk smartd configuration with targeted thresholds and
self-tests scheduled on separate days, replacing the generic `DEVICESCAN`. **It does not fix the
hang**, but it was added during the same investigation because it's useful for catching real disk
problems early (one disk had reached 87°C in the past, another was close to its rated TBW). See the
comments at the top of the file for details and for adapting the `/dev/disk/by-id/...` paths to
different hardware.

```bash
cp smartd.conf /etc/smartd.conf
systemctl restart smartd
smartctl -t long /dev/sdX   # start a long self-test in the background, per disk
```

---

## End-to-end verification

```bash
# 1) No hangs in the current boot
journalctl -b 0 -k | grep -c 'Detected Hardware Unit Hang'   # expected: 0

# 2) ethtool fixes active
ethtool -k eno1 | grep -E 'tcp-segmentation|generic-segmentation|generic-receive'
ethtool --show-eee eno1
ethtool -g eno1

# 3) Watchdog running
systemctl is-active e1000e-watchdog

# 4) No CIFS pointing at itself
pvesm status
mount | grep "<THIS-HOST-IP>"   # should come back empty

# 5) The real test: start the VM that generates the traffic and leave it running for
#    hours or days, then repeat step 1. That's the only way to confirm the bug doesn't
#    come back under real load.
```

**Useful canary counters for confirming stability over time** (past unclean shutdowns: if the
system has hung or been force-powered-off before, these SMART counters are already high, and from
here on they shouldn't grow any further):
```bash
smartctl -A /dev/sdX | grep -E 'POR_Recovery_Count|Unexpect_Power_Loss_Ct'
```

---

## If it happens again anyway

The definitive fix, should the software ones fall short, is replacing the onboard NIC with an
**Intel i210/i211 PCIe card** (~€15-25): move `vmbr0` onto the new card and disable the 82579LM in
the BIOS (Security → Device Security → NIC Controller → Hidden).

---

## Sources

- [e1000e eno1: Detected Hardware Unit Hang — Proxmox Support Forum](https://forum.proxmox.com/threads/e1000e-eno1-detected-hardware-unit-hang.59928/)
- [Intel NIC e1000e hardware unit hang [SOLVED] — Proxmox Support Forum](https://forum.proxmox.com/threads/intel-nic-e1000e-hardware-unit-hang.106001/)
- [Proxmox | Fix "e1000e Detected Hardware Unit Hang" — GitHub gist](https://gist.github.com/brunneis/0c27411a8028610117fefbe5fb669d10)
- [Fix e1000e NIC Hardware Hang on Proxmox — Disable Offloading](https://www.budgetapp.works/blog/e1000e-nic-hardware-hang-fix-proxmox)
- [HP Z220 SFF, Z220 CMT, Z420, Z620, and Z820 Workstations Maintenance and Service Guide](https://images10.newegg.com/User-Manual/User_Manual_9B12K-0019-001G3.pdf) (Table 2-2, BIOS F10 Setup)

---

> Guide by [K3rn3l-P](https://github.com/K3rn3l-P) — see also
> [`passthrough-nvidia-rtx2070`](../passthrough-nvidia-rtx2070) for the same HP Z420 host.
