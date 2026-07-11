-- =============================================================================
-- PulseLab - Supabase Schema
-- Version: 1.3.0
-- Description: Eventos individuais e pseudonimizados de oficinas pontuais de
--              robótica educacional. O script é não destrutivo: a tabela
--              legada `responses` não é removida.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Uma linha representa a resposta de um participante em um evento da oficina.
-- O contexto é repetido intencionalmente para manter o envio offline atômico e
-- evitar dependências entre inserts anônimos.
CREATE TABLE IF NOT EXISTS public.research_events (
    id                         uuid         DEFAULT gen_random_uuid() PRIMARY KEY,
    event_id                   uuid         NOT NULL UNIQUE,
    session_id                 uuid         NOT NULL,
    dyad_id                    uuid         NOT NULL,
    participant_id             text         NOT NULL,
    participant_role           text         NOT NULL
        CHECK (participant_role IN ('computer', 'assembly')),
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
    activity_id                text         NOT NULL,
    computer_id                text         NOT NULL,
    config_version             text         NOT NULL,
    client_version             text         NOT NULL,

    -- Pré-oficina
    prior_robotics             smallint     CHECK (prior_robotics BETWEEN 1 AND 4),
    self_efficacy_pre          smallint     CHECK (self_efficacy_pre BETWEEN 1 AND 4),
    knowledge_score            numeric,
    knowledge_answers          jsonb,

    -- Checkpoints intrassessão
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

CREATE INDEX IF NOT EXISTS idx_research_events_session
    ON public.research_events (session_id);

CREATE INDEX IF NOT EXISTS idx_research_events_workshop
    ON public.research_events (workshop_code, occurred_at);

CREATE INDEX IF NOT EXISTS idx_research_events_participant
    ON public.research_events (participant_id, occurred_at);

CREATE INDEX IF NOT EXISTS idx_research_events_received
    ON public.research_events (received_at DESC);

ALTER TABLE public.research_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_insert_research_events" ON public.research_events;
CREATE POLICY "anon_insert_research_events"
    ON public.research_events
    FOR INSERT
    TO anon
    WITH CHECK (true);

-- =============================================================================
-- STORAGE PRIVADO
-- =============================================================================

INSERT INTO storage.buckets (id, name, public)
VALUES ('screenshots', 'screenshots', false)
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "Allow anonymous uploads to screenshots" ON storage.objects;
CREATE POLICY "Allow anonymous uploads to screenshots"
    ON storage.objects
    FOR INSERT
    TO anon
    WITH CHECK (bucket_id = 'screenshots');

-- Remove a política pública criada pela versão 1.2, caso exista. Leituras devem
-- ocorrer somente em backend autorizado, usando service_role ou URL assinada.
DROP POLICY IF EXISTS "Allow public read access to screenshots" ON storage.objects;

COMMENT ON TABLE public.research_events IS
    'Eventos individuais e pseudonimizados coletados durante oficinas pontuais do PulseLab.';

COMMENT ON COLUMN public.research_events.occurred_at IS
    'Horário do evento no cliente; preserva o momento real mesmo quando o envio ocorre offline.';

COMMENT ON COLUMN public.research_events.received_at IS
    'Horário em que o Supabase recebeu o evento.';

COMMENT ON COLUMN public.research_events.screenshot_path IS
    'Caminho do objeto em bucket privado. Nunca é uma URL pública.';
