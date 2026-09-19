-- Migration: 20260919010000_align_quality_view_and_retention.sql
-- Description:
--   1. Atualiza a view research_session_quality para:
--      - Reconhecer recusa etica (response_status = 'declined') como protocolo cumprido sem forcar 'needs_review'.
--      - Tratar participant_count padrao como 1 caso nao informado (coleta ergonomica por bancada/dispositivo).
--      - Tratar expected_checkpoint_count padrao como 2 (marcos 20 e 40) caso nao informado.
--   2. Garante permissao de consulta para authenticated (painel do pesquisador/instrutor).

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
