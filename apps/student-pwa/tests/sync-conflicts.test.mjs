import assert from "node:assert/strict";
import test from "node:test";
import { isUniqueViolationConflict, sendEventToSupabase } from "../lib/sync-engine.js";

const sampleBody23505 = JSON.stringify({
  code: "23505",
  message: "duplicate key value violates unique constraint 'research_events_pkey'",
  details: "Key (event_id)=(11111111-1111-4111-8111-111111111111) already exists."
});

test("isUniqueViolationConflict reconhece código 23505 como duplicata idempotente", () => {
  assert.equal(isUniqueViolationConflict(409, sampleBody23505), true);
});

test("isUniqueViolationConflict rejeita conflitos relacionais que não sejam unique_violation", () => {
  // 23503 é foreign_key_violation
  const bodyFk = JSON.stringify({
    code: "23503",
    message: "insert or update on table 'research_events' violates foreign key constraint",
    details: "Key (installation_id)=(...) is not present in table 'device_installations'."
  });
  assert.equal(isUniqueViolationConflict(409, bodyFk), false);

  // 23514 é check_violation
  const bodyCheck = JSON.stringify({
    code: "23514",
    message: "new row for relation 'research_events' violates check constraint",
    details: "Failing row contains (...)"
  });
  assert.equal(isUniqueViolationConflict(409, bodyCheck), false);

  // Não é status 409
  assert.equal(isUniqueViolationConflict(400, sampleBody23505), false);
  assert.equal(isUniqueViolationConflict(500, sampleBody23505), false);
});

test("isUniqueViolationConflict rejeita 23505 quando a constraint violada não é a chave esperada", () => {
  // Violação de constraint de unicidade em outro campo que não é a PK esperada (ex: dyad_id)
  const bodyOtherUnique = JSON.stringify({
    code: "23505",
    message: "duplicate key value violates unique constraint 'research_events_dyad_id_key'",
    details: "Key (dyad_id)=(99999999-9999-4999-8999-999999999999) already exists."
  });
  assert.equal(isUniqueViolationConflict(409, bodyOtherUnique, "event_id"), false);
});

test("sendEventToSupabase aceita 23505 como duplicata mas lança erro em outros 409", async () => {
  const originalFetch = globalThis.fetch;
  try {
    // 1. Simula 409 com duplicata comprovada 23505
    globalThis.fetch = async () => ({
      ok: false,
      status: 409,
      text: async () => JSON.stringify({
        code: "23505",
        message: "Key (event_id)=(abc) already exists."
      })
    });

    const dupResult = await sendEventToSupabase({
      event_id: "abc",
      event_type: "session_started",
      session_id: "s1"
    });
    assert.deepEqual(dupResult, { success: true, duplicate: true });

    // 2. Simula 409 com foreign_key_violation 23503
    globalThis.fetch = async () => ({
      ok: false,
      status: 409,
      text: async () => JSON.stringify({
        code: "23503",
        message: "foreign key violation"
      })
    });

    await assert.rejects(
      async () => {
        await sendEventToSupabase({
          event_id: "xyz",
          event_type: "session_started",
          session_id: "s1"
        });
      },
      (err) => {
        assert.equal(err.status, 409);
        return true;
      }
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("syncSingleEvent: integração de sucesso, offline e 4xx quarentena", async () => {
  const { syncSingleEvent } = await import("../lib/sync-engine.js");
  const originalFetch = globalThis.fetch;

  try {
    // 1. Cenário de sucesso (HTTP 201) -> result.success === true
    globalThis.fetch = async () => ({
      ok: true,
      status: 201,
      text: async () => ""
    });

    const successResult = await syncSingleEvent(
      { event_id: "ev-ok-1", event_type: "session_started", session_id: "s-1" },
      { force: true, key: "op-token" }
    );
    assert.equal(successResult.success, true);
    assert.equal(successResult.duplicate, false);

    // 2. Cenário offline / falha de rede -> result.success === false, result.offline === true
    globalThis.fetch = async () => {
      throw new Error("Failed to fetch (network error)");
    };

    const offlineResult = await syncSingleEvent(
      { event_id: "ev-offline-1", event_type: "session_started", session_id: "s-1" },
      { force: true, key: "op-token" }
    );
    assert.equal(offlineResult.success, false);
    assert.equal(offlineResult.offline, true);
    assert.ok(offlineResult.error);

    // 3. Cenário de erro 4xx definitivo (HTTP 400 Bad Request) -> quarentena imediata
    globalThis.fetch = async () => ({
      ok: false,
      status: 400,
      text: async () => "Bad request column mismatch"
    });

    const quarantineResult = await syncSingleEvent(
      { event_id: "ev-4xx-1", event_type: "session_started", session_id: "s-1" },
      { force: true, key: "op-token" }
    );
    assert.equal(quarantineResult.success, false);
    assert.equal(quarantineResult.quarantined, true);
    assert.ok(quarantineResult.error);
    assert.equal(quarantineResult.error.status, 400);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("isUniqueViolationConflict rejeita PK de tabela não relacionada", () => {
  const bodyUnrelatedPk = JSON.stringify({
    code: "23505",
    message: "duplicate key value violates unique constraint 'unrelated_table_pkey'",
    details: "Key (id)=(12345) already exists."
  });
  assert.equal(isUniqueViolationConflict(409, bodyUnrelatedPk, "event_id"), false);

  const bodySchoolPk = JSON.stringify({
    code: "23505",
    message: "duplicate key value violates unique constraint 'schools_pkey'",
    details: "Key (school_id)=(99) already exists."
  });
  assert.equal(isUniqueViolationConflict(409, bodySchoolPk, "session_id"), false);
});

test("flushPendingEvents repassa url e key explicitamente sem cair na anon key", async () => {
  const { flushPendingEvents, DEFAULT_SUPABASE_ANON_KEY } = await import("../lib/sync-engine.js");
  const originalFetch = globalThis.fetch;
  const capturedCalls = [];

  try {
    globalThis.fetch = async (url, options) => {
      capturedCalls.push({ url, headers: options.headers });
      return {
        ok: true,
        status: 201,
        text: async () => ""
      };
    };

    const mockPendingEvents = [
      { event_id: "ev-jwt-1", event_type: "session_started", session_id: "s-jwt-1" }
    ];

    const customUrl = "https://custom-instance.supabase.co";
    const operationalJwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoib3BlcmF0aW9uYWwifQ.test";

    const res = await flushPendingEvents({
      url: customUrl,
      key: operationalJwt,
      force: true,
      pendingEvents: mockPendingEvents
    });

    assert.equal(res.synced, 1);
    assert.equal(capturedCalls.length, 1);
    assert.ok(capturedCalls[0].url.startsWith(customUrl));
    assert.equal(capturedCalls[0].headers.apikey, operationalJwt);
    assert.equal(capturedCalls[0].headers.Authorization, `Bearer ${operationalJwt}`);
    assert.notEqual(capturedCalls[0].headers.apikey, DEFAULT_SUPABASE_ANON_KEY);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
