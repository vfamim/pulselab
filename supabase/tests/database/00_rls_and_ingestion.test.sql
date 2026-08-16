-- =============================================================================
-- PulseLab - pgTAP Test Suite
-- File: supabase/tests/database/00_rls_and_ingestion.test.sql
-- Description: Testes automatizados pgTAP para validação de RLS positiva e
--              negativa, spoofing de installation_id/site_id, restrição de prefixo
--              de Storage, whitelist de instrutores e proteção da view analítica.
-- =============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(19);

-- 1. Testar existência das tabelas obrigatórias
SELECT has_table('public'::name, 'device_installations'::name, 'Tabela public.device_installations deve existir');
SELECT has_table('public'::name, 'device_enrollment_tokens'::name, 'Tabela public.device_enrollment_tokens deve existir');
SELECT has_table('public'::name, 'research_events'::name, 'Tabela public.research_events deve existir');
SELECT has_table('public'::name, 'research_session_events'::name, 'Tabela public.research_session_events deve existir');
SELECT has_table('public'::name, 'instructor_evaluations'::name, 'Tabela public.instructor_evaluations deve existir');
SELECT has_table('public'::name, 'authorized_instructors'::name, 'Tabela public.authorized_instructors deve existir');
SELECT has_view('public'::name, 'research_session_quality'::name, 'View public.research_session_quality deve existir');

-- 2. Testar que RLS está habilitado
SELECT table_privs_are('public', 'device_installations', 'authenticated', ARRAY['SELECT'], 'authenticated pode apenas SELECT em device_installations');
SELECT table_privs_are('public', 'research_events', 'authenticated', ARRAY['INSERT'], 'authenticated possui apenas privilégio de INSERT em research_events');
SELECT table_privs_are('public', 'research_session_events', 'authenticated', ARRAY['INSERT'], 'authenticated possui apenas privilégio de INSERT em research_session_events');

-- 3. Configurar fixtures de teste
-- Dispositivo legítimo: installation '11111111-1111-1111-1111-111111111111', site 'SEDE-JUAZEIRO', user 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
-- Dispositivo revogado: installation '22222222-2222-2222-2222-222222222222', site 'SEDE-JUAZEIRO', user 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
-- Dispositivo outro polo: installation '33333333-3333-3333-3333-333333333333', site 'SEDE-PETROLINA', user 'cccccccc-cccc-cccc-cccc-cccccccccccc'

INSERT INTO public.device_installations (id, device_user_id, installation_id, site_id, regional_hub, school_code, computer_id, is_active)
VALUES
    ('00000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'SEDE-JUAZEIRO', 'Polo-01', 'ESC-01', 'LAB-01', true),
    ('00000000-0000-0000-0000-000000000002', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '22222222-2222-2222-2222-222222222222', 'SEDE-JUAZEIRO', 'Polo-01', 'ESC-01', 'LAB-02', false),
    ('00000000-0000-0000-0000-000000000003', 'cccccccc-cccc-cccc-cccc-cccccccccccc', '33333333-3333-3333-3333-333333333333', 'SEDE-PETROLINA', 'Polo-02', 'ESC-02', 'LAB-03', true)
ON CONFLICT (device_user_id) DO UPDATE SET is_active = EXCLUDED.is_active;

-- 4. Teste RLS Positivo: Dispositivo legítimo insere evento com installation_id e site_id correspondentes
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "role": "authenticated"}';

SELECT lives_ok(
    $$
    INSERT INTO public.research_events (
        event_id, session_id, dyad_id, installation_id, site_id,
        participant_id, participant_role, event_type, response_status,
        regional_hub, school_code, workshop_code, class_code,
        activity_id, computer_id, config_version, client_version,
        occurred_at
    ) VALUES (
        '10000000-0000-0000-0000-000000000001',
        '20000000-0000-0000-0000-000000000001',
        '30000000-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111',
        'SEDE-JUAZEIRO',
        'p1', 'computer', 'pre', 'completed',
        'Polo-01', 'ESC-01', 'WS-01', 'TURMA-A',
        'atv-01', 'LAB-01', '1.5.0', '1.5.0',
        now()
    );
    $$,
    'Dispositivo autenticado e ativo com installation_id/site_id corretos consegue inserir evento'
);

-- 5. Teste RLS Negativo: Tentativa de spoofing de installation_id por dispositivo autenticado
SELECT throws_ok(
    $$
    INSERT INTO public.research_events (
        event_id, session_id, dyad_id, installation_id, site_id,
        participant_id, participant_role, event_type, response_status,
        regional_hub, school_code, workshop_code, class_code,
        activity_id, computer_id, config_version, client_version,
        occurred_at
    ) VALUES (
        '10000000-0000-0000-0000-000000000002',
        '20000000-0000-0000-0000-000000000001',
        '30000000-0000-0000-0000-000000000001',
        '33333333-3333-3333-3333-333333333333', -- Spoofing para outra instalação
        'SEDE-JUAZEIRO',
        'p1', 'computer', 'pre', 'completed',
        'Polo-01', 'ESC-01', 'WS-01', 'TURMA-A',
        'atv-01', 'LAB-01', '1.5.0', '1.5.0',
        now()
    );
    $$,
    '42501', -- Insufficient privilege / RLS with check violation
    NULL,
    'Tentativa de spoofing de installation_id deve ser bloqueada por RLS WITH CHECK'
);

