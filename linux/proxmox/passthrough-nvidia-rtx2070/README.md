# Proxmox NVIDIA RTX 2070 GPU Passthrough – Guida Completa (Testata)

> **Testata su Proxmox VE 6/7/8/9, kernel >=6.8, host UEFI, NVIDIA RTX 2070**  
> Valida per tutte le NVIDIA serie RTX/Ampere/Turing (vedi sez. “IDs PCI”).

---

## Prerequisiti

- Proxmox VE installato e aggiornato (testato 6/7/8/9)
- Accesso root via SSH/shell
- GPU dedicata (NON quella usata dal boot/console host!)
- Mainboard & CPU *con supporto VT-d/IOMMU* (abilitalo nel BIOS!)
- **Disabilita CSM/Legacy Boot** in UEFI/BIOS se presente (CRITICO per molte GPU NVIDIA)
- Backup dati delle VM

---

## 📌 Sezione CSM/Legacy su HP Z420 (dettagliata)

**Per disabilitare il CSM (Compatibility Support Module) su HP Z420:**
- Riavvia il server e premi ripetutamente **F10** all’avvio per accedere al BIOS.
- Vai nel menu:  
  **Storage → Boot Order**
- Cerca e imposta:  
    - **Legacy Support** (o “CSM”): su **Disabled**
    - (Facoltativo) Assicurati che “UEFI Boot Order” sia in cima/Enabled
- Dopo aver disabilitato CSM, il sistema userà solo UEFI. 
    - *Nota*: Secure Boot potrebbe attivarsi automaticamente; puoi lasciarlo attivo o metterlo su Disabled secondo necessità, ma il CSM/legacy deve restare disabilitato.
- **Salva** le modifiche (F10 o ESC → Save) e riavvia.

> _Se Proxmox non parte più:_ Controlla che il disco d’avvio sia compatibile UEFI (conversione da legacy a UEFI può richiedere fix sulle partizioni; vedi la wiki ufficiale Proxmox).

---

## 📌 Console locale su host con una sola GPU passthrough (HP Z420)

**Problema:** se l'host ha una sola GPU e va tutta in passthrough (`disable_vga=1` in
`vfio.conf`), l'host perde la console video locale. Il framebuffer si accende al boot, ma non
appena `vfio-pci` rivendica la scheda (in genere entro i primi ~10 secondi) il framebuffer viene
distrutto e lo schermo va nero. Nessun errore visibile, nessun login — se qualcosa va storto e la
rete non risponde, l'host è irraggiungibile anche fisicamente.

**Soluzione testata:** una seconda GPU economica, dedicata alla sola console dell'host, lasciata
fuori da `vfio.conf`. Su HP Z420 con RTX 2070 in passthrough + GeForce GT 620 come console:

- **Slot:** GT 620 nello slot 5 (bus `0000:04:00`), RTX 2070 lasciata nello slot 2 (bus
  `0000:05:00`). Mappa completa slot fisico → bus PCI sulla Z420:

  | Slot HP | Bus | Tipo | Note |
  |---|---|---|---|
  | 1 (alto) | 07 | PCIe Gen2 x4(x1) | connettore chiuso, una GPU non entra |
  | 2 | 05 | PCIe Gen3 x16 | slot della RTX 2070 |
  | 3 | 06 | PCIe Gen2 x8(x4) open-ended | utilizzabile ma scomodo |
  | 4 | 03 | PCIe Gen3 x8 open-ended | utilizzabile ma scomodo |
  | 5 | 04 | PCIe Gen3 x16 | slot della GT 620 |
  | 6 | 09 | PCI 32bit/33MHz | legacy |

  La RTX 2070 è rimasta nello slot 2 invece di essere spostata: nello slot 5 le ventole
  sarebbero quasi a contatto col case, con temperature più alte sotto carico continuo.

