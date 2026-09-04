# Importazione OVF su Proxmox VE – Linux

## Scopo
Guida pratica per importare una VM in formato OVF su Proxmox VE usando il comando `qm importovf`.

## Prerequisiti

- Proxmox VE installato e funzionante
- File `.ovf` disponibile sul host Proxmox
- Storage configurato su Proxmox (es. `SSD`)

## Sintassi corretta

```bash
qm importovf <vmid> <manifest.ovf> <storage>
```

- `<vmid>`: ID numerico che vuoi assegnare alla VM su Proxmox (es: `100`)
- `<manifest.ovf>`: file `.ovf` (es: `'TERA VM 100.02.ovf'`)
- `<storage>`: nome dello storage Proxmox dove mettere i dischi (es: `SSD`)

> Non serve indicare disco o directory, Proxmox legge tutto dal file OVF.

## Esempio pratico

```bash
qm importovf 100 'TERA VM 100.02.ovf' SSD
```

> Se il nome del file contiene spazi, usa le virgolette.

## Passaggi consigliati

1. Vai nella directory del file OVF:

    ```bash
    cd /mnt/4TB/TERA/Tera-Server(100.02)/TERA_VM-ovf_100.02
    ```

2. Esegui il comando:

    ```bash
    qm importovf 100 'TERA VM 100.02.ovf' SSD
    ```

3. Attendi l’importazione. La VM sarà visibile sull’interfaccia Proxmox.

## Consigli aggiuntivi

- Assicurati che lo storage (`SSD`) sia configurato su Proxmox VE.
- Verifica i permessi e lo spazio disponibile sullo storage.
- Cambia l’ID (`100`) secondo necessità.

---

## Risoluzione problemi comuni

- Storage non trovato: controlla con `pvesm status`
- File OVF non leggibile: verifica permessi e path
- ID VM già in uso: scegli un ID libero con `qm list`

---

**Ultimo aggiornamento:** Aprile 2026
