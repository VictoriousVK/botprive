#!/bin/sh
# Rôle applicatif sans SUPERUSER ni BYPASSRLS : la row-level security le contraint.
set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<SQL
CREATE ROLE alphaedge LOGIN PASSWORD '${APP_DB_PASSWORD}' NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB;
CREATE DATABASE alphaedge OWNER alphaedge;
SQL
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname alphaedge -c "CREATE EXTENSION IF NOT EXISTS vector;"