- **BIOS — designare la GPU di console come primaria:** `F10 → Advanced → VGA Configuration`.
  Il menu elenca le GPU per slot; si seleziona quella desiderata come primaria con **F5**, poi
  **F10** per confermare e *Save & Exit*. **Questa voce compare solo quando ci sono due schede
  video installate** — è per questo che è facile non trovarla mai. Da non confondere con:
  - `Advanced → Bus Options`: nonostante la Maintenance and Service Guide HP lo lasci intendere
    (*"designates one card as primary graphics"*), su Z420/Z620/Z820 contiene solo Numa, MMIO
    Assignment, PCI SERR#, VGA Palette Snooping, PCI Latency Timer — nulla che riguardi quale
    scheda fa da boot device
  - `Advanced → Slot Settings`: abilita/disabilita l'intero slot PCIe, non seleziona la primaria

- **Verifica che la GPU giusta sia diventata la scheda di boot:**
  ```bash
  cat /sys/bus/pci/devices/0000:04:00.0/boot_vga   # GT 620  → atteso 1
  cat /sys/bus/pci/devices/0000:05:00.0/boot_vga   # RTX 2070 → atteso 0
  cat /sys/class/vtconsole/*/name                   # atteso: "(M) frame buffer device"
  ```
  Prima della correzione, in `dmesg` compariva `Console: switching to colour dummy device 80x25`
  pochi secondi dopo il boot (`vfio-pci` che si prendeva la scheda sbagliata). Dopo la
  correzione quella riga sparisce e la console framebuffer resta quella attiva.

- **Effetto collaterale utile:** con la seconda GPU come primaria, `video=efifb:off,vesafb:off`
  (sezione "Kernel cmdline e framebuffer" più sopra) diventa superfluo — non c'è più un
  framebuffer da nascondere al passthrough, perché quello attivo non è sulla GPU passata alla VM.
  Consigliato rimuoverlo comunque dal cmdline: è un parametro pensato per spegnere una console
  framebuffer, e non ha motivo di restare quando quella console è diventata la rete di sicurezza
  dell'host.

- **Verifica passthrough non compromesso:** cambiare la scheda di boot non ha alterato il gruppo
  IOMMU della GPU in passthrough (verificato: restava lo stesso prima e dopo). Da controllare
  comunque caso per caso con `find /sys/kernel/iommu_groups/ -type l | sort` prima e dopo il
  cambio, e riavviando la VM con la GPU passata per confermare che riparta.

---

## 1. Abilita Virtualizzazione nel BIOS

- Riavvia e accedi al BIOS/UEFI (F10 su HP)
- Abilita:
    - **Intel VT-x** (CPU Virtualization)
    - **Intel VT-d** (PCIe/IOMMU pass-through)
- **Disabilita CSM/Compatibility Support Module** come sopra
- Salva e riavvia

---

## 2. Trova la tua scheda NVIDIA e i suoi IDs

```bash
lspci -nn | grep -i nvidia
# O per vedere anche Audio/USB della GPU:
lspci -nn | egrep -i 'vga|audio|usb'
```

Esempio output:
```
05:00.0 VGA compatible controller [0300]: NVIDIA RTX 2070 [10de:1f02]
05:00.1 Audio device [0403]: NVIDIA HD Audio [10de:10f9]
05:00.2 USB controller [0c03]: NVIDIA USB 3.1 Host Controller [10de:1ada]
05:00.3 Serial bus controller [0c80]: NVIDIA USB Type-C UCSI [10de:1adb]
```
Annota tutti gli IDs (qui: **10de:1f02, 10de:10f9, 10de:1ada, 10de:1adb**).

---

## 3. Verifica come boota il sistema

```bash
[ -d /sys/firmware/efi ] && echo "UEFI" || echo "Legacy BIOS"
```
- Se vedi **UEFI** → prosegui con sezione "UEFI"
- Se vedi **Legacy BIOS** → vedi sezione "GRUB"/legacy più sotto

---

## 📌 Kernel cmdline e “framebuffer” (user friendly)

Dopo aver stabilito che UEFI è attivo e CSM disabilitato, **puoi migliorare il passthrough pulendo i framebuffer di sistema** che impediscono il corretto detach della GPU.

