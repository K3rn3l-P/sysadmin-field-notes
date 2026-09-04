# Utility Swap Proxmox VM – Guida rapida

Utility e best practice per gestire la RAM e abilitare lo swap **all’interno delle VM Proxmox/linux**
Valida per Debian/Ubuntu ma facilmente adattabile

---

## Perché serve lo swap in una VM?

- Evita crash improvvisi/OOM-killer quando la RAM si satura (es: Docker, LLM, AI, servizi pesanti)
- Migliora stabilità su VM con workload variabile/dinamico
- È fondamentale dove la RAM “vista” dalla VM è fisiologicamente meno di quella assegnata in GUI

---

## Best practice RAM & SWAP su Proxmox VM

- RAM: assegna in Hardware → Memory, GUI Proxmox (es: 8–32 GiB a seconda del carico)
- **Ballooning:** disabilitato (a meno di esigenze specifiche)
- **Swap:** sempre attivo, almeno 4–8 GiB (anche su SSD, meglio swap che crash!)

---

## Creazione Swap automatica (con script incluso)

### 1. Copia lo script `crea_swap.sh` nella VM  
### 2. Rendi eseguibile  
```bash
chmod +x crea_swap.sh
```
### 3. Esegui specificando la dimensione desiderata (in GiB, default 4GB):  
```bash
sudo ./crea_swap.sh 8   # crea swapfile da 8GB
```

### 4. Controlla che swap sia attivo:  
```bash
free -h
swapon --show
```

---

## Script: crea_swap.sh

```bash
#!/bin/bash
# crea_swap.sh – crea file swap in automatico in una VM
# usage: sudo ./crea_swap.sh [GB]   (es: sudo ./crea_swap.sh 8)
SIZE="${1:-4}" # default a 4GB se non specificato

set -e

if [[ "$EUID" -ne 0 ]]; then
  echo "❌ Devi eseguire come root (usa sudo)!"
  exit 1
fi

if swapon --noheadings --show=NAME | grep -q '/swapfile'; then
  echo "⚠️  Swapfile già presente. Esci senza modificare nulla."
  swapon --show; exit 0
fi

echo "📝 Creo swapfile da ${SIZE} GB in /swapfile ..."
fallocate -l "${SIZE}G" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count="$((SIZE*1024))"
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
if ! grep -q '/swapfile' /etc/fstab; then
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
echo "✅ Swap di ${SIZE}GB creato e attivo!"
swapon --show
```

---

## Domande frequenti

- **Swap su SSD rovina il disco?**  
  **No, se non swap usato pesantemente e continuamente. In ambienti normali, la durata è accettabile e swap protegge i dati da crash/OOM.**

- **Serve reboot dopo swap?**  
  **No!** Lo swap è subito attivo. Reboot serve solo se vuoi verificare la persistenza.

- **La VM vede meno RAM di quella assegnata in Proxmox?**  
  È normale vedere poche centinaia di MB in meno (riservati a firmware/virtualizzatore). Se la differenza è grande, controlla Ballooning e config VM.

---

## Troubleshooting

- **free -h** deve mostrare la riga “Swap” con valore > 0
- **swapon --show** deve elencare `/swapfile`
- **Se vedi errori OOM in dmesg** nonostante swap, aumenta RAM/Swap o limita i processi che consumano più memoria (`ps aux --sort=-%mem | head`)
- **Ballooning ancora attivo?** Disabilitalo dalla GUI Proxmox → Hardware → Memory.
