# API-Referenz: TANSS + Systemhaus.ONE + Supabase

## TANSS API

**Basis-URL**: `https://deine-instanz.tanss.de/backend/api/v1`
**Dokumentation**: https://api-doc.tanss.de
**Auth-Methode**: Custom HTTP-Header `apiToken: {token}`
**Content-Type**: `application/json`

### Authentifizierung

#### POST `/login`

Login und API-Key beziehen.

**Request Body:**
```json
{
  "username": "api-user",
  "password": "geheim"
}
```

**Response (200 OK):**
```json
{
  "apiKey": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expires": "2026-03-25T23:59:59Z"
}
```

**Fehler:**
- `401 Unauthorized` – Falsche Zugangsdaten
- `403 Forbidden` – API-Zugang für User nicht aktiviert
- `429 Too Many Requests` – Rate-Limit (max. 60 Requests/Min)

**Hinweis 2FA:** Bei aktivierter TOTP-2FA zusätzlich `"totp": "123456"` im Body.

---

### Tickets

#### GET `/tickets/own`

Alle Tickets des authentifizierten Users abrufen.

**Header:** `apiToken: {key}`

**Response (200 OK):**
```json
{
  "tickets": [
    {
      "id": 12345,
      "title": "Neuer Mitarbeiter - Arbeitsplatz einrichten",
      "customerId": "C00042",
      "status": "open",
      "priority": "normal",
      "assignedTo": "Max Mustermann",
      "createdAt": "2026-03-24T08:00:00Z",
      "updatedAt": "2026-03-25T10:30:00Z"
    }
  ]
}
```

**Query-Parameter:**
| Parameter | Typ | Beschreibung |
|-----------|-----|-------------|
| `status` | string | Filter: `open`, `closed`, `all` |
| `limit` | int | Max. Ergebnisse (Default: 50) |
| `page` | int | Pagination |

---

#### GET `/tickets/{id}/history`

Ticket-History inkl. aller Kommentare abrufen.

**Header:** `apiToken: {key}`

**Response (200 OK):**
```json
{
  "ticketId": 12345,
  "comments": [
    {
      "id": 9876,
      "content": "#angebot Kunde braucht 5 PCs mit Monitor und Office 365",
      "author": "Max Mustermann",
      "authorId": 42,
      "createdAt": "2026-03-25T10:30:00Z",
      "type": "comment",
      "internal": false
    }
  ]
}
```

---

#### POST `/tickets/{id}/comments`

Neuen Kommentar an ein Ticket hängen.

**Header:** `apiToken: {key}`

**Request Body:**
```json
{
  "content": "Angebot #1042 wurde in Systemhaus.ONE erstellt.",
  "type": "comment",
  "internal": true
}
```

**Response (201 Created):**
```json
{
  "id": 9877,
  "ticketId": 12345,
  "content": "...",
  "createdAt": "2026-03-25T10:35:00Z"
}
```

---

### Kunden

#### GET `/companies/{customerId}`

Kunden-Stammdaten abrufen (für CardCode-Mapping zu S1).

**Response:**
```json
{
  "id": "C00042",
  "name": "Musterkanzlei GmbH",
  "externalId": "K-10042",
  "branch": "Kanzlei",
  "address": { ... }
}
```

---

## Systemhaus.ONE / SAP B1 Service Layer

**Basis-URL**: `https://dein-server:50000`
**API-Pfad**: `/b1s/v2/`
**Protokoll**: OData v4 + REST
**Auth-Methode**: Session Cookies (`B1SESSION`, `ROUTEID`)
**Content-Type**: `application/json`
**Dokumentation**: SAP Business One Service Layer Developer Guide

### Authentifizierung

#### POST `/b1s/v2/Login`

Session starten. Gibt Cookies zurück die bei allen Folge-Requests mitgesendet werden müssen.

**Request Body:**
```json
{
  "UserName":  "api-user",
  "Password":  "geheim",
  "CompanyDB": "S1_PROD"
}
```

**Response (200 OK):**
```json
{
  "odata.metadata": "...",
  "SessionId": "abc123",
  "Version": "10.0",
  "SessionTimeout": 30
}
```

**Response Cookies:**
```
B1SESSION=abc123; Path=/; HttpOnly
ROUTEID=.node1; Path=/
```

**Wichtig:** Session-Timeout = 30 Minuten. Bei Timeout: erneuter Login nötig (HTTP 401 → retry).

---

#### POST `/b1s/v2/Logout`

Session beenden (Best Practice, immer am Ende aufrufen).

**Header:** `Cookie: B1SESSION=abc123; ROUTEID=.node1`

**Response:** `204 No Content`

---

### Angebote (Quotations)

#### POST `/b1s/v2/Quotations`

Neues Angebot erstellen.

**Header:** `Cookie: B1SESSION=...; ROUTEID=...`

