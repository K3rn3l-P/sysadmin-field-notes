#!/usr/bin/env bash

# nvidia_safe_upgrade.sh
# ----------------------
# Safe NVIDIA driver upgrade script for Debian/Ubuntu/Proxmox.
# Upgrades ONLY when every candidate version is aligned.
# Handles automatic hold/unhold of the installed NVIDIA packages.
# Usage: sudo ./nvidia_safe_upgrade.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/nvidia_safe_upgrade.log"
LOG_MAX_BYTES=$((1024 * 1024))
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

EXIT_CODE=0
REBOOT_PENDING=0

if [ -t 1 ]; then
  GREEN="\033[0;32m"
  YELLOW="\033[0;33m"
  RED="\033[0;31m"
  NC="\033[0;0m"
else
  GREEN=""
  YELLOW=""
  RED=""
  NC=""
fi

function die() {
  printf "%bERROR:%b %s\n" "$RED" "$NC" "$*" >&2
  exit 1
}

function info() {
  printf "%b%s%b\n" "$GREEN" "$1" "$NC"
}

function warn() {
  printf "%b%s%b\n" "$YELLOW" "$1" "$NC"
}

function require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

# ----- Blocco PREFERENCES automatico anti-NVIDIA -----
PIN_FILE="/etc/apt/preferences.d/99-nvidia-block"
PIN_FILE_DISABLED="${PIN_FILE}.DISABLED"
PIN_CONTENT=$(cat <<'EOF'
Package: nvidia*
Pin: release *
Pin-Priority: -1

Package: libnvidia*
Pin: release *
Pin-Priority: -1

Package: xserver-xorg-video-nvidia*
Pin: release *
Pin-Priority: -1

Package: firmware-nvidia-gsp*
Pin: release *
Pin-Priority: -1

Package: *cuda*
Pin: release *
Pin-Priority: -1

Package: *nvml*
Pin: release *
Pin-Priority: -1
EOF
)

APT_TIMER_UNITS=(apt-daily.timer apt-daily-upgrade.timer)
APT_TIMERS_DISABLED=0

function ensure_nvidia_pin_block() {
  if [ ! -f "$PIN_FILE" ] || ! diff -q <(echo "$PIN_CONTENT") "$PIN_FILE" >/dev/null 2>&1; then
    echo ">>> Creating or updating the anti-NVIDIA APT pin file: $PIN_FILE"
    echo "$PIN_CONTENT" | sudo tee "$PIN_FILE" > /dev/null
  fi
  sudo chmod 644 "$PIN_FILE" || warn "⚠️ File $PIN_FILE is not writable!"
}

function disable_nvidia_pin_block() {
  if [ -f "$PIN_FILE" ]; then
    echo ">>> Temporarily disabling the NVIDIA pin-block."
    warn "⚠️ DANGER: PIN BLOCK TEMPORARILY INACTIVE!"
    sudo mv "$PIN_FILE" "$PIN_FILE_DISABLED"
  fi
}

function enable_nvidia_pin_block() {
  if [ -f "$PIN_FILE_DISABLED" ]; then
    echo ">>> Restoring the NVIDIA pin-block."
    sudo mv "$PIN_FILE_DISABLED" "$PIN_FILE"
  fi
}

function restore_nvidia_apt_timers() {
  if [ "$APT_TIMERS_DISABLED" -eq 1 ] && command -v systemctl >/dev/null 2>&1; then
    for unit in "${APT_TIMER_UNITS[@]}"; do
      if systemctl list-unit-files --type=timer --no-pager | grep -q "^${unit}"; then
        echo ">>> Restoring APT timer: $unit"
        sudo systemctl start "$unit" >/dev/null 2>&1 || warn "Could not re-enable $unit"
      fi
    done
  fi
}

function disable_apt_timers() {
  if ! command -v systemctl >/dev/null 2>&1; then
    warn "systemctl unavailable: cannot disable the APT timers."
    return
  fi
  for unit in "${APT_TIMER_UNITS[@]}"; do
    if systemctl is-active --quiet "$unit"; then
      echo ">>> Temporarily disabling APT timer: $unit"
      sudo systemctl stop "$unit" >/dev/null 2>&1 || warn "Could not stop $unit"
      APT_TIMERS_DISABLED=1
    fi
  done
}

