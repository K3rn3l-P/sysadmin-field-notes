# Guida Completa – Come "Sbloccare", Cancellare e Riutilizzare un Disco LVM in Proxmox VE

## Scopo  
A volte in Proxmox, un disco o una partizione risulta "bloccata" o inutilizzabile perché ancora in uso da LVM (Logical Volume Manager) anche se le VM non la stanno più usando. Questa guida spiega, con esempi e spiegazioni, come identificare la causa, sbloccare e azzerare un disco per poi riutilizzarlo su Proxmox, esattamente come abbiamo fatto nella nostra esperienza reale.

---

## Prerequisiti e Note di Sicurezza

- **Attenzione:** Tutti i dati sul disco selezionato saranno persi, irrimediabilmente.
- Esegui le operazioni **solo se sei sicuro di lavorare sul disco giusto** (tipicamente `/dev/sdb`, ma controlla!).
- Le operazioni vanno fatte da utente `root` sul nodo Proxmox (via terminale/Shell).

---

## 1. Diagnosi iniziale: capire cosa tiene occupato il disco

**Puoi trovarti davanti a errori come:**
- `disk/partition '/dev/sdb3' has a holder (500)`
- `error wiping '/dev/sdb1': dd: invalid number: '0.9833984375'`

> Questi avvisi vogliono dire che qualcosa (spesso LVM) usa ancora il disco o partizione.

### 1.1 Mostra la situazione dischi e LVM

```bash
# Mostra i dischi e le strutture LVM collegate
lsblk
lvs
pvs
vgs
```

**Output tipico:**
```
sdb                                   8:16   0 223.6G  0 disk
├─sdb1                                8:17   0  1007K  0 part
├─sdb2                                8:18   0     1G  0 part
└─sdb3                                8:19   0 222.6G  0 part
  ├─pve--OLD--xxxx-root        252:3    0  65.6G  0 lvm
  ... (altri LV)
```
Noterai che *la partizione sdb3 ha dei Logical Volumes (LV) associati a un Volume Group (VG) tipo `pve-OLD-...`*.

---

## 2. Disattivare qualsiasi uso del disco (umount, lvchange, vgchange)

È fondamentale disattivare tutti i Logical Volumes e il Volume Group associati al disco:

```bash
# Prova a smontare eventuali filesystem montati (tanti LV potrebbero essere già non montati)
umount /dev/mapper/pve--OLD--xxxx-root   # (se montato)
umount /dev/mapper/pve--OLD--xxxx-data   # (se montato)
# Non andare in errore se già non sono montati.

# Disattiva tutti i LV associati al VG
lvchange -an pve-OLD-xxxx/swap
lvchange -an pve-OLD-xxxx/root
lvchange -an pve-OLD-xxxx/data
lvchange -an pve-OLD-xxxx/data_tmeta
lvchange -an pve-OLD-xxxx/data_tdata
lvchange -an pve-OLD-xxxx/data-tpool
# Puoi elencare tutti i LV con: lvs

# Disattiva il Volume Group intero
vgchange -an pve-OLD-xxxx
```
(Sostituisci `xxxx` con quello che hai trovato da `lsblk/vgs`)

---

## 3. Rimuovere Volume Group e Physical Volume

```bash
# Elimina il Volume Group (chiederà conferma)
vgremove pve-OLD-xxxx

# Rimuovi la firma LVM dalla partizione
pvremove /dev/sdb3
```

Se ricevi ancora errori di "holder", assicurati che nessun processo usi più il disco:
```bash
lsof | grep /dev/sdb
cat /proc/swaps          # Se usato come swap, eseguire swapoff /dev/sdbX
```

---

## 4. Cancellare tutte le firme dal disco
Ora puoi eliminare le firme LVM e la vecchia tabella partizioni dal disco intero, NON solo la partizione:

```bash
wipefs -a /dev/sdb      # Rimuove tutte le firme note
sgdisk --zap-all /dev/sdb  # Cancella la GPT e PMBR

# (Extra sicurezza: cancella i primi MB del disco)
dd if=/dev/zero of=/dev/sdb bs=1M count=10

# (Opzionale) Cancella qualsiasi eventuale swap rimasto attivo
swapoff /dev/sdb2
```

---

## 5. (Opzionale) Crea tabella partizioni nuova

Se vuoi subito preparare il disco per un nuovo uso:
```bash
parted /dev/sdb mklabel gpt
```
Oppure, lascia vuoto per gestire tutto dall’interfaccia GUI di Proxmox.

---

## 6. Riscansiona dalla GUI Proxmox

È ora possibile aggiungere il disco come storage oppure usarlo per nuove VM o container in Proxmox VE dalla GUI senza errori.

---

## FAQ e Errori Comuni

**Q: Ho ancora messaggi “has a holder”?**  
A: Ciò succede se qualcosa usa ancora il disco: verifica con `lsof | grep /dev/sdb` e assicurati che nessun Logical Volume sia ancora attivo (`lvs`, `vgdisplay`).

**Q: Ho paura di cancellare il disco sbagliato!**  
A: Leggi bene output di `lsblk` e verifica taglia/dispositivo prima di procedere. Meglio verificare una volta in più che una in meno!

---

## Risorse Utili

- [Proxmox Wiki - LVM](https://pve.proxmox.com/wiki/LVM)
- [Comandi LVM](https://wiki.archlinux.org/title/LVM)
- [wipefs man page](https://man7.org/linux/man-pages/man8/wipefs.8.html)

---

*Questa guida è stata testata su Proxmox VE 8.x e kernel 6.x, basata su esperienza reale del troubleshooting!*