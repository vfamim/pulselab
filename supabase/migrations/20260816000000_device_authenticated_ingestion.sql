-- Migration: 20260816000000_device_authenticated_ingestion.sql
-- Description: Implementa ingestão autenticada por dispositivo com vínculo fail-closed
--              entre JWT/auth.uid e installation_id/site_id, restringe prefixos de Storage,
--              e aprimora a view de qualidade com contagem estrita de respostas completed
--              e cobertura distinct por participante e checkpoint (grupos 1, 2 e 3).

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. Tabela de dispositivos autorizados vinculados a installation_id
CREATE TABLE IF NOT EXISTS public.device_installations (
    id                         uuid         DEFAULT gen_random_uuid() PRIMARY KEY,
    device_user_id             uuid         NOT NULL,
    installation_id            uuid         NOT NULL UNIQUE,
    site_id                    text         NOT NULL,
    regional_hub               text,
    school_code                text,
    computer_id                text,
    is_active                  boolean      NOT NULL DEFAULT true,
    enrolled_at                timestamptz  NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at                 timestamptz  NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT device_installations_device_user_unique UNIQUE (device_user_id)
);

CREATE INDEX IF NOT EXISTS idx_device_installations_user
    ON public.device_installations (device_user_id);

CREATE INDEX IF NOT EXISTS idx_device_installations_installation
    ON public.device_installations (installation_id);

ALTER TABLE public.device_installations ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.device_installations FROM anon, authenticated;
GRANT SELECT ON TABLE public.device_installations TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.device_installations TO service_role;

DROP POLICY IF EXISTS "authenticated_select_device_installations" ON public.device_installations;
CREATE POLICY "authenticated_select_device_installations"
    ON public.device_installations
    FOR SELECT
    TO authenticated
    USING (
        (device_user_id = auth.uid() AND is_active = true)
        OR (auth.jwt() ->> 'role') = 'service_role'
    );

-- 2. Tabela de tokens de enrollment de uso único
CREATE TABLE IF NOT EXISTS public.device_enrollment_tokens (
    id                         uuid         DEFAULT gen_random_uuid() PRIMARY KEY,
    token_hash                 text         NOT NULL UNIQUE,
    installation_id            uuid         NOT NULL,
    site_id                    text         NOT NULL,
    regional_hub               text,
    school_code                text,
    computer_id                text,
    created_at                 timestamptz  NOT NULL DEFAULT timezone('utc'::text, now()),
    expires_at                 timestamptz  NOT NULL,
    consumed_at                timestamptz,
    consumed_by                uuid
);

CREATE INDEX IF NOT EXISTS idx_device_enrollment_tokens_hash
    ON public.device_enrollment_tokens (token_hash);

CREATE INDEX IF NOT EXISTS idx_device_enrollment_tokens_lookup
    ON public.device_enrollment_tokens (installation_id, site_id);

ALTER TABLE public.device_enrollment_tokens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.device_enrollment_tokens FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.device_enrollment_tokens TO service_role;

-- 3. Políticas RLS fail-closed para research_events
DROP POLICY IF EXISTS "anon_insert_research_events" ON public.research_events;
DROP POLICY IF EXISTS "authenticated_insert_research_events" ON public.research_events;
CREATE POLICY "authenticated_insert_research_events"
    ON public.research_events
    FOR INSERT
    TO authenticated
    WITH CHECK (
        installation_id IS NOT NULL
        AND site_id IS NOT NULL
        AND EXISTS (
            SELECT 1
            FROM public.device_installations di
            WHERE di.device_user_id = auth.uid()
              AND di.is_active = true
              AND di.installation_id = research_events.installation_id
              AND di.site_id = research_events.site_id
        )
    );

-- 4. Políticas RLS fail-closed para research_session_events
DROP POLICY IF EXISTS "anon_insert_research_session_events" ON public.research_session_events;
DROP POLICY IF EXISTS "authenticated_insert_research_session_events" ON public.research_session_events;
CREATE POLICY "authenticated_insert_research_session_events"
    ON public.research_session_events
    FOR INSERT
    TO authenticated
    WITH CHECK (
        installation_id IS NOT NULL
        AND site_id IS NOT NULL
        AND EXISTS (
            SELECT 1
            FROM public.device_installations di
            WHERE di.device_user_id = auth.uid()
              AND di.is_active = true
              AND di.installation_id = research_session_events.installation_id
              AND di.site_id = research_session_events.site_id
        )
    );

-- 5. Storage Policy com restrição estrita por prefixo de installation_id
DROP POLICY IF EXISTS "Allow anonymous uploads to screenshots" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated uploads to screenshots" ON storage.objects;
CREATE POLICY "Allow authenticated uploads to screenshots"
    ON storage.objects
    FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'screenshots'
        AND EXISTS (
            SELECT 1
            FROM public.device_installations di
            WHERE di.device_user_id = auth.uid()
              AND di.is_active = true
              AND di.installation_id::text = split_part(storage.objects.name, '/', 1)
        )
    );

-- 5. View research_session_quality com suporte a grupos 1/2/3 e contagem de respostas completed
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
            0
        ) AS expected_checkpoint_count,
        coalesce(
            max((details ->> 'participant_count')::integer)
                FILTER (
                    WHERE event_type = 'session_started'
                      AND details ->> 'participant_count' IS NOT NULL
                ),
            2
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
            FILTER (WHERE event_type = 'pre' AND response_status = 'completed')
            AS distinct_pre_completed_participants,
        count(DISTINCT participant_id)
            FILTER (WHERE event_type = 'post' AND response_status = 'completed')
            AS distinct_post_completed_participants,
        count(DISTINCT (participant_id, interval_mark))
            FILTER (WHERE event_type = 'checkpoint' AND response_status = 'completed')
            AS distinct_checkpoint_completed_pairs,
        count(DISTINCT interval_mark)
            FILTER (WHERE event_type = 'checkpoint' AND response_status = 'completed')
            AS distinct_completed_interval_marks,
        count(DISTINCT participant_id)
            FILTER (WHERE event_type = 'checkpoint' AND response_status = 'completed')
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
    coalesce(responses.checkpoint_completed_count, 0) AS checkpoint_completed_count,
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
