-- =============================================================================
-- Migration 003: Ingestion-Helper Views und Funktionen
-- =============================================================================
-- Diese Objekte unterstützen den Ingestion-Workflow und die Administrations-UI.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- View 1: angebote_uebersicht
-- Alle Angebote mit aufgelösten Metadaten für einfache Übersicht
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW angebote_uebersicht AS
SELECT
  id,
  metadata->>'angebot_id'                              AS angebot_id,
  metadata->>'angebot_typ'                             AS angebot_typ,
  metadata->>'kunde_branche'                           AS branche,
  (metadata->>'positionen_anzahl')::INT                AS positionen,
  (metadata->>'gesamtwert_netto')::NUMERIC(12, 2)      AS wert_netto,
  metadata->>'status'                                  AS status,
  (metadata->>'datum')::DATE                           AS datum,
  metadata->>'ersteller'                               AS ersteller,
  metadata->>'quelle'                                  AS quelle,
  metadata->'kategorien'                               AS kategorien,
  LEFT(content, 200)                                   AS vorschau,
  created_at,
  updated_at
FROM angebote_vectors
ORDER BY created_at DESC;

COMMENT ON VIEW angebote_uebersicht IS
  'Lesbare Übersicht aller Angebote mit aufgelösten JSONB-Metadaten. '
  'Nur für Lesezugriff – Schreiboperationen direkt auf angebote_vectors.';

-- -----------------------------------------------------------------------------
-- View 2: angebote_qualitaet
-- Qualitätsprüfung: Angebote mit unvollständigen Metadaten identifizieren
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW angebote_qualitaet AS
SELECT
  id,
  metadata->>'angebot_id'   AS angebot_id,
  CASE WHEN metadata->>'angebot_id'        IS NULL THEN 'Kein angebot_id; '       ELSE '' END ||
  CASE WHEN metadata->>'angebot_typ'       IS NULL THEN 'Kein angebot_typ; '      ELSE '' END ||
  CASE WHEN metadata->>'datum'             IS NULL THEN 'Kein datum; '            ELSE '' END ||
  CASE WHEN metadata->>'status'            IS NULL THEN 'Kein status; '           ELSE '' END ||
  CASE WHEN metadata->>'gesamtwert_netto'  IS NULL THEN 'Kein gesamtwert_netto; ' ELSE '' END
    AS fehlende_felder,
  created_at
FROM angebote_vectors
WHERE
  metadata->>'angebot_id'       IS NULL OR
  metadata->>'angebot_typ'      IS NULL OR
  metadata->>'datum'            IS NULL OR
  metadata->>'status'           IS NULL OR
  metadata->>'gesamtwert_netto' IS NULL;

-- -----------------------------------------------------------------------------
-- Funktion 1: angebot_exists
-- Duplikat-Check vor Ingestion (per angebot_id in Metadata)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION angebot_exists(p_angebot_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS(
    SELECT 1
    FROM angebote_vectors
    WHERE metadata->>'angebot_id' = p_angebot_id
  );
$$;

COMMENT ON FUNCTION angebot_exists IS
  'Prüft ob ein Angebot mit der gegebenen angebot_id bereits in angebote_vectors existiert. '
  'Wird vom Ingestion-Workflow aufgerufen bevor ein neues Embedding gespeichert wird.';

-- -----------------------------------------------------------------------------
-- Funktion 2: upsert_angebot
-- Füge Angebot ein oder aktualisiere es wenn angebot_id bereits existiert
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION upsert_angebot(
  p_content    TEXT,
  p_embedding  VECTOR(1536),
  p_metadata   JSONB
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_angebot_id TEXT;
  v_existing_id BIGINT;
  v_result_id   BIGINT;
BEGIN
  v_angebot_id := p_metadata->>'angebot_id';

  IF v_angebot_id IS NOT NULL THEN
    SELECT id INTO v_existing_id
    FROM angebote_vectors
    WHERE metadata->>'angebot_id' = v_angebot_id;
  END IF;

  IF v_existing_id IS NOT NULL THEN
    -- Update: Embedding und Content aktualisieren
    UPDATE angebote_vectors
    SET
      content    = p_content,
      embedding  = p_embedding,
      metadata   = p_metadata,
      updated_at = NOW()
    WHERE id = v_existing_id;
    v_result_id := v_existing_id;
  ELSE
    -- Insert: Neuen Datensatz anlegen
    INSERT INTO angebote_vectors (content, embedding, metadata)
    VALUES (p_content, p_embedding, p_metadata)
    RETURNING id INTO v_result_id;
  END IF;

  RETURN v_result_id;
END;
$$;

COMMENT ON FUNCTION upsert_angebot IS
  'Fügt ein neues Angebot in angebote_vectors ein oder aktualisiert es falls angebot_id bereits existiert. '
  'Gibt die ID des eingefügten/aktualisierten Datensatzes zurück.';

-- -----------------------------------------------------------------------------
-- Funktion 3: angebote_loeschen_nach_quelle
-- Bulk-Löschung aller Angebote einer bestimmten Quelle (für Re-Ingestion)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION angebote_loeschen_nach_quelle(p_quelle TEXT)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_deleted INT;
BEGIN
  DELETE FROM angebote_vectors
  WHERE metadata->>'quelle' = p_quelle;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

COMMENT ON FUNCTION angebote_loeschen_nach_quelle IS
  'Löscht alle Angebote mit der gegebenen Quelle (z. B. "csv" oder "systemhaus-one"). '
  'Nützlich für vollständige Re-Ingestion. Vorsichtig einsetzen!';
