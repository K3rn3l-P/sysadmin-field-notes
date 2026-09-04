# Analisi spazio disco con ncdu – Linux

## Scopo
Guida rapida all'uso di `ncdu` per analizzare e liberare spazio disco in modo interattivo su Linux.

## Prerequisiti

- Sistema Linux con accesso `sudo`
- `ncdu` installato sul sistema

## Installazione

```bash
sudo apt update
sudo apt install ncdu
```

## Uso base

```bash
sudo ncdu /
```

Questo avvia un'interfaccia ncurses che esplora `/` e mostra le directory più pesanti.

## Best practice: limita ncdu al filesystem root

```bash
sudo ncdu -x /
```

- `-x` (--one-file-system): limita all’attuale filesystem, esclude altri mountpoint.
- Rapidissimo e non rischi di includere dati di dischi esterni/smb/backup.

## Cosa significa l'output

Vedrai solo le directory/file del disco dove è montata `/`, ignorando tutto ciò che è montato sotto (`/mnt`, `/DATA`, `/media`, ecc).

## Consigli

- Esamina prima le directory grandi, quindi rimuovi con cautela.
- Non cancellare file di sistema se non sai esattamente cosa fanno.
- Se trovi file temporanei o cache inutili, valuta la cancellazione selettiva.

---

**Ultimo aggiornamento:** Aprile 2026
