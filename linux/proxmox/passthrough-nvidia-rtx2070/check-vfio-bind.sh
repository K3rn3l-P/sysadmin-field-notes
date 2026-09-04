#!/bin/bash
# check-vfio-bind.sh
# Diagnostica NVIDIA Passthrough su Proxmox con suggerimenti rapidi per errori comuni
# Author: K3rn3l-P | https://github.com/K3rn3l-P

set -euo pipefail
IFS=$'\n\t'
ESC="\033"
RESET="${ESC}[0m"
GREEN="${ESC}[32m"
RED="${ESC}[31m"
YELLOW="${ESC}[33m"
CYAN="${ESC}[36m"
PURPLE="${ESC}[35m"
BOLD="${ESC}[1m"
checkmark="${GREEN}✔${RESET}"
crossmark="${RED}✗${RESET}"

msg_header(){ echo -e "${CYAN}${BOLD}\n$1${RESET}"; }
msg_ok(){ echo -e "${GREEN}$1 ${checkmark}${RESET}"; }
msg_warn(){ echo -e "${YELLOW}$1${RESET}"; }
msg_err(){ echo -e "${RED}$1 ${crossmark}${RESET}"; }

echo -e "${CYAN}${BOLD}\n== Verifica avanzata NVIDIA PCI Passthrough (auto) ==${RESET}\n"

FAIL=0
ERRORLOG=()
WARNLOG=()

check_command(){
    if ! command -v "$1" >/dev/null 2>&1; then
        msg_err "Comando '$1' non disponibile"
        echo -e "Installa il pacchetto corretto o esegui questa utility su Proxmox standard."
        exit 1
    fi
}

check_command lspci
check_command awk
check_command grep
check_command find
check_command readlink

module_exists(){
    local mod="$1"
    # Se il modulo è già caricato o builtin, considera disponibile.
    if module_loaded "$mod"; then
        return 0
    fi
    if command -v modinfo >/dev/null 2>&1; then
        modinfo "$mod" >/dev/null 2>&1 && return 0
    fi
    find "/lib/modules/$(uname -r)" -name "${mod}.ko*" 2>/dev/null | grep -q .
}

module_loaded(){
    local mod="$1"
    [[ -d "/sys/module/$mod" ]] && return 0
    grep -xq "$mod" /proc/modules
}

vfio_pci_bound(){
    [[ -d "/sys/bus/pci/drivers/vfio-pci" ]] || return 1
    find "/sys/bus/pci/drivers/vfio-pci/devices" -mindepth 1 -maxdepth 1 2>/dev/null | grep -q .
}

# --- STEP 0: Verifica moduli VFIO ---
msg_header "-- Verifica caricamento moduli kernel --"
if vfio_pci_bound; then
    msg_ok "Driver vfio-pci è attivo e lega la GPU"
    if module_loaded vfio; then
        msg_ok "Modulo vfio: caricato"
    else
        msg_warn "Modulo vfio: non caricato o integrato nel kernel"
    fi
    if module_loaded vfio_iommu_type1; then
        msg_ok "Modulo vfio_iommu_type1: caricato"
    else
        msg_warn "Modulo vfio_iommu_type1: non caricato o integrato nel kernel"
    fi
else
    for mod in vfio vfio_iommu_type1 vfio_pci; do
        if module_loaded "$mod"; then
            msg_ok "Modulo ${mod}: caricato"
        else
            msg_err "Modulo ${mod}: NON caricato"
            ERRORLOG+=("Modulo ${mod} non caricato.\n**Soluzione rapida:**\n- Aggiungi '${mod}' su una nuova riga in /etc/modules.\n- Esegui 'update-initramfs -u -k all' o 'proxmox-boot-tool refresh' e riavvia.\n- Se non usi vfio immediatamente, il passthrough non funzionerà correttamente.")
            FAIL=1
        fi
done
fi

