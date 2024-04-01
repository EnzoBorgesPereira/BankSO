#!/bin/bash

# SUPPRIMER SI ON A DEJA DES CONTAINERS DE CREES ?
ids=$(pct list | awk 'NR>1 {print $1}')
# lxc-info

for id in $ids; do
    pct stop $id
    pct destroy $id
done

# Nombre de containers à ajouter au node
echo -n "Entrez le nombre de containers "slaves" : "
read NUM_CONTAINERS
echo

# IP de départ des containers 
echo -n "Entrez le dernier bit d'IP du premier container (ne pas chevaucher sur l'IP de la gateway - en .1): "
read IP_START
echo

# Mot de passe pour les conteneurs
echo -n "Entrez le mot de passe pour les conteneurs : "
stty -echo
read CONTAINER_PASSWORD
stty echo
echo

# Vérification du mot de passe
echo -n "Confirmez le mot de passe : "
stty -echo
read CONFIRM_PASSWORD
stty echo
echo
if [ "$CONTAINER_PASSWORD" != "$CONFIRM_PASSWORD" ]; then
    echo "Les mots de passe ne correspondent pas."
    exit 1
fi

# Téléchargement de le template ArchLinux
pveam download local archlinux-base_20230608-1_amd64.tar.zst

# -------------------------------------------

# Création du conteneur master
pct create 300 local:vztmpl/archlinux-base_20230608-1_amd64.tar.zst --ostype debian --hostname master --password $CONTAINER_PASSWORD --storage BankSO-storage --cores 2 --net0 "name=eth0,bridge=vmbr2,tag=10,ip=192.168.10.$((IP_START))/24,gw=192.168.10.1" --memory 512 --rootfs 20
echo "Container master (CT ID 300) créé avec succès."
pct set 300 -features 'nesting=1'
# Démarrer le conteneur
pct start 300

echo "Container master (CT ID 300) démarré avec succès."

# -------------------------------------------

# Création du conteneur CA 
pct create 301 local:vztmpl/archlinux-base_20230608-1_amd64.tar.zst --ostype debian --hostname CA --password $CONTAINER_PASSWORD --storage BankSO-storage --cores 2 --net0 "name=eth0,bridge=vmbr2,tag=10,ip=192.168.10.$((IP_START+1))/24,gw=192.168.10.1" --memory 512
echo "Container CA (CT ID 301) créé avec succès."
pct set 301 -features 'nesting=1'
# Démarrer le conteneur
pct start 301

echo "Container CA (CT ID 301) démarré avec succès."

# -------------------------------------------

# Création du conteneur MongoDB
pct create 302 local:vztmpl/archlinux-base_20230608-1_amd64.tar.zst --ostype debian --hostname MongoDB --password $CONTAINER_PASSWORD --storage BankSO-storage --cores 2 --net0 "name=eth0,bridge=vmbr2,tag=10,ip=192.168.10.$((IP_START+2))/24,gw=192.168.10.1" --memory 512 --rootfs 20
echo "Container MongoDB (CT ID 302) créé avec succès."
pct set 302 -features 'nesting=1'
# Démarrer le conteneur
pct start 302

echo "Container MongoDB (CT ID 302) démarré avec succès."

# -------------------------------------------

i=0
while [ $i -le 2 ] 
do
    # Mise-à-jour pacman
    lxc-attach $((300 + i)) -- rm -fr /etc/pacman.d/gnupg
    lxc-attach $((300 + i)) -- pacman-key --init
    lxc-attach $((300 + i)) -- pacman-key --populate archlinux
    lxc-attach $((300 + i)) -- pacman -Sy --noconfirm archlinux-keyring
    lxc-attach $((300 + i)) -- pacman-key --populate archlinux
    
    lxc-attach $((300 + i)) -- pacman -Suy --noconfirm
    lxc-attach $((300 + i)) -- pacman -S sudo openssh sshpass syslog-ng libmaxminddb librdkafka python redis mongo-c-driver net-snmp libdbi msmtp --noconfirm

    lxc-attach -n $((300+$i)) -- /bin/bash -c 'echo "@version: 4.4