function enable_apt_timers() {
  if ! command -v systemctl >/dev/null 2>&1; then
    warn "systemctl unavailable: cannot re-enable the APT timers."
    return
  fi
  for unit in "${APT_TIMER_UNITS[@]}"; do
    if systemctl list-unit-files --type=timer --no-pager | grep -q "^${unit}"; then
      echo ">>> Re-enabling APT timer: $unit"
      sudo systemctl start "$unit" >/dev/null 2>&1 || warn "Could not start $unit"
    fi
  done
}

function restore_nvidia_pin_block_on_exit() {
  trap '
    if [ -f "$PIN_FILE_DISABLED" ]; then
      echo "### [WARN] Automatically restoring the NVIDIA pin-block after an error or interruption."
      sudo mv "$PIN_FILE_DISABLED" "$PIN_FILE"
    fi
    restore_nvidia_apt_timers
  ' EXIT
}

function get_nvidia_pkgs() {
  dpkg -l | awk '/^ii/ && ($2 ~ /^(nvidia|libnvidia|xserver-xorg-video-nvidia|firmware-nvidia-gsp|cuda|nvml|libcuda)/) {print $2}' | sort -u
}

function check_nvidia_mismatch() {
  local kver uver
  kver="$(modinfo nvidia 2>/dev/null | awk '/^version:/ {print $2; exit}' || true)"
  uver="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || true)"

  if [ -z "$kver" ] || [ -z "$uver" ]; then
    warn "Could not determine the NVIDIA kernel/userland versions. Check the driver state."
    return 1
  fi

  if [ "$kver" != "$uver" ]; then
    warn "NVIDIA mismatch: kernel=$kver userland=$uver. System potentially unstable."
    return 1
  fi

  info "NVIDIA kernel module and userland are aligned: $kver"
  return 0
}

function detect_non_apt_nvidia_install() {
  local nvidia_smi_out modinfo_out kver="" uver=""
  echo "No installed NVIDIA packages found via APT/DPKG."
  echo "== Checking for NVIDIA drivers installed outside apt/dpkg =="

  nvidia_smi_out="$(nvidia-smi 2>&1 || true)"
  if [[ "$nvidia_smi_out" =~ NVIDIA-SMI ]]; then
    echo "[INFO] nvidia-smi found and working outside apt:"
    echo "$nvidia_smi_out"
    uver="$(printf '%s' "$nvidia_smi_out" | awk -F': ' '/Driver Version/ {print $2; exit}' | awk '{print $1}')"
  else
    echo "[WARN] nvidia-smi not found, or not working."
  fi

  modinfo_out="$(modinfo nvidia 2>&1 || true)"
  if [[ "$modinfo_out" =~ filename: ]]; then
    echo "[INFO] modinfo nvidia found outside apt:"
    echo "$modinfo_out" | awk '/^filename:/ || /^version:/'
    kver="$(printf '%s' "$modinfo_out" | awk '/^version:/ {print $2; exit}')"
  else
    echo "[WARN] modinfo nvidia not found, or not working."
  fi

  if [[ -n "$kver" && -n "$uver" ]]; then
    if [[ "$kver" != "$uver" ]]; then
      echo "[WARN] ⚠️ Driver mismatch outside APT: kernel=$kver userland=$uver"
    else
      echo "[INFO] Drivers outside APT are aligned: kernel/userland $kver"
    fi
  elif [[ -n "$uver" ]]; then
    echo "[INFO] NVIDIA userland version detected (nvidia-smi only): $uver"
  elif [[ -n "$kver" ]]; then
    echo "[INFO] NVIDIA kernel module version detected (modinfo only): $kver"
  else
    echo "[WARN] No NVIDIA driver detected via nvidia-smi or modinfo."
  fi

  echo "[INFO] NVIDIA drivers installed via runfile, snap, flatpak or containers are not managed by this script."
  echo "[TIP] To update, clean or check manual installations, see: https://wiki.debian.org/NvidiaGraphicsDrivers#Uninstallation"
}

