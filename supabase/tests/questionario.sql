BEGIN;
SELECT no_plan();
INSERT INTO public.device_installations(device_user_id, installation_id, site_id) VALUES
('00000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','SITE_A'),
('00000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','SITE_B');
INSERT INTO public.research_site_memberships(user_id, site_id) VALUES
('00000000-0000-4000-8000-000000000003','SITE_A');

-- O dispositivo envia as respostas como o bridge grava (um evento por pergunta)
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
SELECT lives_ok($q$INSERT INTO public.research_session_events(event_id,session_id,installation_id,site_id,school_code,workshop_code,class_code,activity_id,computer_id,client_version,config_version,event_type,participant_id,participant_role,activity_stage,elapsed_ms,occurred_at,details) VALUES
('e1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','SITE_A','E','O','T','ACT','PET-LAB1-PC03','bridge/3.2.0','bancada-3.2.0','bancada_result_recorded','BANCADA','group','questionario_fim_aula',3000000,'2026-10-06T12:00:00Z',
 '{"item_id":"bancada_linha_v1","value":"em_parte","refused":false,"instrument_version":"bancada-3.2.0","submission_id":"f1000000-0000-4000-8000-000000000001","item_order":1,"session_active":true,"minutes_since_session_start":50}'),
('e1000000-0000-4000-8000-000000000002','c1000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','SITE_A','E','O','T','ACT','PET-LAB1-PC03','bridge/3.2.0','bancada-3.2.0','student_feedback_recorded',NULL,'individual','questionario_fim_aula',3060000,'2026-10-06T12:01:00Z',
 '{"item_id":"crianca_confianca_antes_v1","value":"nao","refused":false,"instrument_version":"bancada-3.2.0","submission_id":"f2000000-0000-4000-8000-000000000002","item_order":3,"session_active":false,"minutes_since_session_start":51}'),
('e1000000-0000-4000-8000-000000000003','c1000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','SITE_A','E','O','T','ACT','PET-LAB1-PC03','bridge/3.2.0','bancada-3.2.0','student_feedback_recorded',NULL,'individual','questionario_fim_aula',3060000,'2026-10-06T12:01:00Z',
 '{"item_id":"crianca_ajudou_v1","value":"recusou","refused":true,"instrument_version":"bancada-3.2.0","submission_id":"f2000000-0000-4000-8000-000000000002","item_order":5}'),
('e1000000-0000-4000-8000-000000000004','c2000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001','SITE_A','E','O','T','ACT','PET-LAB1-PC03','bridge/3.2.0','bancada-3.2.0','student_feedback_recorded',NULL,'individual','questionario_fim_aula',60000,'2026-10-07T12:00:00Z',
 '{"item_id":"crianca_gostou_v1","value":"sim","refused":false,"instrument_version":"bancada-3.2.0","submission_id":"f3000000-0000-4000-8000-000000000003","item_order":1}')
$q$,'device inserts questionnaire answers as session events');
SELECT throws_ok($q$INSERT INTO public.research_session_events(event_id,session_id,installation_id,site_id,school_code,workshop_code,class_code,activity_id,client_version,event_type,occurred_at)
VALUES(gen_random_uuid(),'c1000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','SITE_A','E','O','T','ACT','bridge/3.2.0','student_name_recorded',now())$q$,
'23514',NULL,'unknown event type is still rejected');
RESET ROLE;

-- Dispositivo B, outro polo
INSERT INTO public.research_session_events(event_id,session_id,installation_id,site_id,school_code,workshop_code,class_code,activity_id,client_version,event_type,occurred_at,details) VALUES
('e2000000-0000-4000-8000-000000000001','c3000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000002','SITE_B','E','O','T','ACT','bridge/3.2.0','student_feedback_recorded','2026-10-08T12:00:00Z',
 '{"item_id":"crianca_gostou_v1","value":"nao","refused":"x","submission_id":"f4000000-0000-4000-8000-000000000004","minutes_since_session_start":"muito"}');

-- A aula c2 foi marcada como não autorizada: nunca entra
INSERT INTO public.research_unauthorized_sessions(session_id, installation_id, site_id, status, marked_at)
VALUES('c2000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001','SITE_A','nao_autorizada','2026-10-07T13:00:00Z');

SELECT has_view('public','research_questionario_respostas','view research_questionario_respostas exists');
SELECT ok(NOT has_table_privilege('anon','public.research_questionario_respostas','SELECT'),'anon cannot read questionnaire view');
SELECT ok((SELECT 'security_invoker=true' = ANY(c.reloptions) FROM pg_class c WHERE c.oid = 'public.research_questionario_respostas'::regclass),'questionnaire view runs with security_invoker');

