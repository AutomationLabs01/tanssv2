-- =============================================================================
-- 01_roles.sql – Least-Privilege Rollen und Berechtigungen
-- =============================================================================
-- Rollenmodell (Supabase-kompatibel + eigene Erweiterungen):
--
--   supabase_admin          Superuser-ähnlich (nur intern, kein Login von außen)
--   authenticator           PostgREST-Gateway-Rolle (wechselt je nach JWT zu anon/authenticated)
--   anon                    Nicht-authentifizierte Anfragen (SEHR eingeschränkt)
--   authenticated           Eingeloggte Benutzer (Standard-Zugriff)
--   service_role            Voller Zugriff, umgeht RLS (für n8n/Backend)
--   supabase_storage_admin  Storage API
--   supabase_replication_admin Realtime/Replikation
--   n8n_user                n8n Workflow-Datenbank (nur n8n-Schema)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Rollen anlegen (idempotent)
-- ---------------------------------------------------------------------------

-- authenticator: PostgREST-Einsprungpunkt (kein Superuser, kein direkte Rechte)
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticator') THEN
    CREATE ROLE authenticator NOINHERIT NOCREATEDB NOCREATEROLE LOGIN
      PASSWORD 'PLACEHOLDER_AUTHENTICATOR_PASSWORD'  -- wird von Compose via ENV gesetzt
      CONNECTION LIMIT 100;
  END IF;
END; $$;

-- anon: Nicht-authentifizierte Anfragen (minimale Rechte)
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN NOINHERIT;
  END IF;
END; $$;

-- authenticated: Standard-User (eingeloggt via GoTrue)
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN NOINHERIT;
  END IF;
END; $$;

-- service_role: Backend-Zugriff (umgeht RLS)
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
  END IF;
END; $$;

-- supabase_storage_admin: Storage API
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_storage_admin') THEN
    CREATE ROLE supabase_storage_admin NOINHERIT LOGIN
      PASSWORD 'PLACEHOLDER_STORAGE_PASSWORD'
      CONNECTION LIMIT 20;
  END IF;
END; $$;

-- supabase_replication_admin: Logical Replication für Realtime
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_replication_admin') THEN
    CREATE ROLE supabase_replication_admin NOINHERIT LOGIN REPLICATION
      PASSWORD 'PLACEHOLDER_REPLICATION_PASSWORD'
      CONNECTION LIMIT 10;
  END IF;
END; $$;

-- n8n_user: n8n Workflow-Datenbank (nur n8n-Schema)
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'n8n_user') THEN
    CREATE ROLE n8n_user NOINHERIT NOCREATEDB NOCREATEROLE LOGIN
      PASSWORD 'PLACEHOLDER_N8N_PASSWORD'
      CONNECTION LIMIT 20;
  END IF;
END; $$;

-- ---------------------------------------------------------------------------
-- Rollen-Hierarchie: authenticator darf als anon/authenticated/service_role agieren
-- ---------------------------------------------------------------------------
GRANT anon        TO authenticator;
GRANT authenticated TO authenticator;
GRANT service_role  TO authenticator;

-- ---------------------------------------------------------------------------
-- Schema-Berechtigungen: anon (minimale Rechte)
-- ---------------------------------------------------------------------------
-- public schema: anon darf lesen (mit RLS), NICHT schreiben
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;
GRANT USAGE ON SCHEMA extensions TO anon, authenticated, service_role;

-- anon: kein Schreibzugriff auf irgendeine Tabelle standardmäßig
-- (RLS-Policies in den Migrations erlauben spezifischen Zugriff)
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES TO anon;

-- authenticated: SELECT + Standard-Operationen (DML via RLS eingeschränkt)
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated;

-- service_role: voller Zugriff (für n8n-Workflows, Backend)
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON SEQUENCES TO service_role;

-- ---------------------------------------------------------------------------
-- n8n-Schema: nur n8n_user hat Zugriff
-- ---------------------------------------------------------------------------
GRANT ALL PRIVILEGES ON SCHEMA n8n TO n8n_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA n8n TO n8n_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA n8n TO n8n_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA n8n
  GRANT ALL ON TABLES TO n8n_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA n8n
  GRANT ALL ON SEQUENCES TO n8n_user;

-- n8n_user braucht auch Zugriff auf public für Supabase-RPC-Aufrufe
GRANT USAGE ON SCHEMA public TO n8n_user;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO n8n_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO n8n_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO n8n_user;

-- ---------------------------------------------------------------------------
-- anon darf KEINE Funktionen mit SECURITY DEFINER ausführen
-- (Ausnahme: match_angebote, angebot_exists – explizit erlaubt)
-- Wird in den Migrations spezifisch per GRANT EXECUTE gesteuert
-- ---------------------------------------------------------------------------
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE ALL ON FUNCTIONS FROM anon;

-- ---------------------------------------------------------------------------
-- Explizite RLS-Aktivierung für kritische Tabellen (Reminder)
-- Wird in den Supabase-Migrations gesetzt, hier als Sicherheitsnetz
-- ---------------------------------------------------------------------------
-- Die angebote_vectors-Tabelle wird in Migration 001 mit RLS angelegt.
-- Zur Sicherheit: Falls Tabelle bereits existiert, RLS erzwingen.
DO $$
BEGIN
  IF EXISTS (SELECT FROM information_schema.tables
             WHERE table_schema = 'public' AND table_name = 'angebote_vectors') THEN
    ALTER TABLE public.angebote_vectors ENABLE ROW LEVEL SECURITY;
    ALTER TABLE public.angebote_vectors FORCE ROW LEVEL SECURITY;
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Verbindungslimits per Rolle (Defense in Depth gegen Connection Flooding)
-- ---------------------------------------------------------------------------
ALTER ROLE authenticator       CONNECTION LIMIT 100;
ALTER ROLE n8n_user            CONNECTION LIMIT 20;
ALTER ROLE supabase_storage_admin CONNECTION LIMIT 20;
ALTER ROLE supabase_replication_admin CONNECTION LIMIT 10;

-- supabase_admin: in Produktion auf benötigte Verbindungen begrenzen
ALTER ROLE supabase_admin      CONNECTION LIMIT 10;