@include "scl.conf"
#
# /etc/syslog-ng/syslog-ng.conf
source s_local {
    system();
    internal();
};
filter f_sudo {
    program("sudo");
};
destination d_remote {
    tcp("192.168.10.10" port(514));
};
log {
    source(s_local);
    filter(f_sudo);
    destination(d_remote);
};" > /etc/syslog-ng/syslog-ng.conf'

    lxc-attach -n $((300 + i)) -- systemctl restart syslog-ng@default.service
    lxc-attach -n $((300 + i)) -- systemctl enable syslog-ng@default.service

    # Création super-utilisateur 
    lxc-attach -n $((300 + i)) -- useradd superuser --create-home --home /home/superuser/ -g wheel
    lxc-attach -n $((300 + i)) -- printf "su\nsu\n" | lxc-attach -n $((300 + i)) -- passwd superuser
    lxc-attach -n $((300 + i)) -- sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL) ALL/g' /etc/sudoers



    i=$(( $i + 1 ))
done

# -------------------------------------------

# MISE EN PLACE DU SERVEUR MONGODB

# Installation de MongoDB
lxc-attach -n 302 -- su superuser -c "echo 'su' | sudo -S pacman -S --needed base-devel git --noconfirm"
lxc-attach -n 302 -- su superuser -c "cd /home/superuser/ && git clone https://aur.archlinux.org/yay.git"
lxc-attach -n 302 -- su superuser -c "cd /home/superuser/yay/ && echo 'su' | sudo -S echo "hey" && makepkg -sri --noconfirm"
lxc-attach -n 302 -- su superuser -c "echo 'su' | sudo -S echo "hey" && yay -S --answerclean Installed --answerdiff Installed --removemake --noconfirm mongodb-bin"

# Démarrage du service MongoDB
lxc-attach -n 302 -- systemctl enable mongodb
lxc-attach -n 302 -- systemctl start mongodb

# -------------------------------------------

# CONFIGURATION DU SERVEUR CA

CA_INFO="/C=FR/ST=IDF/L=Paris/O=BankSO/OU=CA/CN=CAserver"

lxc-attach 301 -- openssl genpkey -algorithm RSA -out ca.key
lxc-attach 301 -- openssl req -new -x509 -key ca.key -out ca.crt -subj $CA_INFO
lxc-attach 301 -- chmod 400 ca.key

# Modifier le fichier sshd_config pour le PermitRootLogin
lxc-attach 301 -- sed -i 's\#PermitRootLogin prohibit-password\PermitRootLogin yes\g' /etc/ssh/sshd_config
lxc-attach 301 -- systemctl restart sshd

# -------------------------------------------

# CONFIGURATION DE SURICATA DANS LE CONTENEUR MASTER

# Installation de Suricata

lxc-attach -n 300 -- su superuser -c "echo 'su' | sudo -S pacman -S --needed base-devel git --noconfirm"
lxc-attach -n 300 -- su superuser -c "cd /home/superuser/ && git clone https://aur.archlinux.org/yay.git"
lxc-attach -n 300 -- su superuser -c "cd /home/superuser/yay/ && echo 'su' | sudo -S echo "hey" && makepkg -sri --noconfirm"
lxc-attach -n 300 -- su superuser -c "echo 'su' | sudo -S echo "hey" && yay -S --answerclean Installed --answerdiff Installed --removemake --noconfirm suricata"

# -------------------------------------------

