# Notifiche Proxmox che non arrivano mai — relay Postfix via Gmail

> **Sintomo:** l'email di `root@pam` è configurata (Datacenter → o
> `/etc/pve/user.cfg`), ma non arriva mai nulla — né alert SMART, né backup
> falliti, né test manuali. Risolto e testato su due host Proxmox VE
> (8.4.18 e 8.4.12), agosto 2026.

---

## Causa reale

Il meccanismo di default di Proxmox per le notifiche (target `sendmail` nel
nuovo sistema di notifiche, o le chiamate dirette di `smartd`/`vzdump`
legacy) passa tutto al binario `sendmail`, fornito da **Postfix**. Su
un'installazione Proxmox pulita, **Postfix non ha nessun `relayhost`
configurato**: prova a consegnare direttamente ai server MX di destinazione
(Gmail, Outlook, ecc.), e su una rete residenziale questo fallisce quasi
sempre — porta 25 in uscita bloccata dall'ISP, o il provider di destinazione
rifiuta connessioni da IP residenziali. Il risultato: le email restano
bloccate in coda (`mailq`) per sempre, silenziosamente, e nessuno se ne
accorge finché non serve davvero una notifica.

Conferma dalla documentazione ufficiale Proxmox (capitolo Notifications):
> *"It may be necessary to configure Postfix so that it can deliver mails
> correctly - for example by setting an external mail relay (smart host)"*

## Soluzione: dare a Postfix un relay SMTP esterno

Non serve inventare un sistema di notifiche parallelo (es. un target `smtp`
che bypassa Postfix): basta sistemare Postfix stesso, così **tutto** quello
che già esiste — notifiche Proxmox, `smartd`, backup job legacy — ricomincia
a funzionare insieme, senza toccare nient'altro.

### 1. Prerequisito: App Password (se usi Gmail come relay)

Account Google → Sicurezza → Verifica in due passaggi (deve essere attiva)
→ Password per le app → generane una nuova. **La password normale
dell'account non funziona** per SMTP da programmi terzi.

### 2. Prepara le credenziali

```bash
cd linux/proxmox/postfix-gmail-relay
cp sasl_passwd.example /etc/postfix/sasl_passwd
nano /etc/postfix/sasl_passwd   # sostituisci con le tue credenziali vere
```

Formato del file (una riga per relay):
```
[smtp.gmail.com]:587    tuo-indirizzo@gmail.com:la-tua-app-password
```

### 3. Esegui lo script

```bash
chmod +x configure-postfix-relay.sh
./configure-postfix-relay.sh
```

Lo script (vedi [`configure-postfix-relay.sh`](./configure-postfix-relay.sh)):
- installa `libsasl2-modules` se manca — **gotcha reale riscontrato**: senza
  questo pacchetto Postfix fallisce con `SASL authentication failed... no
  mechanism available`, anche con `sasl_passwd` configurato correttamente.
  Il messaggio d'errore non lo rende ovvio, facile perderci tempo.
- genera l'hash map (`postmap`) e imposta i permessi (`600`, `root:root` —
  il file contiene una password in chiaro)
- configura `relayhost` e i parametri SASL/TLS in `main.cf`
- ricarica Postfix

È idempotente: si può rilanciare senza duplicare righe in `main.cf`.

### 4. Sincronizza il destinatario e testa

Se il server è Proxmox, verifica che `root@pam` abbia un'email valida
(`/etc/pve/user.cfg`, o Datacenter → Permissions → Users), poi testa:

```bash
pvesh create /cluster/notifications/targets/mail-to-root/test
mailq   # deve restare vuota
journalctl -S "-2 min" | grep "postfix/smtp"   # cerca "status=sent"
```

Se non hai Proxmox (solo Postfix su Debian generico):
```bash
echo "test" | mail -s "Test relay" destinatario@esempio.com
```

**Il criterio di successo vero è ricevere l'email**, non solo vedere
`status=sent` nel log — controlla anche nello spam la prima volta (mittente
nuovo).

### 5. Ripulisci la coda vecchia (se c'erano email bloccate da prima)

```bash
mailq                # guarda cosa c'è
postsuper -d ALL      # cancella tutto quello che è in coda
```

---

## Su più host (es. cluster o nodi separati)

