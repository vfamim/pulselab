import test from "node:test";
import assert from "node:assert/strict";
import {
  resolveTargetTable,
  sanitizeEventForSupabase,
  sendEventToSupabase,
  sendSessionToSupabase,
  flushPendingEvents,
} from "../lib/sync-engine.js";

test("resolveTargetTable routes survey responses to research_events and timeline events to research_session_events", () => {
  assert.equal(resolveTargetTable({ event_type: "pre" }), "research_events");
  assert.equal(resolveTargetTable({ event_type: "checkpoint" }), "research_events");
  assert.equal(resolveTargetTable({ event_type: "post" }), "research_events");
  assert.equal(resolveTargetTable({ event_type: "session_started" }), "research_session_events");
  assert.equal(resolveTargetTable({ event_type: "activity_started" }), "research_session_events");
});

test("sanitizeEventForSupabase cleans internal keys and fills required contextual fields", () => {
  const raw = {
    _internal: "drop-me",
    event_id: "evt-1",
    occurred_at: 1727827200000,
  };
  const sanitized = sanitizeEventForSupabase(raw, {
    site: "site-a",
    school: "school-b",
    workshop: "ws-c",
    class: "cl-d",
    group_id: "grp-1",
  });

  assert.equal(sanitized._internal, undefined);
  assert.equal(sanitized.event_id, "evt-1");
  assert.equal(sanitized.site_id, "site-a");
  assert.equal(sanitized.school_code, "school-b");
  assert.equal(sanitized.workshop_code, "ws-c");
  assert.equal(sanitized.class_code, "cl-d");
  assert.equal(sanitized.group_id, "grp-1");
  assert.equal(sanitized.occurred_at, new Date(1727827200000).toISOString());
});

test("sendEventToSupabase posts with correct endpoint and headers", async () => {
  let capturedUrl = "";
  let capturedHeaders = {};
  let capturedBody = null;

  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (url, options) => {
    capturedUrl = url;
    capturedHeaders = options.headers;
    capturedBody = JSON.parse(options.body);
    return {
      ok: true,
      status: 201,
      text: async () => "[]",
    };
  };

  try {
    const success = await sendEventToSupabase({
      event_id: "evt-123",
      event_type: "session_started",
      occurred_at: "2026-10-01T21:40:00Z",
    });

    assert.equal(success, true);
    assert.match(capturedUrl, /\/rest\/v1\/research_session_events\?on_conflict=event_id/);
    assert.equal(capturedHeaders["Content-Type"], "application/json");
    assert.equal(capturedBody.event_id, "evt-123");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("sendSessionToSupabase posts session snapshot to research_bancada_sessions", async () => {
  let capturedUrl = "";
  let capturedBody = null;

  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (url, options) => {
    capturedUrl = url;
    capturedBody = JSON.parse(options.body);
    return {
      ok: true,
      status: 201,
      text: async () => "[]",
    };
  };

  try {
    const session = {
      id: "sess-abc",
      group_id: "grp-xyz",
      context: { site: "site-1", school: "school-1", workshop: "ws-1", class: "class-1" },
      group_size: 2,
      phase: "activity",
      created_at: 1727827200000,
      updated_at: 1727827200000,
      events: [],
    };

    const success = await sendSessionToSupabase(session);

    assert.equal(success, true);
    assert.match(capturedUrl, /\/rest\/v1\/research_bancada_sessions\?on_conflict=session_id/);
    assert.equal(capturedBody.session_id, "sess-abc");
    assert.equal(capturedBody.group_id, "grp-xyz");
  } finally {
    globalThis.fetch = originalFetch;
  }
});
