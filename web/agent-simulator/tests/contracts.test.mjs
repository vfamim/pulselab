import test from "node:test";
import assert from "node:assert/strict";
import {
  CONFIG_HASH,
  TIMELINE_EVENT_TYPES,
  getQualityStatus
} from "../lib/contracts.js";
import {
  PERSISTED_CONTEXT_FIELDS,
  createStoredContext,
  sanitizeStoredContext
} from "../lib/context-storage.js";
import fs from "node:fs";

const baseTimeline = [
  { event_type: "session_started" },
  { event_type: "checkpoint_completed" },
  { event_type: "checkpoint_completed" }
];
const baseResponses = [
  { event_type: "pre" },
  { event_type: "pre" },
  { event_type: "checkpoint" },
  { event_type: "checkpoint" },
  { event_type: "checkpoint" },
  { event_type: "checkpoint" },
  { event_type: "post" },
  { event_type: "post" }
];

test("hash demonstrativo respeita o formato do schema", () => {
  assert.match(CONFIG_HASH, /^[0-9a-f]{64}$/);
});

test("contrato web cobre os tipos da linha do tempo 1.5", () => {
  assert.equal(TIMELINE_EVENT_TYPES.length, 13);
  assert.ok(TIMELINE_EVENT_TYPES.includes("quality_issue"));
  assert.ok(TIMELINE_EVENT_TYPES.includes("session_completed"));
});

test("sessão sem desfecho permanece em andamento", () => {
  assert.equal(
    getQualityStatus({ timeline: baseTimeline, responses: baseResponses }),
    "in_progress"
  );
});

test("sessão completa e sem alerta é classificada como completa", () => {
  assert.equal(
    getQualityStatus({
      timeline: [...baseTimeline, { event_type: "session_completed" }],
      responses: baseResponses
    }),
    "complete"
  );
});

test("alerta rebaixa sessão concluída para revisão", () => {
  assert.equal(
    getQualityStatus({
      timeline: [
        ...baseTimeline,
        { event_type: "quality_issue" },
        { event_type: "session_completed" }
      ],
      responses: baseResponses
    }),
    "needs_review"
  );
});

test("aborto tem precedência sobre completude", () => {
  assert.equal(
    getQualityStatus({
      timeline: [...baseTimeline, { event_type: "session_aborted" }],
      responses: baseResponses
    }),
    "aborted"
  );
});

test("contexto operacional persiste sem autorização ou faixa escolar", () => {
  const stored = createStoredContext({
    site_id: "Juazeiro-BA",
    regional_hub: "Polo-São-Francisco",
    school_code: "ESCOLA-01",
    workshop_code: "OFICINA-02",
    class_code: "TURMA-A",
    group_size: 8,
    activity_id: "atividade-spike",
    authorization_verified: true,
    grade_band: "8º e 9º ano"
  });

  assert.deepEqual(Object.keys(stored), PERSISTED_CONTEXT_FIELDS);
  assert.equal(stored.group_size, 3);
  assert.equal("authorization_verified" in stored, false);
  assert.equal("grade_band" in stored, false);
});

test("contexto salvo ignora campos antigos e reinicia valores inválidos", () => {
  const restored = sanitizeStoredContext({
    site_id: "Sobradinho-BA",
    group_size: "inválido",
    authorization_verified: true,
    grade_band: "legado"
  });

  assert.equal(restored.site_id, "Sobradinho-BA");
  assert.equal(restored.group_size, 2);
  assert.equal("authorization_verified" in restored, false);
  assert.equal("grade_band" in restored, false);
});

test("pré-oficina do simulador não solicita nem envia idade", () => {
  const pageSource = fs.readFileSync(
    new URL("../app/page.jsx", import.meta.url),
    "utf8"
  );

  assert.equal(pageSource.includes("Qual a sua idade?"), false);
  assert.equal(pageSource.includes("student_age"), false);
});

test("sessão solo (1 aluno) é completa com 1 pre, 2 checkpoints e 1 post", () => {
  const soloTimeline = [
    { event_type: "session_started", details: { participant_count: 1 } },
    { event_type: "checkpoint_completed" },
    { event_type: "checkpoint_completed" },
    { event_type: "session_completed" }
  ];
  const soloResponses = [
    { event_type: "pre" },
    { event_type: "checkpoint" },
    { event_type: "checkpoint" },
    { event_type: "post" }
  ];

  assert.equal(
    getQualityStatus({
      timeline: soloTimeline,
      responses: soloResponses,
      participantCount: 1
    }),
    "complete"
  );
});

test("sessão trio (3 alunos) exige cobertura completa de todos os integrantes", () => {
  const trioTimeline = [
    { event_type: "session_started", details: { participant_count: 3 } },
    { event_type: "checkpoint_completed" },
    { event_type: "checkpoint_completed" },
    { event_type: "session_completed" }
  ];
  const partialTrioResponses = [
    { event_type: "pre" },
    { event_type: "pre" },
    { event_type: "checkpoint" },
    { event_type: "checkpoint" },
    { event_type: "checkpoint" },
    { event_type: "checkpoint" },
    { event_type: "post" },
    { event_type: "post" }
  ];
  const fullTrioResponses = [
    { event_type: "pre" },
    { event_type: "pre" },
    { event_type: "pre" },
    { event_type: "checkpoint" },
    { event_type: "checkpoint" },
    { event_type: "checkpoint" },
    { event_type: "checkpoint" },
    { event_type: "checkpoint" },
    { event_type: "checkpoint" },
    { event_type: "post" },
    { event_type: "post" },
    { event_type: "post" }
  ];

  assert.equal(
    getQualityStatus({
      timeline: trioTimeline,
      responses: partialTrioResponses,
      participantCount: 3
    }),
    "needs_review"
  );

  assert.equal(
    getQualityStatus({
      timeline: trioTimeline,
      responses: fullTrioResponses,
      participantCount: 3
    }),
    "complete"
  );
});

test("simulador suporta transições alcançáveis para role_swap, activity_end e rubric", () => {
  const pageSource = fs.readFileSync(
    new URL("../app/page.jsx", import.meta.url),
    "utf8"
  );

  assert.ok(pageSource.includes('setScreen("role_swap")'));
  assert.ok(pageSource.includes('setScreen("activity_end")'));
  assert.ok(pageSource.includes('setScreen("rubric")'));
  assert.ok(pageSource.includes('emitTimeline("role_swapped"'));
  assert.ok(pageSource.includes('emitTimeline("rubric_completed"'));
  assert.ok(pageSource.includes('"individual"'));
  assert.ok(pageSource.includes('"member_3"'));
});