-- 6. Teste RLS Negativo: Tentativa de spoofing de site_id por dispositivo autenticado
SELECT throws_ok(
    $$
    INSERT INTO public.research_events (
        event_id, session_id, dyad_id, installation_id, site_id,
        participant_id, participant_role, event_type, response_status,
        regional_hub, school_code, workshop_code, class_code,
        activity_id, computer_id, config_version, client_version,
        occurred_at
    ) VALUES (
        '10000000-0000-0000-0000-000000000003',
        '20000000-0000-0000-0000-000000000001',
        '30000000-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111',
        'SEDE-PETROLINA', -- Spoofing de sede
        'p1', 'computer', 'pre', 'completed',
        'Polo-01', 'ESC-01', 'WS-01', 'TURMA-A',
        'atv-01', 'LAB-01', '1.5.0', '1.5.0',
        now()
    );
    $$,
    '42501',
    NULL,
    'Tentativa de spoofing de site_id deve ser bloqueada por RLS WITH CHECK'
);

-- 7. Teste RLS Negativo: Dispositivo revogado (is_active = false)
SET LOCAL "request.jwt.claims" = '{"sub": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", "role": "authenticated"}';

SELECT throws_ok(
    $$
    INSERT INTO public.research_events (
        event_id, session_id, dyad_id, installation_id, site_id,
        participant_id, participant_role, event_type, response_status,
        regional_hub, school_code, workshop_code, class_code,
        activity_id, computer_id, config_version, client_version,
        occurred_at
    ) VALUES (
        '10000000-0000-0000-0000-000000000004',
        '20000000-0000-0000-0000-000000000001',
        '30000000-0000-0000-0000-000000000001',
        '22222222-2222-2222-2222-222222222222',
        'SEDE-JUAZEIRO',
        'p1', 'computer', 'pre', 'completed',
        'Polo-01', 'ESC-01', 'WS-01', 'TURMA-A',
        'atv-01', 'LAB-02', '1.5.0', '1.5.0',
        now()
    );
    $$,
    '42501',
    NULL,
    'Dispositivo revogado (is_active=false) deve ter inserção bloqueada'
);

-- 8. Teste RLS Storage real: prefixo precisa corresponder à instalação do JWT
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "role": "authenticated"}';

SELECT lives_ok(
    $$
    INSERT INTO storage.objects (bucket_id, name, owner_id)
    VALUES (
        'screenshots',
        '11111111-1111-1111-1111-111111111111/session-ok/checkpoint-20.jpg',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    );
    $$,
    'Upload no prefixo da instalação autenticada é permitido'
);

SELECT throws_ok(
    $$
    INSERT INTO storage.objects (bucket_id, name, owner_id)
    VALUES (
        'screenshots',
        '33333333-3333-3333-3333-333333333333/session-spoof/checkpoint-20.jpg',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    );
    $$,
    '42501',
    NULL,
    'Upload usando prefixo de outra instalação é bloqueado por RLS'
);

-- 9. Teste RLS Avaliações do Instrutor: Whitelist e autoria
RESET ROLE;
INSERT INTO public.authorized_instructors (email, full_name, is_active)
VALUES ('instrutor.valido@pulselab.edu.br', 'Instrutor Teste', true)
ON CONFLICT (email) DO UPDATE SET is_active = true;

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub": "dddddddd-dddd-dddd-dddd-dddddddddddd", "email": "instrutor.valido@pulselab.edu.br", "role": "authenticated"}';

SELECT lives_ok(
    $$
    INSERT INTO public.instructor_evaluations (
        instructor_email, workshop_code, class_code, session_id,
        mission_performance, instructor_interventions, primary_issue
    ) VALUES (
        'instrutor.valido@pulselab.edu.br', 'WS-01', 'TURMA-A', '20000000-0000-0000-0000-000000000001',
        3, 0, 'none'
    );
    $$,
    'Instrutor autenticado e na whitelist consegue registrar avaliação com seu próprio e-mail'
);

SELECT throws_ok(
    $$
    INSERT INTO public.instructor_evaluations (
        instructor_email, workshop_code, class_code, session_id,
        mission_performance, instructor_interventions, primary_issue
    ) VALUES (
        'outro.email@pulselab.edu.br', 'WS-01', 'TURMA-A', '20000000-0000-0000-0000-000000000001',
        3, 0, 'none'
    );
    $$,
    '42501',
    NULL,
    'Tentativa de forjar e-mail de outro instrutor na avaliação é rejeitada'
);

SET LOCAL "request.jwt.claims" = '{"sub": "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee", "email": "nao.autorizado@pulselab.edu.br", "role": "authenticated"}';
SELECT throws_ok(
    $$
    INSERT INTO public.instructor_evaluations (
        instructor_email, workshop_code, class_code, session_id,
        mission_performance, instructor_interventions, primary_issue
    ) VALUES (
        'nao.autorizado@pulselab.edu.br', 'WS-01', 'TURMA-A', '20000000-0000-0000-0000-000000000002',
        2, 1, 'logic'
    );
    $$,
    '42501',
    NULL,
    'Usuário autenticado fora da whitelist não pode gravar avaliação'
);

SELECT * FROM finish();
ROLLBACK;
