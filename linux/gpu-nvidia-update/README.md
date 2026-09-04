This is the standard approach for an APT-managed NVIDIA system.

# Safe NVIDIA GPU upgrade (Debian/Ubuntu, VM, Proxmox, passthrough)

The `nvidia_safe_upgrade.sh` script upgrades the NVIDIA drivers only when every candidate version
lines up (fail-safe).

## When and why

- VMs or bare metal with an NVIDIA GPU, especially under Proxmox (PCI passthrough), LLM/AI
  workloads, or the Docker GPU runtime.
- Avoids the usual NVIDIA dependency breakage after upgrades or Debian/CUDA repo drift.

## Prerequisites

- Bash, APT
- sudo/root permissions
- Debian, Ubuntu, or a supported VM/container

## Usage

1. Run: `chmod +x nvidia_safe_upgrade.sh && ./nvidia_safe_upgrade.sh`
2. Check the result: it only upgrades when all versions match
3. Otherwise it **UPGRADES NOTHING** — fail-safe by design

## Unattended use / cron

This folder also ships `nvidia_safe_upgrade_auto.sh`, meant to be run from cron.

1. Make the script executable:
   - `chmod +x nvidia_safe_upgrade_auto.sh`
2. Edit root's crontab:
   - `sudo crontab -e`
   - If `crontab` isn't installed on a minimal Debian/Ubuntu, first run:
     - `sudo apt update && sudo apt install -y cron`
     - `sudo systemctl enable --now cron`
3. Add a line like this to run it every Sunday at 02:00:
   - `0 2 * * 0 /usr/bin/env bash /path/to/sysadmin-field-notes/linux/gpu-nvidia-update/nvidia_safe_upgrade_auto.sh`
4. Check the logs in `linux/gpu-nvidia-update/nvidia_safe_upgrade_auto.log`.

### Alternative: a systemd timer
If your system uses `systemd`, a timer works instead of `cron`.

1. Create `/etc/systemd/system/nvidia-safe-upgrade.service` with:
   ```ini
   [Unit]
   Description=Automatic safe NVIDIA driver upgrade

   [Service]
   Type=oneshot
   ExecStart=/usr/bin/env bash /path/to/sysadmin-field-notes/linux/gpu-nvidia-update/nvidia_safe_upgrade_auto.sh
   ```

2. Create `/etc/systemd/system/nvidia-safe-upgrade.timer` with:
   ```ini
   [Unit]
   Description=Timer for nvidia-safe-upgrade.service

   [Timer]
   OnCalendar=Sun 02:00
   Persistent=true

   [Install]
   WantedBy=timers.target
   ```

3. Enable and start the timer:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now nvidia-safe-upgrade.timer
   sudo systemctl status nvidia-safe-upgrade.timer
   ```

4. Read the service logs with:
   ```bash
   journalctl -u nvidia-safe-upgrade.service
   ```

> Note: in the current versions of `nvidia_safe_upgrade.sh` and `nvidia_safe_upgrade_auto.sh`, all
> the dynamic NVIDIA package detection, hold/unhold handling and kernel/userland mismatch checking
> is already built in.
> Separate scripts such as `nvidia_hold_all.sh`, `nvidia_unhold_all.sh` or
> `nvidia_mismatch_check.sh` are no longer needed.
>
> These scripts handle automatically:
> - creating and updating `/etc/apt/preferences.d/99-nvidia-block`
> - temporarily lifting the NVIDIA pin-block before the atomic upgrade
> - restoring the pin-block automatically, even on error or interruption
> - dynamic hold/unhold of every installed NVIDIA package, detected rather than hard-coded
> - checking for an NVIDIA kernel/userland mismatch before and after the upgrade
> - stopping and restarting `apt-daily.timer` and `apt-daily-upgrade.timer` around the atomic upgrade
> - an initial log entry always: the log is created even when there are no NVIDIA APT packages
> - falling back to checking `nvidia-smi` and `modinfo nvidia` by hand when no APT packages are found
>
> In practice: `apt update && apt upgrade` updates Debian/Docker/CasaOS without touching the NVIDIA
> packages these scripts manage.
>
> If the log shows `Candidate: NOT AVAILABLE`, or reports a mismatch, the NVIDIA drivers are held
> and will only be upgraded once a compatible official repository is available again.
>
> The logs also list the active APT repositories and any installed NVIDIA/CUDA packages with no
> candidate available.
>
> On a minimal Debian/Ubuntu VM or container without `cron`, install it with
> `sudo apt install -y cron` and enable it with `sudo systemctl enable --now cron`.
> Alternatively, prefer a `systemd` timer if `systemd` is already available in your environment.

---

## 📚 Clean NVIDIA install guide

For the detailed guide on **installing the NVIDIA drivers from scratch, safely**, on
Debian/Proxmox/VM, see:

➡️ [NVIDIA driver installation guide](../gpu-nvidia-install-guide/)

## Caveats and limits

Run non-interactively (cron/scripts), everything goes to the log so it can be audited.
Watch where `nvidia_safe_upgrade_auto.log` is written and what the write permissions are: under
different permissions the path may change, and the file grows over time.

The automatic script does simple log rotation: past 1 MB, it keeps only the last 1000 lines.

Both scripts now apply `apt-mark hold` to the NVIDIA packages at startup, lift it only for the
atomic upgrade, and put it straight back afterwards.

On a successful upgrade, the script reports whether a reboot is needed to finish configuring the
NVIDIA drivers.

The automatic script exits with code 1 on a mismatch or when a reboot is recommended, and code 2 on
an `apt-get` error.

## Troubleshooting

- If the script reports differing versions, don't install the drivers — wait for the repo packages
  to line up
- Always take a backup or a VM snapshot first

## Extending it

You can add key NVIDIA packages to the script's list to suit your own hardware/VM setup.
