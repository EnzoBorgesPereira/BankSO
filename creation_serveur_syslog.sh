#!/bin/bash

# Creation du serveur syslog
pct create 510 local:vztmpl/archlinux-base_20230608-1_amd64.tar.zst --ostype debian --hostname Syslog --password proxmox --storage BankSO-storage --cores 2 --net0 "name=eth0,bridge=vmbr2,tag=10,ip=192.168.10.10/24,gw=192.168.10.1" --memory 512 --rootfs 20
echo "Container CA (CT ID 510) créé avec succès."
pct set 510 -features 'nesting=1'
pct start 510
echo "Container CA (CT ID 510) démarré avec succès."


# Mise-à-jour pacman
lxc-attach 510 -- rm -fr /etc/pacman.d/gnupg
lxc-attach 510 -- pacman-key --init
lxc-attach 510 -- pacman-key --populate archlinux
lxc-attach 510 -- pacman -Sy --noconfirm archlinux-keyring
lxc-attach 510 -- pacman-key --populate archlinux

lxc-attach 510 -- pacman -Suy --noconfirm
lxc-attach 510 -- pacman -S sudo --noconfirm
lxc-attach 510 -- pacman -S openssh --noconfirm

# Création super-utilisateur 
lxc-attach -n 510 -- useradd superuser --create-home --home /home/superuser/ -g wheel
lxc-attach -n 510 -- printf "su\nsu\n" | lxc-attach -n 510 -- passwd superuser
lxc-attach -n 510 -- sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL) ALL/g' /etc/sudoers

# Installation de syslog-ng
lxc-attach -n 510 -- pacman -S syslog-ng --noconfirm
lxc-attach -n 510 -- pacman -S libmaxminddb librdkafka python redis mongo-c-driver net-snmp libdbi msmtp --noconfirm    
lxc-attach -n 510 -- systemctl restart syslog-ng@default.service
lxc-attach -n 510 -- systemctl enable syslog-ng@default.service

# Préparation des logs
lxc-attach -n 510 -- touch /var/log/nginx.log
lxc-attach -n 510 -- touch /var/log/sudo.log

# Configuration de syslog-ng
lxc-attach -n 510 -- /bin/bash -c 'echo "@version: 4.4
@include \"scl.conf\"

source s_net {
    tcp(ip(0.0.0.0) port(514));
    udp(ip(0.0.0.0) port(514));
};

destination d_sudo {
    file(\"/var/log/sudo.log\");
};

filter f_sudo {
    facility(auth) and program(sudo);
};

log {
    source(s_net);
    filter(f_sudo);
    destination(d_sudo);
};

destination d_nginx {
    file(\"/var/log/nginx.log\");
};

filter f_nginx {
    program(\"nginx\");
};

log { source(s_net); filter(f_nginx); destination(d_nginx); };" > /etc/syslog-ng/syslog-ng.conf'

lxc-attach -n 510 -- systemctl enable syslog-ng@default.service
lxc-attach -n 510 -- systemctl restart syslog-ng@default.service

# Pour forcer le changement de mot de passe
lxc-attach -n 510 -- passwd -e superuser

# Couper l'accès à root
lxc-attach -n 510 -- passwd -l root
