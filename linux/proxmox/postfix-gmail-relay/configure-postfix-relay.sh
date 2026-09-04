#!/bin/bash
# configure-postfix-relay.sh
#
# Configures Postfix on a Proxmox host (or Debian in general) to forward mail
# through an external SMTP relay (Gmail by default), instead of attempting
# direct delivery — which almost always fails on residential networks (port 25
# blocked by the ISP, or the destination provider refusing residential IPs).
# This is the most common reason "Proxmox email notifications never arrive":
# the notification configuration isn't missing, a Postfix relay is.
#
# Prerequisite: create /etc/postfix/sasl_passwd (see sasl_passwd.example in
# this folder) with the real credentials BEFORE running this script.
# Gmail needs an App Password (Google Account -> Security -> 2-Step
# Verification -> App passwords) — the normal account password does NOT work
# for SMTP.
#
# Usage:
#   cp sasl_passwd.example /etc/postfix/sasl_passwd
#   nano /etc/postfix/sasl_passwd   # enter the real credentials
#   ./configure-postfix-relay.sh
#
# Idempotent: safe to re-run without duplicating configuration.

set -euo pipefail

SMTP_SERVER="${1:-smtp.gmail.com}"
SMTP_PORT="${2:-587}"
SASL_FILE="/etc/postfix/sasl_passwd"

if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root." >&2
	exit 1
fi

if [[ ! -f "$SASL_FILE" ]]; then
	echo "Error: $SASL_FILE does not exist." >&2
	echo "Copy sasl_passwd.example to $SASL_FILE and enter the real credentials before re-running." >&2
	exit 1
fi

if grep -q "your-app-password" "$SASL_FILE" 2>/dev/null; then
	echo "Error: $SASL_FILE still holds the template placeholder, not real credentials." >&2
	exit 1
fi

# A gotcha found in practice: without this package Postfix fails SASL
# authentication with "no mechanism available", even when sasl_passwd is
# set up correctly. Easy to miss, and not obvious from the error message.
if ! dpkg -s libsasl2-modules >/dev/null 2>&1; then
	echo "Installing libsasl2-modules (required for SMTP SASL authentication)..."
	apt-get update -qq
	apt-get install -y libsasl2-modules
fi

echo "Generating the Postfix hash map from $SASL_FILE..."
chmod 600 "$SASL_FILE"
chown root:root "$SASL_FILE"
postmap "$SASL_FILE"
chmod 600 "${SASL_FILE}.db"
chown root:root "${SASL_FILE}.db"

echo "Configuring the relay in main.cf..."
postconf -e "relayhost = [${SMTP_SERVER}]:${SMTP_PORT}"
postconf -e "smtp_use_tls = yes"
postconf -e "smtp_sasl_auth_enable = yes"
postconf -e "smtp_sasl_security_options = noanonymous"
postconf -e "smtp_sasl_password_maps = hash:${SASL_FILE}"
postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"

systemctl reload postfix

echo
echo "Done. Verify with:"
echo "  postconf -n relayhost"
echo "  pvesh create /cluster/notifications/targets/mail-to-root/test   # if you're on Proxmox"
echo "  mailq   # should stay empty after sending"
echo "  journalctl -S '-2 min' | grep 'postfix/smtp'   # look for 'status=sent'"
