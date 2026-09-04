# Sensori temperatura e hardware – Linux

## Scopo
Guida per installare e usare `lm-sensors` per monitorare temperatura, ventole e valori hardware su Linux.

## Prerequisiti

- Sistema Linux con accesso `sudo`

## Installazione

```bash
sudo apt update
sudo apt install lm-sensors -y
```

## Rileva sensori

```bash
sudo sensors-detect
```

Rispondi `yes` a tutte le domande per rilevare i moduli compatibili.

## Visualizzazione valori sensori

```bash
sensors -u    # formato numerico
sensors       # output leggibile
```

## Monitoraggio live

```bash
watch -n 2 "sensors | grep -E 'Tctl|Tdie|temp1_input|temp3_input'"
```

> Nota: questo filtro è utile soprattutto su AMD/Ryzen. Su molte CPU Intel (es. Xeon) il comando `sensors` mostra invece solo `Package` e `Core N`.
>
> Per Intel usa:
>
```bash
watch -n 2 "sensors | grep -E 'Core|Package'"
```

---

## Se i sensori CPU non compaiono

- Carica manualmente il modulo CPU:
  ```bash
  sudo modprobe coretemp   # Intel
  sudo modprobe k10temp    # AMD
  ```
- Se dopo reboot i sensori non compaiono, controlla che la riga `coretemp` o `k10temp` sia presente in `/etc/modules`.
- Puoi forzare un reload a caldo senza reboot:
  ```bash
  sudo systemctl restart kmod
  sudo sensors
  ```
- Se usi kernel custom o hardware più esotico, installa anche `i2c-tools` e verifica i chip con:
  ```bash
  sudo apt install i2c-tools -y
  sudo i2cdetect -l
  ```

## Solo temperature CPU pulite

```bash
sensors | grep -E 'Core|Package'
```

---

## Script di monitoraggio live della temperatura CPU

Se vuoi un controllo continuo con allarmi colore, puoi usare lo script `monitor-cpu-temp.sh`.

### Uso

1. Salva lo script in `linux/sensors-hw/monitor-cpu-temp.sh`
2. Rendi eseguibile:
   ```bash
   chmod +x monitor-cpu-temp.sh
   ```
3. Avvia il monitoraggio:
   ```bash
   ./monitor-cpu-temp.sh
   ```
   Puoi passare un intervallo in secondi, ad esempio `./monitor-cpu-temp.sh 5`.

### Cosa fa

- mostra le righe `Core N` e `Package` dai sensori
- usa `OK`, `ALLERTA` e `PERICOLO` nel campo `STATO`
- evidenzia in giallo le temperature sopra 75°C
- evidenzia in rosso le temperature sopra 85°C
- mostra anche una lista di processi top memoria standard (`ps`) per individuare i consumi più alti
- aggiorna continuamente lo schermo finché non premi Ctrl+C

## Cronologia boot e hang hardware

```bash
journalctl --list-boots              # elenco boot con orari di inizio/fine
journalctl -b -N -n 60 --no-pager    # coda log di un boot passato (N negativo, es. -1 = boot precedente)
journalctl -b -N -p err --no-pager   # solo errori di un boot specifico
```

> Se la fine di un boot non mostra uno shutdown pulito nel log successivo,
> è indizio di crash/blocco. Vedi [`e1000e-nic-hang-fix`](../proxmox/e1000e-nic-hang-fix)
> per un caso concreto (conteggio hang NIC per boot).

## Errori termici/hardware nel kernel log

```bash
journalctl -k | grep -iE 'thermal|throttl|mce|Machine Check'
cat /sys/devices/system/edac/mc/mc*/ce_count   # errori ECC RAM correggibili
cat /sys/devices/system/edac/mc/mc*/ue_count   # errori ECC RAM non correggibili
```

---

## Consigli

- Verifica i valori prima e dopo un carico per identificare eventuali anomalie.
- Usa `sensors -u` se vuoi integrare output in script di monitoraggio.

---

**Ultimo aggiornamento:** Agosto 2026
