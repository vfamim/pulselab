-- Marca aulas que chegaram com o CAAE de exemplo da 3.2.1 como não autorizadas.
-- Não apaga nada; a revisão do pesquisador decide depois.
-- Rodar periodicamente após sincronização de polos offline.

insert into public.research_unauthorized_sessions (session_id, installation_id, site_id, marked_at)
select distinct on (e.session_id) e.session_id, e.installation_id, e.site_id, now()
  from public.research_session_events e
 where e.event_type = 'session_started'
   and e.details->>'research_authorization_version' = '12345678.9.0000.1234'
on conflict (session_id) do nothing;
