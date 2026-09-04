# Choosing a disk layout in Proxmox (1 SSD + 4 extra disks)

How to lay out disks in Proxmox depends heavily on the use case, the performance you need, how
simple you want management to be, and how comfortable you are with the tools. What follows is a
practical rundown of the main options — ZFS included for comparison — with notes on organising
1 SSD plus 4 additional disks.

---

## 1. What to weigh up first

- **SSD**: ideal as fast storage for the disks of frequently-used VMs, system (root) partitions, or
  cache.
- **Extra disks (4x HDD or SSD?)**: depends on whether they're spinning or solid state. HDDs are
  usually better used as bulk storage.
- **Redundancy/backup**: software RAID? Backup copies? Do you want fault tolerance?
- **Snapshots and thin provisioning**: for easy snapshots and rollbacks, LVM-Thin.
- **Performance**: are the VMs latency-sensitive, or is everything best-effort?
- **Simplicity**: if you administer it alone, simplicity has real value.

---

## 2. The main options

### 🔹 LVM

- **Pros:** simple to manage, basic snapshot support (not like LVM-Thin), robust and very widely
  used.
- **Cons:** every virtual disk (LV) allocates its space up front ("thick"). Better for classic
  storage and "important" VMs.

### 🔹 LVM-Thin

- **Pros:** advanced snapshots, thin provisioning (you create "large" virtual disks but only the
  data actually written takes up space).
- **Cons:** without monitoring you risk overprovisioning: if the thin pool fills up, Proxmox may
  stop the VMs.
- **Use for:** development and testing VMs, dynamic environments, or anywhere you need frequent
  snapshots.

### 🔹 Directory

- **Pros:** maximum compatibility, reachable like any Linux folder, easy to back up with rsync.
- **Cons:** no native snapshots on ext4 (unless you go btrfs/xfs), no thin provisioning.

---

# 🗂️ ZFS compared with LVM, LVM-Thin and Directory in Proxmox VE

---

## ⏺️ ZFS

### Pros
- 🛡️ **Data integrity**: ZFS constantly validates data and detects (and repairs) bit-rot and
  corruption.
- 🔄 **Very efficient snapshots and clones**: near-instant snapshots and rollbacks.
- 💾 **Transparent compression**: saves space effortlessly with `lz4` or `zstd`.
- ⚡ **Performance and parallelism (copy-on-write)**: excellent on servers with plenty of RAM and a
  decent CPU.
- 🧰 **Flexible software RAID** (RAID-Z, mirror, stripe — all built in).
- 🔁 **Easy replication**: great across multiple nodes, or for replica setups.

### Cons
- 🗄️ **High RAM usage**: ZFS wants **at least 8 GB** of RAM on production installs, ideally more.
- 📦 **Wasteful on small disks**: on low-capacity SSDs/HDDs, usable space shrinks noticeably because
  of metadata/ZIL/overhead.
- ⚠️ **Don't layer it on already-partitioned or otherwise-managed devices**: ZFS works best with
  whole dedicated disks.
- ⚙️ **Needs confidence with ZFS snapshots/replication/RAID**: more powerful means more complex.
- 🛠️ **Shrinking a pool is hard**: once created, removing a single disk from a ZFS pool isn't easy.

---

## ⏺️ When ZFS is the right call
- You want **very high reliability** and data integrity (especially for VMs hosting critical
  services or shared filesystems).
- You need **frequent snapshots**, fast clones, and multiple rollback points.
- You want RAID and management simplified, all handled by ZFS (RAID-Z1, Z2, etc.).
- You have >8 GB of RAM free and **dedicated** to the server — considerably more if you run many
  VMs/containers or large pools.

---

## ⏺️ Setting up ZFS on new disks in Proxmox

**Typical procedure:**

1. **Wipe any existing partitioning on the disks**
   ```bash
   wipefs -a /dev/sdX
   ```

2. **Create a new ZFS pool**
   - (Example, a RAID1 pool across two SSDs:)
     ```bash
     zpool create -f -o ashift=12 datapool mirror /dev/sdb /dev/sdc
     ```
   - (RAIDZ across four disks)
     ```bash
     zpool create -f -o ashift=12 bigpool raidz1 /dev/sdb /dev/sdc /dev/sdd /dev/sde
     ```

3. **Add the pool to Proxmox**
   - In the GUI: Datacenter → Storage → Add → ZFS, pick the pool name (e.g. `datapool`) and the
     type (`ZFS` for file storage, `ZFS-Thin` for block storage).

4. **Enable compression (best practice)**
   ```bash
   zfs set compression=lz4 datapool
   ```

---

### Summary table

| Type | Main advantages | Main drawbacks | Why use it |
|------|-----------------|----------------|------------|
| ZFS | Best integrity, snapshots, built-in RAID, compression | Wants RAM, space overhead, somewhat complex | Critical storage, snapshot-heavy needs |
| LVM | Simple, robust, basic snapshots, ubiquitous | Thick provisioning, limited snapshots and rollback | "Classic" VMs and storage |
| LVM-Thin | Thin provisioning, fast snapshots for VMs and CTs | Watch out for pool saturation | Dynamic and development environments |
| Directory | Simple, visible as plain Linux folders, direct access | No native snapshots, no thin provisioning | ISOs, backups, sharing, containers |

---

## ⏺️ Choosing for this case (SSD + 4 disks)

