BEGIN;
SELECT no_plan();
INSERT INTO public.device_installations(device_user_id, installation_id, site_id) VALUES
('00000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','SITE_A'),
('00000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','SITE_B');
INSERT INTO public.research_site_memberships(user_id, site_id) VALUES
('00000000-0000-4000-8000-000000000003','SITE_A');

-- Permissões
SELECT ok(NOT has_table_privilege('anon','public.research_unauthorized_sessions','SELECT'),'anon cannot read marks');
SELECT ok(NOT has_table_privilege('authenticated','public.research_unauthorized_sessions','SELECT'),'authenticated cannot read marks');
SELECT ok(NOT has_table_privilege('authenticated','public.research_unauthorized_sessions','INSERT'),'authenticated cannot write marks directly');
SELECT ok(has_function_privilege('authenticated','public.research_session_is_authorized(uuid)','EXECUTE'),'views can use the reusable filter');
SELECT ok(NOT has_function_privilege('authenticated','public.review_purge_research_session(uuid)','EXECUTE'),'only service_role purges in review');
SELECT ok(NOT has_function_privilege('authenticated','public.review_restore_research_session(uuid,text)','EXECUTE'),'only service_role restores in review');

-- Dispositivo A: aula marcada (A1), aula normal (A2) e aula enviada antes de ser marcada (A3)
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
INSERT INTO public.research_session_events(event_id,session_id,installation_id,site_id,school_code,workshop_code,class_code,activity_id,client_version,event_type,occurred_at) VALUES
(gen_random_uuid(),'a1000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','SITE_A','E','O','T','ACT','3.0.9','session_started',now()),
(gen_random_uuid(),'a1000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','SITE_A','E','O','T','ACT','3.0.9','session_completed',now()),
(gen_random_uuid(),'a2000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001','SITE_A','E','O','T','ACT','3.0.9','session_started',now()),
(gen_random_uuid(),'a3000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000001','SITE_A','E','O','T','ACT','3.0.9','session_started',now());
INSERT INTO public.research_events(event_id,session_id,dyad_id,installation_id,site_id,participant_id,participant_role,event_type,regional_hub,school_code,workshop_code,class_code,activity_id,computer_id,config_version,client_version,occurred_at) VALUES
(gen_random_uuid(),'a1000000-0000-4000-8000-000000000001',gen_random_uuid(),'10000000-0000-4000-8000-000000000001','SITE_A','A','computer','pre','R','E','O','T','ACT','PC','legacy','legacy',now()),
(gen_random_uuid(),'a2000000-0000-4000-8000-000000000002',gen_random_uuid(),'10000000-0000-4000-8000-000000000001','SITE_A','A','computer','pre','R','E','O','T','ACT','PC','legacy','legacy',now());
INSERT INTO public.research_bancada_sessions(session_id,site_id,installation_id,phase,interrupted,session_payload,created_at,updated_at) VALUES
('a1000000-0000-4000-8000-000000000001','SITE_A','10000000-0000-4000-8000-000000000001','completed',true,'{"authorization_status":"nao_autorizada","marked_at":"2026-10-15T14:00:00Z"}'::jsonb,now(),now()),
('a2000000-0000-4000-8000-000000000002','SITE_A','10000000-0000-4000-8000-000000000001','completed',true,'{}'::jsonb,now(),now()),
('a3000000-0000-4000-8000-000000000003','SITE_A','10000000-0000-4000-8000-000000000001','completed',false,'{}'::jsonb,now(),now());
-- Reenvio de A3 já guardada, agora marcada (ignore-duplicates do bridge)
SELECT lives_ok($q$INSERT INTO public.research_bancada_sessions(session_id,site_id,installation_id,phase,session_payload,created_at,updated_at)
VALUES('a3000000-0000-4000-8000-000000000003','SITE_A','10000000-0000-4000-8000-000000000001','completed','{"authorization_status":"nao_autorizada","marked_at":"2026-10-15T15:00:00Z"}'::jsonb,now(),now())
ON CONFLICT (session_id) DO NOTHING$q$,'resend of stored session with mark does not error');
-- Dispositivo A não consegue marcar em nome de outra instalação
SELECT throws_ok($q$INSERT INTO public.research_bancada_sessions(session_id,site_id,installation_id,phase,session_payload,created_at,updated_at)
VALUES('b1000000-0000-4000-8000-000000000001','SITE_B','10000000-0000-4000-8000-000000000002','completed','{"authorization_status":"nao_autorizada"}'::jsonb,now(),now())
ON CONFLICT (session_id) DO NOTHING$q$,'42501',NULL,'device cannot mark with a foreign installation');
RESET ROLE;

