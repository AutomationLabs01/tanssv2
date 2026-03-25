#!/usr/bin/env bash
# =============================================================================
# backup-db.sh – PostgreSQL-Backup für TANSS RAG Stack
# =============================================================================
# Erstellt:
#   - pg_dump der gesamten Datenbank (komprimiert, verschlüsselt)
#   - Nur-angebote_vectors-Export (für einfache RAG-Wiederherstellung)
#   - Aufräumen alter Backups (> RETENTION_DAYS Tage)
#
# Verwendung:
#   ./scripts/backup-db.sh                  # Vollbackup
#   ./scripts/backup-db.sh --vectors-only   # Nur angebote_vectors
#   ./scripts/backup-db.sh --restore FILE   # Wiederherstellen
#
# Cron (täglich 3 Uhr):
#   0 3 * * * /pfad/zu/scripts/backup-db.sh >> /var/log/tanss-backup.log 2>&1
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$DOCKER_DIR/.env"

# Backup-Konfiguration
BACKUP_DIR="${BACKUP_DIR:-$DOCKER_DIR/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Farben
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${GREEN}INFO${NC}  $*"; }
warn()  { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${YELLOW}WARN${NC}  $*"; }
error() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${RED}ERROR${NC} $*"; exit 1; }

# ---------------------------------------------------------------------------
# Umgebungsvariablen laden
# ---------------------------------------------------------------------------
if [[ -f "$ENV_FILE" ]]; then
  # Nur relevante Variablen laden (kein Source – Sicherheit!)
  POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
  POSTGRES_PORT="${POSTGRES_PORT:-54322}"  # Dev: Host-Port; Prod: über Docker exec
  POSTGRES_DB=$(grep "^POSTGRES_DB=" "$ENV_FILE" | cut -d= -f2- | tr -d '"')
  POSTGRES_USER=$(grep "^POSTGRES_USER=" "$ENV_FILE" | cut -d= -f2- | tr -d '"')
  POSTGRES_PASSWORD=$(grep "^POSTGRES_PASSWORD=" "$ENV_FILE" | cut -d= -f2- | tr -d '"')
  BACKUP_ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY:-}"
else
  error ".env nicht gefunden: $ENV_FILE"
fi

POSTGRES_DB="${POSTGRES_DB:-postgres}"
POSTGRES_USER="${POSTGRES_USER:-supabase_admin}"

# ---------------------------------------------------------------------------
# Modus bestimmen
# ---------------------------------------------------------------------------
MODE="full"
RESTORE_FILE=""
case "${1:-}" in
  --vectors-only) MODE="vectors" ;;
  --restore)      MODE="restore"; RESTORE_FILE="${2:-}"; [[ -z "$RESTORE_FILE" ]] && error "--restore benötigt einen Dateipfad" ;;
esac

# ---------------------------------------------------------------------------
# Backup-Verzeichnis
# ---------------------------------------------------------------------------
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

# ---------------------------------------------------------------------------
# pg_dump über Docker exec (kein direkter Netzwerkzugriff nötig)
# ---------------------------------------------------------------------------
run_pg_dump() {
  local extra_args=("$@")
  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" tanss-postgres \
    pg_dump \
      --username="$POSTGRES_USER" \
      --dbname="$POSTGRES_DB" \
      --no-password \
      --verbose \
      --format=custom \
      --compress=9 \
      "${extra_args[@]}"
}

# ---------------------------------------------------------------------------
# Vollbackup
# ---------------------------------------------------------------------------
if [[ "$MODE" == "full" ]]; then
  BACKUP_FILE="$BACKUP_DIR/full_${TIMESTAMP}.pgdump"
  info "Starte Vollbackup → $BACKUP_FILE"

  run_pg_dump > "$BACKUP_FILE"

  # Optional: Verschlüsselung mit OpenSSL (wenn Key gesetzt)
  if [[ -n "$BACKUP_ENCRYPTION_KEY" ]]; then
    openssl enc -aes-256-cbc -pbkdf2 -iter 100000 \
      -pass "pass:$BACKUP_ENCRYPTION_KEY" \
      -in "$BACKUP_FILE" -out "${BACKUP_FILE}.enc"
    rm "$BACKUP_FILE"
    BACKUP_FILE="${BACKUP_FILE}.enc"
    info "Backup verschlüsselt: $BACKUP_FILE"
  fi

  SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
  info "Vollbackup abgeschlossen: $BACKUP_FILE ($SIZE)"
fi

# ---------------------------------------------------------------------------
# Nur angebote_vectors (schnell, für RAG-Wiederherstellung)
# ---------------------------------------------------------------------------
if [[ "$MODE" == "vectors" || "$MODE" == "full" ]]; then
  VECTORS_FILE="$BACKUP_DIR/vectors_${TIMESTAMP}.pgdump"
  info "Exportiere angebote_vectors → $VECTORS_FILE"

  run_pg_dump --table=public.angebote_vectors > "$VECTORS_FILE"

  SIZE=$(du -sh "$VECTORS_FILE" | cut -f1)
  info "Vectors-Backup abgeschlossen: $VECTORS_FILE ($SIZE)"
fi

# ---------------------------------------------------------------------------
# Wiederherstellen
# ---------------------------------------------------------------------------
if [[ "$MODE" == "restore" ]]; then
  [[ -f "$RESTORE_FILE" ]] || error "Datei nicht gefunden: $RESTORE_FILE"
  warn "ACHTUNG: Stellt Datenbank aus $RESTORE_FILE wieder her!"
  warn "Drücke ENTER zum Fortfahren oder Ctrl+C zum Abbrechen..."
  read -r

  # Entschlüsseln falls nötig
  if [[ "$RESTORE_FILE" == *.enc ]]; then
    [[ -n "$BACKUP_ENCRYPTION_KEY" ]] || error "BACKUP_ENCRYPTION_KEY nicht gesetzt für verschlüsseltes Backup"
    DECRYPTED_FILE="${RESTORE_FILE%.enc}.dec"
    openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
      -pass "pass:$BACKUP_ENCRYPTION_KEY" \
      -in "$RESTORE_FILE" -out "$DECRYPTED_FILE"
    RESTORE_FILE="$DECRYPTED_FILE"
  fi

  docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" tanss-postgres \
    pg_restore \
      --username="$POSTGRES_USER" \
      --dbname="$POSTGRES_DB" \
      --no-password \
      --verbose \
      --clean \
      --if-exists \
      < "$RESTORE_FILE"

  [[ -f "${RESTORE_FILE%.enc}.dec" ]] && rm "${RESTORE_FILE%.enc}.dec"
  info "Wiederherstellung abgeschlossen."
fi

# ---------------------------------------------------------------------------
# Alte Backups aufräumen
# ---------------------------------------------------------------------------
if [[ "$MODE" != "restore" ]]; then
  info "Lösche Backups älter als $RETENTION_DAYS Tage..."
  find "$BACKUP_DIR" -name "*.pgdump" -o -name "*.pgdump.enc" \
    | xargs -I{} find {} -mtime "+$RETENTION_DAYS" -delete 2>/dev/null || true
  REMAINING=$(find "$BACKUP_DIR" -name "*.pgdump*" | wc -l)
  info "$REMAINING Backup-Dateien verbleiben in $BACKUP_DIR"
fi

info "Backup-Script beendet."
