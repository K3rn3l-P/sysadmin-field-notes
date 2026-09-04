# GPU VRAM per Docker container – Linux

## Purpose
How to install and use a script that maps GPU (VRAM) usage from `nvidia-smi` back to Docker
containers, sorted by VRAM in use.

## Prerequisites

- A Linux host with the NVIDIA drivers installed
- `nvidia-smi` available
- Docker installed, if you want the PID mapped to a container

## The script

Save the script as `/usr/local/bin/gpu-vram-by-container.sh` and make it executable.

It pulls its information straight from `nvidia-smi` and shows:

- a per-card GPU summary
- GPU name, driver version, temperature, GPU utilisation %, memory utilisation %
- memory in use and total memory
- processes holding VRAM
- PID → Docker container mapping where available

## Installation and usage

### Option A: run it from the current directory

```bash
chmod +x ./gpu-vram-by-container.sh
./gpu-vram-by-container.sh
```

Use the command's own live mode:

```bash
./gpu-vram-by-container.sh --live 2
```

`--live` refreshes only the values that actually change and keeps the headers and static parts in
the same place on screen.

### Option B: install it on PATH (recommended)

```bash
sudo install -m 0755 ./gpu-vram-by-container.sh /usr/local/bin/gpu-vram-by-container.sh
gpu-vram-by-container.sh
```

Once it's on PATH, the live version runs the same way (the internal live mode is the most reliable
way to run the monitor):

```bash
gpu-vram-by-container.sh --live 2
```

> Note:
>
> If you installed the script on `PATH` and the colours don't show up, first check which copy is
> actually running:
>
> ```bash
> which gpu-vram-by-container.sh
> ```
>
> Then reinstall the updated copy with:
>
> ```bash
> sudo install -m 0755 ./gpu-vram-by-container.sh /usr/local/bin/gpu-vram-by-container.sh
> hash -r
> ```
>
---

## Notes

- The script needs `nvidia-smi`; without it, it exits with an error.
- With Docker installed, it tries to map each PID to the matching container.
- Works both on bare metal and in a VM with GPU passthrough.

---

**Last updated:** April 2026
