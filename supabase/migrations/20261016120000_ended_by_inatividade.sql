-- Migration: 20261016120000_ended_by_inatividade.sql
-- Description:
--   Novo motivo de encerramento da aula: 'inatividade'. O bridge fecha a turma sozinho depois de
--   PULSELAB_SESSION_IDLE_MINUTES (padrão 40) sem nova versão de programa salva no SPIKE, contados
--   da última versão salva ou, sem nenhuma, do início da turma. Evita que a turma seguinte entre
--   na mesma sessão quando o instrutor esquece de encerrar com o computador ligado.
--   A view research_aula_bancada repassa ended_by sem filtrar valores e não muda.

ALTER TABLE public.research_bancada_sessions DROP CONSTRAINT IF EXISTS research_bancada_sessions_ended_by_check;
ALTER TABLE public.research_bancada_sessions ADD CONSTRAINT research_bancada_sessions_ended_by_check
    CHECK (ended_by IS NULL OR ended_by IN ('instrutor', 'tempo', 'sem_encerramento', 'inatividade'));

COMMENT ON COLUMN public.research_bancada_sessions.ended_by IS
    'Quem encerrou a turma: instrutor, tempo (limite atingido), sem_encerramento (fechada pelo bridge) ou inatividade (sem programa salvo no SPIKE pelo limite, padrão 40 min).';