**Cosa sono?**  
- “framebuffer” (es. efifb, vesafb) sono driver che permettono al kernel di usare la scheda video per la console grafica.  
- Se vuoi usare la GPU esclusivamente per le VM, puoi disabilitarli.

**Come fare su Proxmox UEFI:**
1. Modifica la cmdline kernel:
   ```bash
   nano /etc/kernel/cmdline
   ```
   Appendi alla riga esistente:
   ```
   video=efifb:off,vesafb:off
   ```
   Risultato finale esempio:
   ```
   quiet intel_iommu=on iommu=pt video=efifb:off,vesafb:off
   ```
2. Applica:
   ```bash
   proxmox-boot-tool refresh
   reboot
   ```
3. (Se usi legacy GRUB: modifica la riga `GRUB_CMDLINE_LINUX_DEFAULT` e poi `update-grub` + reboot)

**Cosa cambia?**  
- Non vedrai più la console grafica sull’host fisico (usa SSH o la GUI web di Proxmox!)
- Migliora la probabilità che la GPU sia subito “libera” per la guest, senza errori di device busy/reset.

---

### **A) UEFI:**  
Segui la procedura sopra per `/etc/kernel/cmdline` + refresh/reboot.

### **B) Legacy BIOS (GRUB):**  
Modifica `/etc/default/grub` così:
```
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt video=efifb:off,vesafb:off"
```
Poi:
```bash
update-grub
reboot
```
Se IOMMU groups non sono separati puoi anche aggiungere `pcie_acs_override=downstream,multifunction`.

---

## 4. Carica i moduli VFIO e lega la GPU a vfio-pci

1. **Assicurati che i moduli vengano caricati all’avvio**  
   (aggiungi in fondo a `/etc/modules` se non già presenti):
   ```
   vfio
   vfio_iommu_type1
   vfio_pci
   # vfio_virqfd (opzionale, se supportato dal kernel)
   ```
   Nota: `vfio_virqfd` è opzionale e il suo avviso non indica un errore nella tua configurazione. Può essere presente in `/etc/modules` ma non disponibile se il pacchetto kernel corrente non include questo modulo. Aggiungilo solo se il modulo esiste fisicamente in `/lib/modules/$(uname -r)` o risulta disponibile con `modinfo vfio_virqfd`.
2. **Crea/modifica `/etc/modprobe.d/vfio.conf`:**
   ```
   options vfio-pci ids=10de:1f02,10de:10f9,10de:1ada,10de:1adb disable_vga=1
   softdep xhci_hcd pre: vfio-pci
   softdep xhci_pci pre: vfio-pci
   softdep i2c_nvidia_gpu pre: vfio-pci
   ```

3. **Blacklist driver host NVIDIA**
   File `/etc/modprobe.d/blacklist-nvidia.conf`:
   ```
   blacklist nvidia
   blacklist nouveau
   blacklist nvidia_drm
   blacklist nvidia_uvm
   blacklist nvidia_modeset
   ```

4. **(Opzionale) Forza USB NVIDIA su vfio-pci**  
   Solo se vedi che 05:00.2/.3 non sono gestite da vfio-pci dopo reboot:
   ```
   nano /etc/modprobe.d/blacklist-nvidiausb.conf
   ```
   ```
   blacklist xhci_hcd
   blacklist xhci_pci
   blacklist i2c_nvidia_gpu
   ```
   ⚠️ _Può disattivare anche tutte le USB 3.0/3.1 dell’host! Usalo solo se strettamente necessario._

---

## 5. Aggiorna initramfs e reboot

```bash
update-initramfs -u -k all
reboot
```

---

## 📌 Check IOMMU Group separato

- Esegui:
  ```bash
  find /sys/kernel/iommu_groups/ -type l | sort
  ```
