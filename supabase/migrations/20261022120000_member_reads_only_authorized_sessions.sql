-- Migration: 20261022120000_member_reads_only_authorized_sessions.sql
-- Description:
--   Aula marcada como não autorizada deixa de ser lida pelos membros do polo também nas tabelas
--   base. Até aqui o filtro research_session_is_authorized existia só nas views; quem tinha vínculo
--   com o polo lia as aulas recusadas direto em research_events, research_session_events e
--   research_bancada_sessions (PostgREST expõe as tabelas a quem tem grant).
--
--   Só o ramo do membro (research_site_memberships) ganha o filtro. O ramo da máquina dona fica
--   igual: ela já tem os dados localmente e o reenvio com ON CONFLICT precisa enxergar a linha
--   guardada. service_role (revisão do pesquisador) ignora RLS e continua vendo tudo.
--
--   Efeito colateral aceito: em research_installation_last_seen (security_invoker), para o membro,
--   last_received_at deixa de contar chegadas de aulas marcadas.

DROP POLICY IF EXISTS authenticated_select_research_events ON public.research_events;
CREATE POLICY authenticated_select_research_events ON public.research_events FOR SELECT TO authenticated
USING (
    (
        EXISTS (SELECT 1 FROM public.research_site_memberships m WHERE m.user_id = (SELECT auth.uid()) AND m.site_id = research_events.site_id AND m.is_active)
        AND public.research_session_is_authorized(research_events.session_id)
    )
    OR EXISTS (SELECT 1 FROM public.device_installations d WHERE d.device_user_id = (SELECT auth.uid()) AND d.installation_id = research_events.installation_id AND d.site_id = research_events.site_id AND d.is_active)
);

DROP POLICY IF EXISTS authenticated_select_research_session_events ON public.research_session_events;
CREATE POLICY authenticated_select_research_session_events ON public.research_session_events FOR SELECT TO authenticated
USING (
    (
        EXISTS (SELECT 1 FROM public.research_site_memberships m WHERE m.user_id = (SELECT auth.uid()) AND m.site_id = research_session_events.site_id AND m.is_active)
        AND public.research_session_is_authorized(research_session_events.session_id)
    )
    OR EXISTS (SELECT 1 FROM public.device_installations d WHERE d.device_user_id = (SELECT auth.uid()) AND d.installation_id = research_session_events.installation_id AND d.site_id = research_session_events.site_id AND d.is_active)
);

DROP POLICY IF EXISTS authenticated_select_bancada_sessions ON public.research_bancada_sessions;
CREATE POLICY authenticated_select_bancada_sessions ON public.research_bancada_sessions
FOR SELECT TO authenticated
USING (
    (
        research_bancada_sessions.site_id IS NOT NULL
        AND EXISTS (
            SELECT 1 FROM public.research_site_memberships m
            WHERE m.user_id = (SELECT auth.uid())
            AND m.site_id = research_bancada_sessions.site_id
            AND m.is_active
        )
        AND public.research_session_is_authorized(research_bancada_sessions.session_id)
    )
    OR (
        research_bancada_sessions.site_id IS NOT NULL
        AND research_bancada_sessions.installation_id IS NOT NULL
        AND EXISTS (
            SELECT 1 FROM public.device_installations d
            WHERE d.device_user_id = (SELECT auth.uid())
            AND d.installation_id = research_bancada_sessions.installation_id
            AND d.site_id = research_bancada_sessions.site_id
            AND d.is_active
        )
    )
);
