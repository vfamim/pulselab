import test from "node:test";
import assert from "node:assert/strict";
import {
  CONFIG_HASH,
  TIMELINE_EVENT_TYPES,
  getQualityStatus
} from "../lib/contracts.js";

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

test("contrato web cobre os tipos da linha do tempo 1.4", () => {
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