- Cerca che tutti e 4 i device 05:00.x siano **nello stesso gruppo** (OK) **e che non ci siano altri device “estranei” nello stesso gruppo!**
    - Se sì → puoi passare l’intero gruppo/slot PCI senza problemi.
    - Se la GPU condivide gruppo con altri device non desiderati:
        - Aggiungi `pcie_acs_override=downstream,multifunction` nella cmdline kernel e ripeti il check.  
        - Attenzione: questa opzione può abbassare la sicurezza DMA dell’host (solo su mobo desktop e VM “trusted”).

---

## 6. Verifica che i binding vfio siano attivi

Controlla che tutte le funzioni della GPU siano "in use: vfio-pci":

```bash
lspci -nnk -s 05:00.0
lspci -nnk -s 05:00.1
lspci -nnk -s 05:00.2
lspci -nnk -s 05:00.3
```
Devono mostrare in tutti i casi:  
**Kernel driver in use: vfio-pci**

---

## 7. Assegna le funzioni PCI alla VM

**Via GUI:**  
- VM → Hardware → Add → PCI Device
    - Includi almeno 05:00.0 e 05:00.1 (aggiungi anche .2 e .3 per passthrough totale)
    - Spunta “All Functions” se esiste, o aggiungi manualmente tutte le funzioni
- VM Options:  
    - Machine: q35
    - BIOS: OVMF (UEFI)
    - PCI Express: ON

**Via CLI:**  
Configura `/etc/pve/qemu-server/<VMID>.conf`:
```
machine: q35
hostpci0: 0000:05:00,pcie=1,multifunction=on
```

---

## 8. Guest OS e Driver

### Windows 10/11
1. Collega un monitor alla GPU  
2. Installa driver NVIDIA dal sito ufficiale  
3. Controlla Device Manager  
4. Se “Code 43”, aggiungi nel config VM:
   ```
   args: -cpu 'host,kvm=on'
   ```
   o
   ```
   hostpci0: ...,hidden=1
   ```
   *(Proxmox 7+ spesso non serve; legacy o GeForce recenti → vedi troubleshooting)*  

### Linux (Ubuntu/Debian)
1. Collega monitor  
2. Installa driver NVIDIA proprietari  
3. Controlla output con
   ```bash
   nvidia-smi
   ```

---

## 9. Troubleshooting / Fix Rapidi

| Problema                              | Possibile causa             | Fix                                                        |
|----------------------------------------|----------------------------|------------------------------------------------------------|
| VM non si avvia                       | Driver host in uso         | Verifica “in use: vfio-pci”, rimuovi/blacklista nvidia     |
| Schermo nero VM, nessun output        | No OVMF/q35, no monitor    | Usa OVMF/q35, collega monitor fisico                       |
| GPU non compare in guest               | IDs sbagliati, PCI/slot errato| Rivedi ids= in vfio.conf e gruppo IOMMU                      |
| Audio HDMI non funziona                | Funzione 05:00.1 non passthru | Aggiungi anche 05:00.1 alla VM                           |
| USB non bindata a vfio-pci             | xhci_hcd/i2c_nvidia_gpu host | Usa softdep o blacklist mirata                             |
| Host perde USB 3                       | Blacklist xhci globale     | Rimuovi blacklist, usa solo softdep sopra                   |
| VM funziona una volta poi fail         | Bug reset GPU NV/AMD       | Ferma/avvia VM, vedi vendor-reset module (se ricorrente)    |
| VM fail con IOMMU                      | Bios o kernel flag mancanti| Verifica VT-d/CSM, ricontrolla kernel cmdline              |
| Error 43 (NVIDIA Windows)              | Patch anti-cheat mancante  | Usa args kvm=on, hidden=1, vedi opzioni avanzate            |
| Device condivide IOMMU group           | Hardware, no ACS           | Usa pcie_acs_override (solo se necessario)                  |
| Problemi boot/rom GPU                  | GPU recente o custom ROM   | Prova romfile=..., rombar=0 in config VM                    |
| NOvnc non mostra nulla                 | GPU in passthrough         | Serve monitor fisico                                        |

---

## 10. Checklist & Verifica

