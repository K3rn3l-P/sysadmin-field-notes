#!/bin/bash

date +"%F %H:%M:%S"

running=$(pgrep -c backup_script)

if [[ $running -gt 1 ]];then
        echo "script already running. Exiting."
        echo "$(date +"%b %-d %X") blank BACKUP: backup script already running. Exiting." >> /var/log/messages
        exit
fi

echo "starting the script..."
echo "$(date +"%b %-d %X") blank BACKUP: starting the script..." >> /var/log/messages

data=$(date +%Y%m%d)

#variables

SD=
drive_backup=

#end variables

mkdir -p $drive_backup/backup/
cd $drive_backup/backup/

if [[ ! -f bkp_$data.gz ]];then
        echo "starting the backup..."
        echo "$(date +"%b %-d %X") blank BACKUP: starting the backup..." >> /var/log/messages
        sudo dd bs=4M if=/dev/$SD | pv | gzip > $drive_backup/backup/bkp_$data.gz
        if [[ $? -eq 0 ]];then
                echo "backup created successfully. Removing older backups, keeping the last 2"
                echo "$(date +"%b %-d %X") blank BACKUP: backup created successfully. Removing older backups, keeping the last 2" >> /var/log/messages
                ls -ltr bkp*.gz | head -n -2 | awk '{print $NF}' | xargs rm -f --
        else
                echo "WARNING! The backup failed. Old backups are kept, to be safe."
                echo "$(date +"%b %-d %X") blank BACKUP: WARNING! The backup failed. Old backups are kept, to be safe." >> /var/log/messages
        fi
else
        echo "today's backup already exists. Exiting."
        echo "$(date +"%b %-d %X") blank BACKUP: today's backup already exists. Exiting." >> /var/log/messages
fi

echo "script finished"
echo "$(date +"%b %-d %X") blank BACKUP: script finished" >> /var/log/messages
mv -f /tmp/backup_script.log $drive_backup/backup/

exit
