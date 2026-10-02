// Manifesto formal do instrumento versionado (auditoria e integridade científica)
export const PROTOCOL_VERSION = "protocolo-pesquisa-v2";
export const INSTRUMENT_VERSION = "bancada-2.0.0-impasse";

export const INSTRUMENT_MANIFEST = {
  version: INSTRUMENT_VERSION,
  protocol_version: PROTOCOL_VERSION,
  target_construct: "impasse_percebido",
  recall_window_minutes: 2,
  items: {
    pre: {
      prior_robotics: {
        legend: "Vocês na bancada já montaram ou programaram robôs ou blocos antes?",
        options: [
          [1, "🐣 Primeira vez", "Ninguém na bancada mexeu com robôs"],
          [2, "🧩 Pouca prática", "Alguém já viu ou usou 1 ou 2 vezes"],
          [3, "🚀 Já praticamos", "Já montamos ou programamos antes"],
          [4, "⚡ Muita prática", "Temos facilidade com montagem e código"]
        ]
      }
    },
    checkpoint: {
      impasse_state: {
        legend: "Nos dois minutos antes deste aviso, a bancada ficou sem saber o que tentar para avançar?",
        options: [
          ["no", "🟢 Não", "Estávamos conseguindo tentar ideias e testar caminhos"],
          ["yes", "🛑 Sim", "Travamos sem saber o que tentar para avançar"],
          ["off_task", "💬 Fora da tarefa", "Pausa, conversa paralela ou aguardando peça/professor"],
          ["no_consensus", "🤝 Sem acordo", "O grupo não chegou a uma resposta conjunta"]
        ],
        action_skip: "Pular este check-in"
      }
    },
    rubric: {
      execution: "Tentativas bem-sucedidas no teste do sensor (0-3)",
      explanation: "Explicação conceitual demonstrada (0-3)",
      assistance: "Intervenções de apoio do professor",
      next_action: "Próxima ação pedagógica"
    }
  }
};

// SHA-256 canônico do manifesto do instrumento (auditoria e integridade científica)
export const CONFIG_HASH = "603e3f01c6e3383d1facfe95e8491ba8569a42a9f2e5e8156319f7766767082e";

export const TIMELINE_EVENT_TYPES = [
  "session_started",
  "phase_completed",
  "activity_started",
  "heartbeat",
  "checkpoint_started",
  "checkpoint_completed",
  "checkpoint_expired",
  "help_requested",
  "help_resolved",
  "spike_telemetry",
  "role_swapped",
  "ending_requested",
  "rubric_completed",
  "session_completed",
  "session_aborted",
  "quality_issue"
];

export const PARTICIPANTS = {
  grupo: { id: "GRUPO", label: "Grupo" },
  bancada: { id: "BANCADA", label: "Bancada Coletiva" },
  A: { id: "PARTICIPANTE-A", label: "Participante A" },
  B: { id: "PARTICIPANTE-B", label: "Participante B" }
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
  const preCompletedCount = responses.filter(
    (event) => event.event_type === "pre" && (event.response_status === "completed" || !event.response_status)
  ).length;
  const checkpointCompletedCount = responses.filter(
    (event) => event.event_type === "checkpoint" && (event.response_status === "completed" || !event.response_status)
  ).length;
  const postCompletedCount = responses.filter(
    (event) => event.event_type === "post" && (event.response_status === "completed" || !event.response_status)
  ).length;

  if (
    qualityIssueCount > 0 ||
    completedCheckpointCount < expectedCheckpointCount ||
    preCompletedCount < 1 ||
    checkpointCompletedCount < expectedCheckpointCount ||
    postCompletedCount < 1
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
    checkpoint_started: "Check-in iniciado",
    checkpoint_completed: "Check-in registrado",
    checkpoint_expired: "Check-in expirado",
    help_requested: "Ajuda solicitada",
    help_resolved: "Ajuda atendida",
    spike_telemetry: "Telemetria SPIKE",
    role_swapped: "Papéis trocados",
    ending_requested: "Encerramento solicitado",
    rubric_completed: "Rubrica do instrutor concluída",
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
