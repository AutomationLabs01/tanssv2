#!/usr/bin/env bash
# =============================================================================
# generate-secrets.sh – Alle Secrets für den TANSS RAG Stack erzeugen
# =============================================================================
# Führt folgendes aus:
#   1. Zufällige Passwörter und Keys generieren
#   2. Supabase JWT-Keys (anon + service_role) erzeugen
#   3. Self-signed TLS-Zertifikat für lokale Entwicklung
#   4. PostgreSQL SSL-Zertifikat
#   5. .env-Datei mit generierten Werten befüllen
#
# Voraussetzungen: openssl, python3 (für JWT-Generierung)
# Verwendung:      ./scripts/generate-secrets.sh [--prod]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(dirname "$SCRIPT_DIR")"
SECRETS_DIR="$DOCKER_DIR/secrets"
ENV_FILE="$DOCKER_DIR/.env"
ENV_EXAMPLE="$DOCKER_DIR/.env.example"

PROD_MODE=false
if [[ "${1:-}" == "--prod" ]]; then
  PROD_MODE=true
  echo "⚠️  Produktions-Modus: Self-signed Zertifikate werden NICHT erzeugt."
fi

# ---------------------------------------------------------------------------
# Farben für Output
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ---------------------------------------------------------------------------
# Voraussetzungen prüfen
# ---------------------------------------------------------------------------
command -v openssl   >/dev/null 2>&1 || error "openssl ist nicht installiert"
command -v python3   >/dev/null 2>&1 || error "python3 ist nicht installiert"

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

# ---------------------------------------------------------------------------
# Hilfsfunktionen
# ---------------------------------------------------------------------------
gen_random() {
  # Gibt n zufällige URL-sichere Bytes als Hex aus (Länge = 2n)
  local length="${1:-32}"
  openssl rand -hex "$length"
}

gen_password() {
  # Alphanumerisch, URL-sicher, keine Sonderzeichen (für DB-Passwörter)
  local length="${1:-32}"
  openssl rand -base64 "$((length * 3 / 4))" | tr -d '+/=' | head -c "$length"
}

gen_jwt_secret() {
  # JWT Secret: mindestens 40 Zeichen, base64-sicher
  openssl rand -base64 40 | tr -d '\n'
}

# ---------------------------------------------------------------------------
# 1. Zufällige Secrets generieren
# ---------------------------------------------------------------------------
info "Generiere Passwörter und Secrets..."

POSTGRES_PASSWORD=$(gen_password 32)
POSTGRES_PASSWORD_AUTHENTICATOR=$(gen_password 32)
POSTGRES_PASSWORD_STORAGE=$(gen_password 32)
POSTGRES_PASSWORD_N8N=$(gen_password 32)
JWT_SECRET=$(gen_jwt_secret)
REALTIME_DB_ENC_KEY=$(gen_random 16)   # 32 Hex-Zeichen = 128 Bit
SECRET_KEY_BASE=$(gen_random 32)        # 64 Hex-Zeichen
N8N_ENCRYPTION_KEY=$(gen_random 24)     # 48 Hex-Zeichen
N8N_BASIC_AUTH_PASSWORD=$(gen_password 20)

# ---------------------------------------------------------------------------
# 2. Supabase JWT-Keys generieren (anon + service_role)
# ---------------------------------------------------------------------------
info "Generiere Supabase JWT-Keys..."

ANON_KEY=$(python3 - <<EOF
import base64, hashlib, hmac, json, time, struct

def b64url(data):
    if isinstance(data, str):
        data = data.encode()
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()

def jwt(payload, secret):
    header = b64url(json.dumps({"alg": "HS256", "typ": "JWT"}))
    body   = b64url(json.dumps(payload))
    sig    = b64url(hmac.new(
        secret.encode(), f"{header}.{body}".encode(), hashlib.sha256
    ).digest())
    return f"{header}.{body}.{sig}"

# anon: kein Zugriff auf service_role-Features, kein Bypass von RLS
anon_payload = {
    "role": "anon",
    "iss": "supabase-local",
    "iat": int(time.time()),
    "exp": int(time.time()) + (365 * 24 * 3600),  # 1 Jahr
}
print(jwt(anon_payload, "$JWT_SECRET"))
EOF
)

