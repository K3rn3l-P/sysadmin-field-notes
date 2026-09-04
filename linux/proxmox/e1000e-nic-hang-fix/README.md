# Fix blocco totale Proxmox — e1000e "Detected Hardware Unit Hang" (Intel 82579LM)

> **Diagnosticato e risolto su HP Z420 Workstation, Proxmox VE 8.4.18, kernel 6.8.12-20-pve, 1 agosto 2026.**
> Valido per qualunque host con NIC Intel serie e1000e (82579LM e simili) che si blocca sotto carico di rete prolungato.

---

## Sintomo

Con tutte le VM/CT spente e una sola VM accesa che genera traffico di rete
sostenuto e prolungato (nel nostro caso una VM Ubuntu Server), dopo alcune ore
il server diventava **completamente irraggiungibile**: GUI Proxmox, SSH, siti
web sulle VM, l'intera LAN — morto tutto. L'unico modo per uscirne era lo
spegnimento fisico col tasto power, seguito da un riavvio normale.

Sembrava calore, PSU, o un crash del kernel. **Non era nessuna delle tre.**

## Diagnosi

```bash
# Elenco dei boot con orari di inizio/fine
journalctl --list-boots

# Per ogni boot sospetto, conta gli hang della NIC
journalctl -b -N -k | grep -c 'Detected Hardware Unit Hang'
```

Risultato: **centinaia di occorrenze per boot**, e **zero** `Reset adapter`
nei log — il driver rilevava il blocco ma non recuperava mai da solo. La coda
TX della scheda si inchiodava e restava così per sempre, mentre il resto
dell'host era perfettamente vivo (solo muto in rete).

**Cosa ha escluso il calore/PSU:**
- CPU sempre 43-52°C (soglia critica 89°C), zero throttling, zero MCE
  (`sensors`, `journalctl -k | grep -iE 'thermal|throttl|mce'`)
- Gli spegnimenti col tasto power comparivano nel journal come **shutdown
  puliti** (`poweroff.target` raggiunto, journald chiuso in modo ordinato) —
  un kernel panic o una PSU in protezione non producono questo pattern
- PSU (EVGA G3 750W) ampiamente sovradimensionata per il carico reale

**Causa reale:** bug driver/firmware noto sulla Intel 82579LM (e altre e1000e)
quando **TSO/GSO** (TCP/Generic Segmentation Offload) e/o **EEE** (Energy
Efficient Ethernet) sono attivi. Confermato su più thread del forum Proxmox e
gist pubblici (vedi Fonti).

```bash
ethtool -k eno1 | grep -E 'tcp-segmentation|generic-segmentation|generic-receive'
ethtool --show-eee eno1
```

**Verificato anche nel BIOS HP F10 Setup** (manuale ufficiale HP Z220/Z420/
Z620/Z820 Maintenance and Service Guide, Table 2-2): non esiste alcuna
opzione EEE/offload lato firmware su questa generazione di workstation HP —
solo S5 Wake-on-LAN, NIC Option ROM Download, NIC Controller (Available/
Hidden). Il fix è possibile **solo lato OS/driver**.

**Aggravante trovato in parallelo:** lo storage Proxmox `TB4` era un CIFS che
puntava all'IP di questo stesso host (`//10.0.0.10/4TB`) — Proxmox montava via
rete un disco che era già locale. Generava traffico inutile proprio sulla NIC
difettosa e, quando la NIC si bloccava, il mount CIFS finiva in D-state
trascinando giù `pvestatd`/`pveproxy` con sé (sintomo: prima si blocca la GUI,
poi muore tutto).

---

## Fix 1 — Disattivare TSO/GSO/GRO/EEE sulla NIC (causa primaria)

File: [`post-up-vmbr0.conf`](./post-up-vmbr0.conf) — snippet da incollare in
`/etc/network/interfaces`, dentro la stanza `iface vmbr0 inet static`:

```bash
	post-up /usr/sbin/ethtool -K eno1 tso off gso off gro off sg off
	post-up /usr/sbin/ethtool --set-eee eno1 eee off
	post-up /usr/sbin/ethtool -G eno1 rx 4096 tx 4096
```

Applicare anche a caldo (senza riavviare la rete), per verificare subito:

```bash
ethtool -K eno1 tso off gso off gro off sg off
ethtool --set-eee eno1 eee off
ethtool -G eno1 rx 4096 tx 4096
```

Costo prestazionale trascurabile su gigabit: la CPU assorbe il lavoro extra
senza problemi su qualunque workstation Xeon/Core moderna.

## Fix 2 — Watchdog di auto-recovery (rete di sicurezza)

Anche col Fix 1, tenere un watchdog che ripara da solo un eventuale hang
residuo invece di dover correre al tasto power.

File: [`e1000e-watchdog.sh`](./e1000e-watchdog.sh) +
[`e1000e-watchdog.service`](./e1000e-watchdog.service)

```bash
# Copia lo script
cp e1000e-watchdog.sh /usr/local/sbin/e1000e-watchdog.sh
chmod +x /usr/local/sbin/e1000e-watchdog.sh

# Copia il servizio systemd
cp e1000e-watchdog.service /etc/systemd/system/e1000e-watchdog.service

# Abilita e avvia
systemctl daemon-reload
systemctl enable --now e1000e-watchdog.service
```

Segue `journalctl -kf` in tempo reale; alla comparsa di
`Detected Hardware Unit Hang` fa down/up dell'interfaccia (fallback: reload
del modulo `e1000e` se il down/up non basta), riapplica i fix ethtool, e logga
tutto con `logger` (visibile in `journalctl -u e1000e-watchdog`).

