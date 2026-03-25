-- =============================================================================
-- Migration 001: Angebote Vectors Tabelle
-- =============================================================================
-- WICHTIG: Separate Tabelle, NICHT die bestehende "documents"-Tabelle erweitern!
-- Die bestehende Bookstack-RAG-Infrastruktur bleibt unangetastet.
-- =============================================================================

-- pgvector Extension (falls noch nicht aktiv)
CREATE EXTENSION IF NOT EXISTS vector;

-- Haupttabelle für Angebots-Embeddings
CREATE TABLE IF NOT EXISTS angebote_vectors (
  id              BIGSERIAL PRIMARY KEY,
  content         TEXT NOT NULL,                    -- Natürlichsprachliche Serialisierung des Angebots
  embedding       VECTOR(1536) NOT NULL,            -- text-embedding-3-small = 1536 Dimensionen
  metadata        JSONB DEFAULT '{}'::JSONB,        -- Strukturierte Metadaten für Filterung
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- Metadata-Felder die befüllt werden sollen:
-- {
--   "angebot_id":        "ANG-2025-0042",
--   "angebot_typ":       "PC-Arbeitsplatz",   -- PC-Arbeitsplatz | Server | Netzwerk |
--                                             --  Drucker | Telefonie | Software | Mischung
--   "kunde_branche":     "Kanzlei",
--   "kategorien":        ["Hardware", "Peripherie", "Lizenzen", "Service"],
--   "positionen_anzahl": 12,
--   "gesamtwert_netto":  4850.00,
--   "datum":             "2025-06-15",
--   "status":            "gewonnen",          -- gewonnen | verloren | offen
--   "ersteller":         "Max Mustermann",
--   "quelle":            "systemhaus-one"     -- systemhaus-one | csv | pdf
-- }
-- -----------------------------------------------------------------------------

-- HNSW-Index für schnelle Cosine Similarity Search (besser als IVFFlat für kleine DBs)
CREATE INDEX IF NOT EXISTS angebote_vectors_embedding_idx
  ON angebote_vectors
  USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

-- GIN-Index auf Metadata für schnelle JSONB-Filterung (z. B. angebot_typ = 'Server')
CREATE INDEX IF NOT EXISTS angebote_vectors_metadata_idx
  ON angebote_vectors
  USING gin (metadata jsonb_path_ops);

-- Funktionaler Index auf angebot_typ für häufige Filterung ohne JSONB-Overhead
CREATE INDEX IF NOT EXISTS angebote_vectors_typ_idx
  ON angebote_vectors ((metadata->>'angebot_typ'));

-- Funktionaler Index auf Status für Filterung nach gewonnen/verloren/offen
CREATE INDEX IF NOT EXISTS angebote_vectors_status_idx
  ON angebote_vectors ((metadata->>'status'));

-- Trigger: updated_at automatisch aktualisieren
CREATE OR REPLACE FUNCTION update_angebote_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER angebote_vectors_updated_at
  BEFORE UPDATE ON angebote_vectors
  FOR EACH ROW
  EXECUTE FUNCTION update_angebote_updated_at();

-- Row Level Security aktivieren (Supabase Best Practice)
ALTER TABLE angebote_vectors ENABLE ROW LEVEL SECURITY;

-- Policy: Service Role darf alles lesen und schreiben
CREATE POLICY "service_role_full_access" ON angebote_vectors
  USING (true)
  WITH CHECK (true);

COMMENT ON TABLE angebote_vectors IS
  'Vector-Embeddings historischer Angebote aus Systemhaus.ONE für RAG-Vollständigkeitsprüfung. '
  'NICHT mit der Bookstack-documents-Tabelle verwechseln!';

COMMENT ON COLUMN angebote_vectors.content IS
  'Natürlichsprachliche Serialisierung des Angebots nach dem Template in prompts/angebot-serialisierung.md';

COMMENT ON COLUMN angebote_vectors.embedding IS
  'Embedding-Vektor aus OpenAI text-embedding-3-small (1536 Dimensionen)';

COMMENT ON COLUMN angebote_vectors.metadata IS
  'Strukturierte Metadaten: angebot_id, angebot_typ, kunde_branche, kategorien, '
  'positionen_anzahl, gesamtwert_netto, datum, status, ersteller, quelle';
