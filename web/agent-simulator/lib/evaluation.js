/**
 * Módulo de avaliação e assentimento ético para o protocolo PulseLab v2.
 * Extraído para módulo puro importável para garantir coerência entre UI e testes.
 */

/**
 * Verifica se todos os integrantes da bancada (1..teamSize) assentiram individualmente.
 * Decisão ética mandatória: a oficina compartilha robô, projeto e telemetria;
 * portanto, a coleta de pesquisa exige assentimento unânime de 1..teamSize.
 * Se qualquer integrante recusar, a bancada inteira opera em Modo Livre.
 *
 * Fail-closed estrito:
 * - teamSize deve ser inteiro estrito entre 1 e 4.
 * - memberAssents[i] deve ser estritamente === true (nunca falsy ou truthy genérico como "false" ou 1).
 */
export function isAllAssented(teamSize, memberAssents) {
  if (!Number.isInteger(teamSize) || teamSize < 1 || teamSize > 4) {
    return false;
  }
  if (!memberAssents || typeof memberAssents !== "object" || Array.isArray(memberAssents)) {
    return false;
  }
  for (let i = 1; i <= teamSize; i++) {
    if (memberAssents[i] !== true) {
      return false;
    }
  }
  return true;
}

/**
 * Validação fail-closed de snapshot de sessão restaurada.
 * - teamSize deve ser estritamente inteiro entre 1 e 4; caso inválido retorna null.
 * - memberAssents deve conter apenas objetos válidos com booleanos estritos.
 */
export function validateRestoredSession(savedSession) {
  if (!savedSession || typeof savedSession !== "object" || Array.isArray(savedSession)) {
    return null;
  }

  const rawTeamSize = savedSession.teamSize;
  const isStrictTeamSize = Number.isInteger(rawTeamSize) && rawTeamSize >= 1 && rawTeamSize <= 4;
  if (!isStrictTeamSize) {
    return null;
  }

  const assents = savedSession.memberAssents;
  const isAssentsValidObject = assents && typeof assents === "object" && !Array.isArray(assents);
  if (!isAssentsValidObject) {
    return null;
  }

  const allAssented = isAllAssented(rawTeamSize, assents);
  return {
    ...savedSession,
    teamSize: rawTeamSize,
    allAssented,
    memberAssents: assents
  };
}

/**
 * Recusa exportação de dados se a sessão estiver em modo livre ou sem assentimento unânime.
 */
export function downloadSessionData(sessionData, { isFreeMode = false, assentAgreed = false } = {}) {
  if (isFreeMode || !assentAgreed) {
    return null;
  }
  return {
    ...sessionData
  };
}

/**
 * Resolve as experiências individuais dos membros da bancada.
 * Apenas chamada quando a bancada estiver em modo de pesquisa (todos assentiram).
 */
export function resolveMemberExperiences(teamSize, memberAssents = {}, rawExperiences = []) {
  if (!isAllAssented(teamSize, memberAssents)) {
    return [];
  }

  const list = Array.isArray(rawExperiences) ? [...rawExperiences] : [];
  const ordered = [];
  for (let i = 1; i <= teamSize; i++) {
    const existing = list.find((m) => m.memberIndex === i);
    if (existing) {
      ordered.push({
        memberIndex: i,
        rating: existing.skipped ? null : existing.rating,
        skipped: Boolean(existing.skipped)
      });
    } else {
      ordered.push({
        memberIndex: i,
        rating: null,
        skipped: false
      });
    }
  }
  return ordered;
}

/**
 * Valida se a etapa de avaliação final da bancada está pronta para submissão.
 * Cada membro 1..teamSize deve ter respondido com uma nota (1..5) ou optado por pular.
 */
export function isPostScreenReady(teamSize, experiences = []) {
  if (!teamSize || experiences.length !== teamSize) {
    return false;
  }
  return experiences.every((m) => (m.rating !== null && m.rating !== undefined) || m.skipped === true);
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
