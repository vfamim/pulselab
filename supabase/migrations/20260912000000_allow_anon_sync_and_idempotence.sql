-- Migration: 20260912000000_allow_anon_sync_and_idempotence.sql
-- Description: Permite ingestão e resolução idempotente de duplicatas (ON CONFLICT) para anon
--              nas tabelas de eventos da pesquisa do PulseLab.

-- 1. Conceder permissões de INSERT e SELECT para anon (necessário para verificação de conflito)
GRANT INSERT, SELECT ON TABLE public.research_events TO anon;
GRANT INSERT, SELECT ON TABLE public.research_session_events TO anon;

-- 2. Políticas de SELECT para anon resolver conflitos de primary key de forma idempotente
DROP POLICY IF EXISTS "anon_select_research_events" ON public.research_events;
CREATE POLICY "anon_select_research_events"
    ON public.research_events
    FOR SELECT
    TO anon
    USING (true);

DROP POLICY IF EXISTS "anon_select_research_session_events" ON public.research_session_events;
CREATE POLICY "anon_select_research_session_events"
    ON public.research_session_events
    FOR SELECT
    TO anon
    USING (true);

-- 3. Garantir políticas de INSERT para anon
DROP POLICY IF EXISTS "anon_insert_research_events" ON public.research_events;
CREATE POLICY "anon_insert_research_events"
    ON public.research_events
    FOR INSERT
    TO anon
    WITH CHECK (true);

DROP POLICY IF EXISTS "anon_insert_research_session_events" ON public.research_session_events;
CREATE POLICY "anon_insert_research_session_events"
    ON public.research_session_events
    FOR INSERT
    TO anon
    WITH CHECK (true);
