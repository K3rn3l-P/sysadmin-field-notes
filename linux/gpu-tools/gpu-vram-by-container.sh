#!/usr/bin/env bash
set -euo pipefail

# Show GPU VRAM usage per process and map each process to a Docker container (if any).
# Requires: nvidia-smi, docker (optional but recommended)

CSI=$'\033['
RESET=$'\033[0m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
CYAN=$'\033[36m'
BOLD=$'\033[1m'

colorize() {
  local color="$1"
  local text="$2"
  printf '%b%s%b' "$color" "$text" "$RESET"
}

color_percent() {
  local value="$1"
  local text="${2:-${value}%}"
  if (( value >= 90 )); then
    printf '%b' "${RED}${text}${RESET}"
  elif (( value >= 70 )); then
    printf '%b' "${YELLOW}${text}${RESET}"
  else
    printf '%b' "${GREEN}${text}${RESET}"
  fi
}

color_temp() {
  local text="$1"
  local temp
  temp="$(printf '%s' "$text" | sed -E 's/^[[:space:]]*([0-9]+).*$/\1/')"
  if (( temp >= 90 )); then
    color="${RED}${BOLD}"
  elif (( temp >= 75 )); then
    color="${YELLOW}${BOLD}"
  else
    color="${GREEN}"
  fi
  colorize "$color" "$text"
}

color_vram() {
  local value="$1"
  if (( value >= 2000 )); then
    color="${RED}${BOLD}"
  elif (( value >= 1000 )); then
    color="${YELLOW}"
  else
    color="${GREEN}"
  fi
  colorize "$color" "$value"
}

color_container() {
  local text="$1"
  if [[ "$text" == "(host)" ]]; then
    printf '%s' "$text"
  else
    colorize "$CYAN$BOLD" "$text"
  fi
}

LIVE=0
INTERVAL=2
PREV_GPU_LINES=()
PREV_PROC_LINES=()
PREV_PROC_PIDS=()
PREV_GPU_IDS=()
if [[ "${1:-}" == "--live" || "${1:-}" == "-l" ]]; then
  LIVE=1
  INTERVAL="${2:-2}"
fi

clear_screen() {
  printf '\033[H\033[2J'
}

