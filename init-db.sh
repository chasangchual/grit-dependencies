#!/bin/bash
set -e

# If AUTHENTIK_DB is not set, default to 'authentik' 
# or exit with an error so you don't get the "" error.
: "${AUTHENTIK_DB:=authentik}"

# 1. Create the database if it doesn't exist
# We use " " around the db name in the SELECT to handle special characters
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" <<-EOSQL
    SELECT 'CREATE DATABASE "$AUTHENTIK_DB"'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$AUTHENTIK_DB') \gexec
EOSQL

# 2. Install extension in the primary/default database
# Note: Extensions usually require superuser privileges
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS vector;
EOSQL

# 3. Install extension in the newly created Authentik database
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$AUTHENTIK_DB" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS vector;
EOSQL
