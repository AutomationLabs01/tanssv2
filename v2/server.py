#!/usr/bin/env python3
"""
Tanss MCP Server v2
Basierend auf FastMCP für n8n HTTP MCP Client Integration
"""

import os
from fastmcp import FastMCP
import httpx
import json

# Tanss API Konfiguration
TANSS_API_BASE_URL = os.getenv("TANSS_API_BASE_URL", "https://api.tanss.de")
TANSS_API_KEY = os.getenv("TANSS_API_KEY", "")
TEST_MODE = os.getenv("TEST_MODE", "false").lower() == "true" or not TANSS_API_KEY

# FastMCP Server Instanz
mcp = FastMCP("TanssMCPServer")

# HTTP Client für Tanss API (nur wenn nicht im Test-Modus)
tanss_client = None
if not TEST_MODE:
    tanss_client = httpx.AsyncClient(
        base_url=TANSS_API_BASE_URL,
        headers={
            "Authorization": f"Bearer {TANSS_API_KEY}",
            "Content-Type": "application/json"
        },
        timeout=30.0
    )


@mcp.tool()
async def get_ticket_comments(ticket_id: str, toolCallId: str = "") -> str:
    """
    Extrahiert Kommentare aus einem Tanss Ticket anhand der Ticket-ID.
    
    Args:
        ticket_id: Die ID des Tickets, aus dem Kommentare extrahiert werden sollen
    
    Returns:
        JSON-String mit den Kommentaren des Tickets
    """
    ticket_id = str(ticket_id) if ticket_id is not None else ""
    if not ticket_id:
        return json.dumps({"error": "ticket_id ist erforderlich"}, indent=2, ensure_ascii=False)
    
    # Test-Modus: Mock-Daten zurückgeben
    if TEST_MODE:
        return json.dumps({
            "ticket_id": ticket_id,
            "comments": [
                {
                    "id": "1",
                    "author": "Test User",
                    "text": "Dies ist ein Test-Kommentar",
                    "created_at": "2024-01-01T12:00:00Z"
                },
                {
                    "id": "2",
                    "author": "Test User 2",
                    "text": "Ein weiterer Test-Kommentar",
                    "created_at": "2024-01-01T13:00:00Z"
                }
            ],
            "note": "TEST MODE - Mock-Daten"
        }, indent=2, ensure_ascii=False)
    
    # Produktions-Modus: Echte API-Calls
    try:
        response = await tanss_client.get(f"/tickets/{ticket_id}/comments")
        response.raise_for_status()
        return json.dumps(response.json(), indent=2, ensure_ascii=False)
    except httpx.HTTPStatusError as e:
        return json.dumps({
            "error": f"HTTP Fehler: {e.response.status_code}",
            "message": str(e),
            "detail": e.response.text if hasattr(e.response, 'text') else None
        }, indent=2, ensure_ascii=False)
    except Exception as e:
        return json.dumps({"error": f"Fehler beim Abrufen der Kommentare: {str(e)}"}, indent=2, ensure_ascii=False)


@mcp.tool()
async def get_ticket(ticket_id: str, toolCallId: str = "") -> str:
    """
    Ruft ein Tanss Ticket anhand der Ticket-ID ab.
    
    Args:
        ticket_id: Die ID des Tickets
    
    Returns:
        JSON-String mit den Ticket-Daten
    """
    ticket_id = str(ticket_id) if ticket_id is not None else ""
    if not ticket_id:
        return json.dumps({"error": "ticket_id ist erforderlich"}, indent=2, ensure_ascii=False)
    
    # Test-Modus: Mock-Daten zurückgeben
    if TEST_MODE:
        return json.dumps({
            "id": ticket_id,
            "title": "Test Ticket",
            "description": "Dies ist ein Test-Ticket",
            "status": "open",
            "priority": "medium",
            "created_at": "2024-01-01T10:00:00Z",
            "note": "TEST MODE - Mock-Daten"
        }, indent=2, ensure_ascii=False)
    
    # Produktions-Modus: Echte API-Calls
    try:
        response = await tanss_client.get(f"/tickets/{ticket_id}")
        response.raise_for_status()
        return json.dumps(response.json(), indent=2, ensure_ascii=False)
    except httpx.HTTPStatusError as e:
        return json.dumps({
            "error": f"HTTP Fehler: {e.response.status_code}",
            "message": str(e),
            "detail": e.response.text if hasattr(e.response, 'text') else None
        }, indent=2, ensure_ascii=False)
    except Exception as e:
        return json.dumps({"error": f"Fehler beim Abrufen des Tickets: {str(e)}"}, indent=2, ensure_ascii=False)

