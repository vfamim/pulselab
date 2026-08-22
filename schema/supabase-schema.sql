-- =============================================================================
-- PulseLab - Supabase Schema
-- Version: 1.5.0
-- Description: Eventos individuais e pseudonimizados de oficinas pontuais de
--              robótica educacional, acompanhados por uma linha do tempo
--              append-only de evidências e qualidade. Ingestão autenticada por
--              dispositivo com RLS fail-closed vinculado a installation_id.
--              O script é não destrutivo: tabelas e dados legados não são removidos.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =============================================================================
-- DISPOSITIVOS E INSTALAÇÕES AUTORIZADAS (VÍNCULO DE AUTENTICIDADE)
-- =============================================================================

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

COMMENT ON TABLE public.device_installations IS
    'Vínculo de autenticidade entre a credencial autenticada do dispositivo (auth.uid) e o installation_id/site_id registrado.';

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

COMMENT ON TABLE public.device_enrollment_tokens IS
    'Tokens de enrollment de uso único, com hash criptográfico e expiração, para registro seguro de novos dispositivos.';

-- =============================================================================
-- RESPOSTAS E INSTRUMENTOS DE PESQUISA (RESEARCH EVENTS)
-- =============================================================================

-- Uma linha representa a resposta de um participante em um evento da oficina.
-- O contexto é repetido intencionalmente para manter o envio offline atômico e
-- evitar dependências entre inserts anônimos.
CREATE TABLE IF NOT EXISTS public.research_events (
    id                         uuid         DEFAULT gen_random_uuid() PRIMARY KEY,
    event_id                   uuid         NOT NULL UNIQUE,
    session_id                 uuid         NOT NULL,
    dyad_id                    uuid         NOT NULL,
    installation_id            uuid,
    site_id                    text,
    participant_id             text         NOT NULL,
    participant_role           text         NOT NULL
        CHECK (participant_role IN ('computer', 'assembly', 'member_3', 'member_4', 'individual')),
    event_type                 text         NOT NULL
        CHECK (event_type IN ('pre', 'checkpoint', 'post')),
    response_status            text         NOT NULL DEFAULT 'completed'
        CHECK (response_status IN ('completed', 'timeout', 'declined')),
    interval_mark              integer      CHECK (interval_mark IS NULL OR interval_mark >= 0),

    -- Contexto da implementação
    regional_hub               text         NOT NULL,
    school_code                text         NOT NULL,
    workshop_code              text         NOT NULL,
    class_code                 text         NOT NULL,
    grade_band                 text,
    group_size                 integer      CHECK (group_size IS NULL OR (group_size BETWEEN 1 AND 3)),
    activity_id                text         NOT NULL,
    computer_id                text         NOT NULL,
    protocol_version           text,
    config_version             text         NOT NULL,
    config_hash                text
        CONSTRAINT research_events_config_hash_format
        CHECK (config_hash IS NULL OR config_hash ~ '^[0-9a-f]{64}$'),
    client_version             text         NOT NULL,
    activity_stage             text,

    -- Pré-oficina
    -- Campo legado nullable: preservado para consultar coletas anteriores.
    -- Novas versões do agente não solicitam nem enviam a idade individual.
    student_age                integer      CHECK (student_age IS NULL OR (student_age BETWEEN 5 AND 25)),
    prior_robotics             smallint     CHECK (prior_robotics BETWEEN 1 AND 4),
    self_efficacy_pre          smallint     CHECK (self_efficacy_pre BETWEEN 1 AND 4),
    knowledge_score            numeric,
    knowledge_answers          jsonb,

    -- Checkpoints intrassessão
    self_reported_role         text         CHECK (self_reported_role IS NULL OR self_reported_role IN ('computer', 'assembly', 'both', 'testing')),
    mental_effort              smallint     CHECK (mental_effort BETWEEN 1 AND 4),
    progress_state             text         CHECK (progress_state IN (
        'progressing_independently',
        'progressing_with_doubt',
        'trying_without_progress',
        'needs_help_now'
    )),
    collaboration              smallint     CHECK (collaboration BETWEEN 1 AND 4),
    help_requested             boolean,

    -- Encerramento
    post_understanding         smallint     CHECK (post_understanding BETWEEN 1 AND 4),
    post_affects               text[],
    post_return_intent         smallint     CHECK (post_return_intent BETWEEN 1 AND 4),
    mission_performance        smallint     CHECK (mission_performance BETWEEN 0 AND 3),
    instructor_interventions   smallint     CHECK (instructor_interventions >= 0),
    primary_issue              text         CHECK (primary_issue IN (
        'none', 'assembly', 'logic', 'sensor', 'technical', 'collaboration', 'other'
    )),

    -- Contexto técnico do momento. São evidências auxiliares, não medidas de
    -- aprendizagem por si mesmas.
    telemetry_window_title     text,
    telemetry_foreground_app   text,
    telemetry_idle_seconds     integer      CHECK (telemetry_idle_seconds >= 0),
    telemetry_file_size_kb     numeric      DEFAULT 0.0,
    screenshot_path            text,

    response_latency_ms        integer      CHECK (response_latency_ms >= 0),
    elapsed_ms                 bigint
        CONSTRAINT research_events_elapsed_nonnegative
        CHECK (elapsed_ms >= 0),
    checkpoint_lateness_ms     integer
        CONSTRAINT research_events_lateness_nonnegative
        CHECK (checkpoint_lateness_ms >= 0),
    scheduled_at               timestamptz,
    prompted_at                timestamptz,
    captured_at                timestamptz,
    occurred_at                timestamptz  NOT NULL,
    received_at                timestamptz  NOT NULL DEFAULT timezone('utc'::text, now()),

    CHECK (
        post_affects IS NULL OR
        post_affects <@ ARRAY['curious','confident','excited','frustrated','tired','indifferent']::text[]
    ),
    CHECK (post_affects IS NULL OR cardinality(post_affects) BETWEEN 1 AND 2),
    CHECK (
        (event_type = 'checkpoint' AND interval_mark IS NOT NULL) OR
        (event_type <> 'checkpoint' AND interval_mark IS NULL)
    )
);

