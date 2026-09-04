# GPU VRAM per container Docker – Linux

## Scopo
Guida per installare e usare uno script che mappa l'utilizzo GPU (VRAM) di `nvidia-smi` ai container Docker, ordinando i risultati per VRAM utilizzata.

## Prerequisiti

- Host Linux con driver NVIDIA installati
- `nvidia-smi` disponibile
- Docker installato se vuoi mappare il PID al container

## Script

Salva lo script in `/usr/local/bin/gpu-vram-by-container.sh` e rendilo eseguibile.

Lo script raccoglie informazioni direttamente da `nvidia-smi` e mostra:

- riepilogo GPU per ogni scheda
- nome GPU, versione driver, temperatura, utilizzo GPU%, utilizzo memoria%
- memoria utilizzata e memoria totale
- processi con VRAM allocata
- mapping PID → container Docker se disponibile

## Installazione e utilizzo

### Opzione A: esegui dalla cartella corrente

```bash
chmod +x ./gpu-vram-by-container.sh
./gpu-vram-by-container.sh
```

Usa la modalità live interna del comando:

```bash
./gpu-vram-by-container.sh --live 2
```

La modalità `--live` aggiorna solo i valori che cambiano realmente e mantiene le intestazioni/statiche sulla stessa posizione dello schermo.

### Opzione B: installa in PATH (consigliata)

```bash
sudo install -m 0755 ./gpu-vram-by-container.sh /usr/local/bin/gpu-vram-by-container.sh
gpu-vram-by-container.sh
```

Dopo l'installazione in PATH, puoi eseguire la versione live anche così (il modo più affidabile per eseguire il monitor live è usare la modalità interna:):

```bash
gpu-vram-by-container.sh --live 2
```

> Nota:
>
> Se hai installato lo script in `PATH` e i colori non appaiono, prima controlla quale copia viene eseguita:
>
> ```bash
> which gpu-vram-by-container.sh
> ```
>
> Poi reinstalla la copia aggiornata con:
>
> ```bash
> sudo install -m 0755 ./gpu-vram-by-container.sh /usr/local/bin/gpu-vram-by-container.sh
> hash -r
> ```
>
---

## Note

- Lo script richiede `nvidia-smi`; se non è presente, esce con errore.
- Con Docker installato, prova a mappare il PID al container corrispondente.
- Funziona sia su host che su VM con GPU passthrough.

---

**Ultimo aggiornamento:** Aprile 2026