**Request Body:**
```json
{
  "CardCode":    "K-10042",
  "DocDate":     "2026-03-25",
  "DocDueDate":  "2026-04-25",
  "Comments":    "Automatisch aus TANSS Ticket #12345 erstellt",
  "DocumentLines": [
    {
      "LineNum":          0,
      "ItemDescription":  "Dell OptiPlex 7020 Desktop PC",
      "Quantity":         5,
      "UnitPrice":        899.00,
      "TaxCode":          "T1"
    },
    {
      "LineNum":          1,
      "ItemCode":         "MON-DELL-P2425H",
      "ItemDescription":  "Dell P2425H 24\" FHD Monitor",
      "Quantity":         5,
      "UnitPrice":        229.00,
      "TaxCode":          "T1"
    }
  ],
  "UserDefinedFields": {
    "U_TANSS_TicketID": "12345"
  }
}
```

**Hinweis zu `ItemCode`:** Optional. Wenn kein Artikelstamm vorhanden, nur `ItemDescription` ohne `ItemCode` nutzen. SAP B1 erfordert dann einen konfigurierten „Freitext-Artikel" (häufig Kürzel `FREI` oder `DIENSTL`).

**Response (201 Created):**
```json
{
  "DocEntry": 1234,
  "DocNum":   1042,
  "DocDate":  "2026-03-25",
  "CardCode": "K-10042",
  "CardName": "Musterkanzlei GmbH",
  "DocTotal": 5640.00
}
```

---

#### GET `/b1s/v2/Quotations`

Angebote abrufen (für Ingestion).

**Query-Parameter:**

| Parameter | Beispiel | Beschreibung |
|-----------|---------|-------------|
| `$filter` | `DocDate ge '2024-01-01'` | OData-Filter |
| `$expand` | `DocumentLines` | Positionen mitladen |
| `$orderby` | `DocDate desc` | Sortierung |
| `$top` | `100` | Max. Ergebnisse |
| `$skip` | `100` | Pagination-Offset |
| `$select` | `DocNum,DocDate,CardCode,DocTotal` | Felder einschränken |

**Vollständiger Beispiel-URL:**
```
GET /b1s/v2/Quotations?$filter=DocDate ge '2024-01-01' and DocumentStatus eq 'O'&$expand=DocumentLines&$orderby=DocDate desc&$top=50
```

---

#### GET `/b1s/v2/BusinessPartners('{CardCode}')`

Kunden-Stammdaten aus SAP B1 abrufen.

```
GET /b1s/v2/BusinessPartners('K-10042')
```

---

## Supabase REST API

**Basis-URL**: `https://[projekt-id].supabase.co`
**Auth**: Header `apikey: {anon_key}` und `Authorization: Bearer {service_role_key}`

### RPC-Endpunkte

#### POST `/rest/v1/rpc/match_angebote`

Ähnliche Angebote per Cosine Similarity suchen.

**Request Body:**
```json
{
  "query_embedding": [0.123, -0.456, ...],
  "match_threshold": 0.65,
  "match_count": 5,
  "filter_typ": "PC-Arbeitsplatz",
  "filter_status": null
}
```

**Response (200 OK):**
```json
[
  {
    "id": 42,
    "content": "PC-Arbeitsplatz Angebot für Kanzlei...",
    "metadata": {
      "angebot_id": "ANG-2025-0017",
      "angebot_typ": "PC-Arbeitsplatz",
      "status": "gewonnen"
    },
    "similarity": 0.891
  }
]
```

---

#### POST `/rest/v1/rpc/angebot_exists`

Duplikat-Check vor Ingestion.

**Request Body:**
```json
{ "p_angebot_id": "ANG-S1-1042" }
```

**Response:** `true` oder `false`

---

### Tabellen-Endpunkte

#### POST `/rest/v1/angebote_vectors`

Neues Angebot-Embedding einfügen.

**Header:** `Prefer: return=minimal` (spart Bandbreite)

**Request Body:**
```json
{
  "content":   "PC-Arbeitsplatz Angebot für Kanzlei...",
  "embedding": [0.123, -0.456, ...],
  "metadata": {
    "angebot_id":        "ANG-2025-0042",
    "angebot_typ":       "PC-Arbeitsplatz",
    "kunde_branche":     "Kanzlei",
    "kategorien":        ["Hardware", "Peripherie", "Lizenzen", "Service"],
    "positionen_anzahl": 11,
    "gesamtwert_netto":  12450.00,
    "datum":             "2025-06-15",
    "status":            "gewonnen",
    "ersteller":         "Max Mustermann",
    "quelle":            "systemhaus-one"
  }
}
```

---

#### GET `/rest/v1/angebote_uebersicht`

Alle Angebote in übersichtlichem Format (View).

**Query-Parameter:**
```
GET /rest/v1/angebote_uebersicht?order=created_at.desc&limit=10
```

---

## Rate Limits & Best Practices

| System | Rate Limit | Empfehlung |
|--------|-----------|-----------|
| TANSS | ~60 Req/Min | Polling alle 3 Min reicht |
| S1 Service Layer | Keine bekannte Begrenzung | Session-Timeout (30 Min) beachten |
| OpenAI GPT-4o | Tier-abhängig | Retry mit Exponential Backoff |
| OpenAI Embeddings | 1M Tokens/Min (Tier 2+) | Bei Bulk-Ingestion: 1s Pause |
| Supabase | 500 Req/Sek (Standard) | Kein Problem für diesen Use Case |