SELECT is((SELECT marked_at FROM public.research_unauthorized_sessions WHERE session_id='a1000000-0000-4000-8000-000000000001'),'2026-10-15T14:00:00Z'::timestamptz,'snapshot with nao_autorizada records the mark');
SELECT is((SELECT count(*) FROM public.research_unauthorized_sessions WHERE session_id='a3000000-0000-4000-8000-000000000003'),1::bigint,'resend of an already stored session records the mark');
SELECT is((SELECT count(*) FROM public.research_bancada_sessions WHERE session_id='a1000000-0000-4000-8000-000000000001'),1::bigint,'marked session is kept, not deleted');
SELECT is((SELECT count(*) FROM public.research_unauthorized_sessions WHERE session_id='b1000000-0000-4000-8000-000000000001'),0::bigint,'rejected foreign insert leaves no mark');

-- Dispositivo B reenvia o session_id de A2 com a marca: a sessão de A não muda
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
SELECT lives_ok($q$INSERT INTO public.research_bancada_sessions(session_id,site_id,installation_id,phase,session_payload,created_at,updated_at)
VALUES('a2000000-0000-4000-8000-000000000002','SITE_B','10000000-0000-4000-8000-000000000002','completed','{"authorization_status":"nao_autorizada"}'::jsonb,now(),now())
ON CONFLICT (session_id) DO NOTHING$q$,'foreign resend is ignored');
RESET ROLE;
SELECT is((SELECT count(*) FROM public.research_unauthorized_sessions WHERE session_id='a2000000-0000-4000-8000-000000000002'),0::bigint,'only the owning machine can mark a session');

-- Views de análise e qualidade não mostram aula marcada
SET LOCAL ROLE service_role;
SELECT is((SELECT array_agg(session_id::text ORDER BY session_id) FROM public.research_session_quality),ARRAY['a2000000-0000-4000-8000-000000000002'],'quality view hides marked sessions');
SELECT is((SELECT count(*) FROM public.research_session_quality_dimensions WHERE session_id IN ('a1000000-0000-4000-8000-000000000001','a3000000-0000-4000-8000-000000000003')),0::bigint,'quality dimensions hide marked sessions');
SELECT is((SELECT sessions_last_30d FROM public.research_installation_last_seen WHERE installation_id='10000000-0000-4000-8000-000000000001'),1::bigint,'last-seen counts only authorized sessions');
SELECT is((SELECT interrupted_sessions_last_30d FROM public.research_installation_last_seen WHERE installation_id='10000000-0000-4000-8000-000000000001'),1::bigint,'marked interrupted session not counted');
SELECT ok((SELECT last_received_at IS NOT NULL FROM public.research_installation_last_seen WHERE installation_id='10000000-0000-4000-8000-000000000001'),'machine still shows as sending');
SELECT ok(NOT public.research_session_is_authorized('a1000000-0000-4000-8000-000000000001'),'reusable filter is false for marked session');
SELECT ok(public.research_session_is_authorized('a2000000-0000-4000-8000-000000000002'),'reusable filter is true for normal session');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
SELECT is((SELECT count(*) FROM public.research_session_quality),1::bigint,'researcher view hides marked sessions');
-- Tabelas base: o membro do polo também não lê aula marcada fora das views
SELECT is((SELECT count(*) FROM public.research_bancada_sessions WHERE session_id IN ('a1000000-0000-4000-8000-000000000001','a3000000-0000-4000-8000-000000000003')),0::bigint,'researcher cannot read marked sessions in base snapshot table');
SELECT is((SELECT count(*) FROM public.research_session_events WHERE session_id IN ('a1000000-0000-4000-8000-000000000001','a3000000-0000-4000-8000-000000000003')),0::bigint,'researcher cannot read marked session events in base table');
SELECT is((SELECT count(*) FROM public.research_events WHERE session_id = 'a1000000-0000-4000-8000-000000000001'),0::bigint,'researcher cannot read marked legacy events in base table');
SELECT is((SELECT count(*) FROM public.research_bancada_sessions WHERE session_id = 'a2000000-0000-4000-8000-000000000002'),1::bigint,'researcher still reads authorized session in base table');
SELECT is((SELECT count(*) FROM public.research_events WHERE session_id = 'a2000000-0000-4000-8000-000000000002'),1::bigint,'researcher still reads authorized legacy events');
RESET ROLE;
-- A máquina dona continua lendo a própria aula marcada (reenvio com ON CONFLICT)
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
SELECT is((SELECT count(*) FROM public.research_bancada_sessions WHERE session_id = 'a1000000-0000-4000-8000-000000000001'),1::bigint,'owning machine still reads its marked session');
RESET ROLE;

