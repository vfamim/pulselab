-- Migration: 20261017120000_questionario_fim_aula.sql
-- Description:
--   Questionário do fim da aula (instrumento bancada-3.2.0), respondido numa aba do navegador no
--   computador da bancada. O bridge grava um evento por pergunta na sessão da aula:
--     bancada_result_recorded    perguntas 1 a 3, respondidas pela bancada junto, uma vez por aula
--     student_feedback_recorded  perguntas 4 a 8, uma rodada por criança, anônima
--   details: item_id, value (código estável ou 'recusou'), refused, instrument_version,
--   submission_id (código aleatório de cada envio, só para parear as respostas da mesma rodada),
--   item_order, session_active e minutes_since_session_start. Sem nome, idade ou texto livre.
--
--   1. Aceita os dois tipos em research_session_events.event_type.
--   2. View research_questionario_respostas: uma linha por resposta, achatada, para o relatório.
--      Aulas marcadas como não autorizadas nunca entram (research_session_is_authorized).

ALTER TABLE public.research_session_events DROP CONSTRAINT IF EXISTS research_session_events_event_type_check;
ALTER TABLE public.research_session_events ADD CONSTRAINT research_session_events_event_type_check
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
        'bancada_result_recorded',
        'student_feedback_recorded',
        'ending_requested',
        'rubric_completed',
        'session_completed',
        'session_aborted',
        'quality_issue'
    ));

-- security_invoker: cada papel vê só o que o RLS das tabelas de origem permite, como em
-- research_aula_bancada. Valores com tipo inesperado viram NULL em vez de erro.
CREATE OR REPLACE VIEW public.research_questionario_respostas
WITH (security_invoker = true)
AS
SELECT
    e.event_id,
    e.session_id,
    e.site_id                                                              AS polo,
    e.installation_id,
    nullif(e.computer_id, '')                                              AS maquina,
    CASE e.event_type WHEN 'bancada_result_recorded' THEN 'bancada' ELSE 'crianca' END AS parte,
    nullif(e.details ->> 'item_id', '')                                    AS item_id,
    nullif(e.details ->> 'value', '')                                      AS valor,
    coalesce(CASE WHEN jsonb_typeof(e.details -> 'refused') = 'boolean' THEN (e.details -> 'refused')::boolean END,
             e.details ->> 'value' = 'recusou')                            AS recusou,
    nullif(e.details ->> 'submission_id', '')                              AS envio_id,
    coalesce(nullif(e.details ->> 'instrument_version', ''), e.config_version) AS instrument_version,
    e.occurred_at                                                          AS respondido_em,
    (e.occurred_at AT TIME ZONE 'America/Recife')::date                    AS data_local,
    CASE WHEN jsonb_typeof(e.details -> 'minutes_since_session_start') = 'number'
         THEN (e.details -> 'minutes_since_session_start')::numeric
         WHEN e.elapsed_ms IS NOT NULL THEN round(e.elapsed_ms / 60000.0, 1) END AS minutos_desde_inicio,
    CASE WHEN jsonb_typeof(e.details -> 'session_active') = 'boolean' THEN (e.details -> 'session_active')::boolean END AS aula_em_andamento,
    coalesce(s.environment, 'production')                                  AS ambiente
FROM public.research_session_events e
LEFT JOIN public.research_bancada_sessions s ON s.session_id = e.session_id
WHERE e.event_type IN ('bancada_result_recorded', 'student_feedback_recorded')
  AND public.research_session_is_authorized(e.session_id);

REVOKE ALL ON public.research_questionario_respostas FROM anon;
GRANT SELECT ON public.research_questionario_respostas TO authenticated, service_role;
COMMENT ON VIEW public.research_questionario_respostas IS
    'Questionário do fim da aula: uma linha por resposta (bancada ou criança), sem dado que identifique a criança. Aulas não autorizadas ficam fora. Horários em America/Recife.';