SERVICE_ROLE_KEY=$(python3 - <<EOF
import base64, hashlib, hmac, json, time

def b64url(data):
    if isinstance(data, str):
        data = data.encode()
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()

def jwt(payload, secret):
    header = b64url(json.dumps({"alg": "HS256", "typ": "JWT"}))
    body   = b64url(json.dumps(payload))
    sig    = b64url(hmac.new(
        secret.encode(), f"{header}.{body}".encode(), hashlib.sha256
    ).digest())
    return f"{header}.{body}.{sig}"

service_payload = {
    "role": "service_role",
    "iss": "supabase-local",
    "iat": int(time.time()),
    "exp": int(time.time()) + (365 * 24 * 3600),
}
print(jwt(service_payload, "$JWT_SECRET"))
EOF
)

# ---------------------------------------------------------------------------
# 3. Self-signed TLS-Zertifikat für nginx (nur Entwicklung)
# ---------------------------------------------------------------------------
if [[ "$PROD_MODE" == "false" ]]; then
  info "Erzeuge self-signed TLS-Zertifikat für nginx (dev)..."

  DOMAIN="${DOMAIN:-localhost}"
  openssl req -x509 -newkey rsa:4096 \
    -keyout "$SECRETS_DIR/key.pem" \
    -out    "$SECRETS_DIR/cert.pem" \
    -days   365 -nodes \
    -subj   "/CN=$DOMAIN/O=TANSS RAG Dev/C=DE" \
    -addext "subjectAltName=DNS:$DOMAIN,DNS:localhost,IP:127.0.0.1" \
    2>/dev/null
  chmod 600 "$SECRETS_DIR/key.pem"
  chmod 644 "$SECRETS_DIR/cert.pem"
  info "  → $SECRETS_DIR/cert.pem (self-signed, 365 Tage)"
else
  warn "Prod-Modus: Lege echte TLS-Zertifikate in $SECRETS_DIR/cert.pem und $SECRETS_DIR/key.pem ab."
fi

# ---------------------------------------------------------------------------
# 4. PostgreSQL SSL-Zertifikat (CA + Server)
# ---------------------------------------------------------------------------
info "Erzeuge PostgreSQL SSL-Zertifikat..."

# CA-Zertifikat
openssl req -x509 -newkey rsa:4096 \
  -keyout "$SECRETS_DIR/ca.key" \
  -out    "$SECRETS_DIR/ca.crt" \
  -days   3650 -nodes \
  -subj   "/CN=TANSS-RAG-CA/O=Internal/C=DE" \
  2>/dev/null

# Server-Zertifikat (signiert von CA)
openssl req -newkey rsa:4096 -nodes \
  -keyout "$SECRETS_DIR/server.key" \
  -out    "$SECRETS_DIR/server.csr" \
  -subj   "/CN=postgres/O=Internal/C=DE" \
  2>/dev/null

openssl x509 -req \
  -in      "$SECRETS_DIR/server.csr" \
  -CA      "$SECRETS_DIR/ca.crt" \
  -CAkey   "$SECRETS_DIR/ca.key" \
  -CAcreateserial \
  -out     "$SECRETS_DIR/server.crt" \
  -days    3650 \
  -extensions v3_req \
  2>/dev/null

# Berechtigungen: server.key nur für postgres-User lesbar (UID 999 in Image)
chmod 600 "$SECRETS_DIR/server.key" "$SECRETS_DIR/ca.key"
chmod 644 "$SECRETS_DIR/server.crt" "$SECRETS_DIR/ca.crt"
rm -f "$SECRETS_DIR/server.csr"

info "  → PostgreSQL CA:  $SECRETS_DIR/ca.crt"
info "  → Server-Cert:    $SECRETS_DIR/server.crt"

# ---------------------------------------------------------------------------
# 5. .env-Datei befüllen
# ---------------------------------------------------------------------------
info "Schreibe .env-Datei..."

