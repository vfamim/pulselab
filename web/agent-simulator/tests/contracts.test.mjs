import assert from "node:assert/strict";
import test from "node:test";
import { CONFIG_HASH, createUuid, getQualityStatus } from "../lib/contracts.js";

test("CONFIG_HASH possui formato SHA-256 e não é placeholder fictício", () => {
  assert.match(CONFIG_HASH, /^[0-9a-f]{64}$/);
  assert.notEqual(CONFIG_HASH, "d".repeat(64));
});

test("gera identificadores no formato UUID", () => {
  assert.match(createUuid(), /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
});

test("considera completa uma sessão de oficina com dois checkpoints", () => {
  const timeline = [
    { event_type: "session_started", details: { runtime: "browser_pwa" } },
    { event_type: "checkpoint_completed" },
    { event_type: "checkpoint_completed" },
    { event_type: "session_completed" }
  ];
  const responses = [
    { event_type: "pre", response_status: "completed" },
    { event_type: "checkpoint", response_status: "completed" },
    { event_type: "checkpoint", response_status: "completed" },
    { event_type: "post", response_status: "completed" }
  ];

  assert.equal(getQualityStatus({ timeline, responses }), "complete");
});

test("mantém sessão incompleta fora do estado de sucesso", () => {
  assert.equal(getQualityStatus({ timeline: [], responses: [] }), "in_progress");
});

test("CONFIG_HASH corresponde exatamente ao SHA-256 do INSTRUMENT_MANIFEST", async () => {
  const { INSTRUMENT_MANIFEST } = await import("../lib/contracts.js");
  const crypto = await import("node:crypto");
  const calculated = crypto.createHash("sha256").update(JSON.stringify(INSTRUMENT_MANIFEST)).digest("hex");
  assert.equal(CONFIG_HASH, calculated);
});

test("TIMELINE_EVENT_TYPES inclui checkpoint_expired e help_resolved", async () => {
  const { TIMELINE_EVENT_TYPES } = await import("../lib/contracts.js");
  assert.ok(TIMELINE_EVENT_TYPES.includes("checkpoint_expired"));
  assert.ok(TIMELINE_EVENT_TYPES.includes("help_resolved"));
});

test("considera completa uma sessão de oficina rotativa sem checkpoints (apenas pré e pós)", () => {
  const timeline = [
    { event_type: "session_started", details: { runtime: "browser_pwa" } },
    { event_type: "phase_transition", details: { to_stage: 2 } },
    { event_type: "phase_transition", details: { to_stage: 3 } },
    { event_type: "phase_transition", details: { to_stage: 4 } },
    { event_type: "session_completed" }
  ];
  const responses = [
    { event_type: "pre", response_status: "completed" },
    { event_type: "post", response_status: "completed" }
  ];

  assert.equal(getQualityStatus({ timeline, responses }), "complete");
});