function hold_nvidia_pkgs() {
  local pkgs=("$@")
  if [ ${#pkgs[@]} -eq 0 ]; then
    return 0
  fi
  if output=$(sudo apt-mark hold "${pkgs[@]}" 2>&1); then
    info "apt-mark hold: ok"
  else
    warn "Could not hold the NVIDIA packages: $output"
  fi
}

function unhold_nvidia_pkgs() {
  local pkgs=("$@")
  if [ ${#pkgs[@]} -eq 0 ]; then
    return 0
  fi
  if output=$(sudo apt-mark unhold "${pkgs[@]}" 2>&1); then
    info "apt-mark unhold: ok"
  else
    warn "Could not remove the hold: $output"
  fi
}

for cmd in dpkg apt-cache tee awk sudo apt modinfo nvidia-smi; do
  require_cmd "$cmd"
done

if [ "$(id -u)" -ne 0 ]; then
  die "Run this script as root, or with sudo."
fi

if [ -f "$LOG_FILE" ] && [ "$(wc -c <"$LOG_FILE")" -gt "$LOG_MAX_BYTES" ]; then
  tail -n 1000 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi

exec > >(tee -a "$LOG_FILE") 2>&1

restore_nvidia_pin_block_on_exit
ensure_nvidia_pin_block

PKGS=( $(get_nvidia_pkgs) )

if [ ${#PKGS[@]} -eq 0 ]; then
  detect_non_apt_nvidia_install
  exit 0
fi

info "Also logging output to: $LOG_FILE"
info "NOTE: the NVIDIA drivers are always protected from accidental upgrades by apt-mark hold."
info "NVIDIA packages detected: ${PKGS[*]}"
hold_nvidia_pkgs "${PKGS[@]}"

echo
info "==== Checking for an NVIDIA mismatch before the upgrade ===="
if ! check_nvidia_mismatch; then
  warn "Mismatch detected. Best to resolve it before going ahead with the upgrade."
fi

info "Active repositories:"
grep -h '^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null || true

echo
info "==== Checking NVIDIA package versions ===="
ALL_OK=1
REF_VER=""
for PKG in "${PKGS[@]}"; do
  policy=$(apt-cache policy "$PKG" 2>/dev/null || true)
  CAND=$(printf '%s' "$policy" | awk '/Candidate:/ {print $2; exit}')
  INST=$(printf '%s' "$policy" | awk '/Installed:/ {print $2; exit}')

  if [ -z "$CAND" ] || [ "$CAND" == "(none)" ]; then
    warn "  $PKG: Installed: ${INST:-none}  |  Candidate: NOT AVAILABLE"
    ALL_OK=0
    continue
  fi

  info "  $PKG: Installed: ${INST:-none}  |  Candidate: $CAND"

  if [ -z "$REF_VER" ]; then
    REF_VER="$CAND"
  elif [ "$CAND" != "$REF_VER" ]; then
    ALL_OK=0
  fi
done

echo
if [ "$ALL_OK" -eq 1 ]; then
  info "✅ All candidate versions match: $REF_VER"
  read -r -p "Procedo con install/upgrade di TUTTI i pacchetti NVIDIA? [y/N] " RESP
  if [[ "$RESP" =~ ^[Yy]$ ]]; then
    info "Temporarily disabling the NVIDIA pin-block and the automatic APT timers, then unholding the packages for an atomic upgrade..."
    disable_nvidia_pin_block
    disable_apt_timers
    unhold_nvidia_pkgs "${PKGS[@]}"
    set -x
    if ! sudo apt install -y "${PKGS[@]}"; then
      set +x
      info "Restoring the NVIDIA pin-block, re-enabling the APT timers and re-holding the packages..."
      enable_nvidia_pin_block
      enable_apt_timers
      hold_nvidia_pkgs "${PKGS[@]}"
      die "Driver upgrade failed. Check $LOG_FILE for details."
    fi
    set +x
    info "Restoring the NVIDIA pin-block, re-enabling the APT timers and re-holding the packages..."
    enable_nvidia_pin_block
    enable_apt_timers
    hold_nvidia_pkgs "${PKGS[@]}"
    if check_nvidia_mismatch; then
      info "Drivers upgraded and the mismatch is resolved."
    else
      warn "Check the driver mismatch after installation."
    fi
    info "Drivers upgraded. Check any apt messages and reboot if needed."
    if [ -f /var/run/reboot-required ] || [ -f /var/run/reboot-required.pkgs ]; then
      warn "Reboot recommended: the system needs one to finish configuring the packages."
      REBOOT_PENDING=1
    fi
  else
    warn "Upgrade skipped (aborted by the user)."
  fi
else
  warn "❌ WARNING: the candidate versions do NOT match across the key packages."
  warn "No upgrade will be performed. CHECK THE REPOSITORIES and wait for them to line up."
  EXIT_CODE=1
fi

echo
if [ "$REBOOT_PENDING" -eq 1 ]; then
  EXIT_CODE=1
fi
exit "$EXIT_CODE"