# Boucle pour ajouter des containers slaves au node
i=1
IP_LIST=""
while [ $i -le $NUM_CONTAINERS ] 
do
    CONTAINER_NAME="slave$i"
    # Attribuer une adresse IP à chaque nœud
    IP_ADDRESS="192.168.10.$((IP_START+i+2))"
    SERVER_INFO="/C=FR/ST=IDF/L=Paris/O=BankSO/OU=CA/CN=slave$i"

    # Création du conteneur
    pct create $((302 + i)) local:vztmpl/archlinux-base_20230608-1_amd64.tar.zst --ostype debian --hostname $CONTAINER_NAME --password $CONTAINER_PASSWORD --storage BankSO-storage --cores 2 --net0 "name=eth0,bridge=vmbr2,tag=10,ip=192.168.10.$((IP_START+2+$i))/24,gw=192.168.10.1" --memory 512
    echo "Container $CONTAINER_NAME (CT ID $((302 + i))) créé avec succès."
    pct set $((302 + i)) -features 'nesting=1'

    # Démarrer le conteneur
    pct start $((302 + i))

    echo "Container $CONTAINER_NAME (CT ID $((302 + i))) démarré avec succès."

    # Mise-à-jour pacman
    lxc-attach $((302 + i)) -- rm -fr /etc/pacman.d/gnupg
    lxc-attach $((302 + i)) -- pacman-key --init
    lxc-attach $((302 + i)) -- pacman-key --populate archlinux
    lxc-attach $((302 + i)) -- pacman -Sy --noconfirm archlinux-keyring
    lxc-attach $((302 + i)) -- pacman-key --populate archlinux
    lxc-attach $((302 + i)) -- pacman -Suy --noconfirm

    # Installation de sudo
    lxc-attach $((302 + i)) -- pacman -S sudo --noconfirm 

    # Installation Nginx
    lxc-attach $((302 + i)) -- pacman -S nginx --noconfirm
    lxc-attach $((302 + i)) -- systemctl enable nginx
    lxc-attach $((302 + i)) -- systemctl start nginx

    # Installation SSHPass
    lxc-attach $((302 + i)) -- pacman -S sshpass --noconfirm
    
    # Configuration du Nginx
    lxc-attach $((302 + i)) -- rm /usr/share/nginx/html/index.html
    lxc-attach $((302 + i)) -- touch /usr/share/nginx/html/index.html
    lxc-attach $((302 + i)) -- /bin/bash -c 'echo "Slave '"$i"'" > /usr/share/nginx/html/index.html'

    # Création de la clé privée et du certificat pour chaque serveur
    lxc-attach $((302 + i)) -- openssl genrsa -out slave$i.key 2048
    lxc-attach $((302 + i)) -- openssl req -new -key slave$i.key -out slave$i.csr --subj $SERVER_INFO
    lxc-attach $((302 + i)) -- sshpass -p proxmox scp -o StrictHostKeyChecking=no slave$i.csr root@192.168.10.$((IP_START+1)):/tmp
    lxc-attach 301 -- openssl x509 -req -in /tmp/slave$i.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out /tmp/slave$i.crt -days 365
    lxc-attach $((302 + i)) -- sshpass -p proxmox sftp -o StrictHostKeyChecking=no root@192.168.10.$((IP_START+1)):/tmp/slave$i.crt /tmp
    lxc-attach $((302 + i)) -- mv /tmp/slave$i.crt /etc/nginx/slave$i.crt
    lxc-attach $((302 + i)) -- mv slave$i.key /etc/nginx/slave$i.key

    lxc-attach $((302 + i)) -- pacman -S sudo openssh sshpass syslog-ng libmaxminddb librdkafka python redis mongo-c-driver net-snmp libdbi msmtp --noconfirm
    
    # Configuration syslog-ng
    lxc-attach $((302 + i)) -- /bin/bash -c 'echo "@version: 4.4
@include "scl.conf"
#
# /etc/syslog-ng/syslog-ng.conf

source s_local {
    system();
    internal();
};

filter f_sudo {
    program("sudo");
};

filter f_nginx {
    program("nginx");
};

destination d_remote {
    tcp("192.168.10.10" port(514));
};

log {
    source(s_local);
    filter(f_sudo);
    destination(d_remote);
};

log { source(s_local); filter(f_nginx); destination(d_remote); };" > /etc/syslog-ng/syslog-ng.conf'
    lxc-attach -n $((302 + i)) -- systemctl restart syslog-ng@default.service
    lxc-attach -n $((302 + i)) -- systemctl enable syslog-ng@default.service

    IP_LIST="$IP_LIST   server $IP_ADDRESS:80;"

    # Création super-utilisateur 
    lxc-attach -n $((302 + i)) -- useradd superuser --create-home --home /home/superuser/ -g wheel
    lxc-attach -n $((302 + i)) -- printf "su\nsu\n" | lxc-attach -n $((302 + i)) -- passwd superuser
    lxc-attach -n $((302 + i)) -- sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL) ALL/g' /etc/sudoers

    i=$(( $i + 1 ))
