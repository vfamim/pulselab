export const CONFIG_HASH = "d".repeat(64);

export const TIMELINE_EVENT_TYPES = [
  "session_started",
  "phase_completed",
  "activity_started",
  "heartbeat",
  "checkpoint_started",
  "checkpoint_completed",
  "help_requested",
  "role_swapped",
  "ending_requested",
  "rubric_completed",
  "session_completed",
  "session_aborted",
  "quality_issue"
];

export const PARTICIPANTS = {
  A: { id: "PARTICIPANTE-A", label: "Aluno 1" },
  B: { id: "PARTICIPANTE-B", label: "Aluno 2" },
  C: { id: "PARTICIPANTE-C", label: "Aluno 3" },
  D: { id: "PARTICIPANTE-D", label: "Aluno 4" }
};

export function createUuid() {
  if (typeof crypto !== "undefined" && crypto.randomUUID) {
    return crypto.randomUUID();
  }

  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (character) => {
    const random = Math.floor(Math.random() * 16);
    const value = character === "x" ? random : (random & 0x3) | 0x8;
    return value.toString(16);
  });
}

export function getQualityStatus({
  timeline,
  responses,
  expectedCheckpointCount = 2
}) {
  if (timeline.some((event) => event.event_type === "session_aborted")) {
    return "aborted";
  }

  if (!timeline.some((event) => event.event_type === "session_completed")) {
    return "in_progress";
  }

  const qualityIssueCount = timeline.filter(
    (event) => event.event_type === "quality_issue"
  ).length;
  const completedCheckpointCount = timeline.filter(
    (event) => event.event_type === "checkpoint_completed"
  ).length;
  const preCount = responses.filter((event) => event.event_type === "pre").length;
  const checkpointCount = responses.filter(
    (event) => event.event_type === "checkpoint"
  ).length;
  const postCount = responses.filter((event) => event.event_type === "post").length;

  if (
    qualityIssueCount > 0 ||
    completedCheckpointCount < expectedCheckpointCount ||
    preCount < 1 ||
    checkpointCount < expectedCheckpointCount ||
    postCount < 1
  ) {
    return "needs_review";
  }

  return "complete";
}

export function roleLabel(role) {
  if (role === "computer") return "computador e programação";
  if (role === "assembly") return "montagem e testes";
  if (role === "member_3") return "suporte e testes";
  if (role === "member_4") return "documentação e apoio";
  if (role === "individual") return "trabalho individual";
  return role;
}

export function formatEventName(eventType) {
  const labels = {
    session_started: "Sessão iniciada",
    phase_completed: "Fase concluída",
    activity_started: "Atividade iniciada",
    heartbeat: "Sinal de vida",
    checkpoint_started: "Checkpoint iniciado",
    checkpoint_completed: "Checkpoint concluído",
    help_requested: "Ajuda solicitada",
    role_swapped: "Papéis trocados",
    ending_requested: "Encerramento solicitado",
    rubric_completed: "Rubrica concluída",
    session_completed: "Sessão concluída",
    session_aborted: "Sessão interrompida",
    quality_issue: "Alerta de qualidade"
  };

  return labels[eventType] || eventType;
}

export function qualityLabel(status) {
  const labels = {
    in_progress: "Em andamento",
    complete: "Completa",
    needs_review: "Precisa de revisão",
    aborted: "Interrompida"
  };

  return labels[status] || status;
}
