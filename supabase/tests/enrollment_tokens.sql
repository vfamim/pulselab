BEGIN;
SELECT no_plan();

INSERT INTO public.device_enrollment_tokens(token_hash, installation_id, site_id, expires_at, max_uses) VALUES
('hash-polo', NULL, 'PET', now() + interval '30 days', 2),
('hash-expirado', NULL, 'PET', now() - interval '1 day', 5),
('hash-revogado', NULL, 'PET', now() + interval '30 days', 5),
('hash-maquina', '10000000-0000-4000-8000-0000000000aa', 'PET', now() + interval '1 day', 1);
UPDATE public.device_enrollment_tokens SET revoked_at = now() WHERE token_hash = 'hash-revogado';

SELECT ok(NOT has_function_privilege('anon','public.consume_device_enrollment_token(text, uuid, text)','EXECUTE'),'anon cannot consume enrollment tokens');
SELECT ok(NOT has_function_privilege('authenticated','public.consume_device_enrollment_token(text, uuid, text)','EXECUTE'),'devices cannot consume enrollment tokens directly');

SET LOCAL ROLE service_role;
SELECT is((SELECT count(*) FROM public.consume_device_enrollment_token('hash-polo', gen_random_uuid(), 'PET')), 1::bigint, 'site token enrolls first machine');
SELECT is((SELECT count(*) FROM public.consume_device_enrollment_token('hash-polo', gen_random_uuid(), 'PET')), 1::bigint, 'site token enrolls second machine');
SELECT is((SELECT count(*) FROM public.consume_device_enrollment_token('hash-polo', gen_random_uuid(), 'PET')), 0::bigint, 'site token stops at max_uses');
SELECT isnt((SELECT consumed_at FROM public.device_enrollment_tokens WHERE token_hash = 'hash-polo'), NULL, 'exhausted token is marked consumed');
SELECT is((SELECT count(*) FROM public.consume_device_enrollment_token('hash-polo', gen_random_uuid(), 'JUA')), 0::bigint, 'token only enrolls its own site');
SELECT is((SELECT count(*) FROM public.consume_device_enrollment_token('hash-expirado', gen_random_uuid(), 'PET')), 0::bigint, 'expired token refused');
SELECT is((SELECT count(*) FROM public.consume_device_enrollment_token('hash-revogado', gen_random_uuid(), 'PET')), 0::bigint, 'revoked token refused');
SELECT is((SELECT count(*) FROM public.consume_device_enrollment_token('hash-maquina', gen_random_uuid(), 'PET')), 0::bigint, 'machine token refuses another installation');
SELECT is((SELECT count(*) FROM public.consume_device_enrollment_token('hash-maquina', '10000000-0000-4000-8000-0000000000aa', 'PET')), 1::bigint, 'machine token accepts its installation');
SELECT is((SELECT count(*) FROM public.consume_device_enrollment_token('hash-maquina', '10000000-0000-4000-8000-0000000000aa', 'PET')), 0::bigint, 'machine token is single use');
RESET ROLE;

SELECT throws_ok($q$UPDATE public.device_enrollment_tokens SET max_uses = 501 WHERE token_hash = 'hash-polo'$q$, '23514', NULL, 'max_uses bounded');

SELECT * FROM finish();
ROLLBACK;