- [ ] BIOS: VT-x (CPU Virtualization) e VT-d abilitati + CSM/Legacy **DISABILITATO**
- [ ] Kernel flags: `intel_iommu=on iommu=pt` (e, se serve, pcie_acs_override/video=efifb:off) in `/proc/cmdline`
- [ ] /etc/modules contiene moduli VFIO (vedi sopra)
- [ ] File `/etc/modprobe.d/vfio.conf` con tutti i device IDs corretti
- [ ] Driver NVIDIA/Nouveau host blacklistati
- [ ] La GPU e le sue funzioni sono bindate a vfio-pci su `lspci -nnk`
- [ ] Gruppo IOMMU separato oppure override se serve
- [ ] VM configurata q35 + OVMF + tutte le funzioni necessarie in PCI passthrough
- [ ] Driver guest installati e accelerazione OK
- [ ] Guest NVIDIA Windows: nessun Code 43 o errori noti (patch se serve)

---

## 11. Utility: Script di Verifica e Diagnostica Automatica NVIDIA Passthrough

Questa utility bash verifica **tutte le GPU NVIDIA presenti**, controlla che ogni funzione PCIe sia “bindata” a vfio-pci, **autodetecta slot e gruppi IOMMU**, suggerisce soluzioni e mostra lo stato dei parametri fondamentali della kernel cmdline, evidenziando errori secondo la guida.

Vedi file [`check-vfio-bind.sh`](./check-vfio-bind.sh) in questa cartella.

### 📦 Uso

```bash
# Rendi eseguibile lo script (una tantum)
chmod +x check-vfio-bind.sh

# Esegui la diagnostica
./check-vfio-bind.sh
```


**✅ Questo script rileva tutto in automatico (PCI slot, gruppi, funzioni NVIDIA, parametri kernel), segnala in colore/emoji problemi o warning e suggerisce le azioni dalla tua guida – pronto per troubleshooting anche su setup multi-GPU!**

---

Puoi includere questo snippet direttamente nella guida, sostituendo la vecchia sezione, e istruire così:

- **Salva come `check-vfio-bind.sh`**  
- **Rendi eseguibile:**  
  `chmod +x check-vfio-bind.sh`  
- **Esegui:**  
  `./check-vfio-bind.sh`

---

## 12. Opzioni Avanzate & Trucchi Pro

- **`video=efifb:off,vesafb:off`** – "Libera" la GPU dai framebuffer host.
- **`pcie_acs_override=downstream,multifunction`** – Per segmentare gruppi IOMMU "misti": SOLO se gruppo non isolato!
- **Opzione multifunzione (multifunction=on):**
  ```
  hostpci0: 0000:05:00,pcie=1,multifunction=on
  ```
  Utile per GPU con molte funzioni PCIe (audio, USB ecc).
- **ROM bar/ROM file:**
  ```
  hostpci0: 0000:05:00,pcie=1,rombar=0
  hostpci0: ... ,romfile=/path/to/dump.rom
  ```
- **Error 43 Patch:**
  ```
  args: -cpu 'host,kvm=on'
  ```
  o
  ```
  hostpci0: ...,hidden=1
  ```
  (Se Code 43 su GeForce in Windows guest)

- **vendor-reset (Se VM parte solo una volta):**
  - [vendor-reset kernel module](https://github.com/gnif/vendor-reset)

- **Installazione headers kernel custom:**
  ```
  apt install pve-headers-$(uname -r)
  ```

---

## 13. Fonti & Riferimenti

- [Proxmox PCI Passthrough Wiki](https://pve.proxmox.com/wiki/PCI_Passthrough)
- [ArchWiki PCI/VFIO](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF)
- [Discussione Reddit originale](https://www.reddit.com/r/Proxmox/comments)
- [NVIDIA Docs](https://docs.nvidia.com/)
- [K3rn3l-P/utility-scripts](https://github.com/K3rn3l-P/utility-scripts)

---

> **Guida aggiornata e curata da [K3rn3l-P](https://github.com/K3rn3l-P) – se hai dubbi o vuoi integrare, puoi aprire issue/suggestioni sul repo!**