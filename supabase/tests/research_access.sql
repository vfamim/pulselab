BEGIN;
SELECT no_plan();
INSERT INTO public.device_installations(device_user_id, installation_id, site_id) VALUES
('00000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','SITE_A'),
('00000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','SITE_B');
INSERT INTO public.research_site_memberships(user_id, site_id) VALUES
('00000000-0000-4000-8000-000000000003','SITE_A');
INSERT INTO public.research_events(event_id,session_id,dyad_id,installation_id,site_id,participant_id,participant_role,event_type,regional_hub,school_code,workshop_code,class_code,activity_id,computer_id,config_version,client_version,occurred_at)
SELECT gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),installation_id,site_id,'A','computer','pre','R','E','O','T','ACT','PC','legacy','legacy',now() FROM public.device_installations;

SELECT ok(NOT has_table_privilege('anon','public.research_events','INSERT'),'anonymous response ingestion revoked');
SELECT ok(NOT has_table_privilege('anon','public.research_session_events','INSERT'),'anonymous timeline ingestion revoked');
SELECT ok(NOT has_table_privilege('anon','public.research_events','SELECT'),'anonymous reads revoked');
SELECT ok(NOT has_function_privilege('authenticated','public.purge_expired_research_records()','EXECUTE'),'authenticated cannot purge');
SELECT ok(NOT has_function_privilege('anon','public.purge_expired_research_records()','EXECUTE'),'anon cannot purge');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000099","role":"authenticated"}',true);
SELECT is((SELECT count(*) FROM public.research_events),0::bigint,'unaffiliated user sees no responses');
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
SELECT is((SELECT count(*) FROM public.research_events),1::bigint,'device sees only own installation and site');
SELECT lives_ok($q$INSERT INTO public.research_events(event_id,session_id,dyad_id,installation_id,site_id,participant_id,participant_role,event_type,regional_hub,school_code,workshop_code,class_code,activity_id,computer_id,config_version,client_version,occurred_at)
VALUES(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),'10000000-0000-4000-8000-000000000001','SITE_A','A','computer','pre','R','E','O','T','ACT','PC','legacy','legacy',now())$q$,'registered device can insert its own event');
SELECT throws_ok($q$INSERT INTO public.research_events(event_id,session_id,dyad_id,installation_id,site_id,participant_id,participant_role,event_type,regional_hub,school_code,workshop_code,class_code,activity_id,computer_id,config_version,client_version,occurred_at)
VALUES(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),'10000000-0000-4000-8000-000000000002','SITE_B','A','computer','pre','R','E','O','T','ACT','PC','legacy','legacy',now())$q$,'42501',NULL,'device cannot forge another installation');
SELECT throws_ok($q$INSERT INTO public.research_site_memberships(user_id,site_id) VALUES('00000000-0000-4000-8000-000000000001','SITE_B')$q$,'42501',NULL,'client cannot assign its own site membership');
SELECT throws_ok($q$INSERT INTO storage.objects(bucket_id,name) VALUES('screenshots','10000000-0000-4000-8000-000000000001/test.jpg')$q$,'42501',NULL,'screenshot upload disabled');
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
SELECT is((SELECT count(*) FROM public.research_events),2::bigint,'researcher sees assigned site only');
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
SELECT is(public.purge_expired_research_records(),2::bigint,'purge applies only approved site and server receipt age');
SELECT is((SELECT count(*) FROM public.research_events WHERE site_id='SITE_B'),1::bigint,'other site data retained');
RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
