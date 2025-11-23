# Tanss MCP Server v2

Ein Model Context Protocol (MCP) Server für den Zugriff auf die Tanss API. Dieser Server verwendet FastMCP und ist kompatibel mit dem n8n HTTP MCP Client Tool.

## Features

- ✅ FastMCP basiert (einfache und funktionierende Implementierung)
- ✅ HTTP/SSE Transport für n8n HTTP MCP Client
- ✅ GET-Operationen für Tanss API
- ✅ Kommentare aus Tickets extrahieren
- ✅ Tickets abrufen und auflisten
- ✅ Docker-Support
- ✅ Test-Client für lokales Testen

## Voraussetzungen

- Python 3.11+
- Docker (optional, für Container-Betrieb)
- Tanss API Key

## Installation

### Docker Installation (Empfohlen)

1. Umgebungsvariablen konfigurieren:
```bash
export TANSS_API_KEY=your-api-key-here
export TANSS_API_BASE_URL=https://api.tanss.de  # Optional
export SERVER_PORT=8000  # Optional, Standard: 8000
```

2. Container bauen und starten:
```bash
docker-compose up -d
```

3. Server ist erreichbar unter: `http://localhost:8000`

4. Logs anzeigen:
```bash
docker-compose logs -f
```

### Lokale Installation

1. Abhängigkeiten installieren:
```bash
pip install -r requirements.txt
```

2. Umgebungsvariablen setzen:
```bash
cp env.example .env
# Bearbeiten Sie .env und fügen Sie Ihren TANSS_API_KEY ein
export $(cat .env | grep -v '^#' | xargs)
```

3. Server starten:
```bash
./start.sh
# oder
python server.py
```

## N8n HTTP MCP Client Integration

### Konfiguration in n8n

1. **MCP Client Tool Node hinzufügen:**
   - Öffnen Sie n8n und erstellen Sie einen neuen Workflow
   - Fügen Sie den "MCP Client Tool" Node hinzu

2. **Server konfigurieren:**

   **Für Docker Installation:**
   - **Endpoint**: `http://tanss-mcp-server-v2:8000/mcp` (wenn n8n im gleichen Docker-Netzwerk)
   - **Endpoint**: `http://localhost:8000/mcp` (wenn n8n lokal läuft)
   - **Endpoint**: `http://<server-ip>:8000/mcp` (wenn n8n remote läuft)
   - **Server Transport**: `HTTP Streamable` (SSE)
   - **Authentication**: `None` (oder entsprechend Ihrer Konfiguration)

   **Für lokale Installation:**
   - **Endpoint**: `http://localhost:8000/mcp`
   - **Server Transport**: `HTTP Streamable` (SSE)
   - **Authentication**: `None`

3. **Tools auswählen:**
   - **Alle Tools**: Alle verfügbaren Tools werden eingebunden
   - **Ausgewählte Tools**: Wählen Sie spezifische Tools aus
   - **Alle außer**: Schließen Sie bestimmte Tools aus

4. **Verbindung testen:**
   - Führen Sie den Node aus, um die Verbindung zu testen
   - Die verfügbaren Tools sollten angezeigt werden

### Wichtige URL

**MCP Endpoint URL für n8n:**
```
http://localhost:8000/mcp
```

Oder wenn der Server in Docker läuft und n8n im gleichen Netzwerk:
```
http://tanss-mcp-server-v2:8000/mcp
```

### Verfügbare Tools

#### `get_ticket_comments`
Extrahiert Kommentare aus einem Ticket.

**Parameter:**
- `ticket_id` (string, erforderlich): Die ID des Tickets

**Beispiel in n8n:**
```json
{
  "ticket_id": "123"
}
```

#### `get_ticket`
Ruft ein Ticket anhand der ID ab.

**Parameter:**
- `ticket_id` (string, erforderlich): Die ID des Tickets

**Beispiel in n8n:**
```json
{
  "ticket_id": "123"
}
```

#### `list_tickets`
Listet alle verfügbaren Tickets auf.

**Parameter:**
- `limit` (integer, optional): Maximale Anzahl (Standard: 10, Min: 1, Max: 100)
- `offset` (integer, optional): Offset für Pagination (Standard: 0, Min: 0)

**Beispiel in n8n:**
```json
{
  "limit": 20,
  "offset": 0
}
```

## Testen

### Mit dem Test-Client

```bash
export TANSS_API_KEY=your-api-key
python client_test.py
```

### Mit curl

```bash
# Health Check (falls verfügbar)
curl http://localhost:8000/health

# Server Status
curl http://localhost:8000/
```

## Projektstruktur

```
v2/
├── server.py              # FastMCP Server Implementierung
├── client_test.py         # Test-Client
├── requirements.txt       # Python Abhängigkeiten
├── Dockerfile            # Docker Image Definition
├── docker-compose.yml    # Docker Compose Konfiguration
├── start.sh              # Start-Skript
├── Makefile              # Make-Befehle
├── env.example           # Beispiel Umgebungsvariablen
└── README.md             # Diese Datei
```

## Entwicklung

### Lokale Entwicklung

1. Virtuelle Umgebung erstellen:
```bash
python -m venv venv
source venv/bin/activate  # Linux/Mac
# oder
venv\Scripts\activate     # Windows
```

2. Abhängigkeiten installieren:
```bash
pip install -r requirements.txt
```

3. Server starten:
```bash
export TANSS_API_KEY=your-key
python server.py
```

### Docker Entwicklung

```bash
# Container bauen
docker-compose build

# Container starten
docker-compose up

# Container stoppen
docker-compose down

# Logs anzeigen
docker-compose logs -f
```

### Make Befehle

```bash
make install          # Installiert Dependencies
make test             # Führt Tests aus
make docker-build     # Baut Docker Image
make docker-up        # Startet Docker Container
make docker-down      # Stoppt Docker Container
make docker-logs      # Zeigt Docker Logs
make clean            # Bereinigt temporäre Dateien
```

## Konfiguration

### Umgebungsvariablen

- `TANSS_API_KEY` (erforderlich): Ihr Tanss API Schlüssel
- `TANSS_API_BASE_URL` (optional): API Basis-URL (Standard: `https://api.tanss.de`)

## Unterschied zu v1

- **v1**: Verwendet offizielles MCP SDK mit komplexer SSE-Implementierung
- **v2**: Verwendet FastMCP - einfacher, funktionierender Ansatz
- **v2**: Gleiche Grundstruktur wie mcp-server-test
- **v2**: Getestet und funktionsfähig mit n8n HTTP MCP Client

## Fehlerbehebung

### API-Schlüssel nicht gesetzt
Stellen Sie sicher, dass die Umgebungsvariable `TANSS_API_KEY` gesetzt ist.

### Verbindungsfehler
Überprüfen Sie die `TANSS_API_BASE_URL` und stellen Sie sicher, dass der Tanss API Server erreichbar ist.

### Docker-Probleme
- Stellen Sie sicher, dass Docker läuft
- Überprüfen Sie die Logs: `docker-compose logs`
- Prüfen Sie die Port-Freigabe: `docker ps`

### n8n HTTP MCP Client Probleme
- Stellen Sie sicher, dass die Endpoint-URL korrekt ist: `http://<server>:8000/mcp`
- Überprüfen Sie, dass "HTTP Streamable" als Transport ausgewählt ist
- Testen Sie die Verbindung mit dem Test-Client zuerst

## Lizenz

Dieses Projekt ist für den internen Gebrauch bestimmt.

## Versionierung

Dies ist Version 2 (v2) des Tanss MCP Servers, basierend auf der funktionierenden FastMCP-Struktur.

