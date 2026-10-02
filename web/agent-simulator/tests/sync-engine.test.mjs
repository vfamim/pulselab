import assert from "node:assert/strict";
import test from "node:test";
import {
  sanitizeEventForSupabase,
  resolveTargetTable
} from "../lib/sync-engine.js";

test("resolve target table correctly for responses vs timeline events", () => {
  assert.equal(resolveTargetTable({ event_type: "pre" }), "research_events");
  assert.equal(resolveTargetTable({ event_type: "checkpoint" }), "research_events");
  assert.equal(resolveTargetTable({ event_type: "post" }), "research_events");
  assert.equal(resolveTargetTable({ event_type: "session_started" }), "research_session_events");
  assert.equal(resolveTargetTable({ event_type: "spike_telemetry" }), "research_session_events");
  assert.equal(
    resolveTargetTable({ event_type: "pre", _target_table: "custom_table" }),
    "custom_table"
  );
});

test("sanitizeEventForSupabase strips all underscore-prefixed metadata fields", () => {
  const input = {
    event_id: "1234",
    session_id: "5678",
    _delivery_state: "queued",
    _sequence: 1,
    _client_occurred_at: "2026-09-12T21:00:00Z",
    _target_table: "research_session_events",
    details: { foo: "bar" }
  };

  const output = sanitizeEventForSupabase(input);
  assert.equal(output.event_id, "1234");
  assert.equal(output.session_id, "5678");
  assert.deepEqual(output.details, { foo: "bar" });
  assert.equal(output._delivery_state, undefined);
  assert.equal(output._sequence, undefined);
  assert.equal(output._client_occurred_at, undefined);
  assert.equal(output._target_table, undefined);
});

test("student-store exports listPendingEvents and pruneDeliveredEvents", async () => {
  const store = await import("../lib/student-store.js");
  assert.equal(typeof store.listPendingEvents, "function");
  assert.equal(typeof store.pruneDeliveredEvents, "function");
});

