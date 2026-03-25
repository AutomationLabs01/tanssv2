-- =============================================================================
-- 02_realtime.sql – Supabase Realtime Logical Replication Setup
-- =============================================================================

-- Publication für Realtime (nur öffentliche Tabellen)
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
END;
$$;

-- angebote_vectors zur Realtime-Publication hinzufügen (optional, für Live-Updates)
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.angebote_vectors;

-- Replication Slot für Realtime-Service
SELECT pg_create_logical_replication_slot('supabase_realtime_replication_slot', 'pgoutput')
WHERE NOT EXISTS (
  SELECT FROM pg_replication_slots
  WHERE slot_name = 'supabase_realtime_replication_slot'
);

-- Berechtigungen für Realtime
GRANT USAGE ON SCHEMA _realtime TO supabase_admin;
GRANT ALL   ON ALL TABLES IN SCHEMA _realtime TO supabase_admin;

-- Replikationsberechtigungen
GRANT REPLICATION TO supabase_replication_admin;
