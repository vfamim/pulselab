BEGIN;
SELECT no_plan();
INSERT INTO public.device_installations(device_user_id, installation_id, site_id) VALUES
('00000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','SITE_A'),
('00000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','SITE_B');
INSERT INTO public.research_site_memberships(user_id, site_id) VALUES
('00000000-0000-4000-8000-000000000003','SITE_A');

-- Tombstone descarta em silêncio inserts nas três tabelas
INSERT INTO public.research_withdrawals(session_id, source) VALUES ('40000000-0000-4000-8000-000000000001','test');
SELECT ok(NOT has_table_privilege('anon','public.research_withdrawals','SELECT'),'anon cannot read tombstones');
SELECT ok(NOT has_table_privilege('authenticated','public.research_withdrawals','SELECT'),'authenticated cannot read tombstones');
SELECT ok(NOT has_table_privilege('authenticated','public.research_withdrawals','INSERT'),'authenticated cannot write tombstones directly');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
SELECT lives_ok($q$INSERT INTO public.research_events(event_id,session_id,dyad_id,installation_id,site_id,participant_id,participant_role,event_type,regional_hub,school_code,workshop_code,class_code,activity_id,computer_id,config_version,client_version,occurred_at)
VALUES(gen_random_uuid(),'40000000-0000-4000-8000-000000000001',gen_random_uuid(),'10000000-0000-4000-8000-000000000001','SITE_A','A','group','pre','R','E','O','T','ACT','PC','2.4.0','2.4.0',now())$q$,'withdrawn response insert does not error');
SELECT lives_ok($q$INSERT INTO public.research_session_events(event_id,session_id,installation_id,site_id,school_code,workshop_code,class_code,activity_id,client_version,event_type,occurred_at)
VALUES(gen_random_uuid(),'40000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','SITE_A','E','O','T','ACT','2.4.0','heartbeat',now()) ON CONFLICT DO NOTHING$q$,'withdrawn timeline insert does not error');
SELECT lives_ok($q$INSERT INTO public.research_bancada_sessions(session_id,site_id,installation_id,phase,session_payload,created_at,updated_at)
VALUES('40000000-0000-4000-8000-000000000001','SITE_A','10000000-0000-4000-8000-000000000001','completed','{}'::jsonb,now(),now()) ON CONFLICT (session_id) DO NOTHING$q$,'withdrawn snapshot insert does not error');
RESET ROLE;
SELECT is((SELECT count(*) FROM public.research_events WHERE session_id='40000000-0000-4000-8000-000000000001'),0::bigint,'tombstone drops research_events insert');
SELECT is((SELECT count(*) FROM public.research_session_events WHERE session_id='40000000-0000-4000-8000-000000000001'),0::bigint,'tombstone drops research_session_events insert');
SELECT is((SELECT count(*) FROM public.research_bancada_sessions WHERE session_id='40000000-0000-4000-8000-000000000001'),0::bigint,'tombstone drops research_bancada_sessions insert');

SET LOCAL ROLE service_role;
INSERT INTO public.research_bancada_sessions(session_id,site_id,installation_id,phase,session_payload,created_at,updated_at)
VALUES('40000000-0000-4000-8000-000000000001','SITE_A','10000000-0000-4000-8000-000000000001','completed','{}'::jsonb,now(),now())
ON CONFLICT (session_id) DO UPDATE SET phase = excluded.phase;
RESET ROLE;
SELECT is((SELECT count(*) FROM public.research_bancada_sessions WHERE session_id='40000000-0000-4000-8000-000000000001'),0::bigint,'tombstone also drops importer (service_role) upsert');

-- Retirada pelo dispositivo cria tombstone e bloqueia reenvio
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
INSERT INTO public.research_bancada_sessions(session_id,site_id,installation_id,phase,session_payload,created_at,updated_at)
VALUES('50000000-0000-4000-8000-000000000001','SITE_A','10000000-0000-4000-8000-000000000001','completed','{}'::jsonb,now(),now());
SELECT is((public.purge_own_research_session('50000000-0000-4000-8000-000000000001'::uuid)->>'snapshots')::int,1,'device purges its own snapshot');
SELECT is((public.purge_own_research_session('50000000-0000-4000-8000-000000000002'::uuid)->>'already_absent')::boolean,true,'purge of a session never uploaded is idempotent');
SELECT lives_ok($q$INSERT INTO public.research_bancada_sessions(session_id,site_id,installation_id,phase,session_payload,created_at,updated_at)
VALUES('50000000-0000-4000-8000-000000000001','SITE_A','10000000-0000-4000-8000-000000000001','completed','{}'::jsonb,now(),now())$q$,'late resend after purge does not error');
RESET ROLE;
SELECT is((SELECT source FROM public.research_withdrawals WHERE session_id='50000000-0000-4000-8000-000000000001'),'device','purge creates tombstone');
SELECT is((SELECT count(*) FROM public.research_withdrawals WHERE session_id='50000000-0000-4000-8000-000000000002'),1::bigint,'purge of session absent from cloud still creates tombstone (pendrive may arrive later)');
SELECT is((SELECT count(*) FROM public.research_bancada_sessions WHERE session_id='50000000-0000-4000-8000-000000000001'),0::bigint,'late resend after purge is dropped');