**If you want redundancy:**
ZFS is the **strongest** option for **mission-critical** data, but on many small disks it does eat
more space and RAM.
- On a 4-disk pool: RAIDZ1 (single parity) costs you the capacity of 1 disk in 4, and gives you
  safety plus effortless snapshots and rollback.

**If you want maximum simplicity and compatibility:**
Use **LVM-Thin on the SSD** for the "important" VMs, and/or **classic LVM / Directory / software
RAID** on the other disks for bulk storage.

**If you want flexibility:**
- Mix them. SSD → LVM-Thin;
- RAID5/RAID10 with mdadm+LVM on the HDDs for bulk;
- ZFS on a separate pool later (even just for backups and snapshots).

---

## ⏺️ Proxmox integration — best practice

- If you go **ZFS**, dedicate it to pools of important VMs/containers; don't mix it with LVM (one
  disk, one management scheme).
- Use **ZFS-Thin** if you want zvols (block volumes for VMs) and advanced per-VM snapshots.
- Enable **compression** and **pool monitoring** (space and resilver).
- For backups, use separate storage — a Directory, or a secondary ZFS pool.
- **Don't format or carve up ZFS disks with external tools**: do everything through zpool.

---

## ⏺️ ZFS in short

- Pros: strongest data safety, powerful snapshots, compression, RAID all in one system.
- Cons: wants system resources (>8 GB RAM, plenty of CPU under load), reduced usable space on small
  pools, more complexity.

**To try it later:** add at least 2 dedicated disks and manage everything with ZFS (avoiding a mix
with LVM on the same disk). Recommended on production servers with many identical disks and
mission-critical storage.

---

## 3. Example layouts (simplified best practice, without ZFS)

### A very simplified classic scheme

| Disk | Suggested use | Proxmox storage type |
|------|---------------|----------------------|
| SSD | Proxmox system + "important"/fast VMs | LVM-Thin or LVM |
| HDD1+HDD2+HDD3+HDD4 | Bulk storage, ISO files, backups, "static" VMs | LVM, directory or software RAID (mdadm) |

---

### What can you do with the 4 disks?

#### A. Separate, no redundancy

- Each disk added as its own storage (Directory or LVM)
- Pros: simple, no capacity lost.
- Cons: each disk stands alone, so a failure means data loss.

#### B. Software RAID (mdadm) — only if you want redundancy

- Example: RAID 10 (mirroring + striping) → 2 disks' worth of capacity, high speed, fault tolerance.
- RAID 5 (striping + parity) → 3 disks' worth of capacity, tolerates one failed disk (but worse
  write performance).
- So:
  1. Assemble the RAID array (mdadm)
  2. Build LVM or a Directory on top of it and hand that to Proxmox.
- Pros: protection against failure.
- Cons: more complex, and you lose capacity.

#### C. A separate LVM on each disk

- More flexibility in volume management, but no native redundancy.

---

### Recommended pragmatic setup

**SSD:**

- Primary storage for "fast" VMs and/or the system
- Configure it with LVM-Thin (snapshots and thin provisioning for the VMs that matter most)

**Extra disks (HDD):**

- If you don't need redundancy → each disk as its own storage (`bulk1`, `bulk2`, …)
  - backup storage, ISOs, non-critical VM images.
  - Directory (if you want easy access), or classic LVM.

- If you do want redundancy, consider software RAID (mdadm) with LVM on top of the array.

---

## ⚠️ A disk shared over Samba on the same host: never CIFS to yourself

If a disk is already shared over Samba on **this same** Proxmox host (see
[`samba-share`](../../samba-share/README.md)) and you also want it as Proxmox storage, always use
**`Directory` on the local mountpoint**, never `CIFS` pointing at this host's IP — otherwise
Proxmox mounts over the network a disk that is already local, with real consequences (failed
backups, pointless network traffic, and on some NICs hardware instability too). A real case is
documented in [`samba-share`](../../samba-share/README.md) (see "If the shared disk is ALSO a
storage on this same Proxmox host") and in
[`e1000e-nic-hang-fix`](../e1000e-nic-hang-fix/README.md).

## 4. Adding the disks to Proxmox VE (practical notes)

**1. Prepare each disk:**
```bash
wipefs -a /dev/sdx
parted /dev/sdx mklabel gpt
```

**2. In the Proxmox GUI → Datacenter → Storage → Add**

- **Directory**: pick the disk's mountpoint
- **LVM/LVM-Thin**: Proxmox can initialise the disk with LVM/LVM-Thin for you

**3. (Optional) Prepare software RAID**

- Create the RAID (mdadm), then initialise storage on top as if it were a single disk.

---

## 5. Best practice

- **With LVM-Thin**: turn on notifications for when the thin pool reaches high utilisation.
- **Backups**: plan separate storage for PBS (Proxmox Backup Server) backups, or at least snapshots
  plus periodic downloads.
- **Naming**: use clear storage names (`ssd-fast`, `bulk1`, `bulk-raid`, …).
- **Place by workload**: database and fast VMs on the SSD, archives and slow data on HDDs.

---

## In short — recommended layout for this case

### SSD
> LVM-Thin, for important VMs and containers, and possibly the Proxmox system itself.

### 4x disks
> For simplicity, set them up as individual Directories or LVMs (one per disk).
> For redundancy, consider software RAID (mdadm RAID5 or RAID10) with LVM or a Directory on top.
>
> **Skip ZFS only if space is tight or you want the simplest possible installation.**
