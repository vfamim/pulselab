-- Migration: 20261014120000_bancada_quality_and_withdrawal_tombstones.sql
-- Description:
--   1. research_withdrawals: tombstone permanente das sessões retiradas (só session_id).
--   2. purge_own_research_session grava o tombstone antes de apagar.
--   3. Triggers descartam em silêncio qualquer INSERT de sessão retirada nas três tabelas
--      de pesquisa. O descarte silencioso é proposital: os clientes usam ignore-duplicates,
--      tratam a resposta como entregue e nunca reenviam.
--   4. research_bancada_sessions: ended_by, interrupted e data_quality enviados pelo bridge.
--   5. Sessão encerrada (phase = 'completed') nunca volta para em andamento.
--   6. participant_role 'instructor' aceito na linha do tempo (rubric_completed).
--   7. View research_installation_last_seen para a equipe acompanhar máquinas sem envio.

-- =============================================================================
-- 1. TOMBSTONES DE RETIRADA
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.research_withdrawals (
    session_id   uuid         PRIMARY KEY,
    withdrawn_at timestamptz  NOT NULL DEFAULT timezone('utc'::text, now()),
    source       text
);

ALTER TABLE public.research_withdrawals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.research_withdrawals FROM anon, authenticated;
GRANT ALL ON TABLE public.research_withdrawals TO service_role;

COMMENT ON TABLE public.research_withdrawals IS
    'Sessões retiradas pelos participantes. Guarda só o session_id; bloqueia reenvios atrasados (fila do bridge, pendrive).';

-- =============================================================================
-- 2. RETIRADA PELO DISPOSITIVO GRAVA TOMBSTONE
-- =============================================================================

