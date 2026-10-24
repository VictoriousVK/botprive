#!/usr/bin/env sh
# Sauvegarde compressée de la base (à lancer depuis ton ordinateur ou un cron).
#   DATABASE_URL="postgres://…" ./scripts/backup-db.sh
set -eu
: "${DATABASE_URL:?DATABASE_URL manquant}"
mkdir -p backups
file="backups/victorious-$(date -u +%Y%m%d-%H%M).sql.gz"
pg_dump --no-owner --no-privileges "$DATABASE_URL" | gzip > "$file"
echo "Sauvegarde créée : $file"
