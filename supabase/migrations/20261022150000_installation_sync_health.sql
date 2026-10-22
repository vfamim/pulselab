-- Migration: 20261022150000_installation_sync_health.sql
-- Description:
--   research_installation_last_seen ganha a saúde do envio de cada máquina, lida do último sinal de
--   vida (heartbeat) que chegou: eventos pendentes, eventos e sessões em quarentena e o último erro
--   HTTP. Desde a 3.2.8 o bridge não descarta mais em silêncio: erros que dependem da nuvem
--   (403, 404, 408, 429) deixam os dados pendentes, e a quarentena volta para a fila uma vez por dia.
--   Esta view é onde o pesquisador vê, de longe, qual máquina tem envio recusado.
--   As colunas antigas ficam iguais e na mesma ordem; as novas entram no fim.

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
),
seen AS (
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
    GROUP BY m.installation_id, m.site_id
)
SELECT
    s.installation_id,
    s.site_id,
    s.last_received_at,
    s.last_occurred_at,
    s.days_since_last_received,
    s.sessions_last_30d,
    s.interrupted_sessions_last_30d,
    hb.occurred_at AS last_heartbeat_at,
    CASE WHEN jsonb_typeof(hb.details -> 'pending_sync') = 'number' THEN (hb.details ->> 'pending_sync')::integer END AS pending_sync,
    CASE WHEN jsonb_typeof(hb.details -> 'quarantined_events') = 'number' THEN (hb.details ->> 'quarantined_events')::integer END AS quarantined_events,
    CASE WHEN jsonb_typeof(hb.details -> 'quarantined_sessions') = 'number' THEN (hb.details ->> 'quarantined_sessions')::integer END AS quarantined_sessions,
    CASE WHEN jsonb_typeof(hb.details -> 'last_sync_error_status') = 'number' THEN (hb.details ->> 'last_sync_error_status')::integer END AS last_sync_error_status
FROM seen s
LEFT JOIN LATERAL (
    SELECT h.occurred_at, h.details
      FROM public.research_session_events h
     WHERE h.installation_id = s.installation_id
       AND h.site_id IS NOT DISTINCT FROM s.site_id
       AND h.event_type = 'heartbeat'
     ORDER BY h.occurred_at DESC
     LIMIT 1
) hb ON true;

REVOKE ALL ON public.research_installation_last_seen FROM anon;
GRANT SELECT ON public.research_installation_last_seen TO authenticated, service_role;
COMMENT ON VIEW public.research_installation_last_seen IS
    'Última chegada por máquina e saúde do envio pelo último heartbeat (pendentes, quarentena, último erro HTTP). Aulas não autorizadas fora das contagens.';
