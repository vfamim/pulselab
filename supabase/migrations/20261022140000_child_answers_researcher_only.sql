-- Migration: 20261022140000_child_answers_researcher_only.sql
-- Description:
--   As respostas individuais das crianças (perguntas 4 a 8, student_feedback_recorded) são
--   desidentificadas, não anônimas: com máquina, data e ordem das rodadas, quem estava na sala
--   consegue ligar uma rodada a uma criança. Linha a linha, só o pesquisador (service_role) as lê.
--
--   1. research_questionario_respostas deixa de ser lida por authenticated (membros do polo).
--   2. Política de SELECT de research_session_events: o ramo do membro não vê
--      student_feedback_recorded (mantém o filtro de aula autorizada da migração 20261022120000).
--      A máquina dona continua lendo os próprios eventos.
--   3. O snapshot (research_bancada_sessions.session_payload) não guarda essas respostas na
--      timeline: elas já chegam uma a uma em research_session_events, e o snapshot é lido pelos
--      membros na view research_aula_bancada. Um trigger as retira em toda gravação, e as linhas
--      já guardadas são limpas aqui.
--   As respostas da bancada (perguntas 1 a 3, coletivas) continuam visíveis aos membros.

REVOKE SELECT ON public.research_questionario_respostas FROM authenticated;
COMMENT ON VIEW public.research_questionario_respostas IS
    'Questionário do fim da aula: uma linha por resposta (bancada ou criança). Desidentificado, não anônimo: só service_role lê. Aulas não autorizadas ficam fora. Horários em America/Recife.';

DROP POLICY IF EXISTS authenticated_select_research_session_events ON public.research_session_events;
CREATE POLICY authenticated_select_research_session_events ON public.research_session_events FOR SELECT TO authenticated
USING (
    (
        EXISTS (SELECT 1 FROM public.research_site_memberships m WHERE m.user_id = (SELECT auth.uid()) AND m.site_id = research_session_events.site_id AND m.is_active)
        AND public.research_session_is_authorized(research_session_events.session_id)
        AND research_session_events.event_type <> 'student_feedback_recorded'
    )
    OR EXISTS (SELECT 1 FROM public.device_installations d WHERE d.device_user_id = (SELECT auth.uid()) AND d.installation_id = research_session_events.installation_id AND d.site_id = research_session_events.site_id AND d.is_active)
);

CREATE OR REPLACE FUNCTION public.strip_child_answers_from_snapshot()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    IF jsonb_typeof(NEW.session_payload -> 'timeline') = 'array'
       AND EXISTS (SELECT 1 FROM jsonb_array_elements(NEW.session_payload -> 'timeline') e
                    WHERE e ->> 'event_type' = 'student_feedback_recorded') THEN
        NEW.session_payload := jsonb_set(NEW.session_payload, '{timeline}', coalesce(
            (SELECT jsonb_agg(t.e ORDER BY t.ord)
               FROM jsonb_array_elements(NEW.session_payload -> 'timeline') WITH ORDINALITY AS t(e, ord)
              WHERE coalesce(t.e ->> 'event_type', '') <> 'student_feedback_recorded'),
            '[]'::jsonb));
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.strip_child_answers_from_snapshot() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS strip_child_answers_from_snapshot ON public.research_bancada_sessions;
CREATE TRIGGER strip_child_answers_from_snapshot
    BEFORE INSERT OR UPDATE OF session_payload ON public.research_bancada_sessions
    FOR EACH ROW EXECUTE FUNCTION public.strip_child_answers_from_snapshot();

-- Snapshots já guardados: a atribuição dispara o trigger acima.
UPDATE public.research_bancada_sessions s
   SET session_payload = s.session_payload
 WHERE jsonb_typeof(s.session_payload -> 'timeline') = 'array'
   AND EXISTS (SELECT 1 FROM jsonb_array_elements(s.session_payload -> 'timeline') e
                WHERE e ->> 'event_type' = 'student_feedback_recorded');
