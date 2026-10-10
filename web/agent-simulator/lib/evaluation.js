/**
 * Módulo de validação e autorização do protocolo coletivo PulseLab v2.
 * Implementa verificação fail-closed de autorização de pesquisa,
 * validação de snapshots coletivos de bancada e telemetria estrutural do SPIKE.
 */

/**
 * Validação fail-closed estrita da configuração de pesquisa acadêmica.
 *
 * Critérios mandatórios para autorizar a coleta de pesquisa:
 * 1. research_collection_enabled === true (booleano estrito; rejeita falsy e strings como "true")
 * 2. research_authorization_version string não vazia (rejeita null, undefined, vazio ou apenas espaços)
 * 3. research_authorized_purposes array contendo explicitamente "academic_research"
 * 4. group_size inteiro estrito entre 2 e 8 (unidade de observação é a bancada coletiva)
 */
export function isResearchAuthorized(config) {
  if (!config || typeof config !== "object" || Array.isArray(config)) {
    return false;
  }

  // 1. Booleano estrito true
  if (config.research_collection_enabled !== true) {
    return false;
  }

  // 2. Versão de autorização string não vazia
  if (
    typeof config.research_authorization_version !== "string" ||
    config.research_authorization_version.trim().length === 0
  ) {
    return false;
  }

  // 3. Finalidade explícita "academic_research"
  if (
    !Array.isArray(config.research_authorized_purposes) ||
    !config.research_authorized_purposes.includes("academic_research")
  ) {
    return false;
  }

  // 4. group_size inteiro estrito entre 2 e 8
  const groupSize = config.group_size;
  if (!Number.isInteger(groupSize) || groupSize < 2 || groupSize > 8) {
    return false;
  }

  return true;
}

/**
 * Validação fail-closed de snapshot de sessão restaurada no modelo coletivo.
 * - group_size (ou teamSize legado) deve ser inteiro estrito entre 2 e 8.
 * - Rejeita sessões em Modo Livre, sem timestamp de início válido,
 *   sessões no futuro ou que excederam o prazo absoluto de retenção de 7 dias.
 * - Garante sessionId e groupId coletivo.
 */
export function validateRestoredSession(savedSession, options = {}) {
  if (!savedSession || typeof savedSession !== "object" || Array.isArray(savedSession)) {
    return null;
  }

  if (
    savedSession.isFreeMode === true ||
    savedSession.status === "completed" ||
    savedSession.status === "withdrawn" ||
    savedSession.isCompleted === true
  ) {
    return null;
  }

  const rawGroupSize = savedSession.group_size ?? savedSession.teamSize;
  const isStrictGroupSize = Number.isInteger(rawGroupSize) && rawGroupSize >= 2 && rawGroupSize <= 8;
  if (!isStrictGroupSize) {
    return null;
  }

  const startedAt =
    typeof savedSession.startedAt === "number"
      ? savedSession.startedAt
      : savedSession.started_at
        ? new Date(savedSession.started_at).getTime()
        : null;

  const maxAge = typeof options?.maxAgeMs === "number" ? options.maxAgeMs : 7 * 24 * 60 * 60 * 1000;

  if (
    !Number.isFinite(startedAt) ||
    startedAt <= 0 ||
    startedAt > Date.now() ||
    Date.now() - startedAt >= maxAge
  ) {
    return null;
  }

  const sessId = savedSession.sessionId || savedSession.session_id;
  if (typeof sessId !== "string" || sessId.trim().length === 0) {
    return null;
  }

  const grpId = savedSession.groupId || savedSession.group_id;

  return {
    ...savedSession,
    sessionId: sessId,
    session_id: sessId,
    groupId: grpId || sessId,
    group_id: grpId || sessId,
    group_size: rawGroupSize,
    teamSize: rawGroupSize,
    startedAt
  };
}

/**
 * Recusa exportação de dados se a sessão estiver em Modo Livre ou sem autorização institucional válida.
 * Rejeita qualquer compatibilidade permissiva via assentAgreed:
 * apenas researchAuthorized === true e isFreeMode === false autorizam a exportação.
 */
export function downloadSessionData(sessionData, { isFreeMode = false, researchAuthorized = false } = {}) {
  if (isFreeMode === true || researchAuthorized !== true) {
    return null;
  }
  return {
    ...sessionData
  };
}

/**
 * Validação fail-safe da telemetria final do robô SPIKE.
 * Se a captura final retornar project_saved: false ou dados inválidos,
 * preserva a última telemetria válida anterior e registra status técnico separado.
 */
export function validateFinalTelemetry(finalMetrics, previousTelemetry) {
  const isFinalValid =
    finalMetrics &&
    typeof finalMetrics === "object" &&
    finalMetrics.project_saved !== false &&
    typeof finalMetrics.executable_blocks === "number";

  if (isFinalValid) {
    return {
      effectiveTelemetry: finalMetrics,
      technicalStatus: "ok"
    };
  }

  return {
    effectiveTelemetry: previousTelemetry || null,
    technicalStatus: finalMetrics?.project_saved === false ? "project_not_saved" : "invalid_or_unavailable"
  };
}

/**
 * Apenas contagens estruturais e flags de blocos entram na observação;
 * descarta nomes de arquivos, código fonte Scratch/Python e inferências heurísticas.
 */
export function structuralSpikeMetrics(raw) {
  if (!raw || typeof raw !== "object") return null;
  const metrics = {};
  for (const key of ["executable_blocks", "top_level_stacks"]) {
    if (Number.isFinite(raw[key]) && raw[key] >= 0) metrics[key] = raw[key];
  }
  for (const key of ["project_saved", "uses_motor", "uses_sensor", "uses_loop", "uses_condition"]) {
    if (typeof raw[key] === "boolean") metrics[key] = raw[key];
  }
  return metrics;
}
