BEGIN;
SELECT no_plan();
INSERT INTO public.device_installations(device_user_id, installation_id, site_id) VALUES
('00000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','SITE_A'),
('00000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','SITE_A');
INSERT INTO public.research_site_memberships(user_id, site_id) VALUES
('00000000-0000-4000-8000-000000000003','SITE_A');

-- Dois sinais de vida da máquina 1: vale o mais recente
INSERT INTO public.research_session_events(event_id,session_id,installation_id,site_id,school_code,workshop_code,class_code,activity_id,client_version,event_type,occurred_at,details) VALUES
(gen_random_uuid(),'d1000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','SITE_A','E','O','T','ACT','bridge/3.2.8','heartbeat','2026-10-20T12:00:00Z',
 '{"pending_sync":0,"quarantined_events":0,"quarantined_sessions":0}'),
(gen_random_uuid(),'d1000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','SITE_A','E','O','T','ACT','bridge/3.2.8','heartbeat','2026-10-21T12:00:00Z',
 '{"pending_sync":7,"quarantined_events":3,"quarantined_sessions":1,"last_sync_error_status":400}'),
(gen_random_uuid(),'d1000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','SITE_A','E','O','T','ACT','bridge/3.2.8','session_started','2026-10-21T12:30:00Z','{}');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
SELECT is((SELECT concat_ws('|',last_heartbeat_at,pending_sync,quarantined_events,quarantined_sessions,last_sync_error_status)
             FROM public.research_installation_last_seen WHERE installation_id='10000000-0000-4000-8000-000000000001'),
          concat_ws('|','2026-10-21T12:00:00Z'::timestamptz,7,3,1,400),
          'sync health comes from the latest heartbeat');
SELECT is((SELECT sessions_last_30d FROM public.research_installation_last_seen WHERE installation_id='10000000-0000-4000-8000-000000000001'),1::bigint,
          'existing columns unchanged');
RESET ROLE;
-- Máquina cadastrada sem nada enviado (só service_role lê device_installations de outras máquinas)
SET LOCAL ROLE service_role;
SELECT is((SELECT concat_ws('|',coalesce(last_heartbeat_at::text,'-'),coalesce(quarantined_events::text,'-'))
             FROM public.research_installation_last_seen WHERE installation_id='10000000-0000-4000-8000-000000000002'),
          '-|-','machine without heartbeat shows no health data');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
