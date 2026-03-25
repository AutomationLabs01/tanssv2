-- =============================================================================
-- Migration 002: RPC-Funktionen für Similarity Search
-- =============================================================================
-- Diese Funktionen werden vom n8n-Workflow per HTTP oder Supabase-Node aufgerufen.
-- Aufruf-Beispiel:
--   POST /rest/v1/rpc/match_angebote
--   { "query_embedding": [...], "match_threshold": 0.65, "filter_typ": "PC-Arbeitsplatz" }
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Funktion 1: match_angebote
-- Similarity Search mit optionalem Metadata-Filter nach angebot_typ und status
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION match_angebote(
  query_embedding  VECTOR(1536),
  match_threshold  FLOAT   DEFAULT 0.7,
  match_count      INT     DEFAULT 5,
  filter_typ       TEXT    DEFAULT NULL,
  filter_status    TEXT    DEFAULT NULL
)
RETURNS TABLE (
  id          BIGINT,
  content     TEXT,
  metadata    JSONB,
  similarity  FLOAT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    av.id,
    av.content,
    av.metadata,
    (1 - (av.embedding <=> query_embedding))::FLOAT AS similarity
  FROM angebote_vectors av
  WHERE
    (1 - (av.embedding <=> query_embedding)) > match_threshold
    AND (filter_typ    IS NULL OR av.metadata->>'angebot_typ' = filter_typ)
    AND (filter_status IS NULL OR av.metadata->>'status'      = filter_status)
  ORDER BY av.embedding <=> query_embedding   -- ASC = niedrigste Distanz zuerst
  LIMIT match_count;
END;
$$;

COMMENT ON FUNCTION match_angebote IS
  'Führt eine Cosine-Similarity-Suche auf angebote_vectors durch. '
  'filter_typ und filter_status sind optional – bei NULL werden alle Datensätze berücksichtigt.';

-- -----------------------------------------------------------------------------
-- Funktion 2: match_angebote_multi_typ
-- Wie match_angebote, aber mit Array von erlaubten Typen (für Mischungstypen)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION match_angebote_multi_typ(
  query_embedding  VECTOR(1536),
  match_threshold  FLOAT    DEFAULT 0.65,
  match_count      INT      DEFAULT 10,
  filter_typen     TEXT[]   DEFAULT NULL
)
RETURNS TABLE (
  id          BIGINT,
  content     TEXT,
  metadata    JSONB,
  similarity  FLOAT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    av.id,
    av.content,
    av.metadata,
    (1 - (av.embedding <=> query_embedding))::FLOAT AS similarity
  FROM angebote_vectors av
  WHERE
    (1 - (av.embedding <=> query_embedding)) > match_threshold
    AND (filter_typen IS NULL OR av.metadata->>'angebot_typ' = ANY(filter_typen))
  ORDER BY av.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;

-- -----------------------------------------------------------------------------
-- Funktion 3: angebote_stats
-- Statistiken über die Angebots-Vektordatenbank (für Monitoring/Dashboard)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION angebote_stats()
RETURNS TABLE (
  total_angebote     BIGINT,
  angebote_pro_typ   JSONB,
  angebote_pro_status JSONB,
  letztes_update     TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_total    BIGINT;
  v_pro_typ  JSONB;
  v_pro_status JSONB;
  v_letztes  TIMESTAMPTZ;
BEGIN
  SELECT COUNT(*) INTO v_total FROM angebote_vectors;

  SELECT jsonb_object_agg(typ, anzahl)
  INTO v_pro_typ
  FROM (
    SELECT
      COALESCE(metadata->>'angebot_typ', 'unbekannt') AS typ,
      COUNT(*)                                         AS anzahl
    FROM angebote_vectors
    GROUP BY 1
  ) sub;

  SELECT jsonb_object_agg(status, anzahl)
  INTO v_pro_status
  FROM (
    SELECT
      COALESCE(metadata->>'status', 'unbekannt') AS status,
      COUNT(*)                                    AS anzahl
    FROM angebote_vectors
    GROUP BY 1
  ) sub;

  SELECT MAX(created_at) INTO v_letztes FROM angebote_vectors;

  RETURN QUERY
  SELECT v_total, v_pro_typ, v_pro_status, v_letztes;
END;
$$;

COMMENT ON FUNCTION angebote_stats IS
  'Liefert Statistiken über die Angebots-Vektordatenbank: Gesamtanzahl, Aufschlüsselung nach Typ und Status.';
