#!/bin/bash

# Variables
DB_NAME="DB"

# Connexion à la base de données MongoDB et opérations
mongosh <<MONGO_SCRIPT
use $DB_NAME
db.createCollection("users")
db.users.insertMany([
  {
    "name": "John Doe",
    "email": "john@example.com",
    "created_at": new Date()
  },
  {
    "name": "Jane Smith",
    "email": "jane@example.com",
    "created_at": new Date()
  }
])
MONGO_SCRIPT

echo "La base de données MongoDB '$DB_NAME' avec la collection 'users' a été créée avec succès."
