# Proxmox notifications that never arrive — Postfix relay via Gmail

> **Symptom:** `root@pam` has an email address configured (Datacenter → or
> `/etc/pve/user.cfg`), but nothing ever arrives — no SMART alerts, no failed-backup
> notices, not even manual tests. Diagnosed and fixed on two Proxmox VE hosts
> (8.4.18 and 8.4.12), August 2026.

---

## The actual cause

Proxmox's default notification path (the `sendmail` target in the new notification
system, or the legacy direct calls from `smartd`/`vzdump`) hands everything to the
`sendmail` binary, which is provided by **Postfix**. On a clean Proxmox install,
**Postfix has no `relayhost` configured**: it tries to deliver straight to the
destination MX servers (Gmail, Outlook, and so on), and on a residential network that
almost always fails — outbound port 25 blocked by the ISP, or the destination provider
refusing connections from residential IPs. The result: the mail sits in the queue
(`mailq`) forever, silently, and nobody notices until a notification actually matters.

Confirmed by the official Proxmox documentation (Notifications chapter):
> *"It may be necessary to configure Postfix so that it can deliver mails
> correctly - for example by setting an external mail relay (smart host)"*

## The fix: give Postfix an external SMTP relay

There's no need to build a parallel notification system (an `smtp` target that bypasses
Postfix, say): just fix Postfix itself, and **everything** that already exists — Proxmox
notifications, `smartd`, legacy backup jobs — starts working again together, without
touching anything else.

### 1. Prerequisite: an App Password (if you relay through Gmail)

Google account → Security → 2-Step Verification (must be on) → App passwords →
generate a new one. **The normal account password does not work** for SMTP from
third-party programs.

### 2. Prepare the credentials

```bash
cd linux/proxmox/postfix-gmail-relay
cp sasl_passwd.example /etc/postfix/sasl_passwd
nano /etc/postfix/sasl_passwd   # replace with your real credentials
```

File format (one line per relay):
```
[smtp.gmail.com]:587    your-address@gmail.com:your-app-password
```

### 3. Run the script

```bash
chmod +x configure-postfix-relay.sh
./configure-postfix-relay.sh
```

The script (see [`configure-postfix-relay.sh`](./configure-postfix-relay.sh)):
- installs `libsasl2-modules` if it's missing — **a real gotcha**: without that package
  Postfix fails with `SASL authentication failed... no mechanism available`, even when
  `sasl_passwd` is set up correctly. The error message doesn't make that obvious, and
  it's easy to lose time on it.
- builds the hash map (`postmap`) and sets permissions (`600`, `root:root` — the file
  holds a cleartext password)
- configures `relayhost` and the SASL/TLS parameters in `main.cf`
- reloads Postfix

It's idempotent: re-running it won't duplicate lines in `main.cf`.

### 4. Line up the recipient and test

On a Proxmox server, check that `root@pam` has a valid email address
(`/etc/pve/user.cfg`, or Datacenter → Permissions → Users), then test:

```bash
pvesh create /cluster/notifications/targets/mail-to-root/test
mailq   # should stay empty
journalctl -S "-2 min" | grep "postfix/smtp"   # look for "status=sent"
```

Without Proxmox (plain Postfix on Debian):
```bash
echo "test" | mail -s "Test relay" recipient@example.com
```

**The real success criterion is receiving the email**, not just seeing `status=sent` in
the log — check the spam folder the first time too (the sender is new).

### 5. Flush the old queue (if mail was stuck from before)

```bash
mailq                # see what's in there
postsuper -d ALL      # delete everything queued
```

---

## Across multiple hosts (cluster or separate nodes)

The `sasl_passwd` file (with the same relay account) has to be copied to every host that
should send notifications — it isn't shared through `/etc/pve/`. With several independent
Proxmox nodes (not clustered), also check that `/etc/pve/notifications.cfg` has the same
`sendmail` target/matcher on each of them (usually the builtin default — confirm with
`pvesh get /cluster/notifications/targets`).

If a host already has other working notification targets (a webhook to a push-notification
app, for instance), **there's no need to remove them**: the new Postfix relay and the
`sendmail` target coexist quite happily alongside any other target or matcher.

---

## Making notifications recognisable (server name in plain text)

With Postfix working, the next problem is telling **which host** a notification came from
— by default the test message is generic ("Test notification", identical everywhere) and
even real messages show only the technical FQDN, which isn't always easy to place at a
glance.

Proxmox lets you override the email templates in
`/etc/pve/notification-templates/default/<type>-<subject|body>.<txt|html>.hbs`.
They're per-host (not synced between independent nodes), so you can write a memorable
name straight into them (`hp-server`, `mini-server`, whatever you'll recognise instantly).

Ready-made templates are in [`templates/`](./templates) — copy them, replace
`SERVER-NAME` with the name you want for that specific host, and drop them into
`/etc/pve/notification-templates/default/`:

```bash
mkdir -p /etc/pve/notification-templates/default
for f in templates/*.hbs; do
  sed "s/SERVER-NAME/hp-server/g" "$f" > "/etc/pve/notification-templates/default/$(basename "$f")"
done
```
(change `hp-server` to whatever you want for that host)

**Available variables — real gotchas found while testing:**
- `{{ fields.hostname }}` and `{{ target }}` are **generic**, available in *any*
  notification type, `test` included.
- `{{ fqdn }}` is **not** generic: it only exists for the types that pass it explicitly
  (`vzdump`, `package-updates`). Used inside `test-body.txt.hbs` it comes out **empty**,
  with no error — the email is sent with a blank field. The `test` type has a much more
  limited context than the others.
- `{{ timestamp }}` on its own **throws an error** (`parameter not found`): it's a helper
  that needs an argument, e.g. `{{timestamp fence-timestamp}}` (and only in the types that
  pass that particular field, such as `fencing`/`replication`). You don't need it anyway:
  every email already carries a native `Date` header, visible in any mail client without
  repeating it in the body.

Test with the same command as before (`pvesh create
/cluster/notifications/targets/mail-to-root/test`) — if a template has a syntax error,
`pvesh` reports it immediately in its output.

---

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| `SASL authentication failed... no mechanism available` | `libsasl2-modules` missing | `apt install libsasl2-modules` + `systemctl reload postfix` |
| `Connection refused` / `Network is unreachable` on port 25 | No relay configured, Postfix attempts direct delivery | Run this script |
| `535 5.7.8 Username and Password not accepted` (Gmail) | Normal password instead of an App Password, or 2FA not enabled | Generate an App Password |
| Mail sent (`status=sent`) but never arrives | Landed in spam, or wrong `mailto`/recipient | Check spam; verify `mailto-user` in `notifications.cfg` |
| Queue full of old stuck messages | They predate the fix and will still use the old address | `postsuper -d ALL` once the new relay is confirmed working |

---

## Sources

- [Proxmox VE Notifications — official documentation](https://pve.proxmox.com/pve-docs/chapter-notifications.html)
- [K3rn3l-P/sysadmin-field-notes](https://github.com/K3rn3l-P/sysadmin-field-notes)

---

> Guide by [K3rn3l-P](https://github.com/K3rn3l-P)
