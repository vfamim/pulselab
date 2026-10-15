-- Migration: 20261015120000_unauthorized_sessions_review.sql
-- Description:
--   "Não registrar esta turma" deixa de apagar na hora. A aula é marcada como não autorizada,
--   os dados ficam guardados (polos sem internet entregam pendrive meses depois) e a exclusão
--   definitiva é feita na revisão do pesquisador, com tombstone em research_withdrawals.
--   1. research_unauthorized_sessions: marcação por session_id (sem motivo, sem quem recusou).
--   2. research_session_is_authorized(uuid): condição reutilizável. Toda view de análise ou de
--      qualidade, inclusive as que vierem depois (ex.: research_aula_bancada), filtra com
--      WHERE public.research_session_is_authorized(session_id).
--   3. Trigger em research_bancada_sessions: snapshot com session_payload.authorization_status =
--      'nao_autorizada' grava a marcação, inclusive no reenvio de sessão já guardada (o bridge usa
--      ignore-duplicates; o BEFORE INSERT roda antes do ON CONFLICT). Só a máquina dona marca.
--   4. Views research_session_quality e research_installation_last_seen sem aulas marcadas
--      (research_session_quality_dimensions herda o filtro).
--   5. Revisão do pesquisador (service_role): review_purge_research_session grava o tombstone e
--      apaga; review_restore_research_session volta para autorizada com motivo gravado.

-- =============================================================================
-- 1. MARCAÇÃO DE AULA NÃO AUTORIZADA
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.research_unauthorized_sessions (
    session_id      uuid         PRIMARY KEY,
    status          text         NOT NULL DEFAULT 'nao_autorizada',
    marked_at       timestamptz  NOT NULL DEFAULT timezone('utc'::text, now()),
    recorded_at     timestamptz  NOT NULL DEFAULT timezone('utc'::text, now()),
    installation_id uuid,
    site_id         text,
    restored_at     timestamptz,
    restore_reason  text,
    CONSTRAINT research_unauthorized_sessions_status_check
        CHECK (status IN ('nao_autorizada', 'autorizada')),
    CONSTRAINT research_unauthorized_sessions_restore_check
        CHECK (status = 'nao_autorizada' OR (restored_at IS NOT NULL AND length(trim(coalesce(restore_reason, ''))) > 0))
);

ALTER TABLE public.research_unauthorized_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.research_unauthorized_sessions FROM anon, authenticated;
GRANT ALL ON TABLE public.research_unauthorized_sessions TO service_role;

COMMENT ON TABLE public.research_unauthorized_sessions IS
    'Aulas marcadas como não autorizadas pelo instrutor ("Não registrar esta turma"). Dados guardados, nunca usados em análise; exclusão na revisão do pesquisador. status = autorizada só por restauração com motivo.';

-- Sessão já apagada na revisão: a marcação atrasada (pendrive, reenvio) também é descartada.
DROP TRIGGER IF EXISTS drop_withdrawn_research_unauthorized_sessions ON public.research_unauthorized_sessions;
CREATE TRIGGER drop_withdrawn_research_unauthorized_sessions
    BEFORE INSERT ON public.research_unauthorized_sessions
    FOR EACH ROW EXECUTE FUNCTION public.drop_withdrawn_research_rows();

-- =============================================================================
-- 2. CONDIÇÃO REUTILIZÁVEL
-- =============================================================================

