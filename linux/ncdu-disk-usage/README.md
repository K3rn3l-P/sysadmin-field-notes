# Disk usage analysis with ncdu – Linux

## Purpose
Quick guide to using `ncdu` to inspect and reclaim disk space interactively on Linux.

## Prerequisites

- A Linux system with `sudo` access
- `ncdu` installed

## Installation

```bash
sudo apt update
sudo apt install ncdu
```

## Basic usage

```bash
sudo ncdu /
```

This starts an ncurses interface that walks `/` and shows the heaviest directories.

## Best practice: keep ncdu on the root filesystem

```bash
sudo ncdu -x /
```

- `-x` (--one-file-system): stays on the current filesystem and skips other mountpoints.
- Very fast, and there's no risk of pulling in external disks, SMB shares or backups.

## Reading the output

You only see directories and files on the disk where `/` is mounted, ignoring everything mounted
underneath it (`/mnt`, `/DATA`, `/media`, and so on).

## Tips

- Look at the large directories first, then delete carefully.
- Don't remove system files unless you know exactly what they do.
- If you find temporary files or stale caches, consider deleting them selectively.

---

**Last updated:** April 2026
