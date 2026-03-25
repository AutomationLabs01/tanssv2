# Architektur: TANSS → S1 Angebots-Automatisierung

## Gesamtüberblick

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        TANSS (Ticketsystem)                                 │
│                                                                             │
│   Techniker schreibt Kommentar:                                             │
│   "#angebot Kunde braucht 5 PCs mit Monitor und Office 365"                 │
└──────────────────────────────────┬──────────────────────────────────────────┘
                                   │  Polling alle 3 Min (Schedule Trigger)
                                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         n8n Haupt-Workflow                                  │
│                                                                             │
│  Phase 1: Erkennung          Phase 2: Parsen          Phase 3: RAG          │
│  ┌──────────────────┐        ┌──────────────────┐     ┌───────────────────┐ │
│  │ TANSS Login      │        │ OpenAI GPT-4o    │     │ OpenAI Embedding  │ │
│  │ Tickets holen    │───────▶│ Kommentar Parser │────▶│ text-emb-3-small  │ │
│  │ History abrufen  │        │ → JSON Positionen│     └────────┬──────────┘ │
│  │ Filtern (#angebot│        │ + confidence_scr.│              │            │ │
│  └──────────────────┘        └──────────────────┘              ▼            │ │
│                                                        ┌───────────────────┐ │
│  Phase 4: S1 Angebot         Phase 5: Rückmeldung      │ Supabase pgvector │ │
│  ┌──────────────────┐        ┌──────────────────┐      │ match_angebote()  │ │
│  │ S1 Login         │        │ Antwort-Kommentar│      │ Top-5 Ähnliche    │ │
│  │ Payload bauen    │◀──┐    │ formatieren      │      └────────┬──────────┘ │
│  │ POST Quotation   │   │    │ TANSS: Comment   │               │            │ │
│  │ S1 Logout        │   │    │ posten           │               ▼            │ │
│  └──────────────────┘   │    └──────────────────┘      ┌───────────────────┐ │
│           │              └───────────────────────────── │ OpenAI GPT-4o    │ │
│           └─────────────────────────────────────────── │ RAG Vollständig. │ │
│                                                         │ → fehlende Pos.  │ │
│                                                         └───────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
                    │                                    ▲
                    │ POST Quotation                     │ Historische
                    ▼                                    │ Angebote
┌─────────────────────────────────┐   ┌─────────────────┴───────────────────┐
│     Systemhaus.ONE (SAP B1)     │   │         Supabase (pgvector)         │
│     /b1s/v2/Quotations          │   │         angebote_vectors            │
│     DocNum: 1042                │   │         ~500–5000 Angebote          │
└─────────────────────────────────┘   └─────────────────────────────────────┘
                                                         ▲
                                                         │ Ingestion
                                              ┌──────────┴──────────────────┐
                                              │  n8n Ingestion-Workflow     │
                                              │  (Separater Workflow)       │
                                              │  S1 API / CSV / JSON Upload │
                                              └─────────────────────────────┘
```

## Detaillierter Datenfluss

### Phase 1: TANSS-Kommentar erkennen

```
Schedule Trigger (alle 3 Min)
    │
    ▼
TANSS Login → apiKey (JWT, läuft ab)
    │
    ▼
GET /tickets/own → Liste offener Tickets
    │
    ▼
[Loop] Für jedes Ticket:
    GET /tickets/{id}/history → Kommentare
    │
    ▼
Code Node: Filter
    • Timestamp > letzterCheck (Static Data)
    • Enthält "#angebot" oder "#quote"
    • Extrahiere Kommentartext nach Hashtag
    │
    ▼
IF: Hat Angebot-Kommentar?
    • Nein → Stop (kein Output)
    • Ja  → weiter
```

### Phase 2: LLM-Parsing

```
OpenAI GPT-4o
    Input:  Kommentartext ("5 PCs mit Monitor...")
    Prompt: kommentar-parser.md
    Output: {
        "angebot_typ": "PC-Arbeitsplatz",
        "positionen": [...],
        "confidence_score": 0.85
    }
    │
    ▼
IF: confidence_score >= 0.6?
    • Nein → Slack-Warnung, Stop
    • Ja  → weiter
```

### Phase 3: RAG-Prüfung

```
Serialisierung (Code Node)
    Text: "PC-Arbeitsplatz Angebot, 4 Positionen:\nHardware: 5x Dell..."
    │
    ▼
OpenAI text-embedding-3-small
    Input:  Serialisierter Text
    Output: [0.123, -0.456, ...] (1536 Dimensionen)
    │
    ▼
Supabase RPC match_angebote()
    Parameter: embedding, threshold=0.65, count=5, typ="PC-Arbeitsplatz"
    Output:    Top-5 ähnliche historische Angebote (mit Similarity-Score)
    │
    ▼
OpenAI GPT-4o
    Input:  Neues Angebot + 5 historische Angebote
    Prompt: rag-vollstaendigkeitspruefung.md
    Output: {
        "fehlende_positionen": [...],
        "vollstaendigkeit_score": 0.70
    }
```

### Phase 4: Angebot in S1 erstellen

```
S1 Login
    POST /b1s/v2/Login → Cookies (B1SESSION, ROUTEID)
    │
    ▼
Code Node: Payload bauen
    CardCode:      Kunden-ID aus TANSS
    DocDate:       Heute
    DocumentLines: Positionen aus LLM-Parsing
    Comments:      TANSS Ticket-Referenz + RAG-Hinweis
    │
    ▼
POST /b1s/v2/Quotations
    Response: { DocNum: 1042, DocEntry: 5678 }
    │
    ▼
S1 Logout (immer aufrufen, auch bei Fehler!)
```

### Phase 5: TANSS-Rückmeldung

```
Code Node: Kommentar formatieren
    "Angebot #1042 wurde in S1 erstellt.
     RAG-Vollständigkeit: 70%
     Möglicherweise vergessen (KRITISCH):
     - Logitech MK270 Tastatur+Maus (5x)
     - HDMI-Kabel 2m (5x)"
    │
    ▼
POST /tickets/{id}/comments
    • Interner Kommentar (internal: true)
    • Mit Angebot-Link zu S1
```

## Ingestion-Workflow

```
Trigger (Manuell oder Webhook)
    │
    ▼
IF: Datenquelle?
    ├── S1 API    → GET /b1s/v2/Quotations → Normalisieren
    └── JSON/CSV  → Parse → Normalisieren
    │
    ▼
[Für jedes Angebot]
    │
    ▼
Serialisieren (natürlichsprachlicher Text)
    │
    ▼
Duplikat-Check (Supabase RPC angebot_exists)
    • Ja  → Überspringen (zählen)
    • Nein → weiter
    │
    ▼
OpenAI text-embedding-3-small → 1536-Dim Vektor
    │
    ▼
INSERT INTO angebote_vectors (content, embedding, metadata)
    │
    ▼
Slack-Zusammenfassung: "42 importiert, 3 Duplikate übersprungen"
```

## Designentscheidungen

### 1. Polling statt Webhook

**Warum Polling (alle 3 Min) statt TANSS-Webhook?**

TANSS unterstützt Webhooks, aber:
- Webhook-Delivery ist nicht garantiert (TANSS sendet Fire-and-Forget)
- Bei n8n-Restart gehen Webhook-Events verloren
- Polling mit Static Data (Last-Check-Timestamp) ist robuster
- 3-Minuten-Delay ist für Angebotserstellung akzeptabel

### 2. Session-Management

**TANSS:** `apiKey` ist ein JWT mit Ablaufzeit. Bei jedem Workflow-Durchlauf
wird neu eingeloggt (kein Token-Caching zwischen Runs). Simpel und robust.

**S1 (SAP B1):** Session-Cookies müssen innerhalb eines Workflow-Runs weitergegeben
werden. Session-Timeout nach 30 Min. Bei Fehler: Automatischer Re-Login.

### 3. Kein Artikel-Stamm-Lookup

Freitext-Angebote (ohne `ItemCode`) sind bewusste Designentscheidung:
- Techniker kennen Artikelnummern oft nicht
- LLM kennt keine Firmen-internen Artikelnummern
- S1 unterstützt Freitext-Positionen ohne ItemCode

Spätere Optimierung: Fuzzy-Match-Lookup gegen S1 `Items`-Endpunkt.

### 4. Error-Handling-Strategie

```
Fehler-Klassifikation:
├── TRANSIENT (automatisch retry):
│   ├── HTTP 429 (Rate Limit)
│   ├── HTTP 5xx (Server-Fehler)
│   └── Network Timeout
│
└── PERMANENT (Slack-Warnung, kein Retry):
    ├── HTTP 401 (Auth-Fehler → Credentials prüfen)
    ├── confidence_score < 0.6 (Kommentar unklar)
    └── Keine historischen Angebote (RAG gibt 0 Treffer)
```

### 5. Separate Tabelle für Angebots-Embeddings

Siehe `docs/RAG-STRATEGIE.md` für vollständige Begründung. Kurzfassung:
Semantische Isolation von Bookstack-Dokumenten und Angeboten verhindert
Cross-Domain-Similarity-Fehler.

## Monitoring und Observability

### n8n Execution Log

Alle Executions werden in n8n gespeichert:
- Erfolgreiche Runs: Grüne Execution → Angebots-Details im Output
- Fehlgeschlagene Runs: Rote Execution → Fehler im betroffenen Node

### Slack-Benachrichtigungen

| Ereignis | Benachrichtigung |
|----------|-----------------|
| Kommentar nicht parsbar (confidence < 0.6) | Warnung mit Kommentartext |
| S1-Login-Fehler | Kritischer Fehler |
| Angebot erfolgreich erstellt | Keine (kein Spam) |
| Ingestion abgeschlossen | Zusammenfassung (X importiert) |

### Supabase-Metriken

```sql
-- Wöchentliche Statistik
SELECT * FROM angebote_stats();

-- Qualitätsprüfung
SELECT COUNT(*) FROM angebote_qualitaet;

-- Letzte Imports
SELECT angebot_id, angebot_typ, datum, quelle
FROM angebote_uebersicht
ORDER BY created_at DESC
LIMIT 20;
```