-- SECURITY DEFINER: as views são security_invoker e o pesquisador não lê a tabela de marcações.
CREATE OR REPLACE FUNCTION public.research_session_is_authorized(p_session_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT NOT EXISTS (
        SELECT 1 FROM public.research_unauthorized_sessions u
         WHERE u.session_id = p_session_id
           AND u.status = 'nao_autorizada'
    );
$$;

REVOKE ALL ON FUNCTION public.research_session_is_authorized(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.research_session_is_authorized(uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.research_session_is_authorized(uuid) IS
    'false para aula marcada como não autorizada. Filtro obrigatório de toda view de análise ou de qualidade.';

-- =============================================================================
-- 3. MARCAÇÃO PELO CAMINHO DE ENVIO EXISTENTE (snapshot da sessão)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.record_unauthorized_bancada_session()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_marked_at timestamptz;
BEGIN
    IF NEW.session_id IS NULL
       OR coalesce(NEW.session_payload ->> 'authorization_status', '') <> 'nao_autorizada' THEN
        RETURN NEW;
    END IF;

    -- Só a máquina dona da sessão marca: um snapshot já guardado de outra instalação não muda.
    -- (Para a linha nova, o RLS de INSERT já exige installation_id e site_id do próprio dispositivo.)
    IF EXISTS (
        SELECT 1 FROM public.research_bancada_sessions s
         WHERE s.session_id = NEW.session_id
           AND (s.installation_id IS DISTINCT FROM NEW.installation_id
                OR s.site_id IS DISTINCT FROM NEW.site_id)
    ) THEN
        RETURN NEW;
    END IF;

    BEGIN
        v_marked_at := (NEW.session_payload ->> 'marked_at')::timestamptz;
    EXCEPTION WHEN others THEN
        v_marked_at := NULL;
    END;

    -- Primeira marcação vale; restauração feita na revisão não é desfeita por reenvio.
    INSERT INTO public.research_unauthorized_sessions (session_id, marked_at, installation_id, site_id)
    VALUES (NEW.session_id, coalesce(v_marked_at, timezone('utc'::text, now())), NEW.installation_id, NEW.site_id)
    ON CONFLICT (session_id) DO NOTHING;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.record_unauthorized_bancada_session() FROM PUBLIC, anon, authenticated;

-- Nome depois de drop_withdrawn_research_bancada_sessions: triggers rodam em ordem alfabética e
-- sessão com tombstone é descartada antes de gravar marcação.
DROP TRIGGER IF EXISTS record_unauthorized_bancada_session ON public.research_bancada_sessions;
CREATE TRIGGER record_unauthorized_bancada_session
    BEFORE INSERT ON public.research_bancada_sessions
    FOR EACH ROW EXECUTE FUNCTION public.record_unauthorized_bancada_session();

-- =============================================================================
-- 4. VIEWS SEM AULAS MARCADAS
-- =============================================================================

CREATE OR REPLACE VIEW public.research_session_quality
WITH (security_invoker = true)
AS
WITH timeline AS (
    SELECT
        session_id,
        min(installation_id::text)::uuid AS installation_id,
        max(site_id) AS site_id,
        max(regional_hub) AS regional_hub,
        max(school_code) AS school_code,
        max(workshop_code) AS workshop_code,
        max(class_code) AS class_code,
        min(occurred_at) AS first_event_at,
        max(occurred_at) AS last_event_at,
        max(received_at) AS last_received_at,
        count(*) FILTER (WHERE event_type = 'heartbeat') AS heartbeat_count,
        count(*) FILTER (WHERE event_type = 'checkpoint_started') AS checkpoint_started_count,
        count(*) FILTER (WHERE event_type = 'checkpoint_completed') AS checkpoint_completed_count,
        count(*) FILTER (WHERE event_type = 'quality_issue') AS quality_issue_count,
        bool_or(event_type = 'session_completed') AS has_completed,
        bool_or(event_type = 'session_aborted') AS has_aborted,
        coalesce(
            max(jsonb_array_length(details -> 'expected_checkpoints'))
                FILTER (
                    WHERE event_type = 'session_started'
                      AND jsonb_typeof(details -> 'expected_checkpoints') = 'array'
                ),
            2
        ) AS expected_checkpoint_count,
        coalesce(
            max((details ->> 'participant_count')::integer)
                FILTER (
                    WHERE event_type = 'session_started'
                      AND details ->> 'participant_count' IS NOT NULL
                ),
            1
        ) AS participant_count
    FROM public.research_session_events
    WHERE public.research_session_is_authorized(session_id)
    GROUP BY session_id
),
responses AS (
    SELECT
        session_id,
        count(*) FILTER (WHERE event_type = 'pre') AS pre_response_count,
        count(*) FILTER (WHERE event_type = 'pre' AND response_status = 'completed') AS pre_completed_count,
        count(*) FILTER (WHERE event_type = 'checkpoint') AS checkpoint_response_count,
        count(*) FILTER (WHERE event_type = 'checkpoint' AND response_status = 'completed') AS checkpoint_completed_count,
        count(*) FILTER (WHERE event_type = 'post') AS post_response_count,
        count(*) FILTER (WHERE event_type = 'post' AND response_status = 'completed') AS post_completed_count,
        count(*) FILTER (WHERE response_status = 'declined') AS declined_response_count,
        count(*) FILTER (WHERE response_status = 'timeout') AS timeout_response_count,
        count(DISTINCT participant_id)
            FILTER (WHERE event_type = 'pre' AND response_status IN ('completed', 'declined'))
            AS distinct_pre_completed_participants,
        count(DISTINCT participant_id)
            FILTER (WHERE event_type = 'post' AND response_status IN ('completed', 'declined'))
            AS distinct_post_completed_participants,
        count(DISTINCT (participant_id, interval_mark))
            FILTER (WHERE event_type = 'checkpoint' AND response_status IN ('completed', 'declined'))
            AS distinct_checkpoint_completed_pairs,
        count(DISTINCT interval_mark)
            FILTER (WHERE event_type = 'checkpoint' AND response_status IN ('completed', 'declined'))
            AS distinct_completed_interval_marks,
        count(DISTINCT participant_id)
            FILTER (WHERE event_type = 'checkpoint' AND response_status IN ('completed', 'declined'))
            AS distinct_checkpoint_completed_participants,
        count(DISTINCT interval_mark)
            FILTER (WHERE event_type = 'checkpoint' AND screenshot_path IS NOT NULL)
            AS checkpoint_with_screenshot_count
    FROM public.research_events
    WHERE public.research_session_is_authorized(session_id)
    GROUP BY session_id
)
SELECT
    timeline.session_id,
    timeline.installation_id,
    timeline.site_id,
    timeline.regional_hub,
    timeline.school_code,
    timeline.workshop_code,
    timeline.class_code,
    timeline.first_event_at,
    timeline.last_event_at,
    timeline.last_received_at,
    timeline.heartbeat_count,
    timeline.expected_checkpoint_count,
    timeline.checkpoint_started_count,
    timeline.checkpoint_completed_count,
    timeline.participant_count,
    coalesce(responses.pre_response_count, 0) AS pre_response_count,
    coalesce(responses.pre_completed_count, 0) AS pre_completed_count,
    coalesce(responses.checkpoint_response_count, 0) AS checkpoint_response_count,
    coalesce(responses.checkpoint_completed_count, 0) AS checkpoint_completed_response_count,
    coalesce(responses.post_response_count, 0) AS post_response_count,
    coalesce(responses.post_completed_count, 0) AS post_completed_count,
    coalesce(responses.declined_response_count, 0) AS declined_response_count,
    coalesce(responses.timeout_response_count, 0) AS timeout_response_count,
    coalesce(responses.distinct_pre_completed_participants, 0) AS distinct_pre_completed_participants,
    coalesce(responses.distinct_post_completed_participants, 0) AS distinct_post_completed_participants,
    coalesce(responses.distinct_checkpoint_completed_pairs, 0) AS distinct_checkpoint_completed_pairs,
    coalesce(responses.distinct_completed_interval_marks, 0) AS distinct_completed_interval_marks,
    coalesce(responses.distinct_checkpoint_completed_participants, 0) AS distinct_checkpoint_completed_participants,
    coalesce(responses.checkpoint_with_screenshot_count, 0) AS checkpoint_with_screenshot_count,
    timeline.quality_issue_count,
    timeline.has_completed,
    timeline.has_aborted,
    CASE
        WHEN timeline.has_aborted THEN 'aborted'
        WHEN NOT timeline.has_completed THEN 'in_progress'
        WHEN timeline.quality_issue_count > 0
          OR timeline.checkpoint_completed_count < timeline.expected_checkpoint_count
          OR coalesce(responses.distinct_pre_completed_participants, 0) < timeline.participant_count
          OR coalesce(responses.distinct_post_completed_participants, 0) < timeline.participant_count
          OR coalesce(responses.distinct_checkpoint_completed_pairs, 0) < (timeline.expected_checkpoint_count * timeline.participant_count)
          OR coalesce(responses.distinct_completed_interval_marks, 0) < timeline.expected_checkpoint_count
          OR coalesce(responses.distinct_checkpoint_completed_participants, 0) < timeline.participant_count
        THEN 'needs_review'
        ELSE 'complete'
    END AS quality_status
FROM timeline
LEFT JOIN responses USING (session_id);

GRANT SELECT ON TABLE public.research_session_quality TO authenticated;

-- Último envio continua contando qualquer chegada (é sinal de que a máquina envia), mas
-- aulas marcadas não entram nas contagens de sessões.
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
    count(DISTINCT a.session_id) FILTER (
        WHERE a.received_at >= now() - interval '30 days'
          AND public.research_session_is_authorized(a.session_id)
    ) AS sessions_last_30d,
    count(DISTINCT a.session_id) FILTER (
        WHERE a.interrupted AND a.received_at >= now() - interval '30 days'
          AND public.research_session_is_authorized(a.session_id)
    ) AS interrupted_sessions_last_30d
FROM machines m
LEFT JOIN arrivals a
       ON a.installation_id = m.installation_id
      AND a.site_id IS NOT DISTINCT FROM m.site_id
GROUP BY m.installation_id, m.site_id;

REVOKE ALL ON public.research_installation_last_seen FROM anon;
GRANT SELECT ON public.research_installation_last_seen TO authenticated, service_role;

-- =============================================================================
-- 5. REVISÃO DO PESQUISADOR (service_role)
-- =============================================================================

-- Exclusão definitiva de uma aula marcada: tombstone antes de apagar, como purge_own_research_session.
-- O tombstone barra reenvio do bridge e reimportação por pendrive (drop_withdrawn_research_rows).
CREATE OR REPLACE FUNCTION public.review_purge_research_session(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_responses bigint := 0;
    v_timeline bigint := 0;
    v_snapshots bigint := 0;
    v_evaluations bigint := 0;
BEGIN
    IF EXISTS (SELECT 1 FROM public.research_withdrawals w WHERE w.session_id = p_session_id) THEN
        DELETE FROM public.research_unauthorized_sessions u WHERE u.session_id = p_session_id;
        RETURN jsonb_build_object('purged', true, 'already_absent', true, 'session_id', p_session_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.research_unauthorized_sessions u
         WHERE u.session_id = p_session_id AND u.status = 'nao_autorizada'
    ) THEN
        RAISE EXCEPTION 'session % is not marked as nao_autorizada', p_session_id USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.research_withdrawals (session_id, source)
    VALUES (p_session_id, 'revisao_pesquisador')
    ON CONFLICT (session_id) DO NOTHING;

    DELETE FROM public.instructor_evaluations e WHERE e.session_id = p_session_id;
    GET DIAGNOSTICS v_evaluations = ROW_COUNT;
    DELETE FROM public.research_events e WHERE e.session_id = p_session_id;
    GET DIAGNOSTICS v_responses = ROW_COUNT;
    DELETE FROM public.research_session_events e WHERE e.session_id = p_session_id;
    GET DIAGNOSTICS v_timeline = ROW_COUNT;
    DELETE FROM public.research_bancada_sessions s WHERE s.session_id = p_session_id;
    GET DIAGNOSTICS v_snapshots = ROW_COUNT;
    DELETE FROM public.research_unauthorized_sessions u WHERE u.session_id = p_session_id;

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

REVOKE ALL ON FUNCTION public.review_purge_research_session(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.review_purge_research_session(uuid) TO service_role;

-- Volta uma aula marcada para autorizada. Exige motivo, que fica gravado com a data.
CREATE OR REPLACE FUNCTION public.review_restore_research_session(p_session_id uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
    IF length(trim(coalesce(p_reason, ''))) = 0 THEN
        RAISE EXCEPTION 'restore reason is required' USING ERRCODE = '22023';
    END IF;

    UPDATE public.research_unauthorized_sessions u
       SET status = 'autorizada',
           restored_at = timezone('utc'::text, now()),
           restore_reason = trim(p_reason)
     WHERE u.session_id = p_session_id
       AND u.status = 'nao_autorizada';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'session % is not marked as nao_autorizada', p_session_id USING ERRCODE = '22023';
    END IF;

    RETURN jsonb_build_object('restored', true, 'session_id', p_session_id);
END;
$$;

REVOKE ALL ON FUNCTION public.review_restore_research_session(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.review_restore_research_session(uuid, text) TO service_role;