if module_exists vfio_virqfd; then
    if module_loaded vfio_virqfd; then
        msg_ok "Modulo vfio_virqfd: caricato"
    else
        msg_warn "Modulo vfio_virqfd: disponibile ma non caricato (opzionale)"
        WARNLOG+=("Modulo vfio_virqfd disponibile ma non caricato.\n**Come abilitarlo:**\n- Aggiungi 'vfio_virqfd' in /etc/modules.\n- Esegui 'update-initramfs -u -k all' o 'proxmox-boot-tool refresh'.\n- Riavvia l'host.\n- Se il modulo non viene trovato, installa i pacchetti pve-headers per il kernel corrente.\nSe non ti serve il reset avanzato VFIO, puoi ignorare questo avviso.")
    fi
else
    msg_warn "Modulo vfio_virqfd: non disponibile nel kernel corrente (opzionale)"
    WARNLOG+=("Modulo vfio_virqfd non è disponibile nel kernel corrente.\n**Nota importante:** Questo non significa che la tua configurazione in /etc/modules sia sbagliata. Significa che il pacchetto kernel attuale non fornisce il modulo.\n- Controlla con 'modinfo vfio_virqfd' o 'find /lib/modules/$(uname -r) -name \"vfio_virqfd*\"'.\n- Se non è presente, installa i pacchetti pve-headers per il kernel corrente.\n- Se il modulo non serve per il tuo setup, puoi ignorare questo avviso.")
fi

echo ""