CREATE OR REPLACE FUNCTION public.purge_own_research_session(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_installation_id uuid;
    v_site_id text;
    v_owned boolean := false;
    v_known boolean := false;
    v_responses bigint := 0;
    v_timeline bigint := 0;
    v_snapshots bigint := 0;
    v_evaluations bigint := 0;
BEGIN
    SELECT d.installation_id, d.site_id
      INTO v_installation_id, v_site_id
      FROM public.device_installations d
     WHERE d.device_user_id = auth.uid()
       AND d.is_active = true
     LIMIT 1;

    IF v_installation_id IS NULL THEN
        RAISE EXCEPTION 'active device installation required' USING ERRCODE = '42501';
    END IF;

    SELECT
        EXISTS (
            SELECT 1 FROM public.research_events e
             WHERE e.session_id = p_session_id
               AND e.installation_id = v_installation_id
               AND e.site_id = v_site_id
        ) OR EXISTS (
            SELECT 1 FROM public.research_session_events e
             WHERE e.session_id = p_session_id
               AND e.installation_id = v_installation_id
               AND e.site_id = v_site_id
        ) OR EXISTS (
            SELECT 1 FROM public.research_bancada_sessions s
             WHERE s.session_id = p_session_id
               AND s.installation_id = v_installation_id
               AND s.site_id = v_site_id
        )
      INTO v_owned;

    -- Tombstone antes de apagar. Sessão ainda ausente da nuvem também recebe tombstone,
    -- pois pode chegar depois por pendrive. Sessão com dados só de outra instalação, não.
    IF NOT v_owned THEN
        SELECT
            EXISTS (SELECT 1 FROM public.research_events e WHERE e.session_id = p_session_id)
            OR EXISTS (SELECT 1 FROM public.research_session_events e WHERE e.session_id = p_session_id)
            OR EXISTS (SELECT 1 FROM public.research_bancada_sessions s WHERE s.session_id = p_session_id)
          INTO v_known;
    END IF;

    IF v_owned OR NOT v_known THEN
        INSERT INTO public.research_withdrawals (session_id, source)
        VALUES (p_session_id, 'device')
        ON CONFLICT (session_id) DO NOTHING;
    END IF;

    -- Idempotência: uma segunda tentativa após exclusão é sucesso, sem ampliar o escopo.
    IF NOT v_owned THEN
        RETURN jsonb_build_object('purged', true, 'already_absent', true, 'session_id', p_session_id);
    END IF;

    DELETE FROM public.instructor_evaluations e
     WHERE e.session_id = p_session_id
       AND e.site_id = v_site_id;
    GET DIAGNOSTICS v_evaluations = ROW_COUNT;

    DELETE FROM public.research_events e
     WHERE e.session_id = p_session_id
       AND e.installation_id = v_installation_id
       AND e.site_id = v_site_id;
    GET DIAGNOSTICS v_responses = ROW_COUNT;

    DELETE FROM public.research_session_events e
     WHERE e.session_id = p_session_id
       AND e.installation_id = v_installation_id
       AND e.site_id = v_site_id;
    GET DIAGNOSTICS v_timeline = ROW_COUNT;

    DELETE FROM public.research_bancada_sessions s
     WHERE s.session_id = p_session_id
       AND s.installation_id = v_installation_id
       AND s.site_id = v_site_id;
    GET DIAGNOSTICS v_snapshots = ROW_COUNT;

    RETURN jsonb_build_object(
        'purged', true,
        'session_id', p_session_id,
        'responses', v_responses,
        'timeline_events', v_timeline,
        'snapshots', v_snapshots,
        'evaluations', v_evaluations
    );
END;
$$;

REVOKE ALL ON FUNCTION public.purge_own_research_session(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.purge_own_research_session(uuid) TO authenticated, service_role;

-- =============================================================================
-- 3. DESCARTE SILENCIOSO DE ENVIOS DE SESSÕES RETIRADAS
-- =============================================================================

-- SECURITY DEFINER: dispositivos não leem research_withdrawals.
CREATE OR REPLACE FUNCTION public.drop_withdrawn_research_rows()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NEW.session_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.research_withdrawals w WHERE w.session_id = NEW.session_id
    ) THEN
        RETURN NULL;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.drop_withdrawn_research_rows() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS drop_withdrawn_research_events ON public.research_events;
CREATE TRIGGER drop_withdrawn_research_events
    BEFORE INSERT ON public.research_events
    FOR EACH ROW EXECUTE FUNCTION public.drop_withdrawn_research_rows();

DROP TRIGGER IF EXISTS drop_withdrawn_research_session_events ON public.research_session_events;
CREATE TRIGGER drop_withdrawn_research_session_events
    BEFORE INSERT ON public.research_session_events
    FOR EACH ROW EXECUTE FUNCTION public.drop_withdrawn_research_rows();

DROP TRIGGER IF EXISTS drop_withdrawn_research_bancada_sessions ON public.research_bancada_sessions;
CREATE TRIGGER drop_withdrawn_research_bancada_sessions
    BEFORE INSERT ON public.research_bancada_sessions
    FOR EACH ROW EXECUTE FUNCTION public.drop_withdrawn_research_rows();

-- =============================================================================
-- 4. QUALIDADE DA SESSÃO DE BANCADA
-- =============================================================================

ALTER TABLE public.research_bancada_sessions ADD COLUMN IF NOT EXISTS ended_by text;
ALTER TABLE public.research_bancada_sessions ADD COLUMN IF NOT EXISTS interrupted boolean;
ALTER TABLE public.research_bancada_sessions ADD COLUMN IF NOT EXISTS data_quality jsonb;

ALTER TABLE public.research_bancada_sessions DROP CONSTRAINT IF EXISTS research_bancada_sessions_ended_by_check;
ALTER TABLE public.research_bancada_sessions ADD CONSTRAINT research_bancada_sessions_ended_by_check
    CHECK (ended_by IS NULL OR ended_by IN ('instrutor', 'tempo', 'sem_encerramento'));

ALTER TABLE public.research_bancada_sessions DROP CONSTRAINT IF EXISTS research_bancada_sessions_data_quality_check;
ALTER TABLE public.research_bancada_sessions ADD CONSTRAINT research_bancada_sessions_data_quality_check
    CHECK (data_quality IS NULL OR jsonb_typeof(data_quality) = 'object');

COMMENT ON COLUMN public.research_bancada_sessions.ended_by IS
    'Quem encerrou a turma: instrutor, tempo (limite atingido) ou sem_encerramento (fechada pelo bridge).';
COMMENT ON COLUMN public.research_bancada_sessions.interrupted IS
    'Sessão marcada como interrompida pelo bridge.';
COMMENT ON COLUMN public.research_bancada_sessions.data_quality IS
    'Indicadores do bridge: heartbeat_count, max_heartbeat_gap_min, bridge_restarts, corrupted_lines, spike_status, telemetry_events, last_activity_at.';

-- =============================================================================
-- 5. SESSÃO ENCERRADA NÃO REGRIDE
-- =============================================================================

CREATE OR REPLACE FUNCTION public.keep_completed_bancada_session()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    IF OLD.phase = 'completed' AND NEW.phase IS DISTINCT FROM 'completed' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.keep_completed_bancada_session() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS keep_completed_bancada_session ON public.research_bancada_sessions;
CREATE TRIGGER keep_completed_bancada_session
    BEFORE UPDATE ON public.research_bancada_sessions
    FOR EACH ROW EXECUTE FUNCTION public.keep_completed_bancada_session();

-- =============================================================================
-- 6. PAPEL DO INSTRUTOR NA LINHA DO TEMPO
-- =============================================================================

ALTER TABLE public.research_session_events DROP CONSTRAINT IF EXISTS research_session_events_participant_role_check;
ALTER TABLE public.research_session_events ADD CONSTRAINT research_session_events_participant_role_check
    CHECK (participant_role IS NULL OR participant_role IN (
        'computer', 'assembly', 'member_3', 'member_4', 'individual', 'group', 'instructor'
    ));

-- =============================================================================
-- 7. ÚLTIMO ENVIO POR MÁQUINA
-- =============================================================================

-- security_invoker: cada papel vê só o que o RLS das tabelas de origem permite.
-- Pesquisador vê as máquinas do polo que já enviaram dados; service_role vê também
-- as máquinas cadastradas que nunca enviaram (last_received_at nulo).
CREATE OR REPLACE VIEW public.research_installation_last_seen
WITH (security_invoker = true)
AS
WITH arrivals AS (
    SELECT e.installation_id, e.site_id, e.session_id, e.received_at, e.occurred_at, NULL::boolean AS interrupted
      FROM public.research_events e
     WHERE e.installation_id IS NOT NULL
    UNION ALL
    SELECT e.installation_id, e.site_id, e.session_id, e.received_at, e.occurred_at, NULL::boolean
      FROM public.research_session_events e
     WHERE e.installation_id IS NOT NULL
    UNION ALL
    SELECT s.installation_id, s.site_id, s.session_id, s.received_at, s.updated_at, s.interrupted
      FROM public.research_bancada_sessions s
     WHERE s.installation_id IS NOT NULL
),
machines AS (
    SELECT d.installation_id, d.site_id FROM public.device_installations d WHERE d.is_active
    UNION
    SELECT a.installation_id, a.site_id FROM arrivals a
)
SELECT
    m.installation_id,
    m.site_id,
    max(a.received_at) AS last_received_at,
    max(a.occurred_at) AS last_occurred_at,
    floor(extract(epoch FROM (now() - max(a.received_at))) / 86400)::integer AS days_since_last_received,
    count(DISTINCT a.session_id) FILTER (WHERE a.received_at >= now() - interval '30 days') AS sessions_last_30d,
    count(DISTINCT a.session_id) FILTER (WHERE a.interrupted AND a.received_at >= now() - interval '30 days') AS interrupted_sessions_last_30d
FROM machines m
LEFT JOIN arrivals a
       ON a.installation_id = m.installation_id
      AND a.site_id IS NOT DISTINCT FROM m.site_id
GROUP BY m.installation_id, m.site_id;

REVOKE ALL ON public.research_installation_last_seen FROM anon;
GRANT SELECT ON public.research_installation_last_seen TO authenticated, service_role;
COMMENT ON VIEW public.research_installation_last_seen IS
    'Último dado recebido por máquina (installation_id). Janelas de 30 dias contam pelo received_at do servidor.';
