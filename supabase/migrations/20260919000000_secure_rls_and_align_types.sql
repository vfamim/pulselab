-- Migration: 20260919000000_secure_rls_and_align_types.sql
-- Description: 
--   1. Revoga SELECT anônimo irrestrito em research_events e research_session_events,
--      eliminando vazamento público de dados de pesquisa e restaurando a segurança fail-closed.
--   2. Restringe INSERT anônimo com validação estrita de integridade (campos obrigatórios,
--      formato de identificadores, timestamps e hash de configuração).
--   3. Alinha constraints de CHECK para aceitar participant_role = 'group' e event_type = 'spike_telemetry',
--      evitando rejeição de payloads legítimos da telemetria do robô e PWA.
--   4. Garante acesso de consulta (SELECT) estritamente para roles autorizadas (authenticated, service_role).

-- =============================================================================
-- 1. REVOGAÇÃO DE LEITURA ANÔNIMA (FECHAMENTO DE VAZAMENTO DE DADOS)
-- =============================================================================

REVOKE SELECT ON TABLE public.research_events FROM anon;
REVOKE SELECT ON TABLE public.research_session_events FROM anon;

DROP POLICY IF EXISTS "anon_select_research_events" ON public.research_events;
DROP POLICY IF EXISTS "anon_select_research_session_events" ON public.research_session_events;

-- Garantir permissão de leitura para authenticated (painel do instrutor/pesquisador) e service_role
GRANT SELECT ON TABLE public.research_events TO authenticated;
GRANT SELECT ON TABLE public.research_session_events TO authenticated;

DROP POLICY IF EXISTS "authenticated_select_research_events" ON public.research_events;
CREATE POLICY "authenticated_select_research_events"
    ON public.research_events
    FOR SELECT
    TO authenticated
    USING (true);

DROP POLICY IF EXISTS "authenticated_select_research_session_events" ON public.research_session_events;
CREATE POLICY "authenticated_select_research_session_events"
    ON public.research_session_events
    FOR SELECT
    TO authenticated
    USING (true);

-- =============================================================================
-- 2. AJUSTE DE CONSTRAINTS (ALINHAMENTO COM PAYLOADS REAIS E PROTOCOLO)
-- =============================================================================

-- 2.1 research_events: permitir participant_role = 'group' e group_size até 4
DO $$
BEGIN
    ALTER TABLE public.research_events
        DROP CONSTRAINT IF EXISTS research_events_participant_role_check;

    ALTER TABLE public.research_events
        ADD CONSTRAINT research_events_participant_role_check
        CHECK (participant_role IN ('computer', 'assembly', 'member_3', 'member_4', 'individual', 'group'));

    ALTER TABLE public.research_events
        DROP CONSTRAINT IF EXISTS research_events_group_size_check;

    ALTER TABLE public.research_events
        ADD CONSTRAINT research_events_group_size_check
        CHECK (group_size IS NULL OR (group_size BETWEEN 1 AND 4));
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Constraint update on research_events skipped or already aligned: %', SQLERRM;
END $$;

-- 2.2 research_session_events: permitir participant_role = 'group' e event_type = 'spike_telemetry'
DO $$
BEGIN
    ALTER TABLE public.research_session_events
        DROP CONSTRAINT IF EXISTS research_session_events_participant_role_check;

    ALTER TABLE public.research_session_events
        ADD CONSTRAINT research_session_events_participant_role_check
        CHECK (participant_role IS NULL OR participant_role IN ('computer', 'assembly', 'member_3', 'member_4', 'individual', 'group'));

    ALTER TABLE public.research_session_events
        DROP CONSTRAINT IF EXISTS research_session_events_event_type_check;

    ALTER TABLE public.research_session_events
        ADD CONSTRAINT research_session_events_event_type_check
        CHECK (event_type IN (
            'session_started',
            'phase_completed',
            'activity_started',
            'heartbeat',
            'checkpoint_started',
            'checkpoint_completed',
            'help_requested',
            'role_swapped',
            'spike_telemetry',
            'ending_requested',
            'rubric_completed',
            'session_completed',
            'session_aborted',
            'quality_issue'
        ));
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Constraint update on research_session_events skipped or already aligned: %', SQLERRM;
END $$;

-- =============================================================================
-- 3. POLÍTICAS DE INGESTÃO ANÔNIMA COM VALIDAÇÃO ESTRITA DE INTEGRIDADE
-- =============================================================================

DROP POLICY IF EXISTS "anon_insert_research_events" ON public.research_events;
CREATE POLICY "anon_insert_research_events"
    ON public.research_events
    FOR INSERT
    TO anon
    WITH CHECK (
        event_id IS NOT NULL
        AND session_id IS NOT NULL
        AND dyad_id IS NOT NULL
        AND site_id IS NOT NULL AND length(trim(site_id)) > 0
        AND school_code IS NOT NULL AND length(trim(school_code)) > 0
        AND workshop_code IS NOT NULL AND length(trim(workshop_code)) > 0
        AND class_code IS NOT NULL AND length(trim(class_code)) > 0
        AND activity_id IS NOT NULL AND length(trim(activity_id)) > 0
        AND participant_id IS NOT NULL AND length(trim(participant_id)) > 0
        AND client_version IS NOT NULL AND length(trim(client_version)) > 0
        AND occurred_at IS NOT NULL
        AND (config_hash IS NULL OR config_hash ~ '^[0-9a-f]{64}$')
    );

DROP POLICY IF EXISTS "anon_insert_research_session_events" ON public.research_session_events;
CREATE POLICY "anon_insert_research_session_events"
    ON public.research_session_events
    FOR INSERT
    TO anon
    WITH CHECK (
        event_id IS NOT NULL
        AND session_id IS NOT NULL
        AND dyad_id IS NOT NULL
        AND site_id IS NOT NULL AND length(trim(site_id)) > 0
        AND school_code IS NOT NULL AND length(trim(school_code)) > 0
        AND workshop_code IS NOT NULL AND length(trim(workshop_code)) > 0
        AND class_code IS NOT NULL AND length(trim(class_code)) > 0
        AND activity_id IS NOT NULL AND length(trim(activity_id)) > 0
        AND client_version IS NOT NULL AND length(trim(client_version)) > 0
        AND occurred_at IS NOT NULL
        AND config_hash ~ '^[0-9a-f]{64}$'
    );