# --- STEP 1: Trova tutte le funzioni NVIDIA ---
mapfile -t DEVS < <(lspci -nn | grep -i nvidia || true)
if [[ ${#DEVS[@]} -eq 0 ]]; then
    msg_warn "Nessuna funzione NVIDIA trovata con 'grep -i nvidia'. Provo il fallback sul vendor ID NVIDIA..."
    mapfile -t DEVS < <(lspci -nn | grep -i '10de:' || true)
fi
if [[ ${#DEVS[@]} -eq 0 ]]; then
    msg_err "Nessuna funzione NVIDIA rilevata su questo host!"
    echo -e "Verifica con: ${BOLD}lspci -nn | grep -i nvidia${RESET}"
    echo -e "Se non trovi linee NVIDIA, la scheda potrebbe non essere installata, potrebbe essere disabilitata in BIOS o il comando potrebbe essere eseguito su un host senza GPU NVIDIA."
    exit 1
fi

NUM=0
for LINE in "${DEVS[@]}"; do
    PCIADDR=$(printf '%s' "$LINE" | awk '{print $1}')
    DESC=$(printf '%s' "$LINE" | cut -d' ' -f2-)
    DEVS[NUM]="$PCIADDR|$DESC"
    NUM=$((NUM + 1))
done

SLOTS=($(printf "%s\n" "${DEVS[@]}" | cut -d'|' -f1 | cut -d. -f1 | uniq))
for SLOT in "${SLOTS[@]}"; do
    echo -e "${PURPLE}-------------------------------------------${RESET}"
    echo -e "${BOLD}Slot PCIe: ${SLOT}.x - Device(s) NVIDIA${RESET}"
    FOUND_FUNCS=()
    ERR_DEV=0

    for DEV in "${DEVS[@]}"; do
        PCIADDR=$(printf '%s' "$DEV" | cut -d'|' -f1)
        if [[ "$PCIADDR" != ${SLOT}.* ]]; then
            continue
        fi
        DESC=$(printf '%s' "$DEV" | cut -d'|' -f2-)
        printf "${CYAN}%-40s${RESET} (${YELLOW}%s${RESET}): " "$DESC" "$PCIADDR"
        LSPCI_OUT=$(lspci -nnk -s "$PCIADDR" 2>/dev/null || true)
        DRIVER=$(printf '%s' "$LSPCI_OUT" | awk -F': ' '/Kernel driver in use:/ {print $2; exit}')
        MODS=$(printf '%s' "$LSPCI_OUT" | awk -F': ' '/Kernel modules:/ {print $2; exit}')
        if [[ "$DRIVER" == "vfio-pci" ]]; then
            msg_ok "vfio-pci"
        elif [[ -z "$DRIVER" ]]; then
            msg_warn "nessun driver in uso"
            ERRORLOG+=("$PCIADDR ($DESC) non ha un driver in uso.\n**Soluzione:**\n- Controlla /etc/modprobe.d/vfio.conf e blacklist-nvidia.conf.\n- Riavvia dopo aver aggiornato i file di configurazione.\n- Se il driver host è ancora presente, il dispositivo non sarà pronto per la VM.")
            ERR_DEV=1
        else
            msg_err "driver in uso: ${DRIVER}"
            ERRORLOG+=("$PCIADDR ($DESC) è gestito dal driver host ${DRIVER} anziché vfio-pci.\n**Soluzione:**\n- Blacklista ${DRIVER} in /etc/modprobe.d/blacklist-nvidia.conf.\n- Controlla che /etc/modprobe.d/vfio.conf includa gli IDs PCI corretti.\n- Ricostruisci initramfs e riavvia.")
            ERR_DEV=1
        fi
        FOUND_FUNCS+=("$PCIADDR")
    done

    msg_header "-- Check gruppo IOMMU per slot ${SLOT} --"
    GROUPS=()
    for F in "${FOUND_FUNCS[@]}"; do
        if [[ -e "/sys/bus/pci/devices/0000:$F/iommu_group" ]]; then
            GROUPS+=("$(readlink "/sys/bus/pci/devices/0000:$F/iommu_group" | awk -F'/' '{print $NF}')")
        else
            GROUPS+=("none")
        fi
    done
    GROUPS_UNIQ=($(printf "%s\n" "${GROUPS[@]}" | sort -u))
    if [[ ${#GROUPS_UNIQ[@]} -eq 1 && "${GROUPS_UNIQ[0]}" != "none" ]]; then
        GRP="${GROUPS_UNIQ[0]}"
        MEMBERS=$(find "/sys/kernel/iommu_groups/$GRP/devices" -type l | sort || true)
        DEVICE_COUNT=$(printf "%s\n" "${MEMBERS}" | wc -l)
        if [[ $DEVICE_COUNT -eq ${#FOUND_FUNCS[@]} ]]; then
            msg_ok "Gruppo IOMMU ${GRP} OK: nessun device estraneo"
        else
            msg_warn "Gruppo IOMMU ${GRP} contiene altri device"
            echo "${MEMBERS}" | sed 's|.*/||'
            ERRORLOG+=("Il gruppo IOMMU ${GRP} contiene anche altri device oltre la GPU.\n**Soluzione:**\n- Valuta pcie_acs_override=downstream,multifunction.\n- Se possibile, sposta la GPU su uno slot con gruppo isolato.\n- Non inoltrare device aggiuntivi alla VM senza verificarne l'impatto.")
            ERR_DEV=1
        fi
    else
        msg_err "Funzioni NVIDIA in gruppi IOMMU diversi o non rilevati"
        ERRORLOG+=("Le funzioni NVIDIA dello stesso slot non sono tutte nello stesso gruppo IOMMU.\n**Soluzione:**\n- Controlla il BIOS e la compatibilità ACS/IOMMU.\n- Considera di cambiare slot PCIe.\n- Se usi mobo desktop, prova pcie_acs_override con cautela.")
        ERR_DEV=1
    fi

    if [[ "$SLOT" == "${SLOTS[0]}" ]]; then
        msg_header "-- Kernel cmdline (parametri boot critici) --"
        CMDLINE=$(cat /proc/cmdline)
        if grep -q 'intel_iommu=on' <<< "$CMDLINE"; then msg_ok "intel_iommu=on presente"; else msg_err "intel_iommu=on mancante"; ERRORLOG+=("Parametro kernel 'intel_iommu=on' assente.\n**Soluzione:**\n- Aggiungilo a /etc/kernel/cmdline o /etc/default/grub.\n- Esegui proxmox-boot-tool refresh o update-grub, quindi riavvia."); fi
        if grep -q 'iommu=pt' <<< "$CMDLINE"; then msg_ok "iommu=pt presente"; else msg_err "iommu=pt mancante"; ERRORLOG+=("Parametro kernel 'iommu=pt' assente.\n**Soluzione:**\n- Aggiungilo ai parametri di boot e riavvia."); fi
        if grep -q 'video=efifb:off' <<< "$CMDLINE"; then msg_ok "video=efifb:off presente"; else msg_warn "video=efifb:off assente (consigliato)"; fi
        if grep -q 'pcie_acs_override=downstream,multifunction' <<< "$CMDLINE"; then msg_ok "pcie_acs_override presente"; else msg_warn "pcie_acs_override assente (solo se serve)"; fi
        echo ""
    fi

    msg_header "-- Verifica blacklist NVIDIA/nouveau e softdep --"
    MISSING_BLACKLIST=()
    for mod in nvidia nvidia_drm nvidia_uvm nvidia_modeset nouveau; do
        if ! grep -qrE "^[[:space:]]*blacklist[[:space:]]+${mod}([[:space:]]|$)" /etc/modprobe.d/ 2>/dev/null; then
            MISSING_BLACKLIST+=("${mod}")
        fi
    done
    if [[ ${#MISSING_BLACKLIST[@]} -eq 0 ]]; then
        msg_ok "Blacklist driver NVIDIA/nouveau OK"
    else
        msg_err "Mancano blacklist per: ${MISSING_BLACKLIST[*]}"
        ERRORLOG+=("Blacklist mancanti per: ${MISSING_BLACKLIST[*]}.\n**Soluzione:**\n- Crea/modifica /etc/modprobe.d/blacklist-nvidia.conf.\n- Aggiungi: blacklist <modulo> per ogni voce.\n- Ricostruisci initramfs e riavvia.")
        FAIL=1
    fi

    MISSING_SOFTDEP=()
    for dep in xhci_hcd xhci_pci i2c_nvidia_gpu; do
        if ! grep -qrE "^[[:space:]]*softdep[[:space:]]+${dep}[[:space:]]+pre:[[:space:]]*vfio-pci" /etc/modprobe.d/ 2>/dev/null; then
            MISSING_SOFTDEP+=("${dep}")
        fi
    done
    if [[ ${#MISSING_SOFTDEP[@]} -eq 0 ]]; then
        msg_ok "Softdep vfio-pci OK"
    else
        msg_warn "Mancano softdep per: ${MISSING_SOFTDEP[*]}"
        ERRORLOG+=("Softdep mancanti per: ${MISSING_SOFTDEP[*]}.\n**Soluzione:**\n- Aggiungi in /etc/modprobe.d/vfio.conf le righe: softdep <modulo> pre: vfio-pci.\n- Questo aiuta a caricare vfio-pci prima dei driver host.")
    fi

    if [[ $ERR_DEV -eq 0 ]]; then
        msg_ok "SLOT ${SLOT} OK: PCI passthrough NVIDIA pronto"
    else
        msg_err "SLOT ${SLOT} con problemi: vedi suggerimenti"
    fi
done

if [[ ${#ERRORLOG[@]} -gt 0 ]]; then
    echo -e "\n${BOLD}${RED}=== ERRORI & SUGGERIMENTI ===${RESET}"
    for e in "${ERRORLOG[@]}"; do
        echo -e "${YELLOW}----------------------------------------------${RESET}"
        echo -e "$e"
    done
    echo -e "${BOLD}${YELLOW}Consulta anche la sezione troubleshooting/FAQ nella guida per esempi dettagliati.${RESET}"
fi
if [[ ${#WARNLOG[@]} -gt 0 ]]; then
    echo -e "\n${BOLD}${YELLOW}=== AVVISI OPZIONALI ===${RESET}"
    for e in "${WARNLOG[@]}"; do
        echo -e "${YELLOW}----------------------------------------------${RESET}"
        echo -e "$e"
    done
fi

echo -e "${CYAN}-- Script di controllo by K3rn3l-P | https://github.com/K3rn3l-P/utility-scripts --${RESET}"
