# Guida Installazione Pulita Driver NVIDIA su Debian 12 VM/Proxmox

Questa guida spiega come installare i driver NVIDIA in modo sicuro su Debian 12 in ambiente virtualizzato (Proxmox VM, PCI passthrough), evitando mismatch e rotture dovute a repository misti o pacchetti incompatibili.

---

## Avviso importante

⚠️ NON aggiungere MAI repository extra NVIDIA/CUDA a meno che tu non sappia esattamente cosa fai e tu possa allineare TUTTI i pacchetti!

---

## Prerequisiti & Avvertenze

- ☑️ Usa **SOLO repository ufficiali Debian** (`deb.debian.org`), NESSUNA repo CUDA o pacchetti .run NVIDIA
- ☑️ NO repository sperimentali o terze parti (tutto deve venire da Debian)
- ☑️ Main contrib, non-free e non-free-firmware ABILITATI su `/etc/apt/sources.list`
- ☑️ Sistema aggiornato

---

## Step 1 – Aggiorna il sistema

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget sudo vim gnupg2 ca-certificates lsb-release
```

---

## Step 2 – Imposta repository Debian ufficiali

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

## Step 3 – Installa Driver NVIDIA e toolkit CUDA Debian (NON repo NVIDIA!)

```bash
sudo apt install -y nvidia-driver nvidia-cuda-toolkit
sudo reboot
# Dopo riavvio:
nvidia-smi
```

🔎 Se il comando sopra mostra la tua GPU sei a posto!

---

## Step 4 – Installa Docker (ultimo da repo Docker, non serve PPA)

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
sudo usermod -aG docker $USER   # Logout/login per rendere effettivo
```

---

## Step 5 – Installa NVIDIA Container Toolkit

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

#### Test GPU dentro Docker:

```bash
docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi
```

---

## Controllo post-installazione repository

Verifica che non siano state aggiunte repository NVIDIA/CUDA extra:

```bash
grep -Ri nvidia /etc/apt/sources.list*
```

Se il risultato contiene repo come `developer.download.nvidia.com`, rimuovile e poi esegui:

```bash
sudo apt update
```

---

## Step 6 – Checklist post-installazione

- `nvidia-smi` DEVE funzionare e mostrare la scheda video
- I container Docker DEVONO essere in grado di rilevare la GPU
- Esegui almeno un reboot e verifica che il modulo NVIDIA si carichi correttamente (`lsmod | grep nvidia`)
- NO warning rossi in `dmesg`/`syslog`/`kernel`
- Docker e CasaOS funzionano
- NESSUN altro repository NVIDIA/CUDA configurato

---

## Upgrade futuro

Dopo l'installazione di base, usa come UNICO metodo per futuri upgrade driver lo [script di safe upgrade driver NVIDIA](../gpu-nvidia-update/) e NON eseguire un `apt upgrade` diretto sui pacchetti NVIDIA.

---
## 🔒 Sicurezza aggiornamenti: apt upgrade e driver NVIDIA

Anche su sistemi con **solo repository Debian ufficiali**, è raccomandato aggiornare i driver NVIDIA **solo tramite lo script di safe-upgrade dedicato**.

- **Per aggiornamenti di sistema e delle app:**
  - Usa normalmente `apt update && apt upgrade -y`.
- **Per i driver NVIDIA:**
  - NON affidarti solo a `apt upgrade` per `nvidia-driver` e pacchetti correlati.
  - Usa sempre [nvidia_safe_upgrade.sh](../gpu-nvidia-update/) per garantire che **tutte** le versioni dei pacchetti NVIDIA siano allineate prima dell'aggiornamento.
  - Questo evita problemi come:
    - `nvidia-smi` non trovato
    - moduli NVIDIA non caricati
    - Docker/LLM che non rilevano più la GPU

**In caso di dubbio:**
- Tieni i pacchetti NVIDIA in hold con `apt-mark hold ...`
- Sbloccali solo per lo script di upgrade, poi rimetteli in hold.

### Blocca i pacchetti NVIDIA per sicurezza

```bash
sudo apt-mark hold nvidia-driver nvidia-driver-bin nvidia-driver-libs nvidia-kernel-dkms \
  xserver-xorg-video-nvidia nvidia-vdpau-driver nvidia-settings libnvidia-cfg1 \
  firmware-nvidia-gsp nvidia-persistenced
```

### Sblocca e aggiorna solo con lo script

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

- **NON mischiare repo CUDA e repo Debian!**
- Se qualcosa va storto, torna al backup/snapshot VM e ricontrolla TUTTO l’allineamento!

---

## Script aggiornamento sicuro

✳️ Per mantenere il sistema e i driver sempre allineati senza sorprese, usa lo [script di safe upgrade driver NVIDIA](../gpu-nvidia-update/).
