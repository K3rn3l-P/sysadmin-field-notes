#!/bin/bash
# configure-postfix-relay.sh
#
# Configura Postfix su un host Proxmox (o Debian in generale) per inoltrare
# la posta tramite un relay SMTP esterno (default: Gmail), invece di provare
# la consegna diretta — che su reti residenziali fallisce quasi sempre
# (porta 25 bloccata dall'ISP, o il provider di destinazione rifiuta IP
# residenziali). Questo è il motivo più comune per cui "le notifiche email
# di Proxmox non arrivano mai": non manca la configurazione delle notifiche,
# manca un relay su Postfix.
#
# Prerequisito: crea /etc/postfix/sasl_passwd (vedi sasl_passwd.example in
# questa cartella) con le credenziali reali PRIMA di lanciare questo script.
# Per Gmail serve una App Password (Account Google -> Sicurezza -> Verifica
# in due passaggi -> Password per le app) — la password normale dell'account
# NON funziona per SMTP.
#
# Uso:
#   cp sasl_passwd.example /etc/postfix/sasl_passwd
#   nano /etc/postfix/sasl_passwd   # inserisci le credenziali vere
#   ./configure-postfix-relay.sh
#
# Idempotente: si può rilanciare senza duplicare configurazioni.

set -euo pipefail

SMTP_SERVER="${1:-smtp.gmail.com}"
SMTP_PORT="${2:-587}"
SASL_FILE="/etc/postfix/sasl_passwd"

if [[ $EUID -ne 0 ]]; then
	echo "Questo script va eseguito come root." >&2
	exit 1
fi

if [[ ! -f "$SASL_FILE" ]]; then
	echo "Errore: $SASL_FILE non esiste." >&2
	echo "Copia sasl_passwd.example in $SASL_FILE e inserisci le credenziali vere prima di rilanciare." >&2
	exit 1
fi

if grep -q "your-app-password" "$SASL_FILE" 2>/dev/null; then
	echo "Errore: $SASL_FILE contiene ancora il placeholder del template, non le credenziali vere." >&2
	exit 1
fi

# Gotcha riscontrato in pratica: senza questo pacchetto Postfix fallisce
# l'autenticazione SASL con "no mechanism available", anche con
# sasl_passwd configurato correttamente. Facile da perdere, non ovvio
# dal messaggio d'errore.
if ! dpkg -s libsasl2-modules >/dev/null 2>&1; then
	echo "Installo libsasl2-modules (necessario per l'autenticazione SASL SMTP)..."
	apt-get update -qq
	apt-get install -y libsasl2-modules
fi

echo "Genero l'hash map di Postfix da $SASL_FILE..."
chmod 600 "$SASL_FILE"
chown root:root "$SASL_FILE"
postmap "$SASL_FILE"
chmod 600 "${SASL_FILE}.db"
chown root:root "${SASL_FILE}.db"

echo "Configuro il relay in main.cf..."
postconf -e "relayhost = [${SMTP_SERVER}]:${SMTP_PORT}"
postconf -e "smtp_use_tls = yes"
postconf -e "smtp_sasl_auth_enable = yes"
postconf -e "smtp_sasl_security_options = noanonymous"
postconf -e "smtp_sasl_password_maps = hash:${SASL_FILE}"
postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"

systemctl reload postfix

echo
echo "Fatto. Verifica con:"
echo "  postconf -n relayhost"
echo "  pvesh create /cluster/notifications/targets/mail-to-root/test   # se sei su Proxmox"
echo "  mailq   # deve restare vuota dopo l'invio"
echo "  journalctl -S '-2 min' | grep 'postfix/smtp'   # cerca 'status=sent'"
