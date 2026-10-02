// Manifesto formal do instrumento versionado (auditoria e integridade científica)
export const PROTOCOL_VERSION = "protocolo-oficinas-rotativas-v1";
export const INSTRUMENT_VERSION = "oficinas-rotativas-1.0.0";

export const INSTRUMENT_MANIFEST = {
  version: INSTRUMENT_VERSION,
  protocol_version: PROTOCOL_VERSION,
  target_constructs: [
    "experiencia_participacao",
    "resultados_praticos_bancada",
    "apoio_instrutor"
  ],
  stages: [
    "1. Introdução",
    "2. Montagem",
    "3. Experimentação",
    "4. Desafio Final (Corrida e Encerramento)"
  ],
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
    post: {
      experience: {
        legend: "Como foi participar da oficina de robótica de hoje?",
        options: [
          [1, "😞 Muito ruim", "Não gostei da experiência"],
          [2, "🙁 Ruim", "Poderia ter sido melhor"],
          [3, "😐 Nem boa nem ruim", "Achei normal"],
          [4, "🙂 Boa", "Gostei da oficina"],
          [5, "😄 Muito boa", "Adorei a atividade"]
        ],
        action_skip: "Prefiro não responder"
      },
      race: {
        legend: "Desfecho do Desafio da Pista / Corrida",
        options: [
          ["success", "🏆 Concluiu com sucesso", "Carrinho completou o percurso no circuito"],
          ["partial", "⏱️ Não concluiu o percurso", "Travou, saiu da pista ou precisou de ajuste"],
          ["tech_failure", "⚠️ Falha técnica / Bluetooth", "Problema de bateria, desconexão ou peça solta"]
        ]
      },
      assembly: {
        legend: "Critérios de montagem do carrinho com peças LEGO",
        options: [
          ["complete", "🧩 Montagem concluída pelo roteiro"],
          ["partial", "🔧 Montagem parcial / adaptada"],
          ["incomplete", "❌ Não concluiu a montagem"]
        ]
      },
      quiz_entertainment: {
        legend: "Dinâmica lúdica do Quiz A/B pelos botões do robô",
        note: "Dinâmica de entretenimento e recreação (não utilizada como avaliação de aprendizagem)",
        options: [
          ["participated", "🎮 Participaram da brincadeira do Quiz A/B no robô"],
          ["skipped", "⏭️ Dinâmica não realizada"]
        ]
      },
      support_level: {
        legend: "Nível de apoio do instrutor recebido pela bancada",
        options: [
          ["independent", "🟢 Autônomo (trabalharam praticamente sozinhos)"],
          ["occasional", "🟡 Apoio pontual (dúvidas breves tiradas)"],
          ["constant", "🔴 Apoio constante (mediação intensiva necessária)"]
        ]
      }
    }
  }
};

// SHA-256 canônico do manifesto do instrumento (auditoria e integridade científica)
export const CONFIG_HASH = "3c3662c7306d64236b0f7f26da183cc59a36c00061a2077d93fb0272876b2468";

export const TIMELINE_EVENT_TYPES = [
  "session_started",
  "phase_transition",
  "phase_completed",
  "activity_started",
  "heartbeat",
  "checkpoint_started",
  "checkpoint_completed",
  "checkpoint_expired",
  "help_requested",
  "help_resolved",
  "spike_telemetry",
  "race_recorded",
  "quiz_recorded",
  "experience_recorded",
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
  expectedCheckpointCount = 0
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
    phase_transition: "Transição de etapa",
    phase_completed: "Fase concluída",
    activity_started: "Atividade iniciada",
    heartbeat: "Sinal de vida",
    checkpoint_started: "Check-in iniciado",
    checkpoint_completed: "Check-in registrado",
    checkpoint_expired: "Check-in expirado",
    help_requested: "Ajuda solicitada",
    help_resolved: "Ajuda atendida",
    spike_telemetry: "Telemetria SPIKE",
    race_recorded: "Desafio da pista registrado",
    quiz_recorded: "Quiz lúdico registrado",
    experience_recorded: "Avaliação de experiência registrada",
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
