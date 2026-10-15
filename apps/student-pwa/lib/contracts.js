// Manifesto formal do instrumento versionado (auditoria e integridade científica)
// Itens em rascunho: aguardam validação do pesquisador responsável antes de qualquer análise confirmatória.
export const PROTOCOL_VERSION = "protocolo-oficinas-rotativas-v2";
export const INSTRUMENT_VERSION = "bancada-3.2.0";

// Questionário do fim da aula (aba do navegador). Texto aprovado pelo pesquisador responsável:
// não mude as palavras. Os códigos (item_id e valores) são estáveis e o bridge aceita só estes
// (mesma lista em pulselab-bridge.ps1; o teste turma-closing garante).
const SIM_MAIS_OU_MENOS_NAO = [
  ["sim", "Sim"],
  ["mais_ou_menos", "Mais ou menos"],
  ["nao", "Não"]
];

export const INSTRUMENT_MANIFEST = {
  version: INSTRUMENT_VERSION,
  protocol_version: PROTOCOL_VERSION,
  status: "rascunho_pendente_validacao",
  unit_of_analysis: "bancada",
  session_boundary: "da abertura do PulseLab (ou do primeiro programa salvo depois da turma anterior) até Encerrar turma na bandeja, 3 horas, computador desligado por mais de 20 minutos ou 40 minutos sem programa salvo no SPIKE",
  target_constructs: [
    "experiencia_bancada",
    "resultado_pratico_bancada",
    "apoio_instrutor",
    "resultado_testes_carrinho",
    "percepcao_individual_anonima"
  ],
  questionario_fim_aula: {
    stage: "questionario_fim_aula",
    anonymous: true,
    optional: true,
    skip: ["recusou", "Não quero responder"],
    bancada: {
      event_type: "bancada_result_recorded",
      once_per_session: true,
      items: [
        {
          item_id: "bancada_linha_v1",
          number: 1,
          text: "O carrinho de vocês seguiu a linha preta até o fim da pista?",
          options: [["sim", "Sim"], ["em_parte", "Em parte"], ["nao", "Não"]]
        },
        {
          item_id: "bancada_corrida_v1",
          number: 2,
          text: "Como foi a corrida?",
          options: [
            ["ganhamos", "Ganhamos"],
            ["terminamos_sem_ganhar", "Terminamos, mas não ganhamos"],
            ["nao_terminamos", "Não terminamos"],
            ["nao_participamos", "Não participamos"]
          ]
        },
        {
          item_id: "bancada_quiz_v1",
          number: 3,
          text: "No jogo de perguntas, vocês acertaram...",
          options: [
            ["quase_todas", "Quase todas"],
            ["metade", "Metade"],
            ["poucas", "Poucas"],
            ["sem_quiz", "Não teve jogo de perguntas"]
          ]
        }
      ]
    },
    crianca: {
      event_type: "student_feedback_recorded",
      once_per_session: false,
      items: [
        { item_id: "crianca_gostou_v1", number: 4, text: "Eu gostei da aula de robótica.", options: SIM_MAIS_OU_MENOS_NAO },
        { item_id: "crianca_outra_aula_v1", number: 5, text: "Eu queria ter outra aula de robótica.", options: SIM_MAIS_OU_MENOS_NAO },
        { item_id: "crianca_confianca_antes_v1", number: 6, text: "Antes da aula, eu achava que conseguia programar um robô.", options: SIM_MAIS_OU_MENOS_NAO },
        { item_id: "crianca_confianca_agora_v1", number: 7, text: "Agora, eu acho que consigo programar um robô.", options: SIM_MAIS_OU_MENOS_NAO },
        { item_id: "crianca_ajudou_v1", number: 8, text: "Na minha bancada, eu consegui ajudar a montar ou programar.", options: SIM_MAIS_OU_MENOS_NAO }
      ]
    }
  },
  items: {
    bancada: {
      experiencia: {
        item_id: "experiencia_bancada_v1",
        legend: "Como foi a oficina para a sua bancada hoje?",
        options: [
          [1, "😞", "Não gostamos"],
          [2, "😐", "Mais ou menos"],
          [3, "🙂", "Gostamos"],
          [4, "😄", "Adoramos"]
        ],
        action_skip: "Preferimos não responder"
      }
    },
    instrutor: {
      resultado: {
        item_id: "resultado_bancada_v1",
        legend: "Resultado da bancada",
        options: [
          [0, "Não concluiu"],
          [1, "Concluiu em parte"],
          [2, "Concluiu a missão"],
          [3, "Concluiu e foi além"]
        ]
      },
      apoio: {
        item_id: "apoio_instrutor_v1",
        legend: "Apoio que a bancada recebeu",
        options: [
          ["nenhum", "Nenhum"],
          ["algum", "Algum"],
          ["muito", "Muito"]
        ]
      },
      action_skip: "Pular avaliação"
    }
  },
  telemetry: {
    spike: [
      "executable_blocks",
      "top_level_stacks",
      "uses_motor",
      "uses_sensor",
      "uses_loop",
      "uses_condition",
      "uses_variable",
      "uses_procedure",
      "opcode_counts",
      "structure_hash",
      "ct_score",
      "mission_coverage"
    ],
    quality: [
      "heartbeat",
      "ended_by",
      "interrupted",
      "spike_status"
    ]
  }
};

// SHA-256 canônico do manifesto do instrumento (auditoria e integridade científica)
export const CONFIG_HASH = "3e1e3423a7468044ec6bbcc28db81959f0fa3f1a5ee1c7bff97e7e54ef482ba3";

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
  "bancada_result_recorded",
  "student_feedback_recorded",
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
    bancada_result_recorded: "Resultado da bancada (questionário do fim da aula)",
    student_feedback_recorded: "Resposta individual (questionário do fim da aula)",
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

export { isResearchAuthorized } from "./evaluation.js";