Il file `sasl_passwd` (con lo stesso account relay) va replicato su ogni
host che deve mandare notifiche — non è un file condiviso via `/etc/pve/`.
Se usi Proxmox con più nodi indipendenti (non in cluster), verifica anche
che `/etc/pve/notifications.cfg` abbia lo stesso target/matcher `sendmail`
su ciascuno (di solito è già il default builtin — controllalo con
`pvesh get /cluster/notifications/targets`).

Se un host ha già altri target di notifica funzionanti (es. un webhook
verso un'app di notifiche push) **non serve rimuoverli**: il nuovo relay
Postfix e il target `sendmail` coesistono tranquillamente in parallelo con
qualunque altro target/matcher configurato.

---

## Rendere le notifiche riconoscibili (nome server in chiaro)

Con Postfix che funziona, il problema successivo è capire **da quale host**
arriva una notifica — di default il messaggio di test è generico
("Test notification", uguale ovunque) e anche i messaggi reali mostrano solo
l'FQDN tecnico, non sempre facile da riconoscere al volo.

Proxmox permette di sovrascrivere i template email in
`/etc/pve/notification-templates/default/<tipo>-<subject|body>.<txt|html>.hbs`.
Sono per-host (non sincronizzati tra nodi indipendenti), quindi puoi
scriverci direttamente un nome mnemonico (es. `hp-server`, `mini-server`,
qualunque cosa ti aiuti a riconoscerlo subito).

Template pronti in [`templates/`](./templates) — copia, sostituisci
`NOME-SERVER` col nome che vuoi per quell'host specifico, incolla in
`/etc/pve/notification-templates/default/`:

```bash
mkdir -p /etc/pve/notification-templates/default
for f in templates/*.hbs; do
  sed "s/NOME-SERVER/hp-server/g" "$f" > "/etc/pve/notification-templates/default/$(basename "$f")"
done
```
(cambia `hp-server` col nome che vuoi per quell'host)

**Variabili disponibili — gotcha reali riscontrati testando:**
- `{{ fields.hostname }}` e `{{ target }}` sono **generici**, disponibili in
  *qualunque* tipo di notifica, incluso `test`.
- `{{ fqdn }}` **non** è generico: esiste solo per i tipi che lo passano
  esplicitamente (`vzdump`, `package-updates`). Usato dentro il template
  `test-body.txt.hbs` risulta **vuoto**, senza errore — email inviata ma col
  campo bianco. Il tipo `test` ha un contesto molto più limitato degli altri.
- `{{ timestamp }}` da solo **dà errore** (`parameter not found`): è un
  helper che richiede un argomento, es. `{{timestamp fence-timestamp}}` (solo
  nei tipi che passano quel campo specifico, es. `fencing`/`replication`).
  Non serve comunque: ogni email ha già l'header `Date` nativo con
  data/ora, visibile in qualunque client di posta senza doverlo ripetere nel
  corpo.

Testa con lo stesso comando di prima (`pvesh create
/cluster/notifications/targets/mail-to-root/test`) — se un template ha un
errore di sintassi, `pvesh` lo segnala subito in output.

---

## Troubleshooting

| Problema | Causa probabile | Fix |
|---|---|---|
| `SASL authentication failed... no mechanism available` | Manca `libsasl2-modules` | `apt install libsasl2-modules` + `systemctl reload postfix` |
| `Connection refused` / `Network is unreachable` sulla porta 25 | Relay non configurato, Postfix prova la consegna diretta | Esegui questo script |
| `535 5.7.8 Username and Password not accepted` (Gmail) | Password normale invece di App Password, o 2FA non attiva | Genera una App Password |
| Email inviata (`status=sent`) ma non arriva | Finita nello spam, o `mailto`/destinatario sbagliato | Controlla spam; verifica `mailto-user` in `notifications.cfg` |
| Coda piena di vecchi messaggi bloccati | Erano lì da prima del fix, useranno comunque l'indirizzo vecchio | `postsuper -d ALL` dopo aver verificato che il nuovo relay funziona |

---

## Fonti

- [Proxmox VE Notifications — documentazione ufficiale](https://pve.proxmox.com/pve-docs/chapter-notifications.html)
- [K3rn3l-P/utility-scripts](https://github.com/K3rn3l-P/utility-scripts)

---

> Guida curata da [K3rn3l-P](https://github.com/K3rn3l-P)