**Testato** iniettando un hang fittizio nel kernel log:
```bash
echo "<3>e1000e 0000:00:19.0 eno1: Detected Hardware Unit Hang: TEST" > /dev/kmsg
journalctl -u e1000e-watchdog -f   # osserva il recupero, ~6 secondi
```

## Fix 3 — Eliminare lo storage CIFS che punta a se stesso

File: [`storage-cfg-TB4.snippet`](./storage-cfg-TB4.snippet) — mostra il
prima/dopo per `/etc/pve/storage.cfg`: da `cifs` (verso l'IP dell'host stesso)
a `dir` (sul mount locale già esistente). Nessun dato si sposta, i backup
vzdump restano visibili nella stessa cartella.

```bash
# Smonta il vecchio CIFS
systemctl stop mnt-pve-TB4.mount

# Modifica /etc/pve/storage.cfg secondo lo snippet
nano /etc/pve/storage.cfg

# Pulisci la credenziale non più usata e ricarica
rm -f /etc/pve/priv/storage/TB4.pw
systemctl restart pvestatd
pvesm status   # TB4 deve risultare "dir" e "active"
mount | grep "<IP-di-questo-host>" || echo "OK: nessun mount CIFS residuo verso se stesso"
```

Se il disco sottostante è NTFS via ntfs-3g, aggiungere anche in `/etc/fstab`
le opzioni `noatime,big_writes` per ridurre le scritture di metadati:

```
UUID=... /mnt/... ntfs-3g defaults,noatime,big_writes,uid=...,gid=...,umask=007 0 0
```

> **Riscontrato due volte, su due host Proxmox diversi.** Se stai impostando
> da zero una condivisione Samba su un disco Proxmox, la guida
> [`samba-share`](../../samba-share/README.md) ora include l'avviso su questo esatto
> errore — evita di doverlo scoprire nel modo difficile come qui.

## Fix 4 — smartd per-disco (monitoraggio, non causa del problema)

File: [`smartd.conf`](./smartd.conf) — configurazione smartd per-disco con
soglie mirate e self-test pianificati su giorni distinti, al posto del
`DEVICESCAN` generico. **Non risolve l'hang**, ma è stato aggiunto durante la
stessa diagnosi perché utile a intercettare per tempo problemi reali sui
dischi (uno aveva raggiunto 87°C in passato, un altro era vicino al TBW
nominale). Vedi commenti in testa al file per i dettagli e per come adattare
i path `/dev/disk/by-id/...` a un hardware diverso.

```bash
cp smartd.conf /etc/smartd.conf
systemctl restart smartd
smartctl -t long /dev/sdX   # avvia un long self-test in background, per disco
```

---

## Verifica end-to-end

```bash
# 1) Nessun hang nel boot corrente
journalctl -b 0 -k | grep -c 'Detected Hardware Unit Hang'   # atteso: 0

# 2) Fix ethtool attivi
ethtool -k eno1 | grep -E 'tcp-segmentation|generic-segmentation|generic-receive'
ethtool --show-eee eno1
ethtool -g eno1

# 3) Watchdog attivo
systemctl is-active e1000e-watchdog

# 4) Nessun CIFS verso se stesso
pvesm status
mount | grep "<IP-di-questo-host>"   # deve risultare vuoto

# 5) Il vero test: accendere la VM che genera il traffico e lasciarla per
#    ore/giorni, poi ripetere il punto 1. È l'unico modo per confermare che
#    il bug non si ripresenta sotto carico reale.
```

**Contatori spia utili per confermare la stabilità nel tempo** (spegnimenti
non puliti pregressi, se il sistema si è bloccato/spento forzatamente in
passato questi contatori SMART sono già alti e da lì in poi non dovrebbero più
crescere):
```bash
smartctl -A /dev/sdX | grep -E 'POR_Recovery_Count|Unexpect_Power_Loss_Ct'
```

---

## Se il problema si ripresenta comunque

Il fix definitivo, se i fix software non bastassero, è sostituire la NIC
integrata con una **scheda PCIe Intel i210/i211** (~15-25€): spostare `vmbr0`
sulla nuova scheda e disabilitare la 82579LM dal BIOS (Security → Device
Security → NIC Controller → Hidden).

---

## Fonti

- [e1000e eno1: Detected Hardware Unit Hang — Proxmox Support Forum](https://forum.proxmox.com/threads/e1000e-eno1-detected-hardware-unit-hang.59928/)
- [Intel NIC e1000e hardware unit hang [SOLVED] — Proxmox Support Forum](https://forum.proxmox.com/threads/intel-nic-e1000e-hardware-unit-hang.106001/)
- [Proxmox | Fix "e1000e Detected Hardware Unit Hang" — GitHub gist](https://gist.github.com/brunneis/0c27411a8028610117fefbe5fb669d10)
- [Fix e1000e NIC Hardware Hang on Proxmox — Disable Offloading](https://www.budgetapp.works/blog/e1000e-nic-hardware-hang-fix-proxmox)
- [HP Z220 SFF, Z220 CMT, Z420, Z620, and Z820 Workstations Maintenance and Service Guide](https://images10.newegg.com/User-Manual/User_Manual_9B12K-0019-001G3.pdf) (Table 2-2, BIOS F10 Setup)

---

> Guida curata da [K3rn3l-P](https://github.com/K3rn3l-P) — vedi anche
> [`passthrough-nvidia-rtx2070`](../passthrough-nvidia-rtx2070) per lo stesso
> host HP Z420.