SET LOCAL ROLE service_role;
SELECT is((SELECT count(*) FROM public.research_questionario_respostas),4::bigint,'one row per answer, unauthorized lesson left out');
SELECT is((SELECT count(*) FROM public.research_questionario_respostas WHERE session_id='c2000000-0000-4000-8000-000000000002'),0::bigint,'unauthorized lesson never appears');
SELECT is((SELECT concat_ws('|',polo,maquina,parte,item_id,valor,recusou,envio_id,instrument_version,data_local,minutos_desde_inicio,aula_em_andamento,ambiente)
             FROM public.research_questionario_respostas WHERE event_id='e1000000-0000-4000-8000-000000000001'),
          'SITE_A|PET-LAB1-PC03|bancada|bancada_linha_v1|em_parte|f|f1000000-0000-4000-8000-000000000001|bancada-3.2.0|2026-10-06|50|t|production',
          'bancada answer flattened');
SELECT is((SELECT concat_ws('|',parte,valor,recusou,minutos_desde_inicio,coalesce(aula_em_andamento::text,'-'))
             FROM public.research_questionario_respostas WHERE event_id='e1000000-0000-4000-8000-000000000003'),
          'crianca|recusou|t|51.0|-',
          'refusal and fallback to elapsed_ms');
SELECT is((SELECT concat_ws('|',polo,recusou,coalesce(minutos_desde_inicio::text,'-'),instrument_version IS NULL)
             FROM public.research_questionario_respostas WHERE event_id='e2000000-0000-4000-8000-000000000001'),
          'SITE_B|f|-|t',
          'unexpected types become NULL or fall back without error');
RESET ROLE;

-- Respostas individuais: linha a linha, só service_role
SELECT ok(NOT has_table_privilege('authenticated','public.research_questionario_respostas','SELECT'),'authenticated cannot read questionnaire view');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
SELECT throws_ok($q$SELECT count(*) FROM public.research_questionario_respostas$q$,'42501',NULL,'site member query on answers view is denied');
SELECT is((SELECT count(*) FROM public.research_session_events WHERE event_type = 'student_feedback_recorded'),0::bigint,'site member cannot read child answers in base table');
SELECT is((SELECT count(*) FROM public.research_session_events WHERE event_type = 'bancada_result_recorded'),1::bigint,'site member still reads collective bancada answers');
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
SELECT is((SELECT count(*) FROM public.research_session_events WHERE event_type = 'student_feedback_recorded'),3::bigint,'owning machine still reads its own events');
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000099","role":"authenticated"}',true);
SELECT is((SELECT count(*) FROM public.research_session_events),0::bigint,'unaffiliated user sees no events');
RESET ROLE;

-- Snapshot: respostas das crianças nunca ficam na timeline (inserção e atualização)
INSERT INTO public.research_bancada_sessions(session_id,site_id,installation_id,phase,session_payload,created_at,updated_at) VALUES
('c4000000-0000-4000-8000-000000000004','SITE_A','10000000-0000-4000-8000-000000000001','in_progress',
 '{"timeline":[{"event_type":"session_started"},{"event_type":"student_feedback_recorded","details":{"value":"nao"}},{"event_type":"bancada_result_recorded"}]}'::jsonb,now(),now());
SELECT is((SELECT jsonb_path_query_array(session_payload,'$.timeline[*].event_type') FROM public.research_bancada_sessions WHERE session_id='c4000000-0000-4000-8000-000000000004'),
          '["session_started","bancada_result_recorded"]'::jsonb,'child answers stripped from snapshot on insert, order kept');
UPDATE public.research_bancada_sessions SET phase='completed',
       session_payload='{"timeline":[{"event_type":"student_feedback_recorded"}],"data_quality":{}}'::jsonb
 WHERE session_id='c4000000-0000-4000-8000-000000000004';
SELECT is((SELECT session_payload FROM public.research_bancada_sessions WHERE session_id='c4000000-0000-4000-8000-000000000004'),
          '{"timeline":[],"data_quality":{}}'::jsonb,'child answers stripped from snapshot on update');
SET LOCAL ROLE anon;
SELECT throws_ok($q$SELECT count(*) FROM public.research_questionario_respostas$q$,'42501',NULL,'anon query is denied');
RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
