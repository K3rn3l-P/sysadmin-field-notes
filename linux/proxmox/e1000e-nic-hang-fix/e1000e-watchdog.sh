#!/bin/bash
# e1000e-watchdog.sh
#
# La NIC integrata Intel 82579LM (eno1, driver e1000e) di questo HP Z420 e'
# soggetta a un bug driver/firmware noto: sotto traffico TX sostenuto la
# scheda va in "Detected Hardware Unit Hang" e non si riprende mai da sola
# (il driver non emette mai un "Reset adapter"), lasciando l'intero host
# irraggiungibile (GUI Proxmox, SSH, LAN) fino a uno spegnimento fisico.
#
# I fix "a monte" (TSO/GSO/GRO/EEE off, vedi post-up-vmbr0.conf) risolvono
# la stragrande maggioranza dei casi documentati, ma questo servizio resta
# come rete di sicurezza: segue il kernel log in tempo reale e, alla prima
# comparsa dell'hang, riporta su l'interfaccia da solo in pochi secondi,
# invece di richiedere l'intervento fisico sul tasto power.
#
# Vedi README.md in questa cartella per la diagnosi completa.

set -u

IFACE="eno1"
COOLDOWN=30          # secondi minimi fra due interventi, per evitare loop
LAST_ACTION=0
LOG_TAG="e1000e-watchdog"

log() {
	logger -t "$LOG_TAG" -- "$1"
	echo "$(date '+%Y-%m-%d %H:%M:%S') $1"
}

# I settaggi ethtool (TSO/GSO/GRO/EEE off, ring 4096) sopravvivono a un
# semplice down/up ma vengono persi se il modulo e1000e viene ricaricato.
# Li riapplichiamo sempre dopo un recupero riuscito, per non tornare mai
# alla configurazione che ha causato l'hang.
reapply_fix() {
	/usr/sbin/ethtool -K "$IFACE" tso off gso off gro off sg off 2>/dev/null
	/usr/sbin/ethtool --set-eee "$IFACE" eee off 2>/dev/null
	/usr/sbin/ethtool -G "$IFACE" rx 4096 tx 4096 2>/dev/null
}

recover_interface() {
	local now
	now=$(date +%s)
	if (( now - LAST_ACTION < COOLDOWN )); then
		log "Hang rilevato ma entro cooldown (${COOLDOWN}s), salto l'intervento per evitare loop."
		return
	fi
	LAST_ACTION=$now

	log "Hardware Unit Hang rilevato su $IFACE: provo down/up dell'interfaccia."
	ip link set "$IFACE" down
	sleep 2
	ip link set "$IFACE" up
	sleep 3

	if ip link show "$IFACE" | grep -q "state UP"; then
		reapply_fix
		log "Recupero riuscito con down/up: $IFACE e' di nuovo UP (fix TSO/GSO/EEE riapplicato)."
		return
	fi

	log "down/up non ha ripristinato il link: provo il reload del modulo e1000e."
	# Rimuove il bridge dal path solo per il tempo dello swap del modulo;
	# vmbr0 lo ri-attacca automaticamente perche' la nic è bridge-ports.
	modprobe -r e1000e 2>/dev/null
	sleep 2
	modprobe e1000e
	sleep 3

	if ip link show "$IFACE" | grep -q "state UP"; then
		reapply_fix
		log "Recupero riuscito con reload del modulo e1000e (fix TSO/GSO/EEE riapplicato)."
	else
		log "ATTENZIONE: reload del modulo non ha ripristinato $IFACE. Potrebbe servire intervento manuale."
	fi
}

log "Avviato, monitoro $IFACE per 'Detected Hardware Unit Hang' nel kernel log."

# -k = solo messaggi kernel, -f = segue in tempo reale, -n0 = non rileggere il passato
journalctl -k -f -n0 --no-pager | while IFS= read -r line; do
	if [[ "$line" == *"$IFACE"*"Detected Hardware Unit Hang"* ]]; then
		recover_interface
	fi
done
