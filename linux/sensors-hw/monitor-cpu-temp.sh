#!/usr/bin/env bash
# monitor-cpu-temp.sh
# Monitoraggio live temperature CPU (with colors & alert)
# by K3rn3l-P - https://github.com/K3rn3l-P

set -euo pipefail

WARN=75
CRIT=85
INTERVAL="${1:-2}"

cleanup() {
    tput cnorm 2>/dev/null || true
    stty sane 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Nascondi cursore per output continuo
tput civis 2>/dev/null || true

while true; do
    sensors_output=$(sensors 2>/dev/null || true)
    filtered=$(printf '%s\n' "$sensors_output" | grep -E '^(Package id [0-9]+|Core [0-9]+):' || true)

    printf '\033[H\033[2J'
    printf '%s\n\n' "$(date '+%F %T')  ---   CPU TEMP LIVE  (Ctrl+C per uscire)"
    printf '%-16s %-10s %-12s\n' "SENSORE" "TEMP" "STATO"
    printf '%-16s %-10s %-12s\n' "---------------" "----------" "------------"

    if [[ -z "$filtered" ]]; then
        printf '⚠️  Nessuna temperatura CPU trovata. Verifica che i sensori siano configurati e carica il modulo corretto.\n'
        sleep "$INTERVAL"
        continue
    fi

    while IFS= read -r line; do
        if [[ -z "$line" ]]; then
            continue
        fi
        if [[ "$line" =~ ^[[:space:]]*(Package\ id\ [0-9]+|Core\ [0-9]+):[[:space:]]*([+-]?[0-9]+(\.[0-9]+)?)°C ]]; then
            label="${BASH_REMATCH[1]}"
            temp="${BASH_REMATCH[2]}"
            inttemp=${temp%.*}
            state="OK"
            color="\033[32m"

            if (( inttemp >= CRIT )); then
                state="PERICOLO"
                color="\033[31;1m"
            elif (( inttemp >= WARN )); then
                state="ALLERTA"
                color="\033[33;1m"
            fi

            printf '%-16s ' "$label"
            printf '%b%-10s%b ' "$color" "${temp}°C" "\033[0m"
            printf '%-12s\n' "$state"
        fi
    done <<< "$filtered"

    printf '\nProcessi top memoria:\n'
    ps -eo pid,pmem,pcpu,comm --sort=-pmem | head -n 6 | awk 'NR==1 {printf "%-7s %-6s %-6s %s\n", $1, $2, $3, $4; next} {printf "%-7s %-6s %-6s %s\n", $1, $2, $3, $4}'

    sleep "$INTERVAL"
done
