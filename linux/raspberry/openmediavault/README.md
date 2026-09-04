# OpenMediaVault on Raspberry Pi — install and setup

- **Index**
  - [Connect over SSH with the user and password you set](#connect-over-ssh-with-the-user-and-password-you-set)
    - [Link](#link)
  - [Settings](#settings)
  - [Install DLNA, NFS and SMB (optional)](#install-dlna-nfs-and-smb-optional)
    - [Link](#link-1)
  - [OpenMediaVault Gmail notifications configuration](#openmediavault-gmail-notifications-configuration)
  - [Enable Docker and Portainer](#enable-docker-and-portainer)
    - [Link](#link-2)
  - [OpenMediaVault SSH certificates](#openmediavault-ssh-certificates)
    - [Link](#link-3)
  - [WireGuard on OpenMediaVault](#wireguard-on-openmediavault)
    - [Link](#link-4)
  - [Hot backup script with crontab, gz, log file and OMV message log](#hot-backup-script-with-crontab-gz-log-file-and-omv-message-log)
    - [Link](#link-5)
  - [Update Portainer image](#update-portainer-image)
  - [Update Docker image in Portainer](#update-docker-image-in-portainer)

---

**Install RaspbianOS (32/64bit) Raspberry_pi_Imager.exe and select your setting for enter in ssh (usr/passw) + hostname**

> - **Unplug all USB port!!!Important!! and power on**

## Connect over SSH with the user and password you set

```sh
sudo raspi-config
```

**Select localization option and set all option for your language and location, select update and finish**

```sh
sudo reboot
sudo apt update -y
sudo apt upgrade -y
sudo rm -f /etc/systemd/network/99-default.link
sudo adduser <youruser> ssh
sudo wget -O - https://github.com/OpenMediaVault-Plugin-Developers/installScript/raw/master/install | sudo bash
```

**Enter in the browser and push [http://NAS/](http://NAS/)**

- Default password Open Media Vault:
  - Usr:admin
  - Passw:openmediavault

---

### Link

- [https://github.com/OpenMediaVault-Plugin-Developers/installScript](https://github.com/OpenMediaVault-Plugin-Developers/installScript)

---

## Settings

- System > Workbench > set: automatic disconnect to 60 min (Save and apply) #Optional
- User setting (up to right) and change password if you want
- Power management > setting > monitoring = off (Save and apply) #Optional (More power from cpu raspberry)
- Monitoring> enable (Save and apply)
- Scheduled Tasks #Optional (Auto-update and auto-reboot of Open Media Vault)
  omv-upgrade && reboot
- Update Management > find and install update!

---

## Install DLNA, NFS and SMB (optional)

**Save and apply if required**

- Plugins > find > extrasorg > install if not installed & find again > dlna > install #Optional
- User > user > create > Set name and password (Save and apply)
- Shutdown raspberry > unplug power cable and plug in your hhd/ssd, plug in power cable for start NAS!
- Enter in the browser and push [http://NAS/](http://NAS/)
- Storage > File System > mount your hdd/ssd or more..  (Save and apply)
- Shared Folders > Add > (set name if you want) > File system (your hdd/ssd) > Relative path > / > Administrator:write/read, Users:write/read, Other:denied access (Save and apply)
- Select hdd/ssd > privileges > select user created on step 2 > Read/Write (Save and apply)
- Service > DLNA > Setting > Enable (Save and apply)
- Service > DLNA > Shares > Select your hdd/ssd and all media (Save and apply)
- Service > NFS > setting > enable (Save and apply)
- Service > NFS > Shares > add > select your hdd/ssd > Client ex:192.168.1.1/24 > privilege read/write (Save and apply)
- Service > SMB > Setting > enable (Save and apply)
- Service > SMB > Shares > add > select your hdd/ssd > Let's make sure it's turned on: Navigable, ACL inheritance, Inherited permissions, Extended attributes, Stores DOS attributes (Save and apply)
- Test in your computer, smartphone, tv!

---

### Link

- [https://www.youtube.com/watch?v=3sLbC7aR5rQ&list=PLb5v6vFZKig48gV5GHsSA_JRcI_M_8Pwn&index=2](https://www.youtube.com/watch?v=3sLbC7aR5rQ&list=PLb5v6vFZKig48gV5GHsSA_JRcI_M_8Pwn&index=2)

---

## OpenMediaVault Gmail notifications configuration

- System > Notification > Setting
  - Server SMTP: smtp.gmail.com
  - Port SMTP: 465
  - Encryption mode: SSL/TLS (if one day the two options are divided, it will be necessary to select SSL)
  - Email sender: the GMAIL address authorized to access External APPs
  - Enable required authentication
  - Username: copy the email address of email sender
  - Password: Enter your GMAIL "App Password". (Sign in to your Google Account > Security > App Passwords)
  - Primary Email: enter the email address where you want to receive all open media vault (OMV) notifications
  - Secondary email: (optional option) enter another email address where you want to receive Open Media Vault (OMV) notifications
- (Save and apply)
- Test send email!
- System > Notification > Notification > if you want (I only recommend Software Update and Process Monitoring enabled "anti spam")
- ##Attention!!##
- Sign in to your Google Account > Security > App Passwords

---

## Enable Docker and Portainer

- System > omv-extras > portainer > install
- System > omv-extras > portainer > Open Web

**Exposed ports in the container view redirect me to 0.0.0.0. What can I do?**

There are two ways you can fix this.
Method 1: Via the Portainer UI (recommended)

```
From the menu select Environments.
Select the environment. (local)
In the Public IP field, enter the host IP.
Click Update environment.
```

**Method 2: Via the CLI**

So that Portainer can redirect to your Docker host IP address (not the 0.0.0.0 address), you'll need to:

```
Change the configuration of your Docker daemon by adding the --ip option.
Restart the Docker daemon so that the changes take effect.
```

---

### Link

- [https://portal.portainer.io/knowledge/exposed-ports-in-the-container-view-redirect-me-to-0.0.0.0-what-can-i-do](https://portal.portainer.io/knowledge/exposed-ports-in-the-container-view-redirect-me-to-0.0.0.0-what-can-i-do)
- [http://hub.docker.com/](http://hub.docker.com/)

---

## OpenMediaVault SSH certificates

- on OMV > certificates > ssh > create > select the certificate > copy (top)
- inside "Host" write the IP of your Raspberry
- Inside Port leave 22
- Inside User Name write ssh user (Ex: pi)
- Inside Password, type your password to access the user with Putty

**Entrare nella macchina ssh in Putty**

```sh
cd /etc/ssh
ls -ltr
sudo chmod 777 "file" [Es: openmediavault-0dxxx-xxxx-xxxx  (NO!! .PUB!!!)]
```

**nel CMD (prompt dei comandi)**

```sh
cd Desktop
scp pi@"ip_raspberry":/etc/ssh/"file" . [Es: scp pi@10.0.0.30:/etc/ssh/openmediavault-0dxxx-xxxx-xxxx .] !!ATTENTION TO .!!!
```

**Su Putty**

```sh
sudo chmod 600 "file" [Es: openmediavault-0dxxx-xxxx-xxxx  (NO!! .PUB!!!)]
```

**Cercare/aprire Putty gen**

- Conversions > Import key > Desktop "file" [Es: openmediavault-0dxxx-xxxx-xxxx] > Save private key > sel path

**Su Putty**

Category:
SSH > Auth > Credentials > Private key file for authentication > Browse "file" > Session > Hostname pi@10.0.0.30 > Save & Open

---

### Link

- [https://putty.org/](https://putty.org/)

---

## WireGuard on OpenMediaVault

**In this selection, Wireguard is installed on the base machine, for the best performance of vpn..**

**Open port 51820 on your router for expose and access on wireguard on remote wan!!**

- On your "putty"

```sh
sudo apt install curl
sudo apt install vim
curl -L https://install.pivpn.io | bash
```

- In the DNS Provider dialog, select the fast DNS provider like CloudFlare, Google etc.
  This ensures a fast and not crappy VPN connection.
- In the next "Public IP or DNS" dialog box select the DNS Entry item if you have NO-IP.com, DuckDNS etc.. if instead you have a public ip by default, select that.. if you don't know what I'm talking about, set up a DNS Entry.. Google is your friend.

> - Ex: "mydns".duckdns.org

- Confirm and Reboot.

```sh
pivpn help
pivpn -a
```

- The file configuration is in:

```sh
cd /home/pi/configs
ls
hostname -I
```

- copy your ip address ex: 192.168.1.29

```sh
vim "file".config
```

**In "Allowed IPs"**

- Set your subnet IP and remove the unnecessary part of IPv6, follow suit in this sample string:

> - AllowedIPs=192.168.1.0/24

- Open your Wireguard app smartphone and scan QR code

```sh
pivpn -qr
```

- Or download the app for your pc's and copy the .conf file..

```sh
cd Desktop
scp pi@"ip_raspberry":/home/pi/configs/file.conf .
```

---

### Link

- [https://www.wireguard.com/install/](https://www.wireguard.com/install/)
- [https://docs.pivpn.io/wireguard/](https://docs.pivpn.io/wireguard/)

---

## Hot backup script with crontab, gz, log file and OMV message log

- **Prerequisites**

```sh
cd /home/pi
```

```sh
sudo apt install -y pv
```

```sh
sudo apt install -y vim
```

```sh
sudo apt install -y gzip
```

- View installed disks/sdcards

```sh
lsblk -d
```

---

[ ] **Commands in VIM**

* [ ] **dd** = deletion of the entire current line
* [ ] **o** = create an empty line below the cursor in text entry mode
* [ ] **shift+ins** = paste from Windows clipboard memory
* [ ] **:wq** = write and exit

---

**configure the backup script**

- Add SD path ex:
  - SD=mmcblk0) 
- and driver_backup ex:
  - drive_backup=/srv/dev-disk-by-uuid-xxxxxxxxxx) 
- in backup_script file [#variables](https://github.com/K3rn3l-P/Wis-Lix_Tools/blob/2291fe6433f5574b67a2847ab9b775e271094c03/Raspberry/OMV/backup_script.sh#L18)

```sh
SD=mmcblk0
drive_backup=/srv/dev-disk-by-uuid-xxxxxxxxxx
```

```sh
vim backup_script.sh
```

- Copy and paste all the text of the backup_script file you just edited into vim (Lshift + ins)

```sh
chmod 777 backup_script.sh
```

- Then press ESC > insert :wq > press enter

```sh
sudo chmod 660 /var/log/messages
```

```sh
select-editor
```

> 2. /usr/bin/vim.basic

```sh
crontab -e
```

- Select letter o #press the letter "o" on your keyboard
- Lshift + ins #copy and paste
- Then press ESC > insert :wq > press enter

> 00 04 * * * /home/pi/backup_script.sh > /tmp/backup_script.log 2>&1

- The hours is set 04:00AM, if you want change this!
- When you tried to backup, go to openmediavault webpage > Diagnostics > system logs > logs > select Messages in the drop down menu, the logs will display the backup process done!
- **The file will be in the backup folder in the location you chose.**
  **To flash the .gz "image" to a microSD you will need to unzip the .gz file > open your program ex:[https://sourceforge.net/projects/win32diskimager/](https://sourceforge.net/projects/win32diskimager/) > select the SD card > the image file and change the type of file to display in **"all files"** (otherwise it won't find it) > Write > insert SD into Raspberry and turn it on!
  
  **> Premise:**
- **Let's check portainer, because this is a hot backup, so we will have to do an a-doc restore because some environment variables some pointers, in this case portainer, are not saved correctly, so when the restore is done, portainer doesn't work.**
  **Restore portainer without losing any data**
  **Go on your portainer web page, you will immediately notice that the containers are missing etc.. this is a portainer problem, but the docker works perfectly..**

> **let's go fix it..**

- **Go to OMV webpage > System > omv-extras > Portainer > click on Remove data > yes**
- **Go in System > omv-extras > Portainer > Install**
- **Go in your Portainer website and have fun!**

---

### Link
- [https://www.balena.io/etcher](https://www.balena.io/etcher)
- [https://crontab.guru/](https://crontab.guru/)
---

## Update Portainer image

- Open your web of portainer
- Go to Images > in Image list select your name of image Portainer > click on **Pull from registry** on top > click on ok and reload page if finisced to download (F5)
- **remove unused images if any** > close the web page of portainer
- Go to webpage of OpenMediaVault > System > omv-extras > Portainer > click on Install
- On finisced download go on website of Portainer, **It should now be updated**
- Remember to **remove unused images if any**

> This is the clean way to do a portainer update. But if you want to risk update errors, and other possible bugs, you can just use the **Install** button on OpenMediaVault > System > omv-extras > Portainer > click on Install
> At your own risk.

## Update Docker image in Portainer

- **There are two different upgrade possibilities and they are divided by two modes:**

> NB:

1. **Container**

* Click on your Container name stop the container and click on **Recreate** on top, select **Pull latest Image and click on **Recreate**.

2. **Stacks**

* Select your **Container** and stop the container
* Reselect your Container and click on **Remove**

> NB:
> **If you used your external hdd/ssd (ex:/srv/dev-disk-by-uuid-xxxxxxxxx) to save data, you won't lose any data/configuration on the container once it is recreated!**
> **It would be advisable to select **Automatically remove non-persistent volumes**, to do a clean update, but you must be sure that your hdd/ssd containing the container data is **online and working******
> **Otherwise you could **lose all your container data****

* **When the removal process is finished, go to Images > **remove unused images if any****
* **Go to **Stacks** and click on your stacks name > select **Edit** at the top > scroll down and press **Update the stacks** > select **Re-pull Image and redeploy****** ****> ok and wait until the update is finished**

---

[🔼 Back to top](#openmediavault-install)

