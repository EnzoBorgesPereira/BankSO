#!/bin/bash

DATE=$(date '+%Y-%m-%d_%H-%M-%S')

echo -n "Entrez le nom de la base de donnee : "
read DB_NAME
echo

echo -n "Entrez le chemin de l'archive : "
read path
echo


# Créer le dossier de sauvegarde s'il n'existe pas
mkdir -p "$path"

# Sauvegarde de la base de données
mongodump --db "$DB_NAME" --out "$path/$DB_NAME-$DATE"


# restaurer les données
#mongorestore --db DB --dir chemin/du/fichier/bjon
