-- =============================================================================
-- Pulselab - Supabase Schema
-- Version: 1.1.0
-- Description: Engagement collection table for robotics education project.
--              Records student difficulty responses during LEGO Spike sessions.
-- =============================================================================

-- Enable UUID generation (required for gen_random_uuid)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =============================================================================
-- TABLE: responses
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.responses (
    id             uuid         DEFAULT gen_random_uuid() PRIMARY KEY,
    session_id     text         NOT NULL,                          -- GUID generated at daemon boot
    computer_id    text         NOT NULL,                          -- $env:COMPUTERNAME (Windows hostname)
    activity_id    text         NOT NULL,                          -- Activity identifier from config.json
    students       jsonb        NOT NULL DEFAULT '[]'::jsonb,      -- Array of student names/IDs for the session
    difficulty     integer      NOT NULL CHECK (difficulty BETWEEN 1 AND 5),
    interval_mark  integer      NOT NULL CHECK (interval_mark IN (5, 15, 30)),  -- Minute mark that triggered the popup
    responded_at   timestamptz  NOT NULL DEFAULT now(),
    client_version text
);

-- =============================================================================
-- INDEXES
-- =============================================================================

-- Query by session (most common access pattern for analysis)
CREATE INDEX IF NOT EXISTS idx_responses_session_id
    ON public.responses (session_id);

-- Query by activity across all sessions
CREATE INDEX IF NOT EXISTS idx_responses_activity_id
    ON public.responses (activity_id);

-- Query by date range
CREATE INDEX IF NOT EXISTS idx_responses_responded_at
    ON public.responses (responded_at DESC);

-- =============================================================================
-- ROW LEVEL SECURITY (RLS)
-- =============================================================================

ALTER TABLE public.responses ENABLE ROW LEVEL SECURITY;

-- Anon key: INSERT only
-- Rationale: Client daemons use anon key. Students must not be able to
--            read or modify each other's responses (LGPD compliance).
CREATE POLICY "anon_insert_only"
    ON public.responses
    FOR INSERT
    TO anon
    WITH CHECK (true);

-- Service role: full access (used by researchers via Supabase dashboard)
-- Note: service_role bypasses RLS by default. No explicit policy needed.

-- =============================================================================
-- COMMENTS (documentation as code)
-- =============================================================================

COMMENT ON TABLE public.responses IS
    'Pulselab engagement responses. Each row is one student difficulty rating during a session.';

COMMENT ON COLUMN public.responses.session_id IS
    'GUID generated once per daemon boot. All responses within the same OS session share this ID.';

COMMENT ON COLUMN public.responses.computer_id IS
    'Windows hostname ($env:COMPUTERNAME). Identifies the physical machine.';

COMMENT ON COLUMN public.responses.students IS
    'JSON array of student identifiers entered at session start. Example: ["Ana","Bruno"]';

COMMENT ON COLUMN public.responses.interval_mark IS
    'The scheduled minute mark (5, 15, or 30) at which this popup was triggered during the session.';

COMMENT ON COLUMN public.responses.difficulty IS
    'Student self-reported difficulty on a 1-5 scale. 1=very easy, 5=very hard.';
