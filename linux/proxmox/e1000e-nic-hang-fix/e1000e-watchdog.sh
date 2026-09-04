#!/bin/bash
# e1000e-watchdog.sh
#
# The onboard Intel 82579LM NIC (eno1, e1000e driver) on this HP Z420 is
# subject to a known driver/firmware bug: under sustained TX traffic the
# card goes into "Detected Hardware Unit Hang" and never recovers on its
# own (the driver never emits a "Reset adapter"), leaving the whole host
# unreachable (Proxmox GUI, SSH, LAN) until it is physically powered off.
#
# The upstream fixes (TSO/GSO/GRO/EEE off, see post-up-vmbr0.conf) resolve
# the vast majority of documented cases, but this service stays on as a
# safety net: it follows the kernel log in real time and, the moment a hang
# appears, brings the interface back up by itself within seconds instead of
# needing someone at the power button.
#
# See README.md in this folder for the full diagnosis.

set -u

IFACE="eno1"
COOLDOWN=30          # minimum seconds between two interventions, to avoid loops
LAST_ACTION=0
LOG_TAG="e1000e-watchdog"

log() {
	logger -t "$LOG_TAG" -- "$1"
	echo "$(date '+%Y-%m-%d %H:%M:%S') $1"
}

# The ethtool settings (TSO/GSO/GRO/EEE off, ring 4096) survive a plain
# down/up but are lost if the e1000e module gets reloaded. We always
# re-apply them after a successful recovery, so we never fall back to the
# configuration that caused the hang.
reapply_fix() {
	/usr/sbin/ethtool -K "$IFACE" tso off gso off gro off sg off 2>/dev/null
	/usr/sbin/ethtool --set-eee "$IFACE" eee off 2>/dev/null
	/usr/sbin/ethtool -G "$IFACE" rx 4096 tx 4096 2>/dev/null
}

recover_interface() {
	local now
	now=$(date +%s)
	if (( now - LAST_ACTION < COOLDOWN )); then
		log "Hang detected but within the cooldown (${COOLDOWN}s), skipping to avoid a loop."
		return
	fi
	LAST_ACTION=$now

	log "Hardware Unit Hang detected on $IFACE: trying an interface down/up."
	ip link set "$IFACE" down
	sleep 2
	ip link set "$IFACE" up
	sleep 3

	if ip link show "$IFACE" | grep -q "state UP"; then
		reapply_fix
		log "Recovery succeeded with down/up: $IFACE is UP again (TSO/GSO/EEE fix re-applied)."
		return
	fi

	log "down/up did not restore the link: trying an e1000e module reload."
	# Takes the bridge out of the path only for the duration of the module
	# swap; vmbr0 re-attaches automatically because the NIC is in bridge-ports.
	modprobe -r e1000e 2>/dev/null
	sleep 2
	modprobe e1000e
	sleep 3

	if ip link show "$IFACE" | grep -q "state UP"; then
		reapply_fix
		log "Recovery succeeded with an e1000e module reload (TSO/GSO/EEE fix re-applied)."
	else
		log "WARNING: the module reload did not restore $IFACE. Manual intervention may be needed."
	fi
}

log "Started, watching $IFACE for 'Detected Hardware Unit Hang' in the kernel log."

# -k = kernel messages only, -f = follow in real time, -n0 = don't replay the past
journalctl -k -f -n0 --no-pager | while IFS= read -r line; do
	if [[ "$line" == *"$IFACE"*"Detected Hardware Unit Hang"* ]]; then
		recover_interface
	fi
done
