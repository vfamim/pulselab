-- Retirada ética durável: o dispositivo autenticado pode apagar somente a própria sessão.
-- Também inclui snapshots de bancada na retenção institucional já existente.

CREATE OR REPLACE FUNCTION public.purge_own_research_session(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_installation_id uuid;
    v_site_id text;
    v_owned boolean := false;
    v_responses bigint := 0;
    v_timeline bigint := 0;
    v_snapshots bigint := 0;
    v_evaluations bigint := 0;
BEGIN
    SELECT d.installation_id, d.site_id
      INTO v_installation_id, v_site_id
      FROM public.device_installations d
     WHERE d.device_user_id = auth.uid()
       AND d.is_active = true
     LIMIT 1;

    IF v_installation_id IS NULL THEN
        RAISE EXCEPTION 'active device installation required' USING ERRCODE = '42501';
    END IF;

    SELECT
        EXISTS (
            SELECT 1 FROM public.research_events e
             WHERE e.session_id = p_session_id
               AND e.installation_id = v_installation_id
               AND e.site_id = v_site_id
        ) OR EXISTS (
            SELECT 1 FROM public.research_session_events e
             WHERE e.session_id = p_session_id
               AND e.installation_id = v_installation_id
               AND e.site_id = v_site_id
        ) OR EXISTS (
            SELECT 1 FROM public.research_bancada_sessions s
             WHERE s.session_id = p_session_id
               AND s.installation_id = v_installation_id
               AND s.site_id = v_site_id
        )
      INTO v_owned;

    -- Idempotência: uma segunda tentativa após exclusão é sucesso, sem ampliar o escopo.
    IF NOT v_owned THEN
        RETURN jsonb_build_object('purged', true, 'already_absent', true, 'session_id', p_session_id);
    END IF;

    DELETE FROM public.instructor_evaluations e
     WHERE e.session_id = p_session_id
       AND e.site_id = v_site_id;
    GET DIAGNOSTICS v_evaluations = ROW_COUNT;

    DELETE FROM public.research_events e
     WHERE e.session_id = p_session_id
       AND e.installation_id = v_installation_id
       AND e.site_id = v_site_id;
    GET DIAGNOSTICS v_responses = ROW_COUNT;

    DELETE FROM public.research_session_events e
     WHERE e.session_id = p_session_id
       AND e.installation_id = v_installation_id
       AND e.site_id = v_site_id;
    GET DIAGNOSTICS v_timeline = ROW_COUNT;

    DELETE FROM public.research_bancada_sessions s
     WHERE s.session_id = p_session_id
       AND s.installation_id = v_installation_id
       AND s.site_id = v_site_id;
    GET DIAGNOSTICS v_snapshots = ROW_COUNT;

    RETURN jsonb_build_object(
        'purged', true,
        'session_id', p_session_id,
        'responses', v_responses,
        'timeline_events', v_timeline,
        'snapshots', v_snapshots,
        'evaluations', v_evaluations
    );
END;
$$;

REVOKE ALL ON FUNCTION public.purge_own_research_session(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.purge_own_research_session(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.purge_expired_research_records() RETURNS bigint
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
    GET DIAGNOSTICS amount = ROW_COUNT; removed := removed + amount;

    DELETE FROM public.research_bancada_sessions s USING public.research_retention_policies p
    WHERE s.site_id = p.site_id AND s.received_at < now() - make_interval(days => p.event_days);
    GET DIAGNOSTICS amount = ROW_COUNT; removed := removed + amount;

    RETURN removed;
END;
$$;

REVOKE ALL ON FUNCTION public.purge_expired_research_records() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_expired_research_records() TO service_role;
GRANT DELETE ON public.research_bancada_sessions TO service_role;