@mcp.tool()
def n8n_router(sessionId: str, action: str, chatInput: str = "", toolCallId: str = "") -> str:
    """
    Zentrales Router-Tool für n8n-Kompatibilität.
    Unterstützte Aktionen:
      - ping: einfache Erreichbarkeitsprüfung
      - echo: gibt den Chat-Text zurück
      - tools: listet verfügbare Tools mit Parametern
    """
    try:
        sessionId = str(sessionId) if sessionId is not None else ""
        action = (action or "").strip().lower()
        chatInput = chatInput or ""

        if action == "ping":
            return f"[{sessionId}] pong"

        if action == "echo":
            return f"[{sessionId}] {chatInput}"

        if action == "tools":
            tools_description = {
                "tools": [
                    {
                        "name": "get_ticket_comments",
                        "description": "Extrahiert Kommentare aus einem Tanss Ticket anhand der Ticket-ID.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "ticket_id": {"type": "string"}
                            },
                            "required": ["ticket_id"]
                        }
                    },
                    {
                        "name": "get_ticket",
                        "description": "Ruft ein Tanss Ticket anhand der Ticket-ID ab.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "ticket_id": {"type": "string"}
                            },
                            "required": ["ticket_id"]
                        }
                    },
                    {
                        "name": "list_tickets",
                        "description": "Listet Tickets mit Pagination.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "limit": {"type": "integer", "minimum": 1, "maximum": 100, "default": 10},
                                "offset": {"type": "integer", "minimum": 0, "default": 0}
                            },
                            "required": []
                        }
                    }
                ],
                "note": "TEST MODE aktiv" if TEST_MODE else "LIVE MODE"
            }
            return json.dumps(tools_description, indent=2, ensure_ascii=False)

        return f"[{sessionId}] Unbekannte action: {action}"
    except Exception as e:
        return json.dumps({"error": f"Router-Fehler: {str(e)}"}, indent=2, ensure_ascii=False)


@mcp.tool()
async def list_tickets(limit: int = 10, offset: int = 0, toolCallId: str = "") -> str:
    """
    Listet alle verfügbaren Tickets auf.
    
    Args:
        limit: Maximale Anzahl der zurückgegebenen Tickets (Standard: 10, Min: 1, Max: 100)
        offset: Offset für Pagination (Standard: 0, Min: 0)
    
    Returns:
        JSON-String mit der Liste der Tickets
    """
    # Werte sicher casten
    try:
        limit = int(limit)
    except Exception:
        limit = 10
    try:
        offset = int(offset)
    except Exception:
        offset = 0
    # Validierung nach Cast
    limit = max(1, min(100, limit))
    offset = max(0, offset)
    
    # Test-Modus: Mock-Daten zurückgeben
    if TEST_MODE:
        tickets = []
        for i in range(offset, offset + limit):
            tickets.append({
                "id": str(i + 1),
                "title": f"Test Ticket {i + 1}",
                "status": "open" if i % 2 == 0 else "closed",
                "priority": "high" if i % 3 == 0 else "medium",
                "created_at": f"2024-01-{(i % 28) + 1:02d}T10:00:00Z"
            })
        return json.dumps({
            "tickets": tickets,
            "total": 100,
            "limit": limit,
            "offset": offset,
            "note": "TEST MODE - Mock-Daten"
        }, indent=2, ensure_ascii=False)
    
    # Produktions-Modus: Echte API-Calls
    try:
        params = {"limit": limit, "offset": offset}
        response = await tanss_client.get("/tickets", params=params)
        response.raise_for_status()
        return json.dumps(response.json(), indent=2, ensure_ascii=False)
    except httpx.HTTPStatusError as e:
        return json.dumps({
            "error": f"HTTP Fehler: {e.response.status_code}",
            "message": str(e),
            "detail": e.response.text if hasattr(e.response, 'text') else None
        }, indent=2, ensure_ascii=False)
    except Exception as e:
        return json.dumps({"error": f"Fehler beim Abrufen der Tickets: {str(e)}"}, indent=2, ensure_ascii=False)


if __name__ == "__main__":
    import sys
    
    # Im Test-Modus keine Validierung des API Keys
    if TEST_MODE:
        print("⚠️  TEST MODE aktiviert - Mock-Daten werden zurückgegeben", file=sys.stderr)
        print("   Setzen Sie TANSS_API_KEY für echte API-Calls", file=sys.stderr)
    elif not TANSS_API_KEY:
        print("FEHLER: TANSS_API_KEY Umgebungsvariable ist nicht gesetzt!", file=sys.stderr)
        print("   Setzen Sie TEST_MODE=true zum Testen ohne API Key", file=sys.stderr)
        sys.exit(1)
    
    # HTTP Transport aktivieren, Pfad /mcp für n8n HTTP MCP Client
    mcp.run(
        transport="http",
        host="0.0.0.0",
        port=8000,
        path="/mcp"
    )

