BEGIN;
SELECT no_plan();
INSERT INTO public.device_installations(device_user_id, installation_id, site_id) VALUES
('00000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','SITE_A'),
('00000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','SITE_B');
INSERT INTO public.research_site_memberships(user_id, site_id) VALUES
('00000000-0000-4000-8000-000000000003','SITE_A');

-- Aula completa, como o bridge grava (Close-BridgeSession): timeline com dois spike_telemetry
INSERT INTO public.research_bancada_sessions(session_id,group_id,site_id,installation_id,school_code,workshop_code,class_code,environment,protocol_version,instrument_version,group_size,phase,ended_by,interrupted,data_quality,session_payload,created_at,updated_at)
VALUES('a0000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','SITE_A','10000000-0000-4000-8000-000000000001','ESC1','OF1','T1','production','v2.4','bancada-2.4.0',4,'completed','instrutor',false,
'{"heartbeat_count":10,"max_heartbeat_gap_min":1.5,"bridge_restarts":0,"corrupted_lines":0,"spike_status":"ok","telemetry_events":2,"last_activity_at":"2026-10-06T11:55:00Z"}'::jsonb,
$j${"session_id":"a0000000-0000-4000-8000-000000000001","computer_id":"PET-LAB1-PC03","site_id":"SITE_A","start_mode":"atividade_spike","client_version":"bridge/3.0.9","instrument_version":"bancada-2.4.0","started_at":"2026-10-06T11:05:00Z","completed_at":"2026-10-06T11:55:00Z","duration_seconds":3000,"status":"completed","phase":"completed","ended_by":"instrutor","interrupted":false,
"summary":{"telemetry_events":2,"final":{"executable_blocks":12,"ct_total":7}},
"timeline":[
 {"event_type":"session_started","details":{"start_mode":"atividade_spike"}},
 {"event_type":"spike_telemetry","details":{"executable_blocks":3,"uses_motor":false,"uses_sensor":false,"uses_loop":false,"uses_condition":false,"ct_score":{"total":2},"spike_status":"ok"}},
 {"event_type":"heartbeat","details":{"spike_status":"ok"}},
 {"event_type":"spike_telemetry","details":{"executable_blocks":12,"uses_motor":true,"uses_sensor":true,"uses_loop":true,"uses_condition":false,"ct_score":{"total":7},"spike_status":"ok"}},
 {"event_type":"session_completed","details":{"ended_by":"instrutor"}}
]}$j$::jsonb,
'2026-10-06T11:05:00Z','2026-10-06T11:55:00Z');

-- Aula sem timeline no snapshot, ainda em andamento, que começou 23h30 locais (02h30 UTC do dia seguinte)
INSERT INTO public.research_bancada_sessions(session_id,site_id,installation_id,school_code,phase,session_payload,created_at,updated_at)
VALUES('a0000000-0000-4000-8000-000000000002','SITE_A','10000000-0000-4000-8000-000000000001','ESC1','in_progress',
'{"computer_id":"PET-LAB1-PC03","start_mode":"abertura_app"}'::jsonb,'2026-10-07T02:30:00Z','2026-10-07T14:30:00Z');
INSERT INTO public.research_session_events(event_id,session_id,installation_id,site_id,school_code,workshop_code,class_code,activity_id,client_version,event_type,occurred_at,details) VALUES
(gen_random_uuid(),'a0000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001','SITE_A','E','O','T','ACT','bridge/3.0.9','spike_telemetry','2026-10-07T02:50:00Z','{"executable_blocks":5,"uses_motor":true,"ct_score":{"total":3},"spike_status":"ok"}'),
(gen_random_uuid(),'a0000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001','SITE_A','E','O','T','ACT','bridge/3.0.9','spike_telemetry','2026-10-07T02:40:00Z','{"executable_blocks":1,"uses_motor":false,"ct_score":{"total":1},"spike_status":"ok"}'),
(gen_random_uuid(),'a0000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001','SITE_A','E','O','T','ACT','bridge/3.0.9','heartbeat','2026-10-07T02:55:00Z','{"spike_status":"ok"}');

-- Snapshot com tipos inesperados: não pode derrubar a view
INSERT INTO public.research_bancada_sessions(session_id,site_id,installation_id,school_code,phase,ended_by,interrupted,data_quality,session_payload,created_at,updated_at)
VALUES('a0000000-0000-4000-8000-000000000003','SITE_B','10000000-0000-4000-8000-000000000002','ESC2','completed','sem_encerramento',true,
'{"telemetry_events":"x","bridge_restarts":2,"spike_status":"pasta_nao_encontrada"}'::jsonb,
'{"duration_seconds":"abc","timeline":{"not":"an array"},"computer_id":"","summary":[1]}'::jsonb,'2026-10-08T12:00:00Z','2026-10-08T12:20:00Z');

-- Aula encerrada sem nenhum programa salvo e sem data_quality
INSERT INTO public.research_bancada_sessions(session_id,site_id,installation_id,school_code,phase,ended_by,session_payload,created_at,updated_at)
VALUES('a0000000-0000-4000-8000-000000000004','SITE_A','10000000-0000-4000-8000-000000000001','ESC1','completed','tempo',
'{"timeline":[{"event_type":"session_started","details":{}}]}'::jsonb,'2026-10-09T12:00:00Z','2026-10-09T15:00:00Z');