output_stats() {
  if ! command -v nvidia-smi >/dev/null 2>&1; then
    echo 'ERROR: nvidia-smi not found. Are NVIDIA drivers installed inside this VM?'
    exit 1
  fi

  HAS_DOCKER=0
  if command -v docker >/dev/null 2>&1; then
    HAS_DOCKER=1
  fi

  DOCKER_PS=''
  if [[ "$HAS_DOCKER" -eq 1 ]]; then
    DOCKER_PS="$(docker ps --no-trunc 2>/dev/null || true)"
  fi

  GPU_INFO=$(nvidia-smi --query-gpu=index,name,driver_version,memory.total,memory.used,utilization.gpu,utilization.memory,temperature.gpu,gpu_uuid --format=csv,noheader,nounits 2>/dev/null)
  if [[ -z "$GPU_INFO" ]]; then
    echo 'ERROR: no NVIDIA GPU detected or nvidia-smi failed.'
    exit 1
  fi

  local gpu_count=0
  local line
  local gpu_line
  local proc_line
  local row

  declare -A GPU_UUID_TO_INDEX=()
  GPU_LINES=()
  GPU_IDS=()

  while IFS=, read -r gpu_index gpu_name driver total used gpu_util mem_util temp gpu_uuid; do
    gpu_index="$(printf '%s' "$gpu_index" | sed 's/^ *//;s/ *$//')"
    gpu_name="$(printf '%s' "$gpu_name" | sed 's/^ *//;s/ *$//')"
    driver="$(printf '%s' "$driver" | sed 's/^ *//;s/ *$//')"
    total="$(printf '%s' "$total" | sed 's/^ *//;s/ *$//')"
    used="$(printf '%s' "$used" | sed 's/^ *//;s/ *$//')"
    gpu_util="$(printf '%s' "$gpu_util" | sed 's/^ *//;s/ *$//')"
    temp="$(printf '%s' "$temp" | sed 's/^ *//;s/ *$//')"
    mem_util="$(printf '%s' "$mem_util" | sed 's/^ *//;s/ *$//')"
    gpu_uuid="$(printf '%s' "$gpu_uuid" | sed 's/^ *//;s/ *$//')"

    mem_percent=0
    if [[ "$total" =~ ^[0-9]+$ ]] && [[ "$used" =~ ^[0-9]+$ ]] && [[ "$total" -gt 0 ]]; then
      mem_percent=$((used * 100 / total))
    fi

    GPU_UUID_TO_INDEX["$gpu_uuid"]="$gpu_index"
    temp_field=$(printf '%-7s' "${temp}°C")
    temp_text=$(color_temp "$temp_field")
    gpu_util_field=$(printf '%-6s' "${gpu_util}%")
    gpu_util_text=$(color_percent "$gpu_util" "$gpu_util_field")
    mem_field=$(printf '%-11s' "${mem_percent}%")
    mem_text=$(color_percent "$mem_percent" "$mem_field")
    used_text=$(color_vram "$used")
    gpu_line=$(printf '%-4s %-22s %-13s %-7s %-6s %-11s %s/%s\033[K' "$gpu_index" "$gpu_name" "$driver" "$temp_text" "$gpu_util_text" "$mem_text" "$used_text" "$total")
    GPU_LINES+=("$gpu_line")
    GPU_IDS+=("$gpu_index")
    gpu_count=$((gpu_count + 1))
  done <<< "$GPU_INFO"

  PROC_LINES=()
  PROC_PIDS=()
  PROCS=$(nvidia-smi --query-compute-apps=pid,process_name,used_gpu_memory,gpu_uuid --format=csv,noheader,nounits 2>/dev/null | sed '/^[[:space:]]*$/d')
  if [[ -z "$PROCS" ]]; then
    echo 'No GPU processes found.'
    exit 0
  fi

  while IFS= read -r line; do
    pid="$(printf '%s' "$line" | cut -d',' -f1 | sed 's/^ *//;s/ *$//')"
    pname="$(printf '%s' "$line" | cut -d',' -f2 | sed 's/^ *//;s/ *$//')"
    used="$(printf '%s' "$line" | cut -d',' -f3 | sed 's/^ *//;s/ *$//')"
    gpu_uuid="$(printf '%s' "$line" | cut -d',' -f4 | sed 's/^ *//;s/ *$//')"
    gpu_index="${GPU_UUID_TO_INDEX[$gpu_uuid]:-?}"

    container_short='(host)'
    container_info='-'
    if [[ -r "/proc/$pid/cgroup" ]]; then
      cg="$(tr '\n' ' ' < "/proc/$pid/cgroup")"
      cid64="$(printf '%s' "$cg" | sed -n 's/.*docker-\([0-9a-f]\{64\}\)\.scope.*/\1/p')"
      if [[ -z "$cid64" ]]; then
        cid64="$(printf '%s' "$cg" | sed -n 's#.*docker/\([0-9a-f]\{64\}\).*#\1#p')"
      fi
      if [[ -n "$cid64" ]]; then
        container_short="${cid64:0:12}"
        if [[ "$HAS_DOCKER" -eq 1 ]]; then
          container_info="$(printf '%s' "$DOCKER_PS" | grep -F "$cid64" || true)"
        fi
      fi
    fi

    if [[ -n "$container_info" && "$container_info" != "-" ]]; then
      img="$(printf '%s' "$container_info" | awk '{print $2}')"
      name="$(printf '%s' "$container_info" | awk '{print $NF}')"
      container_info="$img ($name)"
    fi

    pid_field=$(printf '%-8s' "$pid")
    used_field=$(printf '%-10s' "$used")
    gpu_index_field=$(printf '%-5s' "$gpu_index")
    container_field=$(printf '%-14s' "$container_short")
    process_field=$(printf '%-16s' "$pname")

    used_text=$(color_vram "$used_field")
    if [[ "$container_short" != "(host)" ]]; then
      container_field=$(colorize "$CYAN" "$container_field")
    fi
    if [[ "$container_info" != "-" ]]; then
      container_info=$(colorize "$YELLOW" "$container_info")
    fi
    process_text=$(colorize "$BOLD$CYAN" "$process_field")

    proc_line=$(printf '%-8s %-10s %-5s %-14s %-16s %s\033[K' "$pid_field" "$used_text" "$gpu_index_field" "$container_field" "$process_text" "$container_info")
    PROC_LINES+=("$proc_line")
    PROC_PIDS+=("$pid")
  done <<< "$PROCS"

  if [[ "$LIVE" -eq 0 ]]; then
    printf '%s
' "${BOLD}GPU summary:${RESET}"
    printf '%-4s %-22s %-13s %-7s %-6s %-11s %s\n' "GPU" "NAME" "DRIVER" "TEMP" "GPU%" "MEM%" "USED/TOTAL"
    printf '%-4s %-22s %-13s %-7s %-6s %-11s %s\n' "---" "----" "------" "----" "----" "-------" "-----------"
    for line in "${GPU_LINES[@]}"; do
      printf '%b\n' "$line"
    done
    printf '\n%s\n' "${BOLD}Processes holding GPU VRAM:${RESET}"
    printf '%-8s %-10s %-5s %-14s %-16s %s\n' "PID" "VRAM(MB)" "GPU" "CONTAINER" "PROCESS" "IMAGE/NAME"
    printf '%-8s %-10s %-5s %-14s %-16s %s\n' "--------" "--------" "---" "--------------" "----------------" "------------------------------"
    for line in "${PROC_LINES[@]}"; do
      printf '%b\n' "$line"
    done
    PREV_GPU_LINES=("${GPU_LINES[@]}")
    PREV_PROC_LINES=("${PROC_LINES[@]}")
    PREV_PROC_PIDS=("${PROC_PIDS[@]}")
    PREV_GPU_IDS=("${GPU_IDS[@]}")
    return
  fi

  if [[ ${#PREV_GPU_LINES[@]} -ne ${#GPU_LINES[@]} || ${PREV_GPU_IDS[*]} != ${GPU_IDS[*]} ]]; then
    clear_screen
    printf '%s
' "${BOLD}GPU summary:${RESET}"
    printf '%-4s %-22s %-13s %-7s %-6s %-11s %s\n' "GPU" "NAME" "DRIVER" "TEMP" "GPU%" "MEM%" "USED/TOTAL"
    printf '%-4s %-22s %-13s %-7s %-6s %-11s %s\n' "---" "----" "------" "----" "----" "-------" "-----------"
    for line in "${GPU_LINES[@]}"; do printf '%b\n' "$line"; done
    PREV_GPU_LINES=("${GPU_LINES[@]}")
    PREV_PROC_LINES=()
    PREV_PROC_PIDS=()
    PREV_GPU_IDS=("${GPU_IDS[@]}")
  else
    for i in "${!GPU_LINES[@]}"; do
      if [[ "${GPU_LINES[i]}" != "${PREV_GPU_LINES[i]}" ]]; then
        printf '\033[%s;1H' $((4 + i))
        printf '%b\n' "${GPU_LINES[i]}"
        PREV_GPU_LINES[i]="${GPU_LINES[i]}"
      fi
    done
  fi

  local proc_start=$((4 + ${#GPU_LINES[@]} + 2))
  if [[ ${#PREV_PROC_LINES[@]} -ne ${#PROC_LINES[@]} || ${PREV_PROC_PIDS[*]} != ${PROC_PIDS[*]} ]]; then
    printf '\033[%s;1H' "$proc_start"
    printf '%s\n' "${BOLD}Processes holding GPU VRAM:${RESET}"
    printf '%-8s %-10s %-5s %-14s %-16s %s\n' "PID" "VRAM(MB)" "GPU" "CONTAINER" "PROCESS" "IMAGE/NAME"
    printf '%-8s %-10s %-5s %-14s %-16s %s\n' "--------" "--------" "---" "--------------" "----------------" "------------------------------"
    for line in "${PROC_LINES[@]}"; do printf '%b\n' "$line"; done
    PREV_PROC_LINES=("${PROC_LINES[@]}")
    PREV_PROC_PIDS=("${PROC_PIDS[@]}")
  else
    for i in "${!PROC_LINES[@]}"; do
      if [[ "${PROC_LINES[i]}" != "${PREV_PROC_LINES[i]}" ]]; then
        printf '\033[%s;1H' $((proc_start + 3 + i))
        printf '%b\n' "${PROC_LINES[i]}"
        PREV_PROC_LINES[i]="${PROC_LINES[i]}"
      fi
    done
    PREV_PROC_PIDS=("${PROC_PIDS[@]}")
  fi
}

if [[ "$LIVE" -eq 1 ]]; then
  clear_screen
  output_stats
  while true; do
    printf '\033[H'
    output_stats
    sleep "$INTERVAL"
  done
else
  output_stats
fi
