-- Migration: 20261003150000_revoke_excessive_anon_access.sql
-- Description:
--   Correção forward-only revogando privilégios e políticas anônimas excessivas
--   concedidas na migração 20261001220000.
--   1. Restaura o modelo de privilégio mínimo: role anon não pode ler nem inserir
--      em research_events e research_session_events.
--   2. Revoga SELECT, INSERT e UPDATE anônimos irrestritos em research_bancada_sessions.
--   3. Restringe research_bancada_sessions a service_role (operações administrativas
--      de importação/consolidação) e authenticated devidamente vinculado a site_id.

-- 1. Revoga privilégios anônimos de research_events e research_session_events
REVOKE ALL ON TABLE public.research_events FROM anon;
REVOKE ALL ON TABLE public.research_session_events FROM anon;

DROP POLICY IF EXISTS "anon_insert_research_events" ON public.research_events;
DROP POLICY IF EXISTS "anon_select_research_events" ON public.research_events;
DROP POLICY IF EXISTS "anon_insert_research_session_events" ON public.research_session_events;
DROP POLICY IF EXISTS "anon_select_research_session_events" ON public.research_session_events;

-- 2. Revoga privilégios e políticas anônimas irrestritas em research_bancada_sessions
REVOKE ALL ON TABLE public.research_bancada_sessions FROM anon;

DROP POLICY IF EXISTS "anon_select_bancada_sessions" ON public.research_bancada_sessions;
DROP POLICY IF EXISTS "anon_update_bancada_sessions" ON public.research_bancada_sessions;
DROP POLICY IF EXISTS "anon_insert_bancada_sessions" ON public.research_bancada_sessions;

-- 3. Configura permissões estritas em research_bancada_sessions
-- Snapshots de bancada são estritamente append-only para dispositivos autenticados.
-- Atualizações e reconciliações são reservadas exclusivamente para o service_role (importador/pesquisador).
ALTER TABLE public.research_bancada_sessions ADD COLUMN IF NOT EXISTS installation_id uuid;

REVOKE UPDATE, DELETE ON TABLE public.research_bancada_sessions FROM authenticated;
GRANT SELECT, INSERT ON TABLE public.research_bancada_sessions TO authenticated;
GRANT ALL ON TABLE public.research_bancada_sessions TO service_role;

DROP POLICY IF EXISTS authenticated_insert_bancada_sessions ON public.research_bancada_sessions;
CREATE POLICY authenticated_insert_bancada_sessions ON public.research_bancada_sessions
FOR INSERT TO authenticated
WITH CHECK (
    session_id IS NOT NULL
    AND research_bancada_sessions.site_id IS NOT NULL
    AND research_bancada_sessions.installation_id IS NOT NULL
    AND EXISTS (
        SELECT 1 FROM public.device_installations d
        WHERE d.device_user_id = (SELECT auth.uid())
        AND d.installation_id = research_bancada_sessions.installation_id
        AND d.site_id = research_bancada_sessions.site_id
        AND d.is_active
    )
);

DROP POLICY IF EXISTS authenticated_select_bancada_sessions ON public.research_bancada_sessions;
CREATE POLICY authenticated_select_bancada_sessions ON public.research_bancada_sessions
FOR SELECT TO authenticated
USING (
    (
        research_bancada_sessions.site_id IS NOT NULL
        AND EXISTS (
            SELECT 1 FROM public.research_site_memberships m
            WHERE m.user_id = (SELECT auth.uid())
            AND m.site_id = research_bancada_sessions.site_id
            AND m.is_active
        )
    )
    OR (
        research_bancada_sessions.site_id IS NOT NULL
        AND research_bancada_sessions.installation_id IS NOT NULL
        AND EXISTS (
            SELECT 1 FROM public.device_installations d
            WHERE d.device_user_id = (SELECT auth.uid())
            AND d.installation_id = research_bancada_sessions.installation_id
            AND d.site_id = research_bancada_sessions.site_id
            AND d.is_active
        )
    )
);

DROP POLICY IF EXISTS authenticated_update_bancada_sessions ON public.research_bancada_sessions;

-- 4. Alinha constraints de tipo de evento em research_session_events
DO $$
BEGIN
    ALTER TABLE public.research_session_events
        DROP CONSTRAINT IF EXISTS research_session_events_event_type_check;

    ALTER TABLE public.research_session_events
        ADD CONSTRAINT research_session_events_event_type_check
        CHECK (event_type IN (
            'session_started',
            'phase_completed',
            'phase_transition',
            'activity_started',
            'heartbeat',
            'checkpoint_started',
            'checkpoint_completed',
            'help_requested',
            'role_swapped',
            'spike_telemetry',
            'experience_recorded',
            'race_recorded',
            'quiz_recorded',
            'ending_requested',
            'rubric_completed',
            'session_completed',
            'session_aborted',
            'quality_issue'
        ));
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Constraint update skipped or already aligned: %', SQLERRM;
END $$;