if [[ -f "$ENV_FILE" ]]; then
  warn ".env existiert bereits – wird gesichert als .env.bak"
  cp "$ENV_FILE" "$ENV_FILE.bak"
fi

# .env.example als Vorlage kopieren und Werte ersetzen
cp "$ENV_EXAMPLE" "$ENV_FILE"
chmod 600 "$ENV_FILE"

# sed-Ersetzungen (kompatibel mit macOS und Linux)
replace_env() {
  local key="$1"
  local value="$2"
  # Sonderzeichen im Value escapen
  local escaped_value
  escaped_value=$(printf '%s\n' "$value" | sed 's/[[\.*^$()+?{|]/\\&/g')
  sed -i.tmp "s|^${key}=.*|${key}=${escaped_value}|" "$ENV_FILE"
  rm -f "${ENV_FILE}.tmp"
}

replace_env "POSTGRES_PASSWORD"               "$POSTGRES_PASSWORD"
replace_env "POSTGRES_PASSWORD_AUTHENTICATOR"  "$POSTGRES_PASSWORD_AUTHENTICATOR"
replace_env "POSTGRES_PASSWORD_STORAGE"        "$POSTGRES_PASSWORD_STORAGE"
replace_env "POSTGRES_PASSWORD_N8N"            "$POSTGRES_PASSWORD_N8N"
replace_env "JWT_SECRET"                       "$JWT_SECRET"
replace_env "ANON_KEY"                         "$ANON_KEY"
replace_env "SERVICE_ROLE_KEY"                 "$SERVICE_ROLE_KEY"
replace_env "REALTIME_DB_ENC_KEY"              "$REALTIME_DB_ENC_KEY"
replace_env "SECRET_KEY_BASE"                  "$SECRET_KEY_BASE"
replace_env "N8N_ENCRYPTION_KEY"               "$N8N_ENCRYPTION_KEY"
replace_env "N8N_BASIC_AUTH_PASSWORD"          "$N8N_BASIC_AUTH_PASSWORD"

# ---------------------------------------------------------------------------
# 6. Data-Verzeichnisse anlegen
# ---------------------------------------------------------------------------
info "Erstelle Data-Verzeichnisse..."
mkdir -p "$DOCKER_DIR/data/postgres" \
         "$DOCKER_DIR/data/n8n" \
         "$DOCKER_DIR/data/storage"

# ---------------------------------------------------------------------------
# 7. Zusammenfassung
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Secrets erfolgreich generiert!                      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Generierte Dateien:"
echo "  $ENV_FILE            ← Passwörter und Keys"
echo "  $SECRETS_DIR/        ← TLS-Zertifikate"
echo ""
echo -e "${YELLOW}WICHTIG – Nächste Schritte:${NC}"
echo "  1. .env öffnen und externe Credentials eintragen:"
echo "     - TANSS_BASE_URL, TANSS_USERNAME, TANSS_PASSWORD"
echo "     - S1_BASE_URL, S1_USERNAME, S1_PASSWORD, S1_COMPANY_DB"
echo "     - OPENAI_API_KEY"
echo "     - DOMAIN (deine öffentliche Domain)"
echo "     - WEBHOOK_URL (https://deine-domain.de/webhook)"
echo ""
echo "  2. Stack starten:"
echo "     cd $(dirname "$DOCKER_DIR")"
echo "     docker compose -f docker/docker-compose.yml up -d"
echo ""
echo -e "${RED}SICHERHEITSHINWEIS:${NC}"
echo "  - .env und secrets/ NIEMALS in Git einchecken!"
echo "  - Prüfe dass beide in .gitignore eingetragen sind."
echo ""

# Prüfen ob .gitignore passt
GITIGNORE="$(dirname "$DOCKER_DIR")/.gitignore"
if [[ -f "$GITIGNORE" ]]; then
  if ! grep -q "docker/.env" "$GITIGNORE" && ! grep -q "docker/secrets" "$GITIGNORE"; then
    warn ".gitignore enthält keine Einträge für docker/.env und docker/secrets!"
    warn "Bitte manuell prüfen."
  fi
fi
