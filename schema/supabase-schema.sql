-- =============================================================================
-- Pulselab - Supabase Schema
-- Version: 1.2.0
-- Description: Multi-modal Learning Analytics (MMLA) table for robotics education.
--              Records children cognitive load, post-test attitudes, active application,
--              idle time, and screen capture URLs during LEGO Spike sessions.
-- =============================================================================

-- Enable UUID generation (required for gen_random_uuid)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =============================================================================
-- TABLE: responses
-- =============================================================================

DROP TABLE IF EXISTS public.responses CASCADE;

CREATE TABLE public.responses (
    id                         uuid         DEFAULT gen_random_uuid() PRIMARY KEY,
    session_id                 uuid         NOT NULL,                          -- GUID generated at daemon boot
    regional_hub               text         NOT NULL,                          -- Vindo do config.json, ex: 'Polo-Nordeste-01'
    computer_id                text         NOT NULL,                          -- $env:COMPUTERNAME (Windows hostname)
    interval_mark              integer      NOT NULL CHECK (interval_mark IN (20, 40, 99)), -- 20/40 min mark or 99 (Ending)
    
    -- Student PC Telemetry (Computer Student)
    student_pc_name            text         NOT NULL,                          -- Name of child at PC
    student_pc_load            integer      NOT NULL CHECK (student_pc_load BETWEEN 1 AND 4), -- Cognitive effort
    student_pc_post_afet       text         CHECK (student_pc_post_afet IN ('Orgulho', 'Concentração', 'Frustração')), -- Only on mark 99
    student_pc_post_att        boolean,                                        -- Only on mark 99: Wants to return?

    -- Student Desk Telemetry (Assembly Table Student)
    student_desk_name          text         NOT NULL,                          -- Name of child at physical desk
    student_desk_load          integer      NOT NULL CHECK (student_desk_load BETWEEN 1 AND 4), -- Cognitive effort
    student_desk_post_afet     text         CHECK (student_desk_post_afet IN ('Orgulho', 'Concentração', 'Frustração')), -- Only on mark 99
    student_desk_post_att      boolean,                                        -- Only on mark 99: Wants to return?

    -- OS & Workspace Telemetry
    telemetry_window_title     text,                                           -- Title of focused window
    telemetry_foreground_app   text,                                           -- Focused process name, e.g., 'SPIKE'
    telemetry_idle_seconds     integer,                                        -- Inactivity duration in seconds
    telemetry_file_size_kb     numeric      DEFAULT 0.0,                       -- Last modified .llsp/.spk file size in KB
    screenshot_url             text,                                           -- URL of screenshot uploaded to Storage
    
    created_at                 timestamptz  NOT NULL DEFAULT timezone('utc'::text, now())
);

-- =============================================================================
-- INDEXES
-- =============================================================================

-- Query responses for a specific workshop session
CREATE INDEX IF NOT EXISTS idx_responses_session_id
    ON public.responses (session_id);

-- Query responses by machine or date range
CREATE INDEX IF NOT EXISTS idx_responses_computer_id
    ON public.responses (computer_id);

CREATE INDEX IF NOT EXISTS idx_responses_created_at
    ON public.responses (created_at DESC);

-- =============================================================================
-- ROW LEVEL SECURITY (RLS) - responses table
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

-- =============================================================================
-- SUPABASE STORAGE BUCKET: screenshots
-- =============================================================================

-- Create the public bucket if not exists
INSERT INTO storage.buckets (id, name, public)
VALUES ('screenshots', 'screenshots', true)
ON CONFLICT (id) DO NOTHING;

-- RLS policies for storage objects
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- Allow anonymous users to upload compressed screenshots into the 'screenshots' bucket
CREATE POLICY "Allow anonymous uploads to screenshots"
    ON storage.objects
    FOR INSERT
    TO anon
    WITH CHECK (bucket_id = 'screenshots');

-- Allow anyone to read uploaded screenshots publicly
CREATE POLICY "Allow public read access to screenshots"
    ON storage.objects
    FOR SELECT
    TO public
    USING (bucket_id = 'screenshots');

-- =============================================================================
-- COMMENTS (documentation as code)
-- =============================================================================

COMMENT ON TABLE public.responses IS
    'Pulselab multimodal learning analytics responses. Each row represents a dual student rating at a specific interval mark (20, 40 or 99).';

COMMENT ON COLUMN public.responses.session_id IS
    'GUID generated once per daemon manual run. Identifies all data points of the current workshop session.';

COMMENT ON COLUMN public.responses.interval_mark IS
    'The time mark of the evaluation (20 minutes, 40 minutes, or 99 for Ending/Post-test).';