-- Dispositivo não cria tombstone para sessão de outra instalação
INSERT INTO public.research_bancada_sessions(session_id,site_id,installation_id,phase,session_payload,created_at,updated_at)
VALUES('50000000-0000-4000-8000-000000000003','SITE_B','10000000-0000-4000-8000-000000000002','completed','{}'::jsonb,now(),now());
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
SELECT is((public.purge_own_research_session('50000000-0000-4000-8000-000000000003'::uuid)->>'already_absent')::boolean,true,'foreign session is not purged');
RESET ROLE;
SELECT is((SELECT count(*) FROM public.research_withdrawals WHERE session_id='50000000-0000-4000-8000-000000000003'),0::bigint,'foreign session gets no tombstone');
SELECT is((SELECT count(*) FROM public.research_bancada_sessions WHERE session_id='50000000-0000-4000-8000-000000000003'),1::bigint,'foreign session snapshot preserved');

-- Sessão encerrada nunca regride para em andamento
SET LOCAL ROLE service_role;
INSERT INTO public.research_bancada_sessions(session_id,site_id,installation_id,phase,ended_by,session_payload,created_at,updated_at)
VALUES('60000000-0000-4000-8000-000000000001','SITE_A','10000000-0000-4000-8000-000000000001','completed','instrutor','{"v":"final"}'::jsonb,now(),now());
INSERT INTO public.research_bancada_sessions(session_id,site_id,installation_id,phase,session_payload,created_at,updated_at)
VALUES('60000000-0000-4000-8000-000000000001','SITE_A','10000000-0000-4000-8000-000000000001','in_progress','{"v":"stale"}'::jsonb,now(),now())
ON CONFLICT (session_id) DO UPDATE SET phase = excluded.phase, session_payload = excluded.session_payload, ended_by = excluded.ended_by;
SELECT is((SELECT phase || '|' || (session_payload->>'v') || '|' || ended_by FROM public.research_bancada_sessions WHERE session_id='60000000-0000-4000-8000-000000000001'),'completed|final|instrutor','upsert cannot regress completed snapshot');
UPDATE public.research_bancada_sessions SET phase = NULL WHERE session_id='60000000-0000-4000-8000-000000000001';
SELECT is((SELECT phase FROM public.research_bancada_sessions WHERE session_id='60000000-0000-4000-8000-000000000001'),'completed','update cannot clear completed phase');
UPDATE public.research_bancada_sessions SET data_quality = '{"bridge_restarts": 2}'::jsonb WHERE session_id='60000000-0000-4000-8000-000000000001';
SELECT is((SELECT (data_quality->>'bridge_restarts')::int FROM public.research_bancada_sessions WHERE session_id='60000000-0000-4000-8000-000000000001'),2,'completed snapshot still accepts updates that keep it completed');
INSERT INTO public.research_bancada_sessions(session_id,site_id,installation_id,phase,session_payload,created_at,updated_at)
VALUES('60000000-0000-4000-8000-000000000002','SITE_A','10000000-0000-4000-8000-000000000001','in_progress','{}'::jsonb,now(),now());
UPDATE public.research_bancada_sessions SET phase = 'completed' WHERE session_id='60000000-0000-4000-8000-000000000002';
SELECT is((SELECT phase FROM public.research_bancada_sessions WHERE session_id='60000000-0000-4000-8000-000000000002'),'completed','in_progress snapshot can be completed');
RESET ROLE;

