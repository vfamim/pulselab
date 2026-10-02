-- Prepared for review; this branch never applies migrations to a remote project.
-- Legacy datasets retain their instrument semantics. V2 test exports are NOT
-- accepted by the legacy ingestion path and have no remote upload adapter.
CREATE TABLE public.research_site_memberships (
    user_id uuid NOT NULL,
    site_id text NOT NULL CHECK (length(trim(site_id)) > 0),
    is_active boolean NOT NULL DEFAULT true,
    PRIMARY KEY (user_id, site_id)
);
ALTER TABLE public.research_site_memberships ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.research_site_memberships FROM anon, authenticated;
GRANT SELECT ON public.research_site_memberships TO authenticated;
GRANT ALL ON public.research_site_memberships TO service_role;
CREATE POLICY own_membership ON public.research_site_memberships FOR SELECT TO authenticated
USING (user_id = (SELECT auth.uid()) AND is_active);

REVOKE ALL ON public.research_events, public.research_session_events FROM anon;
DROP POLICY IF EXISTS anon_insert_research_events ON public.research_events;
DROP POLICY IF EXISTS anon_select_research_events ON public.research_events;
DROP POLICY IF EXISTS anon_insert_research_session_events ON public.research_session_events;
DROP POLICY IF EXISTS anon_select_research_session_events ON public.research_session_events;

DROP POLICY IF EXISTS authenticated_select_research_events ON public.research_events;
CREATE POLICY authenticated_select_research_events ON public.research_events FOR SELECT TO authenticated
USING (
    EXISTS (SELECT 1 FROM public.research_site_memberships m WHERE m.user_id = (SELECT auth.uid()) AND m.site_id = research_events.site_id AND m.is_active)
    OR EXISTS (SELECT 1 FROM public.device_installations d WHERE d.device_user_id = (SELECT auth.uid()) AND d.installation_id = research_events.installation_id AND d.site_id = research_events.site_id AND d.is_active)
);
DROP POLICY IF EXISTS authenticated_select_research_session_events ON public.research_session_events;
CREATE POLICY authenticated_select_research_session_events ON public.research_session_events FOR SELECT TO authenticated
USING (
    EXISTS (SELECT 1 FROM public.research_site_memberships m WHERE m.user_id = (SELECT auth.uid()) AND m.site_id = research_session_events.site_id AND m.is_active)
    OR EXISTS (SELECT 1 FROM public.device_installations d WHERE d.device_user_id = (SELECT auth.uid()) AND d.installation_id = research_session_events.installation_id AND d.site_id = research_session_events.site_id AND d.is_active)
);
CREATE INDEX IF NOT EXISTS research_events_site_access ON public.research_events(site_id);
CREATE INDEX IF NOT EXISTS research_session_events_site_access ON public.research_session_events(site_id);

-- Authenticated devices retain only their existing installation/site-bound INSERT.
-- No public or device screenshot upload in this protocol.
DROP POLICY IF EXISTS "Allow anonymous uploads to screenshots" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated uploads to screenshots" ON storage.objects;

DROP POLICY IF EXISTS authenticated_insert_instructor_evaluations ON public.instructor_evaluations;
CREATE POLICY authenticated_insert_instructor_evaluations ON public.instructor_evaluations FOR INSERT TO authenticated
WITH CHECK (
    instructor_email = coalesce((SELECT auth.jwt()) ->> 'email', '')
    AND session_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.research_site_memberships m WHERE m.user_id = (SELECT auth.uid()) AND m.site_id = instructor_evaluations.site_id AND m.is_active)
    AND EXISTS (SELECT 1 FROM public.research_session_events e WHERE e.session_id = instructor_evaluations.session_id AND e.site_id = instructor_evaluations.site_id)
);
DROP POLICY IF EXISTS authenticated_select_instructor_evaluations ON public.instructor_evaluations;
CREATE POLICY authenticated_select_instructor_evaluations ON public.instructor_evaluations FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.research_site_memberships m WHERE m.user_id = (SELECT auth.uid()) AND m.site_id = instructor_evaluations.site_id AND m.is_active));

-- Expose separate dimensions instead of calling a declined session analytically complete.
CREATE VIEW public.research_session_quality_dimensions WITH (security_invoker = true) AS
SELECT q.session_id, q.site_id,
       CASE WHEN q.has_aborted THEN 'aborted' WHEN q.has_completed THEN 'completed' ELSE 'in_progress' END AS operational_status,
       q.pre_completed_count, q.checkpoint_completed_response_count, q.post_completed_count,
       q.declined_response_count, q.timeout_response_count,
       EXISTS (SELECT 1 FROM public.instructor_evaluations e WHERE e.session_id = q.session_id AND e.site_id = q.site_id) AS outcome_available,
       false AS automatic_research_eligibility
FROM public.research_session_quality q;
REVOKE ALL ON public.research_session_quality_dimensions FROM anon;
GRANT SELECT ON public.research_session_quality_dimensions TO authenticated, service_role;
COMMENT ON VIEW public.research_session_quality_dimensions IS 'Operational completion is separate from valid responses and outcome availability. No automatic eligibility or cross-version pooling.';

-- Explicitly approved, per-site retention. No default retention for legacy data:
-- an administrator must record an institutional decision before scheduling this.
CREATE TABLE public.research_retention_policies (
    site_id text PRIMARY KEY,
    event_days integer NOT NULL CHECK (event_days BETWEEN 1 AND 3650),
    approval_reference text NOT NULL CHECK (length(trim(approval_reference)) > 0)
);
ALTER TABLE public.research_retention_policies ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.research_retention_policies FROM anon, authenticated;
GRANT ALL ON public.research_retention_policies TO service_role;
CREATE FUNCTION public.purge_expired_research_records() RETURNS bigint
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE removed bigint := 0; amount bigint;
BEGIN
    DELETE FROM public.research_events e USING public.research_retention_policies p
    WHERE e.site_id = p.site_id AND e.received_at < now() - make_interval(days => p.event_days);
    GET DIAGNOSTICS amount = ROW_COUNT; removed := removed + amount;
    DELETE FROM public.research_session_events e USING public.research_retention_policies p
    WHERE e.site_id = p.site_id AND e.received_at < now() - make_interval(days => p.event_days);
    GET DIAGNOSTICS amount = ROW_COUNT; removed := removed + amount;
    DELETE FROM public.instructor_evaluations e USING public.research_retention_policies p
    WHERE e.site_id = p.site_id AND e.created_at < now() - make_interval(days => p.event_days);
    GET DIAGNOSTICS amount = ROW_COUNT;
    RETURN removed + amount;
END;
$$;
REVOKE ALL ON FUNCTION public.purge_expired_research_records() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_expired_research_records() TO service_role;
GRANT DELETE ON public.research_events, public.research_session_events, public.instructor_evaluations TO service_role;
