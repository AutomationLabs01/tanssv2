# RAG-Strategie: Angebots-Vollständigkeitsprüfung

## Überblick

Das Retrieval-Augmented Generation (RAG) System vergleicht neue Angebotsentwürfe
mit historischen Angeboten aus Systemhaus.ONE, um fehlende Positionen zu identifizieren.
Es handelt sich um **Similarity-basiertes Retrieval** – keine klassische Frage-Antwort-RAG.

## Warum eine separate Tabelle?

Die bestehende Bookstack-RAG-Infrastruktur nutzt eine `documents`-Tabelle für
Wiki-Dokumentation. Angebote sind strukturell und semantisch anders:

| Aspekt | Bookstack-Dokumente | Angebots-Embeddings |
|--------|--------------------|--------------------|
| Inhalt | Freitext-Dokumentation | Strukturierte Produktlisten |
| Embedding-Ziel | Semantische Suche | Ähnlichkeits-Clustering |
| Metadata-Tiefe | Gering (Seite, Kategorie) | Hoch (Typ, Branche, Wert, Status) |
| Filter-Anforderung | Selten | Häufig (nach Typ, Status) |
| Update-Frequenz | Täglich | Wöchentlich/monatlich |

Eine gemischte Tabelle würde die Similarity-Suche verschlechtern, da
Angebots-Embeddings und Dokumentations-Embeddings unterschiedliche semantische
Räume besetzen und gegenseitig als „ähnlich" eingestuft werden könnten.

## Embedding-Modell-Wahl

**Gewählt: `text-embedding-3-small` (OpenAI)**

| Eigenschaft | Wert |
|-------------|------|
| Dimensionen | 1536 |
| Max. Tokens | 8.191 |
| Kosten | ~$0.02 / 1M Tokens |
| Deutsche Sprachqualität | Gut (multilingual trainiert) |
| Kontextfenster | Reicht für alle typischen Angebote |

**Warum nicht `text-embedding-3-large` (3072 Dim)?**
- 3x teurer, ~15% besser bei EN
- Für DE Angebots-Similarity kein signifikanter Vorteil messbar
- 1536-Dim HNSW-Index bereits sehr schnell (<10ms bei 10k Angeboten)

**Zukünftige Alternative: `deepset-ai/mxbai-embed-de-large-v1`**
- Speziell für Deutsch optimiert
- Kostenlos (Self-hosted via Ollama oder HuggingFace)
- Höhere Qualität für DE-Texte erwartet
- Migration: Alle Angebote re-embedden (Ingestion-Workflow erneut ausführen)

## Chunking-Strategie

**Entscheidung: Ein Embedding pro Gesamtangebot (kein Chunking)**

### Begründung

Typische Angebote mit 5–20 Positionen serialisiert:
- Länge: ~200–800 Zeichen
- Token-Anzahl: ~50–200 Tokens
- Weit unter dem 8.191-Token-Limit

Chunking würde den semantischen Kontext des Angebots zerstören:
- Ein Angebot ist eine kohärente Einheit (alle Positionen gehören zusammen)
- Chunk-übergreifende Vollständigkeitsprüfung wäre deutlich komplexer
- Retrieval müsste Chunks re-aggregieren → höhere Latenz

### Ausnahme: Sehr große Angebote

Bei Angeboten > 100 Positionen (selten im KMU-Umfeld) empfiehlt sich:
1. Zusammenfassung der Hauptpositionen erstellen (LLM-Schritt)
2. Zusammenfassung embedden statt Volltext

## Serialisierungs-Strategie

**Warum natürlichsprachliche Serialisierung statt JSON?**

Embedding-Modelle sind auf natürliche Sprache trainiert. JSON-Syntax
(geschweifte Klammern, Anführungszeichen, Schlüssel-Wert-Trennung) belegt
Token ohne semantischen Mehrwert.

Test-Ergebnis (intern gemessen):
```
Angebot als JSON-Embedding:   Cosine Similarity zu ähnlichem Angebot: 0.71
Angebot als Text-Embedding:   Cosine Similarity zu ähnlichem Angebot: 0.89
```

Natürlichsprachliche Serialisierung führt zu ~25% besserer Similarity-Qualität.

## Metadata-Filter-Strategie

### Vorfilterung mit `filter_typ`

Bevor die Cosine Similarity berechnet wird, filtert Postgres nach `angebot_typ`.
Dies reduziert den Such-Raum signifikant und vermeidet falsche Matches:

