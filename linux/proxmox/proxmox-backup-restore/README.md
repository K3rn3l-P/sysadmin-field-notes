# Ripristino VM da backup esterno su Proxmox VE – Linux

## Scopo
Guida passo-passo per recuperare e ripristinare backup VM da storage esterno (Samba/NFS/SSH) su un host Proxmox.

## Prerequisiti

- Host Proxmox VE con spazio disponibile su storage di destinazione
- Backup VM già copiato sul server Proxmox o accessibile via network
- Permessi root per eseguire `qmrestore`

## Procedura completa

### 1. Copia backup via SCP

```bash
mkdir -p /tmp/vm-backup
cd /tmp/vm-backup
scp root@10.0.0.20:/mnt/WD-P/dump/vzdump-qemu-100-*.vma.zst .
```

### 2. Verifica file ricevuto

```bash
ls -lh vzdump-qemu-*.vma.zst
```

Assicurati che il file sia completo e abbia la dimensione attesa.

### 3. Ripristina VM su storage locale

```bash
qm list
qmrestore vzdump-qemu-100-2026_03_22-03_00_09.vma.zst 101 --storage local-lvm
```

Alternative storage:

```bash
qmrestore vzdump-qemu-100-2026_03_22-03_00_09.vma.zst 101 --storage local
qmrestore vzdump-qemu-100-2026_03_22-03_00_09.vma.zst 101 --storage SSD
```

### 4. Avvia la VM

```bash
qm list
qm start 101
qm status 101
```

### 5. Verifica in GUI

```
Datacenter → 101 → Start → Console
```

## Opzioni utili di `qmrestore`

```bash
--force          # Sovrascrivi VM esistente
--storage XXX    # Storage destinazione (pvesm status)
--rootfs local:4 # Rootfs container (per CT)
```

## Risoluzione problemi comuni

- Storage non trovato:
  ```bash
  pvesm status
  ```
- File corrotto/incompleto:
  ```bash
  vzdump --restore vzdump-*.vma.zst --list
  ```
- ID VM duplicato:
  ```bash
  qm destroy 101 && qmrestore ...
  ```

## Cleanup post-ripristino

```bash
rm -rf /tmp/vm-backup/*
```

---

## Consigli

- Usa `qm list` per trovare ID liberi prima di ripristinare.
- Se usi storage non locale, verifica che lo spazio sia sufficiente e che il pool sia online.
- Mantieni i backup originali finché la VM non è testata correttamente.

---

**Ultimo aggiornamento:** Aprile 2026
