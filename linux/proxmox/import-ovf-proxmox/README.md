# Importing an OVF into Proxmox VE – Linux

## Purpose
Practical guide to importing a VM in OVF format into Proxmox VE with `qm importovf`.

## Prerequisites

- A working Proxmox VE installation
- The `.ovf` file available on the Proxmox host
- Storage configured in Proxmox (for example `SSD`)

## Correct syntax

```bash
qm importovf <vmid> <manifest.ovf> <storage>
```

- `<vmid>`: the numeric ID to assign to the VM in Proxmox (e.g. `100`)
- `<manifest.ovf>`: the `.ovf` file (e.g. `'TERA VM 100.02.ovf'`)
- `<storage>`: the name of the Proxmox storage to put the disks on (e.g. `SSD`)

> There's no need to name a disk or a directory — Proxmox reads all of that from the OVF file.

## Worked example

```bash
qm importovf 100 'TERA VM 100.02.ovf' SSD
```

> Quote the filename if it contains spaces.

## Suggested steps

1. Change into the directory holding the OVF file:

    ```bash
    cd /mnt/4TB/TERA/Tera-Server(100.02)/TERA_VM-ovf_100.02
    ```

2. Run the command:

    ```bash
    qm importovf 100 'TERA VM 100.02.ovf' SSD
    ```

3. Wait for the import to finish. The VM then shows up in the Proxmox interface.

## Further tips

- Make sure the storage (`SSD`) is configured in Proxmox VE.
- Check permissions and free space on the storage.
- Change the ID (`100`) as needed.

---

## Common problems

- Storage not found: check with `pvesm status`
- OVF file unreadable: verify permissions and path
- VM ID already in use: pick a free one with `qm list`

---

**Last updated:** April 2026
