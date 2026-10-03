BEGIN;
SELECT no_plan();
INSERT INTO public.device_installations(device_user_id, installation_id, site_id) VALUES
('00000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','SITE_A'),
('00000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','SITE_B'),
('00000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000004','SITE_A');
INSERT INTO public.research_site_memberships(user_id, site_id) VALUES
('00000000-0000-4000-8000-000000000003','SITE_A');
INSERT INTO public.research_events(event_id,session_id,dyad_id,installation_id,site_id,participant_id,participant_role,event_type,regional_hub,school_code,workshop_code,class_code,activity_id,computer_id,config_version,client_version,occurred_at)
SELECT gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),installation_id,site_id,'A','computer','pre','R','E','O','T','ACT','PC','legacy','legacy',now() FROM public.device_installations;
INSERT INTO public.research_bancada_sessions(session_id, site_id, session_payload, created_at, updated_at) VALUES
('20000000-0000-4000-8000-000000000001', 'SITE_A', '{"test": 1}'::jsonb, now(), now()),
('20000000-0000-4000-8000-000000000002', 'SITE_B', '{"test": 2}'::jsonb, now(), now());

SELECT ok(NOT has_table_privilege('anon','public.research_events','INSERT'),'anonymous response ingestion revoked');
SELECT ok(NOT has_table_privilege('anon','public.research_session_events','INSERT'),'anonymous timeline ingestion revoked');
SELECT ok(NOT has_table_privilege('anon','public.research_events','SELECT'),'anonymous reads revoked');
SELECT ok(NOT has_table_privilege('anon','public.research_bancada_sessions','SELECT'),'anonymous bancada sessions read revoked');
SELECT ok(NOT has_table_privilege('anon','public.research_bancada_sessions','UPDATE'),'anonymous bancada sessions update revoked');
SELECT ok(NOT has_table_privilege('anon','public.research_bancada_sessions','INSERT'),'anonymous bancada sessions insert revoked');
SELECT ok(NOT has_table_privilege('authenticated','public.research_bancada_sessions','UPDATE'),'authenticated bancada sessions update revoked (append-only)');
SELECT ok(NOT has_table_privilege('authenticated','public.research_bancada_sessions','DELETE'),'authenticated bancada sessions delete revoked');
SELECT ok(NOT has_function_privilege('authenticated','public.purge_expired_research_records()','EXECUTE'),'authenticated cannot purge');
SELECT ok(NOT has_function_privilege('anon','public.purge_expired_research_records()','EXECUTE'),'anon cannot purge');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000099","role":"authenticated"}',true);
SELECT is((SELECT count(*) FROM public.research_events),0::bigint,'unaffiliated user sees no responses');
SELECT is((SELECT count(*) FROM public.research_bancada_sessions),0::bigint,'unaffiliated user sees no bancada sessions');
SELECT throws_ok($q$INSERT INTO public.research_bancada_sessions(session_id, site_id, session_payload, created_at, updated_at) VALUES (gen_random_uuid(), 'SITE_A', '{}'::jsonb, now(), now())$q$, '42501', NULL, 'unaffiliated user cannot insert bancada session');

SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
SELECT is((SELECT count(*) FROM public.research_events),1::bigint,'device sees only own installation and site');
SELECT is((SELECT count(*) FROM public.research_bancada_sessions),0::bigint,'bench device cannot read bancada session snapshots');
SELECT lives_ok($q$INSERT INTO public.research_events(event_id,session_id,dyad_id,installation_id,site_id,participant_id,participant_role,event_type,regional_hub,school_code,workshop_code,class_code,activity_id,computer_id,config_version,client_version,occurred_at)
VALUES(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),'10000000-0000-4000-8000-000000000001','SITE_A','A','computer','pre','R','E','O','T','ACT','PC','legacy','legacy',now())$q$,'registered device can insert its own event');
SELECT throws_ok($q$INSERT INTO public.research_events(event_id,session_id,dyad_id,installation_id,site_id,participant_id,participant_role,event_type,regional_hub,school_code,workshop_code,class_code,activity_id,computer_id,config_version,client_version,occurred_at)
VALUES(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),'10000000-0000-4000-8000-000000000002','SITE_B','A','computer','pre','R','E','O','T','ACT','PC','legacy','legacy',now())$q$,'42501',NULL,'device cannot forge another installation');