-- Compatibilidade com bancos que já possuam a tabela da versão 1.3.
ALTER TABLE public.research_events
    ADD COLUMN IF NOT EXISTS installation_id uuid,
    ADD COLUMN IF NOT EXISTS site_id text,
    ADD COLUMN IF NOT EXISTS protocol_version text,
    ADD COLUMN IF NOT EXISTS config_hash text,
    ADD COLUMN IF NOT EXISTS activity_stage text,
    ADD COLUMN IF NOT EXISTS elapsed_ms bigint,
    ADD COLUMN IF NOT EXISTS checkpoint_lateness_ms integer,
    ADD COLUMN IF NOT EXISTS scheduled_at timestamptz,
    ADD COLUMN IF NOT EXISTS prompted_at timestamptz,
    ADD COLUMN IF NOT EXISTS captured_at timestamptz;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'research_events_config_hash_format'
          AND conrelid = 'public.research_events'::regclass
    ) THEN
        ALTER TABLE public.research_events
            ADD CONSTRAINT research_events_config_hash_format
            CHECK (config_hash IS NULL OR config_hash ~ '^[0-9a-f]{64}$');
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'research_events_elapsed_nonnegative'
          AND conrelid = 'public.research_events'::regclass
    ) THEN
        ALTER TABLE public.research_events
            ADD CONSTRAINT research_events_elapsed_nonnegative
            CHECK (elapsed_ms IS NULL OR elapsed_ms >= 0);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'research_events_lateness_nonnegative'
          AND conrelid = 'public.research_events'::regclass
    ) THEN
        ALTER TABLE public.research_events
            ADD CONSTRAINT research_events_lateness_nonnegative
            CHECK (checkpoint_lateness_ms IS NULL OR checkpoint_lateness_ms >= 0);
    END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_research_events_session
    ON public.research_events (session_id);