-- Papel do instrutor e novas colunas sob RLS do dispositivo
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
SELECT lives_ok($q$INSERT INTO public.research_session_events(event_id,session_id,installation_id,site_id,school_code,workshop_code,class_code,activity_id,client_version,event_type,participant_role,occurred_at)
VALUES(gen_random_uuid(),'70000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','SITE_A','E','O','T','ACT','2.4.0','rubric_completed','instructor',now())$q$,'instructor participant_role accepted on rubric_completed');
SELECT throws_ok($q$INSERT INTO public.research_session_events(event_id,session_id,installation_id,site_id,school_code,workshop_code,class_code,activity_id,client_version,event_type,participant_role,occurred_at)
VALUES(gen_random_uuid(),'70000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','SITE_A','E','O','T','ACT','2.4.0','rubric_completed','teacher',now())$q$,'23514',NULL,'unknown participant_role still rejected');
SELECT lives_ok($q$INSERT INTO public.research_bancada_sessions(session_id,site_id,installation_id,phase,ended_by,interrupted,data_quality,session_payload,created_at,updated_at)
VALUES('70000000-0000-4000-8000-000000000001','SITE_A','10000000-0000-4000-8000-000000000001','completed','tempo',true,
'{"heartbeat_count":12,"max_heartbeat_gap_min":3.5,"bridge_restarts":1,"corrupted_lines":0,"spike_status":"ok","telemetry_events":40,"last_activity_at":"2026-10-14T12:00:00Z"}'::jsonb,
'{}'::jsonb,now(),now())$q$,'enrolled device writes ended_by, interrupted and data_quality');
SELECT throws_ok($q$INSERT INTO public.research_bancada_sessions(session_id,site_id,installation_id,ended_by,session_payload,created_at,updated_at)
VALUES(gen_random_uuid(),'SITE_A','10000000-0000-4000-8000-000000000001','aluno','{}'::jsonb,now(),now())$q$,'23514',NULL,'unknown ended_by rejected');
SELECT throws_ok($q$INSERT INTO public.research_bancada_sessions(session_id,site_id,installation_id,data_quality,session_payload,created_at,updated_at)
VALUES(gen_random_uuid(),'SITE_A','10000000-0000-4000-8000-000000000001','[1]'::jsonb,'{}'::jsonb,now(),now())$q$,'23514',NULL,'data_quality must be an object');
SELECT throws_ok($q$INSERT INTO public.research_bancada_sessions(session_id,site_id,installation_id,ended_by,session_payload,created_at,updated_at)
VALUES(gen_random_uuid(),'SITE_B','10000000-0000-4000-8000-000000000002','tempo','{}'::jsonb,now(),now())$q$,'42501',NULL,'new columns do not relax installation binding');
RESET ROLE;
SELECT is((SELECT ended_by || '|' || interrupted::text || '|' || (data_quality->>'spike_status') FROM public.research_bancada_sessions WHERE session_id='70000000-0000-4000-8000-000000000001'),'tempo|true|ok','new columns persisted');

-- Último envio por máquina
SELECT ok(NOT has_table_privilege('anon','public.research_installation_last_seen','SELECT'),'anon cannot read last-seen view');
SELECT ok(has_table_privilege('authenticated','public.research_installation_last_seen','SELECT'),'authenticated can read last-seen view under RLS');
SET LOCAL ROLE service_role;
SELECT is((SELECT count(*) FROM public.research_installation_last_seen),2::bigint,'service_role sees every enrolled machine');
SELECT is((SELECT interrupted_sessions_last_30d FROM public.research_installation_last_seen WHERE installation_id='10000000-0000-4000-8000-000000000001'),1::bigint,'interrupted sessions counted');
SELECT is((SELECT sessions_last_30d FROM public.research_installation_last_seen WHERE installation_id='10000000-0000-4000-8000-000000000001'),3::bigint,'sessions counted once across tables');
SELECT is((SELECT days_since_last_received FROM public.research_installation_last_seen WHERE installation_id='10000000-0000-4000-8000-000000000001'),0,'fresh data is zero days old');
RESET ROLE;
UPDATE public.research_bancada_sessions SET received_at = now() - interval '45 days' WHERE site_id = 'SITE_B';
SET LOCAL ROLE service_role;
SELECT is((SELECT days_since_last_received FROM public.research_installation_last_seen WHERE installation_id='10000000-0000-4000-8000-000000000002'),45,'silent machine shows days since last data');
SELECT is((SELECT sessions_last_30d FROM public.research_installation_last_seen WHERE installation_id='10000000-0000-4000-8000-000000000002'),0::bigint,'old sessions fall out of the 30-day window');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
SELECT is((SELECT array_agg(DISTINCT site_id) FROM public.research_installation_last_seen),ARRAY['SITE_A'],'researcher sees only assigned site machines');
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000099","role":"authenticated"}',true);
SELECT is((SELECT count(*) FROM public.research_installation_last_seen),0::bigint,'unaffiliated user sees no machines');
RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
