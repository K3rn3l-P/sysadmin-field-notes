Questo è lo standard ufficiale per sistema NVIDIA con APT.

# Aggiornamento Sicuro NVIDIA GPU (Debian/Ubuntu, VM, Proxmox, Passthrough)

Script `nvidia_safe_upgrade.sh`: aggiorna i driver NVIDIA solo se tutte le versioni candidate sono allineate (fail-safe).

## Scenari/Motivazione

- Sistemi VM o hardware fisico con GPU NVIDIA, soprattutto se usati in Proxmox (PCI passthrough), LLM, AI, Docker runtime GPU.
- Evita rotture comuni delle dipendenze NVIDIA dopo aggiornamenti/disallineamenti dei repo Debian/CUDA.

## Prerequisiti

- Bash, APT
- Permessi sudo/root
- Debian, Ubuntu, oppure container VM supportate

## Come usare

1. Esegui: `chmod +x nvidia_safe_upgrade.sh && ./nvidia_safe_upgrade.sh`
2. Verifica risultato: aggiorna solo se tutte le versioni sono uguali
3. In caso contrario **NON AGGIORNA** nulla: sicurezza totale

## Uso automatico / cron

Questa cartella include anche lo script automatico `nvidia_safe_upgrade_auto.sh`, pensato per esecuzione da cron.

1. Rendi eseguibile lo script:
   - `chmod +x nvidia_safe_upgrade_auto.sh`
2. Modifica il crontab di root:
   - `sudo crontab -e`
   - Se `crontab` non è installato su Debian/Ubuntu minimal, esegui prima:
     - `sudo apt update && sudo apt install -y cron`
     - `sudo systemctl enable --now cron`
3. Aggiungi una riga come questa per farlo partire ogni domenica alle 02:00:
   - `0 2 * * 0 /usr/bin/env bash /path/to/utility-scripts/linux/gpu-nvidia-update/nvidia_safe_upgrade_auto.sh`
4. Controlla i log in `linux/gpu-nvidia-update/nvidia_safe_upgrade_auto.log`.

### Opzione alternativa: systemd timer
Se il tuo sistema usa `systemd`, puoi usare un timer invece di `cron`.

1. Crea `/etc/systemd/system/nvidia-safe-upgrade.service` con:
   ```ini
   [Unit]
   Description=Aggiornamento sicuro driver NVIDIA automatico

   [Service]
   Type=oneshot
   ExecStart=/usr/bin/env bash /path/to/utility-scripts/linux/gpu-nvidia-update/nvidia_safe_upgrade_auto.sh
   ```

2. Crea `/etc/systemd/system/nvidia-safe-upgrade.timer` con:
   ```ini
   [Unit]
   Description=Timer per nvidia-safe-upgrade.service

   [Timer]
   OnCalendar=Sun 02:00
   Persistent=true

   [Install]
   WantedBy=timers.target
   ```

3. Abilita e avvia il timer:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now nvidia-safe-upgrade.timer
   sudo systemctl status nvidia-safe-upgrade.timer
   ```

4. Visualizza i log del servizio con:
   ```bash
   journalctl -u nvidia-safe-upgrade.service
   ```

> Nota: con le versioni correnti di `nvidia_safe_upgrade.sh` e `nvidia_safe_upgrade_auto.sh`, tutte le funzioni di rilevamento dinamico dei pacchetti NVIDIA, gestione hold/unhold e controllo mismatch kernel/userland sono già integrate.
> Non è più necessario usare script separati come `nvidia_hold_all.sh`, `nvidia_unhold_all.sh` o `nvidia_mismatch_check.sh`.
>
> Questi script gestiscono automaticamente:
> - creazione/aggiornamento di `/etc/apt/preferences.d/99-nvidia-block`
> - disabilitazione temporanea del pin-block NVIDIA prima dell'upgrade atomico
> - riabilitazione automatica del pin-block anche su errore o interruzione
> - hold/unhold dinamico di tutti i pacchetti NVIDIA installati rilevati in modo non statico
> - controllo mismatch kernel/userland NVIDIA prima e dopo l'upgrade
> - stop/start automatico di `apt-daily.timer` e `apt-daily-upgrade.timer` durante l'upgrade atomico
> - log iniziale sempre attivo: anche se non ci sono pacchetti APT NVIDIA, viene creato il log
> - verifica manuale di `nvidia-smi` e `modinfo nvidia` quando non ci sono pacchetti APT trovati
>
> In pratica: `apt update && apt upgrade` aggiorna Debian/Docker/CasaOS senza toccare i pacchetti NVIDIA gestiti dagli script.
>
> Se nel log compare `Candidate: NON DISPONIBILE` o viene segnalato un mismatch, i driver NVIDIA sono bloccati e verranno aggiornati solo quando un repository ufficiale compatibile sarà nuovamente disponibile.
>
> I log includono anche la lista dei repository APT attivi e i pacchetti NVIDIA/CUDA installati senza candidate disponibili.
>
> Se stai usando una VM/container Debian/Ubuntu minimal senza `cron`, installa `cron` con `sudo apt install -y cron` e abilitalo con `sudo systemctl enable --now cron`.
> In alternativa, puoi preferire un `systemd timer` se nel tuo ambiente è già disponibile `systemd`.

---

## 📚 Guida installazione pulita NVIDIA

Per la guida dettagliata su come **installare i driver NVIDIA da zero in modo sicuro** su Debian/Proxmox/VM, vedi:

➡️ [Guida Installazione Driver NVIDIA](../gpu-nvidia-install-guide/)

## Criticità / limiti

In uso non-interattivo (cron/script) lo script registra tutto sul log per consentire auditing.
Attenzione a dove viene scritto `nvidia_safe_upgrade_auto.log` e ai permessi di scrittura: con permessi diversi il percorso potrebbe cambiare e il file può crescere nel tempo.

Lo script automatico include una rotazione log semplice: se il file supera 1MB, mantiene solo le ultime 1000 righe.

Entrambi gli script ora applicano automaticamente `apt-mark hold` ai pacchetti NVIDIA all'avvio e rimuovono temporaneamente il blocco solo durante l'aggiornamento atomico, poi lo ripristinano subito dopo.

In caso di aggiornamento riuscito, lo script segnala se è richiesto un reboot per completare la configurazione dei driver NVIDIA.

Lo script automatico esce con codice 1 se trova mismatch o se è raccomandato il reboot, e codice 2 in caso di errore `apt-get`.

## Risoluzione problemi

- Se lo script segnala versioni diverse, non installare driver, attendi allineamento pacchetti nei repo
- Fai sempre un backup o snapshot della VM/sistema prima

## Estendibile

Puoi aggiungere pacchetti chiave NVIDIA nella lista dello script, secondo il tuo scenario hardware/VM.