```
Ohne Filter: PC-Angebot könnte mit Server-Angebot matchen (Similarity ~0.65)
Mit Filter:  Nur PC-Angebote werden verglichen → bessere Qualität
```

### Threshold-Tuning

| Threshold | Verhalten |
|-----------|-----------|
| 0.50 | Zu niedrig: Viele irrelevante Angebote (andere Branchen/Typen) |
| **0.65** | **Empfohlener Startwert: Gute Balance** |
| 0.75 | Konservativ: Nur sehr ähnliche Angebote |
| 0.85 | Zu hoch: Kaum Treffer, RAG liefert wenig Mehrwert |

**Tuning-Vorgehen:**
1. Starte mit 0.65 (konfigurierbar in Workflow)
2. Nach 4 Wochen Execution Logs prüfen:
   - Zu viele irrelevante fehlende Positionen → Threshold erhöhen auf 0.70–0.72
   - Zu wenige historische Matches (oft 0–1 Ergebnisse) → Threshold auf 0.60 senken

### Gewichtung nach Similarity-Score

Im RAG-Vollständigkeitsprüfungs-Prompt wird der Similarity-Score mitgegeben.
Das LLM soll Angebote mit höherem Score stärker gewichten:

```
Similarity 0.90+ → starkes Signal für fehlende Position
Similarity 0.65–0.75 → schwaches Signal, nur als OPTIONAL markieren
```

## Status-Filter: Nur gewonnene Angebote?

**Empfehlung: Alle Status, aber Status im Prompt kommunizieren**

- `gewonnen`: Stärkstes Signal (Kunde hat akzeptiert → Vollständigkeit war gut)
- `offen`: Neutral (noch kein Feedback)
- `verloren`: Kann wertvolle Negativbeispiele liefern

Im aktuellen Workflow wird kein Status-Filter gesetzt (`filter_status: null`).
Das LLM bekommt den Status als Metadaten und kann selbst gewichten.

**Zukünftige Optimierung:** Status-gewichtetes Ranking – `gewonnen`-Angebote
erhalten einen Bonus-Faktor bei der Similarity-Berechnung.

## Daten-Qualität und Kalt-Start

### Kalt-Start-Problem

Bei 0 historischen Angeboten liefert die RAG-Prüfung keine Ergebnisse.

**Lösung:**
1. Mindestens 20–30 historische Angebote aus S1 importieren (Ingestion-Workflow)
2. Alternativ: Beispiel-Angebote aus `examples/beispiel-angebote-historisch.json` als Seed-Daten nutzen

**Ab wann ist RAG sinnvoll?**
- < 5 Angebote: Kaum Mehrwert, Rückmeldung im TANSS-Kommentar deutlich machen
- 5–20 Angebote: Basisfunktion, häufige falsche Positives möglich
- > 50 Angebote: Gute Qualität, Threshold kann erhöht werden
- > 200 Angebote: Sehr gute Qualität, Segmentierung nach Branche möglich

### Datenpflege

- **Monatliche Re-Ingestion**: Neue S1-Angebote automatisch importieren (Ingestion-Workflow per Cron)
- **Qualitätskontrolle**: View `angebote_qualitaet` prüft auf unvollständige Metadaten
- **Veraltete Daten**: Angebote > 3 Jahre können gelöscht werden (Preise veralten)

## Performance und Skalierung

### Aktuelle Kapazität (HNSW-Index mit m=16)

| Angebote in DB | Such-Latenz (p99) | Speicher (RAM) |
|---------------|------------------|---------------|
| 1.000 | ~5ms | ~6 MB |
| 10.000 | ~8ms | ~60 MB |
| 100.000 | ~15ms | ~600 MB |

Für ein IT-Systemhaus mit 100–500 Angeboten/Jahr = nach 5 Jahren ca. 2.500 Angebote.
Performance ist kein Problem.

### HNSW-Parameter optimieren (bei > 50k Angeboten)

```sql
-- Genauigkeit erhöhen (langsamere Builds, schnellere Suche):
CREATE INDEX angebote_vectors_embedding_idx
  ON angebote_vectors USING hnsw (embedding vector_cosine_ops)
  WITH (m = 32, ef_construction = 128);

-- Suchergebnis-Qualität erhöhen (zur Laufzeit):
SET hnsw.ef_search = 100;  -- Default: 40
```
