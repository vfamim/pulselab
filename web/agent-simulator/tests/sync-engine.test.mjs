import test from "node:test";
import assert from "node:assert/strict";
import {
  sendEventToSupabase,
  syncSingleEvent,
  flushPendingEvents,
} from "../lib/sync-engine.js";
test("test-mode sync fails closed without touching the network even with supplied credentials", async () => {
  let requests = 0;
  const original = globalThis.fetch;
  globalThis.fetch = async () => {
    requests++;
    throw new Error("network forbidden");
  };
  try {
    await assert.rejects(
      sendEventToSupabase(
        { environment: "production" },
        "https://example.com",
        "key",
      ),
    );
    assert.equal(await syncSingleEvent({}), false);
    assert.equal((await flushPendingEvents()).disabled, true);
    assert.equal(requests, 0);
  } finally {
    globalThis.fetch = original;
  }
});
