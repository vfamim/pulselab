-- Migration: 20261001220000_enable_v2_sync_and_bancada_sessions.sql
-- Description:
--   1. Flexibiliza colunas legadas NOT NULL (installation_id, regional_hub, computer_id, dyad_id, config_version, config_hash)
--      em research_session_events e research_events para compatibilidade com o protocolo v2 de bancada portátil.
--   2. Adiciona coluna group_id para acomodar o identificador da bancada coletiva.
--   3. Ajusta políticas de RLS e permissões de INSERT e SELECT para anon.
--   4. Cria a tabela research_bancada_sessions com suporte a Store-and-Forward de snapshots completos de sessão.

-- 1. Relax legacy NOT NULL columns on research_session_events to support portable v2
ALTER TABLE public.research_session_events ALTER COLUMN installation_id DROP NOT NULL;
ALTER TABLE public.research_session_events ALTER COLUMN regional_hub DROP NOT NULL;
ALTER TABLE public.research_session_events ALTER COLUMN computer_id DROP NOT NULL;
ALTER TABLE public.research_session_events ALTER COLUMN protocol_version DROP NOT NULL;
ALTER TABLE public.research_session_events ALTER COLUMN config_version DROP NOT NULL;
ALTER TABLE public.research_session_events ALTER COLUMN config_hash DROP NOT NULL;
ALTER TABLE public.research_session_events ALTER COLUMN dyad_id DROP NOT NULL;
ALTER TABLE public.research_session_events ADD COLUMN IF NOT EXISTS group_id uuid;
ALTER TABLE public.research_session_events DROP CONSTRAINT IF EXISTS research_session_events_config_hash_check;

-- 2. Relax legacy NOT NULL columns on research_events to support portable v2
ALTER TABLE public.research_events ALTER COLUMN regional_hub DROP NOT NULL;
ALTER TABLE public.research_events ALTER COLUMN computer_id DROP NOT NULL;
ALTER TABLE public.research_events ALTER COLUMN config_version DROP NOT NULL;
ALTER TABLE public.research_events ALTER COLUMN dyad_id DROP NOT NULL;
ALTER TABLE public.research_events ADD COLUMN IF NOT EXISTS group_id uuid;

-- 3. Adjust RLS policies for anon INSERT
DROP POLICY IF EXISTS "anon_insert_research_events" ON public.research_events;
CREATE POLICY "anon_insert_research_events" ON public.research_events
FOR INSERT TO anon WITH CHECK (
    event_id IS NOT NULL 
    AND session_id IS NOT NULL 
    AND occurred_at IS NOT NULL
);

DROP POLICY IF EXISTS "anon_insert_research_session_events" ON public.research_session_events;
CREATE POLICY "anon_insert_research_session_events" ON public.research_session_events
FOR INSERT TO anon WITH CHECK (
    event_id IS NOT NULL 
    AND session_id IS NOT NULL 
    AND occurred_at IS NOT NULL
);

-- Ensure permissions
GRANT INSERT, SELECT ON TABLE public.research_events TO anon;
GRANT INSERT, SELECT ON TABLE public.research_session_events TO anon;

-- 4. Create research_bancada_sessions table for complete snapshot resilience
CREATE TABLE IF NOT EXISTS public.research_bancada_sessions (
    session_id uuid PRIMARY KEY,
    group_id uuid,
    site_id text,
    school_code text,
    workshop_code text,
    class_code text,
    environment text DEFAULT 'production',
    protocol_version text,
    instrument_version text,
    group_size integer,
    phase text,
    session_payload jsonb NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    received_at timestamp with time zone DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.research_bancada_sessions ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE ON TABLE public.research_bancada_sessions TO anon, authenticated, service_role;

DROP POLICY IF EXISTS "anon_insert_bancada_sessions" ON public.research_bancada_sessions;
CREATE POLICY "anon_insert_bancada_sessions" ON public.research_bancada_sessions
FOR INSERT TO anon WITH CHECK (session_id IS NOT NULL);

DROP POLICY IF EXISTS "anon_update_bancada_sessions" ON public.research_bancada_sessions;
CREATE POLICY "anon_update_bancada_sessions" ON public.research_bancada_sessions
FOR UPDATE TO anon USING (true) WITH CHECK (session_id IS NOT NULL);

DROP POLICY IF EXISTS "anon_select_bancada_sessions" ON public.research_bancada_sessions;
CREATE POLICY "anon_select_bancada_sessions" ON public.research_bancada_sessions
FOR SELECT TO anon USING (true);
