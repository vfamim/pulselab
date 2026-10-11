-- Tokens de cadastro por polo.
--
-- Antes, cada token era ligado a um installation_id conhecido de antemão. Como o
-- installation_id agora é gerado no próprio computador (dados_locais/installation.json),
-- o coordenador emite um token por polo com limite de usos e validade; cada máquina do
-- polo usa o mesmo token uma vez, no primeiro contato com a internet.
--
-- Tokens antigos (com installation_id) continuam válidos e de uso único.

ALTER TABLE public.device_enrollment_tokens ALTER COLUMN installation_id DROP NOT NULL;
ALTER TABLE public.device_enrollment_tokens ADD COLUMN IF NOT EXISTS max_uses integer NOT NULL DEFAULT 1;
ALTER TABLE public.device_enrollment_tokens ADD COLUMN IF NOT EXISTS use_count integer NOT NULL DEFAULT 0;
ALTER TABLE public.device_enrollment_tokens ADD COLUMN IF NOT EXISTS revoked_at timestamptz;

-- Tokens já consumidos pelo fluxo antigo contam como usados.
UPDATE public.device_enrollment_tokens SET use_count = 1 WHERE consumed_at IS NOT NULL AND use_count = 0;

ALTER TABLE public.device_enrollment_tokens DROP CONSTRAINT IF EXISTS device_enrollment_tokens_uses_check;
ALTER TABLE public.device_enrollment_tokens ADD CONSTRAINT device_enrollment_tokens_uses_check
    CHECK (max_uses BETWEEN 1 AND 500 AND use_count BETWEEN 0 AND max_uses);

-- Consome um uso do token de forma atômica. O UPDATE trava a linha, então duas máquinas
-- usando o mesmo token ao mesmo tempo não ultrapassam max_uses.
CREATE OR REPLACE FUNCTION public.consume_device_enrollment_token(
    p_token_hash text,
    p_installation_id uuid,
    p_site_id text
)
RETURNS TABLE (token_id uuid, regional_hub text, school_code text, computer_id text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    UPDATE public.device_enrollment_tokens t
       SET use_count = t.use_count + 1,
           consumed_at = CASE
               WHEN t.use_count + 1 >= t.max_uses THEN timezone('utc'::text, now())
               ELSE t.consumed_at
           END
     WHERE t.token_hash = p_token_hash
       AND t.site_id = p_site_id
       AND t.revoked_at IS NULL
       AND t.expires_at > now()
       AND t.use_count < t.max_uses
       AND (t.installation_id IS NULL OR t.installation_id = p_installation_id)
    RETURNING t.id, t.regional_hub, t.school_code, t.computer_id;
END;
$$;

REVOKE ALL ON FUNCTION public.consume_device_enrollment_token(text, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.consume_device_enrollment_token(text, uuid, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_device_enrollment_token(text, uuid, text) TO service_role;