-- Restauração exige motivo e devolve a aula às views
SET LOCAL ROLE service_role;
SELECT throws_ok($q$SELECT public.review_restore_research_session('a3000000-0000-4000-8000-000000000003',' ')$q$,'22023',NULL,'restore requires a reason');
SELECT throws_ok($q$SELECT public.review_restore_research_session('a2000000-0000-4000-8000-000000000002','motivo')$q$,'22023',NULL,'restore of unmarked session fails');
SELECT is((public.review_restore_research_session('a3000000-0000-4000-8000-000000000003','marcada no computador errado')->>'restored')::boolean,true,'restore with reason');
SELECT is((SELECT status || '|' || restore_reason FROM public.research_unauthorized_sessions WHERE session_id='a3000000-0000-4000-8000-000000000003'),'autorizada|marcada no computador errado','restore reason recorded');
SELECT is((SELECT count(*) FROM public.research_session_quality WHERE session_id='a3000000-0000-4000-8000-000000000003'),1::bigint,'restored session back in views');
INSERT INTO public.research_bancada_sessions(session_id,site_id,installation_id,phase,session_payload,created_at,updated_at)
VALUES('a3000000-0000-4000-8000-000000000003','SITE_A','10000000-0000-4000-8000-000000000001','completed','{"authorization_status":"nao_autorizada"}'::jsonb,now(),now())
ON CONFLICT (session_id) DO NOTHING;
SELECT is((SELECT status FROM public.research_unauthorized_sessions WHERE session_id='a3000000-0000-4000-8000-000000000003'),'autorizada','late resend does not undo a restore');

-- Apagar na revisão: tombstone e remoção
SELECT throws_ok($q$SELECT public.review_purge_research_session('a2000000-0000-4000-8000-000000000002')$q$,'22023',NULL,'review never purges an unmarked session');
SELECT is((public.review_purge_research_session('a1000000-0000-4000-8000-000000000001')->>'snapshots')::int,1,'review purge deletes the snapshot');
SELECT is((SELECT source FROM public.research_withdrawals WHERE session_id='a1000000-0000-4000-8000-000000000001'),'revisao_pesquisador','review purge records tombstone');
SELECT is((SELECT count(*) FROM public.research_session_events WHERE session_id='a1000000-0000-4000-8000-000000000001'),0::bigint,'review purge deletes timeline');
SELECT is((SELECT count(*) FROM public.research_unauthorized_sessions WHERE session_id='a1000000-0000-4000-8000-000000000001'),0::bigint,'review purge removes the mark');
SELECT is((public.review_purge_research_session('a1000000-0000-4000-8000-000000000001')->>'already_absent')::boolean,true,'second purge is idempotent');
RESET ROLE;

-- Reenvio de aula apagada é barrado (bridge e pendrive)
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
SELECT lives_ok($q$INSERT INTO public.research_session_events(event_id,session_id,installation_id,site_id,school_code,workshop_code,class_code,activity_id,client_version,event_type,occurred_at)
VALUES(gen_random_uuid(),'a1000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','SITE_A','E','O','T','ACT','3.0.9','heartbeat',now())$q$,'late event resend does not error');
SELECT lives_ok($q$INSERT INTO public.research_bancada_sessions(session_id,site_id,installation_id,phase,session_payload,created_at,updated_at)
VALUES('a1000000-0000-4000-8000-000000000001','SITE_A','10000000-0000-4000-8000-000000000001','completed','{"authorization_status":"nao_autorizada"}'::jsonb,now(),now())
ON CONFLICT (session_id) DO NOTHING$q$,'late snapshot resend does not error');
RESET ROLE;
SET LOCAL ROLE service_role;
INSERT INTO public.research_bancada_sessions(session_id,site_id,installation_id,phase,session_payload,created_at,updated_at)
VALUES('a1000000-0000-4000-8000-000000000001','SITE_A','10000000-0000-4000-8000-000000000001','completed','{"authorization_status":"nao_autorizada"}'::jsonb,now(),now())
ON CONFLICT (session_id) DO UPDATE SET session_payload = excluded.session_payload;
INSERT INTO public.research_unauthorized_sessions(session_id) VALUES ('a1000000-0000-4000-8000-000000000001') ON CONFLICT DO NOTHING;
RESET ROLE;
SELECT is((SELECT count(*) FROM public.research_session_events WHERE session_id='a1000000-0000-4000-8000-000000000001'),0::bigint,'late event of purged session dropped');
SELECT is((SELECT count(*) FROM public.research_bancada_sessions WHERE session_id='a1000000-0000-4000-8000-000000000001'),0::bigint,'late snapshot of purged session dropped (device and importer)');
SELECT is((SELECT count(*) FROM public.research_unauthorized_sessions WHERE session_id='a1000000-0000-4000-8000-000000000001'),0::bigint,'late mark of purged session dropped');
SELECT * FROM finish();
ROLLBACK;
