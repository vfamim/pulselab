// The UI and export use this same manifest. Any wording change changes its hash.
export const PROTOCOL_VERSION = "pulselab-bancada-v2-test";
export const INSTRUMENT = {
  version: "bancada-2.0.0-test.1",
  unit: "group",
  status: "experimental_not_validated",
  activity: {
    id: "distance-stop",
    version: "0.1-test",
    title: "Parar diante de um obstáculo",
    objective:
      "Programar o robô para avançar e parar ao detectar um obstáculo a menos de 10 cm. Testar três vezes.",
    explanationPrompt:
      "Mostrem como a leitura do sensor faz o motor parar e por que a leitura precisa se repetir.",
  },
  pre: [
    {
      id: "prior_robotics",
      text: "Antes de hoje, quantos integrantes já tinham montado ou programado um robô?",
      kind: "experience",
      options: [
        ["none", "Nenhum"],
        ["some", "Alguns"],
        ["all", "Todos"],
        ["unknown", "Não sabemos"],
      ],
    },
    {
      id: "group_confidence",
      text: "Quanto o grupo acredita que consegue realizar a missão?",
      kind: "ordinal",
      options: [
        [1, "Nada confiante"],
        [2, "Pouco confiante"],
        [3, "Bastante confiante"],
        [4, "Muito confiante"],
      ],
    },
    {
      id: "knowledge_sensor_pre",
      text: "O que informa ao programa que há um obstáculo perto do robô?",
      kind: "knowledge",
      options: [
        ["sensor", "A leitura do sensor de distância"],
        ["motor", "A velocidade do motor"],
        ["loop", "A quantidade de repetições"],
        ["unknown", "Não sabemos"],
      ],
      correct: "sensor",
    },
    {
      id: "knowledge_loop_pre",
      text: "O robô se move enquanto o obstáculo pode mudar de posição. Quando deve ler a distância?",
      kind: "knowledge",
      options: [
        ["once", "Apenas no início"],
        ["repeat", "Repetidamente enquanto se move"],
        ["end", "Só depois de parar"],
        ["unknown", "Não sabemos"],
      ],
      correct: "repeat",
    },
  ],
  checkpoint: [
    {
      id: "group_mental_effort",
      text: "Quanto o grupo precisou pensar para fazer a parte em que estava agora?",
      kind: "ordinal",
      options: [
        [1, "Muito pouco"],
        [2, "Pouco"],
        [3, "Bastante"],
        [4, "Muito"],
      ],
    },
    {
      id: "progress",
      text: "Qual etapa vocês estão realizando agora?",
      kind: "category",
      options: [
        ["assembly", "Montando o robô"],
        ["programming", "Programando"],
        ["testing", "Testando o funcionamento"],
        ["revising", "Revisando depois de testar"],
      ],
    },
    {
      id: "blocked",
      text: "Neste momento, vocês conseguem continuar a tarefa?",
      kind: "category",
      options: [
        ["yes", "Conseguimos continuar"],
        ["no", "Estamos sem conseguir avançar"],
      ],
    },
    {
      id: "participation_opportunity",
      text: "Desde a última pergunta, todos tiveram oportunidade de dar ideias e participar?",
      kind: "ordinal",
      groupOnly: true,
      options: [
        [1, "Nunca"],
        [2, "Algumas vezes"],
        [3, "Quase sempre"],
        [4, "Sempre"],
      ],
    },
  ],
  post: [
    {
      id: "perceived_understanding",
      text: "Quanto o grupo acredita que consegue explicar como o robô funciona?",
      kind: "ordinal",
      options: [
        [1, "Nada"],
        [2, "Uma parte"],
        [3, "Quase tudo"],
        [4, "Tudo"],
      ],
    },
    {
      id: "return_intent",
      text: "Vocês gostariam de participar de outra oficina?",
      kind: "ordinal",
      options: [
        [1, "Não"],
        [2, "Provavelmente não"],
        [3, "Provavelmente sim"],
        [4, "Sim"],
      ],
    },
    {
      id: "group_affect",
      text: "Qual sentimento o grupo escolhe para descrever esta oficina?",
      kind: "category",
      options: [
        ["curious", "Curiosidade"],
        ["confident", "Confiança"],
        ["excited", "Animação"],
        ["frustrated", "Frustração"],
        ["tired", "Cansaço"],
        ["indifferent", "Indiferença"],
      ],
    },
    {
      id: "knowledge_sensor_post",
      text: "O robô precisa parar perto de uma caixa. Qual informação o programa deve verificar?",
      kind: "knowledge",
      options: [
        ["motor", "O nome do motor"],
        ["sensor", "A distância indicada pelo sensor"],
        ["blocks", "O número de blocos"],
        ["unknown", "Não sabemos"],
      ],
      correct: "sensor",
    },
    {
      id: "knowledge_loop_post",
      text: "Uma caixa é colocada no caminho depois que o robô começou a andar. Como o programa pode percebê-la?",
      kind: "knowledge",
      options: [
        ["once", "Usando só a leitura feita ao ligar"],
        ["end", "Lendo apenas depois de parar"],
        ["repeat", "Atualizando a leitura durante o movimento"],
        ["unknown", "Não sabemos"],
      ],
      correct: "repeat",
    },
  ],
  rubric: {
    execution:
      "Número de execuções que pararam antes do obstáculo, entre três tentativas nas mesmas condições (0–3). Apoio não altera esta contagem.",
    explanation: [
      "Não relaciona sensor e movimento",
      "Identifica sensor ou motor",
      "Explica a condição que faz parar",
      "Explica condição e necessidade de repetir a leitura",
    ],
    assistance:
      "Número de intervenções do instrutor, registrado separadamente do resultado.",
  },
  retention_days: 7,
  checkpoints_minutes: [20, 40],
};

export function questionsFor(phase, groupSize) {
  return INSTRUMENT[phase].filter((q) => !q.groupOnly || groupSize > 1);
}

export function validateAnswers(phase, groupSize, answers) {
  return questionsFor(phase, groupSize).every(
    (q) =>
      Object.hasOwn(answers, q.id) &&
      (answers[q.id] === null ||
        (groupSize > 1 && answers[q.id] === "no_consensus") ||
        q.options.some(([value]) => value === answers[q.id])),
  );
}

export async function instrumentHash() {
  const bytes = new TextEncoder().encode(JSON.stringify(INSTRUMENT));
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(hash), (n) =>
    n.toString(16).padStart(2, "0"),
  ).join("");
}

export function knowledgeResult(phase, answers = {}) {
  const items = INSTRUMENT[phase].filter((q) => q.kind === "knowledge");
  const answered = items.filter(
    (q) => answers[q.id] != null && answers[q.id] !== "no_consensus",
  );
  return {
    correct: answered.filter((q) => answers[q.id] === q.correct).length,
    answered: answered.length,
    total: items.length,
  };
}
