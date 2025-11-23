#!/bin/bash
# Start-Skript für den Tanss MCP Server v2

# Prüfe ob .env Datei existiert
if [ ! -f .env ]; then
    echo "⚠️  .env Datei nicht gefunden. Erstelle sie aus env.example..."
    if [ -f env.example ]; then
        cp env.example .env
        echo "✅ .env Datei erstellt. Bitte TANSS_API_KEY eintragen!"
        exit 1
    else
        echo "❌ env.example nicht gefunden!"
        exit 1
    fi
fi

# Lade Umgebungsvariablen
export $(cat .env | grep -v '^#' | xargs)

# Prüfe ob API Key gesetzt ist
if [ -z "$TANSS_API_KEY" ]; then
    echo "❌ TANSS_API_KEY ist nicht gesetzt!" >&2
    exit 1
fi

# Starte MCP Server
echo "🚀 Starte Tanss MCP Server v2..."
echo "📡 MCP Endpoint: http://0.0.0.0:8000/mcp"
python server.py