done

lxc-attach 300 -- pacman -S nginx --noconfirm
lxc-attach 300 -- systemctl enable nginx
lxc-attach 300 -- systemctl start nginx

# -------------------------------------------

# Configuration de la clé privée et du certificat pour le loadbalanceur
lxc-attach 300 -- openssl genrsa -out loadbalancer.key 2048
lxc-attach 300 -- openssl req -new -key loadbalancer.key -out loadbalancer.csr --subj $SERVER_INFO
lxc-attach 300 -- sshpass -p proxmox scp -o StrictHostKeyChecking=no loadbalancer.csr root@192.168.10.$((IP_START+1)):/tmp
lxc-attach 301 -- openssl x509 -req -in /tmp/loadbalancer.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out /tmp/loadbalancer.crt -days 365
lxc-attach 300 -- sshpass -p proxmox sftp -o StrictHostKeyChecking=no root@192.168.10.$((IP_START+1)):/tmp/loadbalancer.crt /tmp
lxc-attach 300 -- mv /tmp/loadbalancer.crt /etc/nginx/loadbalancer.crt
lxc-attach 300 -- mv loadbalancer.key /etc/nginx/loadbalancer.key

# Configuration du load balancing
lxc-attach 300 -- /bin/bash -c 'echo "#user http;
worker_processes  1;

#error_log  logs/error.log;
#error_log  logs/error.log  notice;
#error_log  logs/error.log  info;

#pid        logs/nginx.pid;


events {
    worker_connections  3024;
}


http {
    include       mime.types;
    default_type  application/octet-stream;

    upstream web_servers {
        $IP_LIST
    }
    
    # Configuration du serveur Nginx
    server {
        listen 443 ssl;
        server_name 192.168.10.$((IP_START));

        ssl_certificate /etc/nginx/loadbalancer.crt;
        ssl_certificate_key /etc/nginx/loadbalancer.key;
    
        location / {
            proxy_pass http://web_servers;
        }
    }

    server {
        listen 80;
        server_name 192.168.10.$((IP_START));
        return 301 https://$host$request_uri;
    }
    
    sendfile        on;

    keepalive_timeout  65;
}" > /etc/nginx/nginx.conf'


lxc-attach -n 300 -- /bin/bash -c "cat <<EOF > /etc/nginx/nginx.conf
#user http;
worker_processes  1;
#error_log  logs/error.log;
#error_log  logs/error.log  notice;
#error_log  logs/error.log  info;
#pid        logs/nginx.pid;
events {
    worker_connections  3024;
}
http {
    include       mime.types;
    default_type  application/octet-stream;
    upstream web_servers {
        $IP_LIST
    }
    
    # Configuration du serveur Nginx
    server {
        listen 443 ssl;
        server_name 192.168.10.$IP_START;

        ssl_certificate /etc/nginx/loadbalancer.crt;
        ssl_certificate_key /etc/nginx/loadbalancer.key;
    
        location / {
            proxy_pass http://web_servers;
        }
    }

    server {
        listen 80;
        server_name 192.168.10.$IP_START;
        return 301 https://$host$request_uri;
    }
}
EOF"



lxc-attach 300 -- systemctl restart nginx

# -------------------------------------------

# Configuration des utilisateurs

i=0
CONTAINER_MAX=$((2 + $NUM_CONTAINERS))
while [ $i -le  $CONTAINER_MAX ] 
do
    # Pour forcer le changement de mot de passe
    lxc-attach -n $((300+$i)) -- passwd -e superuser

    # Couper l'accès à root
    lxc-attach -n $((300+$i)) -- passwd -l root

    i=$(( $i + 1 ))
done

echo "Configuration des utilisateurs terminée."
echo "Configuration du cluster et création des containers terminée."
