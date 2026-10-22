BEGIN;
SELECT no_plan();

-- Prazo de guarda gravado e protegido
SELECT is((SELECT delete_after FROM public.research_archive_deadline),'2032-12-31'::date,'archive deadline is 2032-12-31');
SELECT ok(NOT has_table_privilege('authenticated','public.research_archive_deadline','SELECT'),'authenticated cannot read deadline');
SELECT ok(NOT has_table_privilege('authenticated','public.research_archive_deadline','UPDATE'),'authenticated cannot change deadline');
SELECT ok(NOT has_table_privilege('anon','public.research_archive_deadline','UPDATE'),'anon cannot change deadline');
SELECT throws_ok($q$INSERT INTO public.research_archive_deadline(delete_after,approval_reference) VALUES('2040-01-01','outra')$q$,'23505',NULL,'only one deadline row');

INSERT INTO public.device_installations(device_user_id, installation_id, site_id) VALUES
('00000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','SITE_A');
INSERT INTO public.research_events(event_id,session_id,dyad_id,installation_id,site_id,participant_id,participant_role,event_type,regional_hub,school_code,workshop_code,class_code,activity_id,computer_id,config_version,client_version,occurred_at) VALUES
(gen_random_uuid(),'c1000000-0000-4000-8000-000000000001',gen_random_uuid(),'10000000-0000-4000-8000-000000000001','SITE_A','A','computer','pre','R','E','O','T','ACT','PC','legacy','legacy',now());
INSERT INTO public.research_session_events(event_id,session_id,installation_id,site_id,school_code,workshop_code,class_code,activity_id,client_version,event_type,occurred_at) VALUES
(gen_random_uuid(),'c1000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','SITE_A','E','O','T','ACT','3.2.4','session_started',now()),
(gen_random_uuid(),'c2000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001','SITE_A','E','O','T','ACT','3.2.4','session_started',now());
INSERT INTO public.research_bancada_sessions(session_id,site_id,installation_id,phase,session_payload,created_at,updated_at) VALUES
('c1000000-0000-4000-8000-000000000001','SITE_A','10000000-0000-4000-8000-000000000001','completed','{}'::jsonb,now(),now()),
('c2000000-0000-4000-8000-000000000002','SITE_A','10000000-0000-4000-8000-000000000001','completed','{"authorization_status":"nao_autorizada"}'::jsonb,now(),now());

-- Antes do prazo e sem política por polo: nada é apagado
SET LOCAL ROLE service_role;
SELECT is(public.purge_expired_research_records(),0::bigint,'before deadline nothing is purged');
RESET ROLE;
SELECT is((SELECT count(*) FROM public.research_bancada_sessions WHERE session_id::text LIKE 'c%'),2::bigint,'snapshots kept before deadline');

-- Depois do prazo: tudo é apagado, inclusive linhas do tempo e marcações
UPDATE public.research_archive_deadline SET delete_after = current_date - 1;
SET LOCAL ROLE service_role;
SELECT is(public.purge_expired_research_records(),6::bigint,'after deadline everything is purged');
RESET ROLE;
SELECT is((SELECT count(*) FROM public.research_events),0::bigint,'no events left');
SELECT is((SELECT count(*) FROM public.research_session_events),0::bigint,'no session events left');
SELECT is((SELECT count(*) FROM public.research_bancada_sessions),0::bigint,'no session snapshots left');
SELECT is((SELECT count(*) FROM public.research_unauthorized_sessions),0::bigint,'no marks left');

-- Coleta atrasada (pendrive) que chega depois do prazo cai na execução seguinte
INSERT INTO public.research_session_events(event_id,session_id,installation_id,site_id,school_code,workshop_code,class_code,activity_id,client_version,event_type,occurred_at) VALUES
(gen_random_uuid(),'c3000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000001','SITE_A','E','O','T','ACT','3.2.4','session_started',now());
SET LOCAL ROLE service_role;
SELECT is(public.purge_expired_research_records(),1::bigint,'late arrival after deadline is purged next run');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
