# Chocolatey: install and bulk upgrades

Field notes for setting up the Chocolatey package manager on Windows and keeping packages current.
The canonical instructions live in the official docs, linked below — what follows is the short
path plus the bits worth remembering.

## Requirements

- Windows 7+ / Windows Server 2003+
- PowerShell v2+
- .NET Framework 4+ (the installer pulls in 4.0 if it's missing)

No Visual Studio required: once you have `choco.exe`, you're set.

## Install

Run an **administrative shell** first (a non-admin install is possible, see the docs).

From `cmd`:

```
@"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -InputFormat None -ExecutionPolicy Bypass -Command "iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))" && SET "PATH=%PATH%;%ALLUSERSPROFILE%\chocolatey\bin"
```

From PowerShell there's one extra step: `Get-ExecutionPolicy` must not return `Restricted`. Use
`Set-ExecutionPolicy Bypass -Scope Process` (per-session, the safer choice) or `AllSigned`.

```
Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
```

Check it worked with `choco` or `choco -?`.

## Chocolatey GUI

```
choco install chocolateygui
choco upgrade chocolateygui
```

## Upgrading everything at once

[`upgrade-choco-packages.ps1`](./upgrade-choco-packages.ps1) is a one-liner:

```powershell
choco upgrade all -y
```

Worth scheduling, but read what it plans to do first: `choco outdated` lists the pending upgrades
without applying them.

## Sources

- [Chocolatey installation docs](https://docs.chocolatey.org/en-us/choco/setup)
- [Getting started](https://docs.chocolatey.org/en-us/getting-started)

The install commands above are quoted from the official Chocolatey documentation.
