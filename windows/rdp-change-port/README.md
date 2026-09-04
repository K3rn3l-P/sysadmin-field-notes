# Remote Desktop: hardening and changing the default port

Enabling Windows Remote Desktop properly, then moving it off the default port 3389 — which is the
single most scanned port on the internet for RDP.

- **Index**
  - [Administrator account and password](#administrator-account-and-password)
  - [User setup](#user-setup)
  - [Notes](#notes)
  - [Transferring files over RDP](#transferring-files-over-rdp)
  - [Registry tweak](#registry-tweak)
  - [Changing the default port 3389](#changing-the-default-port-3389)
  - [Links](#links)

---

#### Administrator account and password

- Run > `control userpasswords2`
- Make sure the account you intend to use is an **Administrator**
- The account must have a password set — RDP requires one, and it's the bare minimum for security
- Settings > System > Remote Desktop > enable > "make discoverable" > Show settings

  - Under Private (current profile) > Network discovery: turn on network discovery and automatic
    setup (enable both)

#### User setup

- User accounts > select the users allowed to connect remotely to this PC
- Confirm the account is already listed (e.g. **"Eric already has access"**)
- To add other accounts: Add > Advanced > Find Now > pick the account name at the bottom (e.g.
  Michael) > double click > OK > **reboot the machine**
- Open a command prompt:

```sh
cmd
```

- Find the PC's IP address:

```sh
ipconfig
```

- Open the Remote Desktop Connection app
- Enter the IP of the machine you want to control > Connect > the account's password

---

> #### Notes
>
> - Sometimes the **"More choices"** option for signing in with another account doesn't work. When
>   that happens:
> - Use another account > enter `.\` before the username, with the matching password, e.g. **`.\Eric`**

---

#### Transferring files over RDP

- Open the Remote Desktop Connection app
- Show Options > Local Resources > at the bottom, More > under Drives, tick the disk you want, e.g.
  (C:) > OK > back to General > Connect
- File Explorer > This PC > Redirected drives and folders > pick the disk to copy, create or paste
  files

#### Registry tweak

- `no-rdp-lock.reg` (optional) — sets `fQueryUserConfigFromLocalMachine`, which stops RDP sessions
  from locking up in certain configurations.

#### Changing the default port 3389

- Run `change-rdp-port.bat` (it elevates itself via UAC)
- Use a 4-digit port number higher than the default 3389 (e.g. 3390) — **recommended**
- If the command doesn't take effect, reboot and run the file again as the first thing you do
- Verify it worked: Settings > System > Remote Desktop > Advanced settings > check "Remote Desktop
  port"

> From then on you can only connect by specifying the port:

- Open Remote Desktop Connection > under Computer, enter `IP:port` (e.g. `192.168.1.20:3390`) >
  Connect

> **Note:** changing the port is obscurity, not security. Combine it with a strong password, and
> ideally don't expose RDP to the internet at all — put it behind a VPN.

---

### Links

- [Change the listening port for Remote Desktop — Microsoft Learn](https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/clients/change-listening-port)

---

[🔼 Back to top](#remote-desktop-hardening-and-changing-the-default-port)
