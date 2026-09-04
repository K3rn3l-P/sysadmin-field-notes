# Condivisione disco in rete con Samba – Linux

## Scopo
Guida per creare una condivisione Samba su Linux e permettere l'accesso da altri host in rete.

## Prerequisiti

- Sistema Linux con accesso `sudo`
- Rete locale funzionante
- Disco o directory da condividere montata sul server

## Installazione

```bash
sudo apt update
sudo apt install samba
```

## Creazione utente Samba

```bash
sudo adduser condiviso
sudo smbpasswd -a condiviso
```

## Configurazione della condivisione

Aggiungi la sezione seguente in `/etc/samba/smb.conf`:

```ini
[4TB]
   path = /mnt/4TB
   browseable = yes
   writable = yes
   valid users = condiviso
   create mask = 0770
   directory mask = 0770
```

## Permessi cartella

```bash
sudo chown -R condiviso:condiviso /mnt/4TB
sudo chmod -R 770 /mnt/4TB
```

## Riavvio servizio Samba

```bash
sudo systemctl restart smbd
```

## Accesso da Windows

- Percorso di rete: `\\IP_DEL_SERVER_PROXMOX\4TB`
- Utente: `condiviso`
- Password: quella impostata con `smbpasswd`

---

## ⚠️ Se il disco condiviso è ANCHE uno storage di questo stesso Proxmox

Errore commesso due volte (su due host diversi) prima di essere diagnosticato:
se aggiungi questo stesso disco come storage Proxmox **CIFS puntando all'IP
di questo host**, crei un loop di rete verso se stesso — Proxmox monta via
rete un disco che è già locale.

```
❌ SBAGLIATO — storage.cfg con CIFS verso l'IP di questo stesso host:

cifs: NomeStorage
	path /mnt/pve/NomeStorage
	server <IP DI QUESTO STESSO HOST>   ← qui il problema
	share 4TB
	...
```

Conseguenze osservate in produzione: traffico di rete inutile (che su una
NIC con bug come l'Intel 82579LM può innescare hang hardware — vedi
[`e1000e-nic-hang-fix`](../proxmox/e1000e-nic-hang-fix/README.md)), latenza aggiuntiva,
e soprattutto **job di backup falliti**: il `rename()` finale di vzdump
(da `.vma.dat` a `.vma.zst`) è risultato inaffidabile passando per il mount
CIFS verso se stesso, con errore `unable to rename ... .vma.dat to ....vma.zst`
— backup che sembravano completati ma in realtà erano scarti da 12+ ore di
lavoro perso.

```
✅ CORRETTO — storage Directory sul mountpoint locale, niente rete:

dir: NomeStorage
	path /mnt/4TB
	content backup,iso,vztmpl,import,snippets
```

**Nota sul `content`:** se il disco è NTFS (via ntfs-3g, come in questa
guida), evita `images`/`rootdir` nel content — NTFS non gestisce permessi
Unix e symlink come servirebbe per dischi VM/CT.

**Regola pratica:** CIFS in `storage.cfg` ha senso solo quando `server` è
l'IP di **un'altra macchina**. Se `server` è l'IP di questo stesso host,
usa sempre `dir` sul path di mount locale.

## Info extra

- Firewall: consentire TCP `445/139`, UDP `137/138`
- Per aggiungere altri utenti:
  ```bash
  sudo smbpasswd -a nomeutente
  ```
- Per usare gruppi, aggiungi gli utenti al gruppo `condiviso`.

---

**Ultimo aggiornamento:** Aprile 2026
