-- Migration: 20261022130000_research_archive_deadline.sql
-- Description:
--   Prazo de guarda dos dados da pesquisa na nuvem. As Res. CNS 466 (XI.2.f) e 510 (art. 28)
--   pedem guarda por no mínimo 5 anos após o término da pesquisa; o TCLE informa às famílias a
--   data em que os dados são apagados. Até aqui não havia prazo nenhum: purge_expired_research_records
--   só aplicava políticas por polo (research_retention_policies, vazia) e nada a agendava.
--
--   1. research_archive_deadline: uma linha com a data depois da qual tudo é apagado
--      (2032-12-31: término previsto em 2027 + 5 anos). Mudar a data exige nova migração ou
--      service_role, e deve acompanhar o parecer do CEP.
--   2. purge_expired_research_records passa a apagar, depois do prazo, todos os eventos, linhas do
--      tempo, avaliações e marcações de aula. Coletas que chegarem depois (pendrive atrasado) caem
--      na execução seguinte. As políticas por polo continuam valendo antes do prazo.
--   3. pg_cron roda a limpeza todo dia às 03:30 UTC. pg_cron só existe no banco configurado em
--      cron.database_name (postgres no Supabase); em outro banco, a migração avisa e não agenda.

CREATE TABLE IF NOT EXISTS public.research_archive_deadline (
    singleton          boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    delete_after       date    NOT NULL,
    approval_reference text    NOT NULL CHECK (length(trim(approval_reference)) > 0)
);
ALTER TABLE public.research_archive_deadline ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.research_archive_deadline FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.research_archive_deadline TO service_role;

INSERT INTO public.research_archive_deadline (delete_after, approval_reference)
VALUES ('2032-12-31', 'Guarda por 5 anos apos o termino da pesquisa (previsto em 2027), Res. CNS 466 XI.2.f e 510 art. 28. Atualizar com o parecer do CEP.')
ON CONFLICT (singleton) DO NOTHING;

COMMENT ON TABLE public.research_archive_deadline IS
    'Data depois da qual purge_expired_research_records apaga todos os dados da pesquisa. Deve coincidir com o TCLE.';

CREATE OR REPLACE FUNCTION public.purge_expired_research_records() RETURNS bigint
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE removed bigint := 0; amount bigint;
BEGIN
    -- Fim do prazo de guarda: apaga tudo (WHERE true por causa do pg_safeupdate).
    IF EXISTS (SELECT 1 FROM public.research_archive_deadline d WHERE current_date > d.delete_after) THEN
        DELETE FROM public.research_events WHERE true;
        GET DIAGNOSTICS amount = ROW_COUNT; removed := removed + amount;
        DELETE FROM public.research_session_events WHERE true;
        GET DIAGNOSTICS amount = ROW_COUNT; removed := removed + amount;
        DELETE FROM public.instructor_evaluations WHERE true;
        GET DIAGNOSTICS amount = ROW_COUNT; removed := removed + amount;
        DELETE FROM public.research_bancada_sessions WHERE true;
        GET DIAGNOSTICS amount = ROW_COUNT; removed := removed + amount;
        DELETE FROM public.research_unauthorized_sessions WHERE true;
        GET DIAGNOSTICS amount = ROW_COUNT; removed := removed + amount;
        RETURN removed;
    END IF;

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

DO $$
BEGIN
    IF current_database() = current_setting('cron.database_name', true) THEN
        CREATE EXTENSION IF NOT EXISTS pg_cron;
        PERFORM cron.schedule('pulselab-purge-research', '30 3 * * *', 'SELECT public.purge_expired_research_records()');
    ELSE
        RAISE WARNING 'pg_cron indisponivel no banco %; agende public.purge_expired_research_records() diariamente.', current_database();
    END IF;
END;
$$;
