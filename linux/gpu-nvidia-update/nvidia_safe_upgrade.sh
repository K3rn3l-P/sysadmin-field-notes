#!/usr/bin/env bash

# nvidia_safe_upgrade.sh
# ----------------------
# Script per aggiornamento sicuro driver NVIDIA su Debian/Ubuntu/Proxmox.
# Aggiorna SOLO se tutte le versioni candidate sono allineate.
# Gestisce hold/unhold automatico dei pacchetti NVIDIA installati.
# Uso: sudo ./nvidia_safe_upgrade.sh

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
  command -v "$1" >/dev/null 2>&1 || die "Comando richiesto non trovato: $1"
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
    echo ">>> Creo o aggiorno il file pin APT anti-NVIDIA: $PIN_FILE"
    echo "$PIN_CONTENT" | sudo tee "$PIN_FILE" > /dev/null
  fi
  sudo chmod 644 "$PIN_FILE" || warn "⚠️ File $PIN_FILE non scrivibile!"
}

function disable_nvidia_pin_block() {
  if [ -f "$PIN_FILE" ]; then
    echo ">>> Disabilito temporaneamente il pin-block NVIDIA."
    warn "⚠️ PERICOLO: BLOCCO PIN TEMPORANEAMENTE NON ATTIVO!"
    sudo mv "$PIN_FILE" "$PIN_FILE_DISABLED"
  fi
}

function enable_nvidia_pin_block() {
  if [ -f "$PIN_FILE_DISABLED" ]; then
    echo ">>> Ripristino il pin-block NVIDIA."
    sudo mv "$PIN_FILE_DISABLED" "$PIN_FILE"
  fi
}

function restore_nvidia_apt_timers() {
  if [ "$APT_TIMERS_DISABLED" -eq 1 ] && command -v systemctl >/dev/null 2>&1; then
    for unit in "${APT_TIMER_UNITS[@]}"; do
      if systemctl list-unit-files --type=timer --no-pager | grep -q "^${unit}"; then
        echo ">>> Ripristino timer APT: $unit"
        sudo systemctl start "$unit" >/dev/null 2>&1 || warn "Impossibile riattivare $unit"
      fi
    done
  fi
}

function disable_apt_timers() {
  if ! command -v systemctl >/dev/null 2>&1; then
    warn "systemctl non disponibile: non posso disabilitare i timer APT."
    return
  fi
  for unit in "${APT_TIMER_UNITS[@]}"; do
    if systemctl is-active --quiet "$unit"; then
      echo ">>> Disabilito temporaneamente il timer APT: $unit"
      sudo systemctl stop "$unit" >/dev/null 2>&1 || warn "Impossibile fermare $unit"
      APT_TIMERS_DISABLED=1
    fi
  done
}

function enable_apt_timers() {
  if ! command -v systemctl >/dev/null 2>&1; then
    warn "systemctl non disponibile: non posso riabilitare i timer APT."
    return
  fi
  for unit in "${APT_TIMER_UNITS[@]}"; do
    if systemctl list-unit-files --type=timer --no-pager | grep -q "^${unit}"; then
      echo ">>> Riabilito timer APT: $unit"
      sudo systemctl start "$unit" >/dev/null 2>&1 || warn "Impossibile avviare $unit"
    fi
  done
}

function restore_nvidia_pin_block_on_exit() {
  trap '
    if [ -f "$PIN_FILE_DISABLED" ]; then
      echo "### [WARN] Ripristino automatico del pin-block NVIDIA dopo errore o interruzione."
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
    warn "Impossibile rilevare versioni NVIDIA kernel/userland. Controlla lo stato del driver."
    return 1
  fi

  if [ "$kver" != "$uver" ]; then
    warn "Mismatch NVIDIA: kernel=$kver userland=$uver. Sistema potenzialmente instabile."
    return 1
  fi

  info "Modulo kernel e userland NVIDIA sono allineati: $kver"
  return 0
}

function detect_non_apt_nvidia_install() {
  local nvidia_smi_out modinfo_out kver="" uver=""
  echo "Nessun pacchetto NVIDIA installato trovato via APT/DPKG."
  echo "== Check driver NVIDIA installati fuori da apt/dpkg =="

  nvidia_smi_out="$(nvidia-smi 2>&1 || true)"
  if [[ "$nvidia_smi_out" =~ NVIDIA-SMI ]]; then
    echo "[INFO] nvidia-smi trovato e funzionante fuori da apt:"
    echo "$nvidia_smi_out"
    uver="$(printf '%s' "$nvidia_smi_out" | awk -F': ' '/Driver Version/ {print $2; exit}' | awk '{print $1}')"
  else
    echo "[WARN] nvidia-smi non trovato o non funzionante."
  fi

  modinfo_out="$(modinfo nvidia 2>&1 || true)"
  if [[ "$modinfo_out" =~ filename: ]]; then
    echo "[INFO] modinfo nvidia trovato fuori da apt:"
    echo "$modinfo_out" | awk '/^filename:/ || /^version:/'
    kver="$(printf '%s' "$modinfo_out" | awk '/^version:/ {print $2; exit}')"
  else
    echo "[WARN] modinfo nvidia non trovato o non funzionante."
  fi

  if [[ -n "$kver" && -n "$uver" ]]; then
    if [[ "$kver" != "$uver" ]]; then
      echo "[WARN] ⚠️ Mismatch driver fuori da APT: kernel=$kver userland=$uver"
    else
      echo "[INFO] Driver fuori da APT allineati: kernel/userland $kver"
    fi
  elif [[ -n "$uver" ]]; then
    echo "[INFO] Versione userland NVIDIA rilevata (solo nvidia-smi): $uver"
  elif [[ -n "$kver" ]]; then
    echo "[INFO] Versione modulo kernel NVIDIA rilevata (solo modinfo): $kver"
  else
    echo "[WARN] Nessun driver NVIDIA rilevato via nvidia-smi o modinfo."
  fi

  echo "[INFO] Driver NVIDIA installati via runfile, snap, flatpak o container non sono gestiti da questo script."
  echo "[TIP] Per aggiornare/CLEAN/auto-controllare installazioni manuali consulta: https://wiki.debian.org/NvidiaGraphicsDrivers#Uninstallation"
}

