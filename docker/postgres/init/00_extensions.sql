-- =============================================================================
-- 00_extensions.sql – Extensions und Basis-Setup
-- Wird beim ersten Start des Containers ausgeführt (docker-entrypoint-initdb.d)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
-- pgvector: Vektorsuche für RAG (Angebots-Embeddings)
CREATE EXTENSION IF NOT EXISTS vector          WITH SCHEMA extensions;

-- pg_stat_statements: Query-Performance-Monitoring
CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA extensions;

-- uuid-ossp: UUID-Generierung (Supabase Standard)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp"     WITH SCHEMA extensions;

-- pgcrypto: Kryptographie-Funktionen (für Supabase Auth)
CREATE EXTENSION IF NOT EXISTS pgcrypto        WITH SCHEMA extensions;

-- pg_net: Asynchrone HTTP-Requests aus Postgres (Supabase Edge Functions)
-- Nur installieren wenn pg_net im Image verfügbar ist
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_net') THEN
    EXECUTE 'CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions';
  END IF;
END;
$$;

-- pgjwt: JWT-Generierung (Supabase Auth)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pgjwt') THEN
    EXECUTE 'CREATE EXTENSION IF NOT EXISTS pgjwt WITH SCHEMA extensions';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Schemas erstellen
-- ---------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS storage;
CREATE SCHEMA IF NOT EXISTS _realtime;
CREATE SCHEMA IF NOT EXISTS n8n;        -- Eigenes Schema für n8n (Isolation)
CREATE SCHEMA IF NOT EXISTS graphql_public;

-- ---------------------------------------------------------------------------
-- Search Path – Reihenfolge der Schema-Suche
-- ---------------------------------------------------------------------------
ALTER DATABASE postgres SET search_path TO public, extensions;