-- Aula esquecida aberta, fechada pelo bridge sem programa salvo no SPIKE (inatividade)
INSERT INTO public.research_bancada_sessions(session_id,site_id,installation_id,school_code,phase,ended_by,interrupted,data_quality,session_payload,created_at,updated_at)
VALUES('a0000000-0000-4000-8000-000000000005','SITE_A','10000000-0000-4000-8000-000000000001','ESC1','completed','inatividade',false,
'{"heartbeat_count":8,"spike_status":"sem_alteracao","telemetry_events":0}'::jsonb,
'{"duration_seconds":2400,"start_mode":"abertura_app","timeline":[{"event_type":"session_started","details":{}}]}'::jsonb,'2026-10-10T11:00:00Z','2026-10-10T11:40:00Z');

-- Privilégios e modo da view
SELECT has_view('public','research_aula_bancada','view research_aula_bancada exists');
SELECT ok(NOT has_table_privilege('anon','public.research_aula_bancada','SELECT'),'anon cannot read aula view');
SELECT ok(has_table_privilege('authenticated','public.research_aula_bancada','SELECT'),'authenticated can read aula view under RLS');
SELECT ok((SELECT 'security_invoker=true' = ANY(c.reloptions) FROM pg_class c WHERE c.oid = 'public.research_aula_bancada'::regclass),'aula view runs with security_invoker');

-- Valores planos
SET LOCAL ROLE service_role;
SELECT is((SELECT count(*) FROM public.research_aula_bancada),5::bigint,'one row per bancada session');
SELECT is((SELECT concat_ws('|',polo,escola,maquina,installation_id,data_local,hora_inicio,hora_fim,duracao_min,encerrada_por,interrompida,fase,modo_inicio)
             FROM public.research_aula_bancada WHERE session_id='a0000000-0000-4000-8000-000000000001'),
          'SITE_A|ESC1|PET-LAB1-PC03|10000000-0000-4000-8000-000000000001|2026-10-06|08:05|08:55|50.0|instrutor|f|completed|atividade_spike',
          'identification, local time and closing fields');
SELECT is((SELECT concat_ws('|',versoes_programa,blocos_executaveis,usa_motor,usa_sensor,usa_laco,usa_condicao,ct_score,spike_status)
             FROM public.research_aula_bancada WHERE session_id='a0000000-0000-4000-8000-000000000001'),
          '2|12|t|t|t|f|7|ok',
          'last spike_telemetry snapshot from the timeline');
SELECT is((SELECT concat_ws('|',sinais_de_vida,maior_lacuna_min,reinicios,linhas_corrompidas,client_version,instrument_version,ambiente,origem)
             FROM public.research_aula_bancada WHERE session_id='a0000000-0000-4000-8000-000000000001'),
          '10|1.5|0|0|bridge/3.0.9|bancada-2.4.0|production|nuvem',
          'data quality, versions and origin');
SELECT is((SELECT concat_ws('|',data_local,hora_inicio,coalesce(hora_fim,'-'),coalesce(duracao_min::text,'-'),versoes_programa,blocos_executaveis,usa_motor,ct_score,spike_status,modo_inicio)
             FROM public.research_aula_bancada WHERE session_id='a0000000-0000-4000-8000-000000000002'),
          '2026-10-06|23:30|-|-|2|5|t|3|ok|abertura_app',
          'no timeline: telemetry from research_session_events, local date before midnight, open session has no end');
SELECT is((SELECT concat_ws('|',coalesce(maquina,'-'),duracao_min,coalesce(versoes_programa::text,'-'),coalesce(blocos_executaveis::text,'-'),reinicios,spike_status,interrompida,encerrada_por)
             FROM public.research_aula_bancada WHERE session_id='a0000000-0000-4000-8000-000000000003'),
          '-|20.0|-|-|2|pasta_nao_encontrada|t|sem_encerramento',
          'unexpected payload types become NULL and duration falls back to timestamps');
SELECT is((SELECT concat_ws('|',versoes_programa,duracao_min,coalesce(spike_status,'-'),coalesce(ct_score::text,'-'))
             FROM public.research_aula_bancada WHERE session_id='a0000000-0000-4000-8000-000000000004'),
          '0|180.0|-|-',
          'timeline without spike_telemetry means zero saved versions');
SELECT is((SELECT concat_ws('|',encerrada_por,interrompida,versoes_programa,duracao_min,modo_inicio)
             FROM public.research_aula_bancada WHERE session_id='a0000000-0000-4000-8000-000000000005'),
          'inatividade|f|0|40.0|abertura_app',
          'lesson closed for inactivity passes through the view');
RESET ROLE;

-- A view não abre acesso que as tabelas não abrem
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
SELECT is((SELECT array_agg(DISTINCT polo) FROM public.research_aula_bancada),ARRAY['SITE_A'],'researcher sees only assigned site lessons');
SELECT is((SELECT count(*) FROM public.research_aula_bancada),(SELECT count(*) FROM public.research_bancada_sessions),'researcher: view rows equal table rows');
SELECT is((SELECT blocos_executaveis FROM public.research_aula_bancada WHERE session_id='a0000000-0000-4000-8000-000000000002'),5,'researcher reads timeline fallback under RLS');
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
SELECT is((SELECT count(*) FROM public.research_aula_bancada),(SELECT count(*) FROM public.research_bancada_sessions),'device: view rows equal table rows');
SELECT is((SELECT count(*) FROM public.research_aula_bancada WHERE polo = 'SITE_B'),0::bigint,'device does not see other site lessons');
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000099","role":"authenticated"}',true);
SELECT is((SELECT count(*) FROM public.research_aula_bancada),0::bigint,'unaffiliated user sees no lessons');
RESET ROLE;
SET LOCAL ROLE anon;
SELECT throws_ok($q$SELECT count(*) FROM public.research_aula_bancada$q$,'42501',NULL,'anon query is denied');
RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
