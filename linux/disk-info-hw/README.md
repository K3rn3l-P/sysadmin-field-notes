# Comandi hardware e disco – Linux

## Scopo
Raccoglie comandi utili per ottenere informazioni su CPU, RAM, dischi, partizioni e bus hardware su Linux.

## Prerequisiti

- Sistema Linux con accesso `sudo`

## Info CPU

```bash
lscpu
```

## Info RAM

```bash
free -h
```

## Info dischi e partizioni

```bash
lsblk
fdisk -l
df -h
cat /proc/partitions
```

## Info bus/dispositivi PCI o USB

```bash
lspci
lsusb
```

## Montaggi filesystem

```bash
mount
cat /proc/mounts
```

## Identifica modelli disco

```bash
cat /sys/block/sd*/device/model
cat /sys/block/sd*/device/vendor
```

## Inventario esteso (dmidecode)

```bash
dmidecode -t system -t baseboard   # produttore/modello scheda madre
dmidecode -t bios                  # versione BIOS
dmidecode -t slot                  # slot PCIe liberi/occupati
```

## SMART (salute dischi)

```bash
smartctl -i /dev/sdX      # modello — spesso indica se è un disco SMR o CMR
smartctl -H /dev/sdX      # health overall PASSED/FAILED
smartctl -A /dev/sdX      # tutti gli attributi
smartctl -l error /dev/sdX     # error log
smartctl -l selftest /dev/sdX  # storico self-test
smartctl -t long /dev/sdX      # avvia uno self-test esteso in background (sola lettura, sicuro anche su disco in uso)
```

> Attenzione: attributi con lo stesso nome hanno significati leggermente
> diversi tra vendor — es. `188 Command_Timeout` su un disco Seagate SMR è
> indicativo di stress; `235 POR_Recovery_Count` (Samsung) e
> `174 Unexpect_Power_Loss_Ct` (Crucial) contano gli spegnimenti non puliti:
> se crescono nel tempo, il sistema sta subendo blocchi/riavvii forzati anche
> se non ci si è accorti di nulla.

---

## Consigli

- Usa `lsblk` per vedere rapidamente dischi, partizioni e punti di mount.
- Controlla `df -h` per ricevere la capacità usata su filesystem montati.
- Usa `lspci` e `lsusb` per trovare informazioni su schede grafiche, adattatori e controller.

---

**Ultimo aggiornamento:** Agosto 2026
