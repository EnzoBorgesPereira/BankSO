#!/bin/bash

LOGFILE="/var/log/config_backup.log"
BACKUPDIR="/var/backups/etc_backups/$(date +%Y-%m-%d_%H-%M-%S)"
LASTBACKUPDIR=$(ls -td /var/backups/etc_backups/*/ | head -1)  # Last backup as reference
RSYNCCOMMAND="rsync"

# Backup function
backup_configs() {
    echo "Debut de la sauvegarde des configurations de /etc" | tee -a "${LOGFILE}"
    mkdir -p "${BACKUPDIR}"
    $RSYNCCOMMAND -aH --compare-dest="${LASTBACKUPDIR}" /etc/ "${BACKUPDIR}" 2>&1 | tee -a "${LOGFILE}"
    echo "Sauvegarde des configurations terminee" | tee -a "${LOGFILE}"
}

# Update function
update_system() {
    echo "Debut de la mise a jour du systeme" | tee -a "${LOGFILE}"
    sudo apt-get update 2>&1 | tee -a "${LOGFILE}"
    echo "Mise a jour de la liste des paquets terminee" | tee -a "${LOGFILE}"
    sudo apt-get upgrade -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y 2>&1 | tee -a "${LOGFILE}"
    echo "Mise a jour du systeme terminee" | tee -a "${LOGFILE}"
}

# Main function
main() {
    echo "===== $(date) =====" | tee -a "${LOGFILE}"

    backup_configs
    update_system

    echo "Script termine" | tee -a "${LOGFILE}"
    echo "=================" | tee -a "${LOGFILE}"
}

# Execute the main function
main

#Don't forget to add execute permission :
#chmod +x /usr/local/bin/update_and_backup.sh

# Auto run at 4 am with "sudo crontab -e"
#0 4 * * * /usr/local/bin/update_and_backup.sh >> /var/log/update_and_backup_cron.log 2>&1