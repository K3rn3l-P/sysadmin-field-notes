# Correzione NVIDIA host Proxmox – Linux

## Scopo
Guida per blacklistare i driver NVIDIA/Nouveau sull'host Proxmox quando la GPU deve essere passata a una VM o a un container.

## Prerequisiti

- Host Proxmox VE
- Accesso root via shell
- GPU dedicata a passthrough verso VM/LXC

## Verifica GPU

```bash
lspci | grep -i nvidia
```

Oppure:

```bash
lspci | grep -i vga
lspci -nnk | grep -A 10 '05:00'
```

## Controlla i file di blacklist

```bash
cat /etc/modprobe.d/vfio.conf
cat /etc/modprobe.d/blacklist-nvidia2070.conf
```

Esempio di file per passthrough:

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

## Aggiorna initramfs e GRUB

```bash
update-initramfs -u && update-grub && reboot
```

## Verifica dopo reboot

```bash
lspci -nnk | grep -A 10 '05:00'
```

---

## Note

- Assicurati che la GPU sia destinata a una VM o a un container prima di blacklistare i driver sull'host.
- Dopo il reboot, controlla che l'host non carichi più i driver NVIDIA/Nouveau per quel device.

---

**Ultimo aggiornamento:** Aprile 2026