CREATE INDEX IF NOT EXISTS idx_research_events_installation_time
    ON public.research_events (installation_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_research_events_workshop
    ON public.research_events (workshop_code, occurred_at);

CREATE INDEX IF NOT EXISTS idx_research_events_participant
    ON public.research_events (participant_id, occurred_at);

CREATE INDEX IF NOT EXISTS idx_research_events_received
    ON public.research_events (received_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_research_events_logical_unique
    ON public.research_events (session_id, participant_id, event_type, COALESCE(interval_mark, -1));

ALTER TABLE public.research_events ENABLE ROW LEVEL SECURITY;

-- O agente autenticado recebe somente INSERT; SELECT, UPDATE e DELETE continuam revogados.
REVOKE ALL ON TABLE public.research_events FROM anon, authenticated;
GRANT INSERT ON TABLE public.research_events TO authenticated;

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

-- =============================================================================
-- LINHA DO TEMPO DE SESSÃO E CONTROLE DE QUALIDADE
-- =============================================================================

-- Eventos append-only permitem reconstruir o ciclo de vida da oficina mesmo
-- quando a rede está instável. Esta tabela não contém respostas dos estudantes.
CREATE TABLE IF NOT EXISTS public.research_session_events (
    event_id                   uuid         PRIMARY KEY,
    session_id                 uuid         NOT NULL,
    dyad_id                    uuid         NOT NULL,
    installation_id            uuid         NOT NULL,

    site_id                    text         NOT NULL,
    regional_hub               text         NOT NULL,
    school_code                text         NOT NULL,
    workshop_code              text         NOT NULL,
    class_code                 text         NOT NULL,
    grade_band                 text,
    activity_id                text         NOT NULL,
    computer_id                text         NOT NULL,

    protocol_version           text         NOT NULL,
    config_version             text         NOT NULL,
    config_hash                text         NOT NULL
        CHECK (config_hash ~ '^[0-9a-f]{64}$'),
    client_version             text         NOT NULL,

    event_type                 text         NOT NULL
        CHECK (event_type IN (
            'session_started',
            'phase_completed',
            'activity_started',
            'heartbeat',
            'checkpoint_started',
            'checkpoint_completed',
            'help_requested',
            'role_swapped',
            'ending_requested',
            'rubric_completed',
            'session_completed',
            'session_aborted',
            'quality_issue'
        )),
    severity                   text         NOT NULL DEFAULT 'info'
        CHECK (severity IN ('info', 'warning', 'error')),
    interval_mark              integer      CHECK (interval_mark IS NULL OR interval_mark >= 0),
    participant_id             text,
    participant_role           text
        CHECK (participant_role IS NULL OR participant_role IN ('computer', 'assembly', 'member_3', 'member_4', 'individual')),
    activity_stage             text,

    elapsed_ms                 bigint       CHECK (elapsed_ms IS NULL OR elapsed_ms >= 0),
    scheduled_at               timestamptz,
    occurred_at                timestamptz  NOT NULL,
    received_at                timestamptz  NOT NULL DEFAULT timezone('utc'::text, now()),
    details                    jsonb        NOT NULL DEFAULT '{}'::jsonb
        CHECK (jsonb_typeof(details) = 'object')
);

CREATE INDEX IF NOT EXISTS idx_research_session_events_session_time
    ON public.research_session_events (session_id, occurred_at);

CREATE INDEX IF NOT EXISTS idx_research_session_events_installation_time
    ON public.research_session_events (installation_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_research_session_events_type_time
    ON public.research_session_events (event_type, occurred_at DESC);

ALTER TABLE public.research_session_events ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.research_session_events FROM anon, authenticated;
GRANT INSERT ON TABLE public.research_session_events TO authenticated;

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

-- =============================================================================
-- LEITURA ANALÍTICA PROTEGIDA (VIEW DE QUALIDADE DA SESSÃO)
-- =============================================================================

-- Consolida completude e alertas sem expor dados ao agente de coleta. A view
-- usa os privilégios do chamador e permanece revogada para anon/authenticated;
-- deve ser consultada apenas pelo backend administrativo autorizado.
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

REVOKE ALL ON TABLE public.research_session_quality FROM anon, authenticated;

-- =============================================================================
-- STORAGE PRIVADO DE SCREENSHOTS COM RESTRIÇÃO POR PREFIXO DE INSTALAÇÃO
-- =============================================================================

INSERT INTO storage.buckets (id, name, public)
VALUES ('screenshots', 'screenshots', false)
ON CONFLICT (id) DO UPDATE SET public = false;

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

-- Remove a política pública criada pela versão 1.2, caso exista. Leituras devem
-- ocorrer somente em backend autorizado, usando service_role ou URL assinada.
DROP POLICY IF EXISTS "Allow public read access to screenshots" ON storage.objects;

COMMENT ON TABLE public.research_events IS
    'Eventos individuais e pseudonimizados coletados durante oficinas pontuais do PulseLab.';

COMMENT ON TABLE public.research_session_events IS
    'Linha do tempo append-only de execução, evidências técnicas minimizadas e qualidade da coleta.';

COMMENT ON VIEW public.research_session_quality IS
    'Resumo protegido de completude e alertas por sessão; leitura exclusiva do backend administrativo.';

COMMENT ON COLUMN public.research_session_events.details IS
    'Metadados técnicos minimizados do evento; não deve receber nomes, respostas livres ou títulos de janelas.';

COMMENT ON COLUMN public.research_events.occurred_at IS
    'Horário do evento no cliente; preserva o momento real mesmo quando o envio ocorre offline.';

COMMENT ON COLUMN public.research_events.received_at IS
    'Horário em que o Supabase recebeu o evento.';

COMMENT ON COLUMN public.research_events.screenshot_path IS
    'Caminho do objeto em bucket privado. Nunca é uma URL pública.';

-- =============================================================================
-- AVALIAÇÃO DE CAMPO DO INSTRUTOR (PORTAL DO INSTRUTOR /instrutor/)
-- =============================================================================

-- Criada antes das policies de avaliação porque elas consultam a whitelist.
CREATE TABLE IF NOT EXISTS public.authorized_instructors (
    id                         uuid         DEFAULT gen_random_uuid() PRIMARY KEY,
    email                      text         NOT NULL UNIQUE,
    full_name                  text,
    role_description           text         DEFAULT 'Instrutor de Robótica',
    is_active                  boolean      NOT NULL DEFAULT true,
    added_at                   timestamptz  NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE TABLE IF NOT EXISTS public.instructor_evaluations (
    id                         uuid         DEFAULT gen_random_uuid() PRIMARY KEY,
    instructor_email           text         NOT NULL,
    submitted_at               timestamptz  NOT NULL DEFAULT timezone('utc'::text, now()),
    workshop_code              text         NOT NULL,
    class_code                 text         NOT NULL,
    site_id                    text,
    session_id                 uuid,
    dyad_id                    uuid,
    installation_id            uuid,
    mission_performance        smallint     NOT NULL CHECK (mission_performance BETWEEN 0 AND 3),
    instructor_interventions   smallint     NOT NULL CHECK (instructor_interventions >= 0),
    primary_issue              text         NOT NULL CHECK (primary_issue IN (
        'none', 'assembly', 'logic', 'sensor', 'technical', 'collaboration', 'other'
    )),
    notes                      jsonb        NOT NULL DEFAULT '{}'::jsonb,
    created_at                 timestamptz  NOT NULL DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.instructor_evaluations
    ADD COLUMN IF NOT EXISTS session_id uuid,
    ADD COLUMN IF NOT EXISTS dyad_id uuid,
    ADD COLUMN IF NOT EXISTS installation_id uuid;

CREATE INDEX IF NOT EXISTS idx_instructor_evaluations_email
    ON public.instructor_evaluations (instructor_email, submitted_at DESC);

CREATE INDEX IF NOT EXISTS idx_instructor_evaluations_workshop
    ON public.instructor_evaluations (workshop_code, submitted_at DESC);

CREATE INDEX IF NOT EXISTS idx_instructor_evaluations_session
    ON public.instructor_evaluations (session_id);

ALTER TABLE public.instructor_evaluations ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.instructor_evaluations FROM anon, authenticated;
GRANT INSERT, SELECT ON TABLE public.instructor_evaluations TO authenticated;

DROP POLICY IF EXISTS "allow_insert_instructor_evaluations" ON public.instructor_evaluations;
DROP POLICY IF EXISTS "authenticated_insert_instructor_evaluations" ON public.instructor_evaluations;
CREATE POLICY "authenticated_insert_instructor_evaluations"
    ON public.instructor_evaluations
    FOR INSERT
    TO authenticated
    WITH CHECK (
        instructor_email = COALESCE(auth.jwt() ->> 'email', '')
        AND session_id IS NOT NULL
        AND EXISTS (
            SELECT 1
            FROM public.authorized_instructors ai
            WHERE lower(ai.email) = lower(COALESCE(auth.jwt() ->> 'email', ''))
              AND ai.is_active = true
        )
    );

DROP POLICY IF EXISTS "authenticated_select_instructor_evaluations" ON public.instructor_evaluations;
CREATE POLICY "authenticated_select_instructor_evaluations"
    ON public.instructor_evaluations
    FOR SELECT
    TO authenticated
    USING (
        instructor_email = COALESCE(auth.jwt() ->> 'email', '')
        AND EXISTS (
            SELECT 1
            FROM public.authorized_instructors ai
            WHERE lower(ai.email) = lower(COALESCE(auth.jwt() ->> 'email', ''))
              AND ai.is_active = true
        )
    );

COMMENT ON TABLE public.instructor_evaluations IS
    'Avaliações de campo preenchidas de forma independente pelos instrutores no Portal do Instrutor (/instrutor/).';

-- =============================================================================
-- LISTA DE INSTRUTORES AUTORIZADOS (WHITELIST DE ACESSO EXCLUSIVO)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.authorized_instructors (
    id                         uuid         DEFAULT gen_random_uuid() PRIMARY KEY,
    email                      text         NOT NULL UNIQUE,
    full_name                  text,
    role_description           text         DEFAULT 'Instrutor de Robótica',
    is_active                  boolean      NOT NULL DEFAULT true,
    added_at                   timestamptz  NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_authorized_instructors_email
    ON public.authorized_instructors (email);

ALTER TABLE public.authorized_instructors ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.authorized_instructors FROM anon, authenticated;
GRANT SELECT ON TABLE public.authorized_instructors TO authenticated;

DROP POLICY IF EXISTS "allow_select_authorized_instructors" ON public.authorized_instructors;
DROP POLICY IF EXISTS "authenticated_select_authorized_instructors" ON public.authorized_instructors;
CREATE POLICY "authenticated_select_authorized_instructors"
    ON public.authorized_instructors
    FOR SELECT
    TO authenticated
    USING (
        (email = COALESCE(auth.jwt() ->> 'email', '') AND is_active = true)
        OR (auth.jwt() ->> 'role') = 'service_role'
    );

COMMENT ON TABLE public.authorized_instructors IS
    'Lista seleta e autorizada de instrutores que possuem acesso exclusivo ao portal de avaliacao.';

-- Cadastrar o administrador inicial Vinicius Famim (vfamim@gmail.com)
INSERT INTO public.authorized_instructors (email, full_name, role_description, is_active)
VALUES ('vfamim@gmail.com', 'Vinicius Famim', 'Coordenador / Administrador PulseLab', true)
ON CONFLICT (email) DO UPDATE SET is_active = true;
