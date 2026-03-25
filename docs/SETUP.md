# Setup-Anleitung: TANSS → S1 Angebots-Automatisierung

## Voraussetzungen

Bevor du beginnst, stelle sicher dass folgendes vorhanden ist:

- [ ] n8n (self-hosted) ab Version 1.40.0 mit AI-Paket (`n8n start --tunnel` oder Docker)
- [ ] Supabase-Projekt mit aktivierter `pgvector`-Extension
- [ ] OpenAI API-Key mit Zugriff auf `gpt-4o` und `text-embedding-3-small`
- [ ] TANSS-Instanz mit API-Zugang und einem dedizierten API-User
- [ ] Systemhaus.ONE / SAP B1 Service Layer erreichbar (Port 50000)

---

## Schritt 1: Supabase-Datenbank vorbereiten

### 1.1 pgvector aktivieren

Gehe in deinem Supabase-Projekt zu **SQL-Editor** und führe aus:

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

### 1.2 Migrations ausführen

Führe die drei Migrations-Dateien **in dieser Reihenfolge** im SQL-Editor aus:

```bash
# Inhalt der Dateien in die Supabase SQL-Konsole kopieren und ausführen:
supabase/migrations/001_create_angebote_vectors.sql
supabase/migrations/002_create_match_function.sql
supabase/migrations/003_create_ingestion_helpers.sql
```

Alternativ mit der Supabase CLI:

```bash
supabase db push --db-url "postgresql://postgres:[PASSWORD]@[HOST]:5432/postgres"
```

### 1.3 Verifizierung

```sql
-- Tabelle und Indizes prüfen
SELECT tablename, indexname FROM pg_indexes WHERE tablename = 'angebote_vectors';

-- Funktionen prüfen
SELECT routine_name FROM information_schema.routines
WHERE routine_schema = 'public' AND routine_type = 'FUNCTION';
```

---

## Schritt 2: n8n Workflows importieren

### 2.1 Haupt-Workflow importieren

1. n8n öffnen → **Workflows** → **Import from File**
2. Datei `n8n-workflows/tanss-s1-angebot-workflow.json` auswählen
3. Workflow wird importiert (noch nicht aktivieren!)

### 2.2 Ingestion-Workflow importieren

1. n8n öffnen → **Workflows** → **Import from File**
2. Datei `n8n-workflows/angebote-ingestion-workflow.json` auswählen

---

## Schritt 3: Credentials in n8n anlegen

### 3.1 OpenAI Credentials

1. **Settings** → **Credentials** → **Add Credential**
2. Typ: **OpenAI API**
3. API Key: `sk-...` (aus `.env`)
4. Name: `OpenAI API`
5. **Speichern**
6. In beiden Workflows: Alle OpenAI-Nodes → Credential auf `OpenAI API` setzen

### 3.2 Supabase (HTTP-basiert, kein eigener Credential-Typ nötig)

Die Supabase-Aufrufe laufen über HTTP Request Nodes mit den Umgebungsvariablen
`SUPABASE_URL` und `SUPABASE_SERVICE_ROLE_KEY`. Kein separates Credential nötig.

### 3.3 Slack (optional)

1. **Settings** → **Credentials** → **Add Credential**
2. Typ: **Slack Webhook**
3. Webhook URL: `https://hooks.slack.com/services/...`
4. Name: `Slack Webhook`

---

## Schritt 4: Umgebungsvariablen setzen

### Option A: n8n Settings (empfohlen für Docker-Deployments)

In der n8n `docker-compose.yml` oder `.env`:

```env
N8N_CUSTOM_ENV_FILE=/path/to/.env
```

Oder direkt als Docker Environment Variables:

```yaml
environment:
  - TANSS_BASE_URL=https://deine-instanz.tanss.de
  - TANSS_USERNAME=api-user
  - TANSS_PASSWORD=geheim
  # ... alle weiteren Variablen aus .env.example
```

### Option B: Direkt in n8n Workflow-Settings

1. Workflow öffnen → **Workflow Settings** → **Environment Variables**
2. Jede Variable einzeln hinzufügen

### Benötigte Variablen

Kopiere `.env.example` nach `.env` und befülle alle Felder:

```bash
cp .env.example .env
nano .env  # oder dein bevorzugter Editor
```

---

## Schritt 5: Test – Ingestion-Workflow

### 5.1 Beispieldaten importieren

1. Ingestion-Workflow öffnen
2. **Test Workflow** (manueller Trigger) klicken
3. Im Webhook-Trigger alternativ: POST-Request senden:

```bash
curl -X POST http://dein-n8n:5678/webhook/angebote-ingestion \
  -H "Content-Type: application/json" \
  -d @examples/beispiel-angebote-historisch.json
```

### 5.2 Ergebnis prüfen

```sql
-- In Supabase SQL-Editor:
SELECT * FROM angebote_uebersicht LIMIT 10;
```

Erwartetes Ergebnis: 3–5 Zeilen mit den importierten Beispiel-Angeboten.

---

## Schritt 6: Test – Haupt-Workflow

### 6.1 Test-Kommentar in TANSS erstellen

Öffne ein beliebiges Ticket in TANSS und erstelle einen Kommentar:

```
#angebot Kunde braucht 3 neue Arbeitsplatz-PCs mit Monitor und Microsoft 365. Dell oder HP. Bitte auch Einrichtung einplanen.
```

### 6.2 Workflow manuell triggern (ohne warten auf Schedule)

1. Haupt-Workflow öffnen
2. **Test Workflow** klicken
3. Execution Log beobachten

### 6.3 Erwartetes Ergebnis

- ✅ TANSS-Login erfolgreich
- ✅ Kommentar mit `#angebot` gefunden
- ✅ OpenAI parsed 4–6 Positionen
- ✅ Supabase findet 3–5 ähnliche historische Angebote
- ✅ S1-Angebot wird erstellt (DocNum erscheint im Log)
- ✅ Rückmeldungs-Kommentar in TANSS-Ticket erscheint

---

## Schritt 7: Workflow aktivieren

Erst nach erfolgreichem Test:

1. Haupt-Workflow öffnen
2. Toggle oben rechts: **Aktiv** → grün
3. Der Schedule-Trigger läuft ab jetzt alle 3 Minuten

---

## Häufige Fehler beim Setup

### TANSS: HTTP 401 bei Login

```
Fehler: apiKey fehlt in Response
```

**Lösung**: TANSS-User muss API-Zugang haben. Prüfe in TANSS unter Administration → Benutzer → API-Zugang erlauben.

### S1: HTTP 404 bei Login

```
Fehler: Cannot POST /b1s/v2/Login
```

**Lösung**: `S1_BASE_URL` prüfen. Muss `https://server:50000` sein (KEIN trailing slash, KEIN `/b1s/v2` am Ende der Base URL).

### Supabase: HTTP 400 bei match_angebote

```
Fehler: function match_angebote does not exist
```

**Lösung**: Migration `002_create_match_function.sql` wurde nicht ausgeführt. Migrations in der richtigen Reihenfolge erneut ausführen.

### OpenAI: Rate Limit bei Ingestion

```
Fehler: 429 Too Many Requests
```

**Lösung**: Ingestion-Workflow um einen **Wait Node** (1–2 Sekunden) nach dem Embedding-Node erweitern. Besonders relevant bei > 50 Angeboten gleichzeitig.

### n8n: Static Data funktioniert nicht

```
Kommentare werden doppelt verarbeitet
```

**Lösung**: Sicherstellen dass n8n im Production-Modus läuft (nicht `--tunnel`). Static Data wird nur im Production-Execution-Mode persistent gespeichert.
