# Clean NVIDIA driver install on Debian 12 VM / Proxmox

This guide covers installing the NVIDIA drivers safely on Debian 12 in a virtualised environment
(Proxmox VM, PCI passthrough), avoiding the version mismatches and breakage that come from mixed
repositories or incompatible packages.

---

## Important warning

⚠️ NEVER add extra NVIDIA/CUDA repositories unless you know exactly what you're doing and can keep
ALL the packages aligned!

---

## Prerequisites and caveats

- ☑️ Use **only the official Debian repositories** (`deb.debian.org`) — no CUDA repos, no NVIDIA
  `.run` packages
- ☑️ No experimental or third-party repositories (everything comes from Debian)
- ☑️ main, contrib, non-free and non-free-firmware ENABLED in `/etc/apt/sources.list`
- ☑️ System up to date

---

## Step 1 – Update the system

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget sudo vim gnupg2 ca-certificates lsb-release
```

---

## Step 2 – Set up the official Debian repositories

```bash
sudo tee /etc/apt/sources.list > /dev/null <<'EOF2'
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-backports main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
EOF2

sudo apt update
```

---

## Step 3 – Install the NVIDIA driver and Debian's CUDA toolkit (NOT the NVIDIA repo!)

```bash
sudo apt install -y nvidia-driver nvidia-cuda-toolkit
sudo reboot
# After the reboot:
nvidia-smi
```

🔎 If that command shows your GPU, you're set.

---

## Step 4 – Install Docker (latest from the Docker repo, no PPA needed)

```bash
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER   # log out and back in for this to take effect
```

---

## Step 5 – Install the NVIDIA Container Toolkit

```bash
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
sudo sed -i 's|^deb |deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] |' /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt update
sudo apt install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

#### Test the GPU inside Docker:

```bash
docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi
```

---

## Post-install repository check

Make sure no extra NVIDIA/CUDA repositories crept in:

```bash
grep -Ri nvidia /etc/apt/sources.list*
```

If the output mentions repos like `developer.download.nvidia.com`, remove them and then run:

```bash
sudo apt update
```

---

## Step 6 – Post-install checklist

- `nvidia-smi` MUST work and show the card
- Docker containers MUST be able to see the GPU
- Reboot at least once and confirm the NVIDIA module loads (`lsmod | grep nvidia`)
- No red warnings in `dmesg`/`syslog`/`kernel`
- Docker and CasaOS both work
- NO other NVIDIA/CUDA repository configured

---

## Future upgrades

Once the base install is done, use the
[NVIDIA safe driver upgrade script](../gpu-nvidia-update/) as the ONLY way to upgrade the driver.
Do not run a plain `apt upgrade` over the NVIDIA packages.

---
## 🔒 Update safety: apt upgrade and the NVIDIA driver

Even on a system with **only official Debian repositories**, upgrade the NVIDIA drivers **through
the dedicated safe-upgrade script only**.

- **For system and application updates:**
  - `apt update && apt upgrade -y` as usual.
- **For the NVIDIA drivers:**
  - Don't rely on `apt upgrade` alone for `nvidia-driver` and its related packages.
  - Always use [nvidia_safe_upgrade.sh](../gpu-nvidia-update/) so that **all** NVIDIA package
    versions are aligned before the upgrade.
  - This avoids problems such as:
    - `nvidia-smi` not found
    - NVIDIA modules not loading
    - Docker/LLM workloads no longer seeing the GPU

**When in doubt:**
- Hold the NVIDIA packages with `apt-mark hold ...`
- Unhold them only for the upgrade script, then put the hold back.

### Hold the NVIDIA packages, to be safe

```bash
sudo apt-mark hold nvidia-driver nvidia-driver-bin nvidia-driver-libs nvidia-kernel-dkms \
  xserver-xorg-video-nvidia nvidia-vdpau-driver nvidia-settings libnvidia-cfg1 \
  firmware-nvidia-gsp nvidia-persistenced
```

### Unhold and upgrade with the script only

```bash
sudo apt-mark unhold nvidia-driver nvidia-driver-bin nvidia-driver-libs nvidia-kernel-dkms \
  xserver-xorg-video-nvidia nvidia-vdpau-driver nvidia-settings libnvidia-cfg1 \
  firmware-nvidia-gsp nvidia-persistenced
./nvidia_safe_upgrade.sh
sudo apt-mark hold nvidia-driver nvidia-driver-bin nvidia-driver-libs nvidia-kernel-dkms \
  xserver-xorg-video-nvidia nvidia-vdpau-driver nvidia-settings libnvidia-cfg1 \
  firmware-nvidia-gsp nvidia-persistenced
```

---

## Troubleshooting

- **Don't mix the CUDA repo with the Debian repo!**
- If something goes wrong, roll back to the VM backup/snapshot and re-check every version.

---

## Safe upgrade script

✳️ To keep the system and the drivers aligned without surprises, use the
[NVIDIA safe driver upgrade script](../gpu-nvidia-update/).