function hold_nvidia_pkgs() {
  local pkgs=("$@")
  if [ ${#pkgs[@]} -eq 0 ]; then
    return 0
  fi
  if output=$(sudo apt-mark hold "${pkgs[@]}" 2>&1); then
    info "apt-mark hold: ok"
  else
    warn "Impossibile mettere in hold i pacchetti NVIDIA: $output"
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
    warn "Impossibile rimuovere il blocco hold: $output"
  fi
}

for cmd in dpkg apt-cache tee awk sudo apt modinfo nvidia-smi; do
  require_cmd "$cmd"
done

if [ "$(id -u)" -ne 0 ]; then
  die "Esegui questo script come root o con sudo."
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

info "Logging output anche su: $LOG_FILE"
info "NOTA: I driver NVIDIA sono sempre protetti da upgrade accidentali tramite apt-mark hold."
info "Pacchetti NVIDIA rilevati: ${PKGS[*]}"
hold_nvidia_pkgs "${PKGS[@]}"

echo
info "==== Verifica mismatch NVIDIA prima dell'upgrade ===="
if ! check_nvidia_mismatch; then
  warn "Mismatch rilevato. Si consiglia di risolvere prima di procedere con l'upgrade."
fi

info "Repository attivi:"
grep -h '^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null || true

echo
info "==== Verifica versione pacchetti NVIDIA ===="
ALL_OK=1
REF_VER=""
for PKG in "${PKGS[@]}"; do
  policy=$(apt-cache policy "$PKG" 2>/dev/null || true)
  CAND=$(printf '%s' "$policy" | awk '/Candidate:/ {print $2; exit}')
  INST=$(printf '%s' "$policy" | awk '/Installed:/ {print $2; exit}')

  if [ -z "$CAND" ] || [ "$CAND" == "(none)" ]; then
    warn "  $PKG: Installed: ${INST:-none}  |  Candidate: NON DISPONIBILE"
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
  info "✅ Tutte le versioni candidate coincidono: $REF_VER"
  read -r -p "Procedo con install/upgrade di TUTTI i pacchetti NVIDIA? [y/N] " RESP
  if [[ "$RESP" =~ ^[Yy]$ ]]; then
    info "Disabilito temporaneamente il pin-block NVIDIA e i timer APT automatici, quindi sblocco i pacchetti per upgrade atomico..."
    disable_nvidia_pin_block
    disable_apt_timers
    unhold_nvidia_pkgs "${PKGS[@]}"
    set -x
    if ! sudo apt install -y "${PKGS[@]}"; then
      set +x
      info "Ripristino del pin-block NVIDIA, riattivo i timer APT e il blocco hold dei pacchetti..."
      enable_nvidia_pin_block
      enable_apt_timers
      hold_nvidia_pkgs "${PKGS[@]}"
      die "Aggiornamento driver fallito. Controlla $LOG_FILE per dettagli."
    fi
    set +x
    info "Ripristino del pin-block NVIDIA, riattivo i timer APT e il blocco hold dei pacchetti..."
    enable_nvidia_pin_block
    enable_apt_timers
    hold_nvidia_pkgs "${PKGS[@]}"
    if check_nvidia_mismatch; then
      info "Driver aggiornati e mismatch risolto."
    else
      warn "Controlla il mismatch dei driver dopo l'installazione."
    fi
    info "Driver aggiornati. Controlla eventuali messaggi di apt e riavvia il sistema se necessario."
    if [ -f /var/run/reboot-required ] || [ -f /var/run/reboot-required.pkgs ]; then
      warn "Riavvio raccomandato: il sistema richiede un reboot per completare la configurazione dei pacchetti."
      REBOOT_PENDING=1
    fi
  else
    warn "Upgrade ignorato (abortito dall'utente)."
  fi
else
  warn "❌ WARNING: Le versioni candidate NON combaciano tra i pacchetti chiave."
  warn "Nessun aggiornamento verrà eseguito. CONTROLLA I REPOSITORY e attendi allineamento."
  EXIT_CODE=1
fi

echo
if [ "$REBOOT_PENDING" -eq 1 ]; then
  EXIT_CODE=1
fi
exit "$EXIT_CODE"