-- Snapshots RLS: device insert, null installation_id, peer installation, cross-site, and append-only check
SELECT lives_ok($q$INSERT INTO public.research_bancada_sessions(session_id, site_id, installation_id, session_payload, created_at, updated_at) VALUES ('30000000-0000-4000-8000-000000000001', 'SITE_A', '10000000-0000-4000-8000-000000000001', '{"data": "ok"}'::jsonb, now(), now())$q$, 'registered device can insert snapshot for its site and installation');
SELECT throws_ok($q$INSERT INTO public.research_bancada_sessions(session_id, site_id, installation_id, session_payload, created_at, updated_at) VALUES (gen_random_uuid(), 'SITE_A', NULL, '{"data": "null_installation"}'::jsonb, now(), now())$q$, '42501', NULL, 'bancada session insert with NULL installation_id rejected');
SELECT throws_ok($q$INSERT INTO public.research_bancada_sessions(session_id, site_id, installation_id, session_payload, created_at, updated_at) VALUES (gen_random_uuid(), 'SITE_A', '10000000-0000-4000-8000-000000000004', '{"data": "peer_installation"}'::jsonb, now(), now())$q$, '42501', NULL, 'device cannot forge peer installation in same site');
SELECT throws_ok($q$INSERT INTO public.research_bancada_sessions(session_id, site_id, installation_id, session_payload, created_at, updated_at) VALUES (gen_random_uuid(), 'SITE_B', '10000000-0000-4000-8000-000000000002', '{"data": "cross_site_installation"}'::jsonb, now(), now())$q$, '42501', NULL, 'device cannot insert snapshot for another site or installation');
SELECT throws_ok($q$INSERT INTO public.research_bancada_sessions(session_id, site_id, installation_id, session_payload, created_at, updated_at) VALUES (gen_random_uuid(), NULL, '10000000-0000-4000-8000-000000000001', '{"data": "null_site"}'::jsonb, now(), now())$q$, '42501', NULL, 'bancada session insert with NULL site_id rejected');
SELECT throws_ok($q$INSERT INTO public.research_bancada_sessions(session_id, site_id, installation_id, session_payload, created_at, updated_at) VALUES (gen_random_uuid(), 'SITE_B', '10000000-0000-4000-8000-000000000001', '{"data": "forged"}'::jsonb, now(), now())$q$, '42501', NULL, 'device cannot insert snapshot for another site');

-- Dispositivo de bancada NÃO pode atualizar snapshot (append-only)
SELECT throws_ok($q$UPDATE public.research_bancada_sessions SET session_payload = '{"data": "updated"}'::jsonb WHERE session_id = '30000000-0000-4000-8000-000000000001'$q$, '42501', NULL, 'bench device cannot update snapshots (append-only)');

-- Outro dispositivo na mesma sede (Device 4) tenta alterar sessão do Device 1 -> bloqueado
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000004","role":"authenticated"}',true);
SELECT throws_ok($q$UPDATE public.research_bancada_sessions SET session_payload = '{"data": "tampered_by_peer"}'::jsonb WHERE session_id = '30000000-0000-4000-8000-000000000001'$q$, '42501', NULL, 'peer device in same site cannot update another device snapshot');

SELECT throws_ok($q$UPDATE public.research_bancada_sessions SET session_payload = '{"hacked": true}'::jsonb WHERE session_id = '20000000-0000-4000-8000-000000000002'$q$, '42501', NULL, 'device cannot update cross-site snapshot');

SELECT throws_ok($q$INSERT INTO public.research_site_memberships(user_id,site_id) VALUES('00000000-0000-4000-8000-000000000001','SITE_B')$q$,'42501',NULL,'client cannot assign its own site membership');
SELECT throws_ok($q$INSERT INTO storage.objects(bucket_id,name) VALUES('screenshots','10000000-0000-4000-8000-000000000001/test.jpg')$q$,'42501',NULL,'screenshot upload disabled');
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
SELECT is((SELECT count(*) FROM public.research_events),3::bigint,'researcher sees assigned site only');
SELECT is((SELECT count(*) FROM public.research_bancada_sessions),2::bigint,'researcher sees bancada sessions of assigned site only');
SELECT is((SELECT count(*) FROM public.research_bancada_sessions WHERE site_id = 'SITE_B'),0::bigint,'researcher cannot see SITE_B snapshots');
SELECT is((SELECT count(*) FROM public.research_bancada_sessions WHERE session_payload->>'hacked' = 'true'),0::bigint,'device cannot update another site snapshot');
RESET ROLE;
UPDATE public.research_site_memberships SET is_active=false;
SET LOCAL ROLE authenticated;
SELECT is((SELECT count(*) FROM public.research_events),0::bigint,'revocation removes researcher access');
RESET ROLE;
UPDATE public.device_installations SET is_active=false WHERE site_id='SITE_A';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
SELECT is((SELECT count(*) FROM public.research_events),0::bigint,'disabled device cannot read');
RESET ROLE;
SELECT is(public.purge_expired_research_records(),0::bigint,'no retention policy means no deletion');
INSERT INTO public.research_retention_policies VALUES('SITE_A',7,'TEST-APPROVAL');
UPDATE public.research_events SET received_at=now()-interval '10 days';
SET LOCAL ROLE service_role;
SELECT is(public.purge_expired_research_records(),3::bigint,'purge applies only approved site and server receipt age');
SELECT is((SELECT count(*) FROM public.research_events WHERE site_id='SITE_B'),1::bigint,'other site data retained');
SELECT lives_ok($q$INSERT INTO public.research_bancada_sessions(session_id, site_id, installation_id, session_payload, created_at, updated_at) VALUES (gen_random_uuid(), 'SITE_A', NULL, '{"data": "service_role_import"}'::jsonb, now(), now())$q$, 'service_role can insert session snapshots without restriction');
RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
