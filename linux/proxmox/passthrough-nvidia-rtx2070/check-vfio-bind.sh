#!/bin/bash
# check-vfio-bind.sh
# NVIDIA passthrough diagnostics on Proxmox, with quick hints for common errors
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

echo -e "${CYAN}${BOLD}\n== Advanced NVIDIA PCI passthrough check (automatic) ==${RESET}\n"

FAIL=0
ERRORLOG=()
WARNLOG=()

check_command(){
    if ! command -v "$1" >/dev/null 2>&1; then
        msg_err "Command '$1' not available"
        echo -e "Install the right package, or run this utility on a standard Proxmox host."
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
    # If the module is already loaded or built in, treat it as available.
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

# --- STEP 0: check the VFIO modules ---
msg_header "-- Checking kernel module loading --"
if vfio_pci_bound; then
    msg_ok "The vfio-pci driver is active and bound to the GPU"
    if module_loaded vfio; then
        msg_ok "Modulo vfio: caricato"
    else
        msg_warn "vfio module: not loaded, or built into the kernel"
    fi
    if module_loaded vfio_iommu_type1; then
        msg_ok "Modulo vfio_iommu_type1: caricato"
    else
        msg_warn "vfio_iommu_type1 module: not loaded, or built into the kernel"
    fi
else
    for mod in vfio vfio_iommu_type1 vfio_pci; do
        if module_loaded "$mod"; then
            msg_ok "Modulo ${mod}: caricato"
        else
            msg_err "Module ${mod}: NOT loaded"
            ERRORLOG+=("Module ${mod} is not loaded.\n**Quick fix:**\n- Add '${mod}' on a new line in /etc/modules.\n- Run 'update-initramfs -u -k all' or 'proxmox-boot-tool refresh', then reboot.\n- Without vfio loaded, passthrough will not work correctly.")
            FAIL=1
        fi
done
fi

if module_exists vfio_virqfd; then
    if module_loaded vfio_virqfd; then
        msg_ok "Modulo vfio_virqfd: caricato"
    else
        msg_warn "vfio_virqfd module: available but not loaded (optional)"
        WARNLOG+=("vfio_virqfd is available but not loaded.\n**How to enable it:**\n- Add 'vfio_virqfd' to /etc/modules.\n- Run 'update-initramfs -u -k all' or 'proxmox-boot-tool refresh'.\n- Reboot the host.\n- If the module isn't found, install the pve-headers packages for the current kernel.\nIf you don't need advanced VFIO reset, you can ignore this warning.")
    fi
else
    msg_warn "vfio_virqfd module: not available in the current kernel (optional)"
    WARNLOG+=("vfio_virqfd is not available in the current kernel.\n**Important note:** this does not mean your /etc/modules configuration is wrong. It means the current kernel package doesn't ship the module.\n- Check with 'modinfo vfio_virqfd' or 'find /lib/modules/$(uname -r) -name \"vfio_virqfd*\"'.\n- If it isn't there, install the pve-headers packages for the current kernel.\n- If your setup doesn't need the module, you can ignore this warning.")
fi

echo ""

# --- STEP 1: Trova tutte le funzioni NVIDIA ---
mapfile -t DEVS < <(lspci -nn | grep -i nvidia || true)
if [[ ${#DEVS[@]} -eq 0 ]]; then
    msg_warn "No NVIDIA functions found with 'grep -i nvidia'. Falling back to the NVIDIA vendor ID..."
    mapfile -t DEVS < <(lspci -nn | grep -i '10de:' || true)
fi
if [[ ${#DEVS[@]} -eq 0 ]]; then
    msg_err "No NVIDIA functions detected on this host!"
    echo -e "Check with: ${BOLD}lspci -nn | grep -i nvidia${RESET}"
    echo -e "If no NVIDIA lines appear, the card may not be installed, may be disabled in the BIOS, or this may simply be a host without an NVIDIA GPU."
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
            msg_warn "no driver in use"
            ERRORLOG+=("$PCIADDR ($DESC) has no driver in use.\n**Fix:**\n- Check /etc/modprobe.d/vfio.conf and blacklist-nvidia.conf.\n- Reboot after updating the configuration files.\n- While the host driver is still present, the device won't be ready for the VM.")
            ERR_DEV=1
        else
            msg_err "driver in uso: ${DRIVER}"
            ERRORLOG+=("$PCIADDR ($DESC) is handled by the host driver ${DRIVER} instead of vfio-pci.\n**Fix:**\n- Blacklist ${DRIVER} in /etc/modprobe.d/blacklist-nvidia.conf.\n- Check that /etc/modprobe.d/vfio.conf lists the right PCI IDs.\n- Rebuild initramfs and reboot.")
            ERR_DEV=1
        fi
        FOUND_FUNCS+=("$PCIADDR")
    done

    msg_header "-- IOMMU group check for slot ${SLOT} --"
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
            msg_ok "IOMMU group ${GRP} OK: no unrelated devices"
        else
            msg_warn "IOMMU group ${GRP} contains other devices"
            echo "${MEMBERS}" | sed 's|.*/||'
            ERRORLOG+=("IOMMU group ${GRP} contains devices other than the GPU.\n**Fix:**\n- Consider pcie_acs_override=downstream,multifunction.\n- If possible, move the GPU to a slot with an isolated group.\n- Don't pass extra devices through to the VM without checking the impact.")
            ERR_DEV=1
        fi
    else
        msg_err "NVIDIA functions in different IOMMU groups, or not detected"
        ERRORLOG+=("The NVIDIA functions on the same slot are not all in the same IOMMU group.\n**Fix:**\n- Check the BIOS and ACS/IOMMU compatibility.\n- Consider moving to a different PCIe slot.\n- On a desktop board, try pcie_acs_override carefully.")
        ERR_DEV=1
    fi

    if [[ "$SLOT" == "${SLOTS[0]}" ]]; then
        msg_header "-- Kernel cmdline (parametri boot critici) --"
        CMDLINE=$(cat /proc/cmdline)
        if grep -q 'intel_iommu=on' <<< "$CMDLINE"; then msg_ok "intel_iommu=on present"; else msg_err "intel_iommu=on missing"; ERRORLOG+=("Kernel parameter 'intel_iommu=on' is missing.\n**Fix:**\n- Add it to /etc/kernel/cmdline or /etc/default/grub.\n- Run proxmox-boot-tool refresh or update-grub, then reboot."); fi
        if grep -q 'iommu=pt' <<< "$CMDLINE"; then msg_ok "iommu=pt present"; else msg_err "iommu=pt missing"; ERRORLOG+=("Kernel parameter 'iommu=pt' is missing.\n**Fix:**\n- Add it to the boot parameters and reboot."); fi
        if grep -q 'video=efifb:off' <<< "$CMDLINE"; then msg_ok "video=efifb:off present"; else msg_warn "video=efifb:off absent (recommended)"; fi
        if grep -q 'pcie_acs_override=downstream,multifunction' <<< "$CMDLINE"; then msg_ok "pcie_acs_override present"; else msg_warn "pcie_acs_override absent (only if needed)"; fi
        echo ""
    fi

    msg_header "-- Checking NVIDIA/nouveau blacklist and softdep --"
    MISSING_BLACKLIST=()
    for mod in nvidia nvidia_drm nvidia_uvm nvidia_modeset nouveau; do
        if ! grep -qrE "^[[:space:]]*blacklist[[:space:]]+${mod}([[:space:]]|$)" /etc/modprobe.d/ 2>/dev/null; then
            MISSING_BLACKLIST+=("${mod}")
        fi
    done
    if [[ ${#MISSING_BLACKLIST[@]} -eq 0 ]]; then
        msg_ok "Blacklist driver NVIDIA/nouveau OK"
    else
        msg_err "Missing blacklist entries for: ${MISSING_BLACKLIST[*]}"
        ERRORLOG+=("Missing blacklist entries for: ${MISSING_BLACKLIST[*]}.\n**Fix:**\n- Create or edit /etc/modprobe.d/blacklist-nvidia.conf.\n- Add: blacklist <module> for each entry.\n- Rebuild initramfs and reboot.")
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
        msg_warn "Missing softdep entries for: ${MISSING_SOFTDEP[*]}"
        ERRORLOG+=("Missing softdep entries for: ${MISSING_SOFTDEP[*]}.\n**Fix:**\n- Add lines to /etc/modprobe.d/vfio.conf in the form: softdep <module> pre: vfio-pci.\n- This helps vfio-pci load before the host drivers.")
    fi

    if [[ $ERR_DEV -eq 0 ]]; then
        msg_ok "SLOT ${SLOT} OK: PCI passthrough NVIDIA pronto"
    else
        msg_err "SLOT ${SLOT} has problems: see the suggestions"
    fi
done

if [[ ${#ERRORLOG[@]} -gt 0 ]]; then
    echo -e "\n${BOLD}${RED}=== ERRORI & SUGGERIMENTI ===${RESET}"
    for e in "${ERRORLOG[@]}"; do
        echo -e "${YELLOW}----------------------------------------------${RESET}"
        echo -e "$e"
    done
    echo -e "${BOLD}${YELLOW}See the troubleshooting/FAQ section of the guide for detailed examples.${RESET}"
fi
if [[ ${#WARNLOG[@]} -gt 0 ]]; then
    echo -e "\n${BOLD}${YELLOW}=== AVVISI OPZIONALI ===${RESET}"
    for e in "${WARNLOG[@]}"; do
        echo -e "${YELLOW}----------------------------------------------${RESET}"
        echo -e "$e"
    done
fi

echo -e "${CYAN}-- Check script by K3rn3l-P | https://github.com/K3rn3l-P/sysadmin-field-notes --${RESET}"
