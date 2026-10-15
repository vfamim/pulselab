-- Migration: 20261015120000_research_aula_bancada_view.sql
-- Description:
--   View research_aula_bancada: uma linha por sessão de bancada (aula), com colunas planas
--   extraídas do snapshot (session_payload) gravado pelo bridge. Base do relatório
--   tooling/data/relatorio-pulselab.py.
--
--   Campos lidos do snapshot (New-BridgeSnapshot e Close-BridgeSession no bridge):
--     computer_id (rótulo da máquina), start_mode, client_version, duration_seconds,
--     data_quality.{heartbeat_count, max_heartbeat_gap_min, bridge_restarts, corrupted_lines,
--     spike_status, telemetry_events}, summary.{telemetry_events, final.{executable_blocks, ct_total}}
--     e o último evento spike_telemetry da timeline (executable_blocks, uses_motor, uses_sensor,
--     uses_loop, uses_condition, ct_score.total, spike_status).
--   Sem timeline no snapshot, o último spike_telemetry vem de research_session_events.
--
--   Nenhum texto livre é exposto. Valores com tipo inesperado viram NULL em vez de erro.
--   Horário local: America/Recife (UTC-3, sem horário de verão), o mesmo de todos os polos.

-- security_invoker: cada papel vê só o que o RLS das tabelas de origem permite, como em
-- research_installation_last_seen. Pesquisador vê as aulas dos polos em que tem vínculo ativo.
CREATE OR REPLACE VIEW public.research_aula_bancada
WITH (security_invoker = true)
AS
WITH base AS (
    SELECT
        s.*,
        CASE WHEN jsonb_typeof(s.session_payload) = 'object' THEN s.session_payload ELSE '{}'::jsonb END AS p,
        CASE WHEN jsonb_typeof(s.data_quality) = 'object' THEN s.data_quality
             WHEN jsonb_typeof(s.session_payload -> 'data_quality') = 'object' THEN s.session_payload -> 'data_quality'
             ELSE '{}'::jsonb END AS dq
    FROM public.research_bancada_sessions s
    -- Aulas marcadas como não autorizadas nunca entram em análise (ver 20261015120000).
    WHERE public.research_session_is_authorized(s.session_id)
),
enriched AS (
    SELECT
        b.*,
        CASE WHEN jsonb_typeof(b.p -> 'summary') = 'object' THEN b.p -> 'summary' ELSE '{}'::jsonb END AS summ,
        CASE WHEN jsonb_typeof(b.p -> 'timeline') = 'array' THEN b.p -> 'timeline' ELSE NULL END AS tl,
        CASE WHEN b.phase = 'completed' THEN b.updated_at END AS fim
    FROM base b
)
SELECT
    e.session_id,
    e.site_id                                                         AS polo,
    e.school_code                                                     AS escola,
    nullif(e.p ->> 'computer_id', '')                                 AS maquina,
    e.installation_id,
    (e.created_at AT TIME ZONE 'America/Recife')::date                AS data_local,
    to_char(e.created_at AT TIME ZONE 'America/Recife', 'HH24:MI')    AS hora_inicio,
    to_char(e.fim AT TIME ZONE 'America/Recife', 'HH24:MI')           AS hora_fim,
    e.created_at                                                      AS inicio_em,
    e.fim                                                             AS fim_em,
    round(coalesce(
        CASE WHEN jsonb_typeof(e.p -> 'duration_seconds') = 'number'
             THEN (e.p -> 'duration_seconds')::numeric / 60 END,
        extract(epoch FROM (e.fim - e.created_at)) / 60
    ), 1)                                                             AS duracao_min,
    e.ended_by                                                        AS encerrada_por,
    e.interrupted                                                     AS interrompida,
    e.phase                                                           AS fase,
    nullif(e.p ->> 'start_mode', '')                                  AS modo_inicio,
    coalesce(
        CASE WHEN jsonb_typeof(e.dq -> 'telemetry_events') = 'number' THEN (e.dq -> 'telemetry_events')::numeric::integer END,
        CASE WHEN jsonb_typeof(e.summ -> 'telemetry_events') = 'number' THEN (e.summ -> 'telemetry_events')::numeric::integer END,
        tel.versoes::integer,
        CASE WHEN e.tl IS NOT NULL THEN 0 END
    )                                                                 AS versoes_programa,
    coalesce(
        CASE WHEN jsonb_typeof(tel.d -> 'executable_blocks') = 'number' THEN (tel.d -> 'executable_blocks')::numeric::integer END,
        CASE WHEN jsonb_typeof(e.summ #> '{final,executable_blocks}') = 'number' THEN (e.summ #> '{final,executable_blocks}')::numeric::integer END
    )                                                                 AS blocos_executaveis,
    CASE WHEN jsonb_typeof(tel.d -> 'uses_motor') = 'boolean' THEN (tel.d -> 'uses_motor')::boolean END         AS usa_motor,
    CASE WHEN jsonb_typeof(tel.d -> 'uses_sensor') = 'boolean' THEN (tel.d -> 'uses_sensor')::boolean END       AS usa_sensor,
    CASE WHEN jsonb_typeof(tel.d -> 'uses_loop') = 'boolean' THEN (tel.d -> 'uses_loop')::boolean END           AS usa_laco,
    CASE WHEN jsonb_typeof(tel.d -> 'uses_condition') = 'boolean' THEN (tel.d -> 'uses_condition')::boolean END AS usa_condicao,
    coalesce(
        CASE WHEN jsonb_typeof(tel.d #> '{ct_score,total}') = 'number' THEN (tel.d #> '{ct_score,total}')::numeric END,
        CASE WHEN jsonb_typeof(e.summ #> '{final,ct_total}') = 'number' THEN (e.summ #> '{final,ct_total}')::numeric END
    )                                                                 AS ct_score,
    coalesce(nullif(e.dq ->> 'spike_status', ''), nullif(tel.d ->> 'spike_status', '')) AS spike_status,
    CASE WHEN jsonb_typeof(e.dq -> 'heartbeat_count') = 'number' THEN (e.dq -> 'heartbeat_count')::numeric::integer END      AS sinais_de_vida,
    CASE WHEN jsonb_typeof(e.dq -> 'max_heartbeat_gap_min') = 'number' THEN (e.dq -> 'max_heartbeat_gap_min')::numeric END   AS maior_lacuna_min,
    CASE WHEN jsonb_typeof(e.dq -> 'bridge_restarts') = 'number' THEN (e.dq -> 'bridge_restarts')::numeric::integer END      AS reinicios,
    CASE WHEN jsonb_typeof(e.dq -> 'corrupted_lines') = 'number' THEN (e.dq -> 'corrupted_lines')::numeric::integer END      AS linhas_corrompidas,
    nullif(e.p ->> 'client_version', '')                              AS client_version,
    coalesce(e.instrument_version, nullif(e.p ->> 'instrument_version', '')) AS instrument_version,
    e.environment                                                     AS ambiente,
    'nuvem'::text                                                     AS origem
FROM enriched e
LEFT JOIN LATERAL (
    -- Último spike_telemetry: da timeline do snapshot (ordem de gravação) ou, sem timeline,
    -- da linha do tempo enviada evento a evento (mesmo RLS, por security_invoker).
    SELECT
        CASE WHEN jsonb_typeof(x.d) = 'object' THEN x.d ELSE '{}'::jsonb END AS d,
        x.versoes
    FROM (
        SELECT t.ev -> 'details' AS d, count(*) OVER () AS versoes, t.ord
          FROM jsonb_array_elements(e.tl) WITH ORDINALITY AS t(ev, ord)
         WHERE e.tl IS NOT NULL
           AND t.ev ->> 'event_type' = 'spike_telemetry'
        UNION ALL
        SELECT ev.details, count(*) OVER (), row_number() OVER (ORDER BY ev.occurred_at, ev.received_at)
          FROM public.research_session_events ev
         WHERE e.tl IS NULL
           AND ev.session_id = e.session_id
           AND ev.event_type = 'spike_telemetry'
    ) x
    ORDER BY x.ord DESC
    LIMIT 1
) tel ON true;

REVOKE ALL ON public.research_aula_bancada FROM anon;
GRANT SELECT ON public.research_aula_bancada TO authenticated, service_role;
COMMENT ON VIEW public.research_aula_bancada IS
    'Uma linha por aula de bancada (sessão), com colunas planas do snapshot do bridge. Horários em America/Recife.';
