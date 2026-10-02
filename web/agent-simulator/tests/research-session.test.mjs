import test from "node:test";
import assert from "node:assert/strict";
import {
  createSession,
  addEvent,
  saveResponse,
  openCheckpoint,
  changeRoles,
  requestHelp,
  progressHelp,
  finishSession,
  sessionQuality,
  exportSession,
} from "../lib/research-session.js";
import { INSTRUMENT, instrumentHash, questionsFor } from "../lib/protocol.js";
const context = {
  site: "S01",
  school: "E01",
  workshop: "O01",
  class: "T01",
  instructor: "I01",
  grade_band: "fundamental-2",
  platform: "spike",
  group_size: 2,
};
const answers = (phase, size = 2, skip = false) =>
  Object.fromEntries(
    questionsFor(phase, size).map((q) => [q.id, skip ? null : q.options[0][0]]),
  );
const rubric = {
  successful_trials: 2,
  explanation: 2,
  interventions: 7,
  main_issue: "sensor",
  next_action: "repeat_sensor",
  setup_minutes: 5,
};

test("does not create records without every individual assent or usable context", async () => {
  await assert.rejects(createSession(context, [true, false]));
  await assert.rejects(createSession(context, [true]));
  await assert.rejects(
    createSession({ ...context, school: "geral" }, [true, true]),
  );
});
test("stable group identity, actual group size and instrument hash survive roles", async () => {
  let s = await createSession(context, [true, true], 1000);
  const id = s.group_id;
  s = saveResponse(s, "pre", answers("pre"), null, 2000);
  s = changeRoles(
    s,
    [
      { slot: "A", role: "assembly" },
      { slot: "B", role: "computer" },
    ],
    3000,
  );
  assert.equal(s.group_id, id);
  assert.equal(s.group_size, 2);
  assert.equal(s.responses.pre.group_id, id);
  assert.equal(s.instrument_hash, await instrumentHash());
  assert.deepEqual(exportSession(s).instrument, INSTRUMENT);
});
test("manual checkpoints preserve real time and expose deviations", async () => {
  let s = await createSession(context, [true, true], 1000);
  s = saveResponse(s, "pre", answers("pre"), null, 2000);
  s = openCheckpoint(s, 20, "manual_test", 4000);
  assert.equal(s.events.at(-1).elapsed_ms, 2000);
  assert.equal(s.events.at(-1).details.early_ms, 1198000);
  assert.equal(sessionQuality(s).timing_deviations, 1);
});
test("declined answers complete procedure without inflating analytical coverage", async () => {
  let s = await createSession(context, [true, true]);
  s = saveResponse(s, "pre", answers("pre", 2, true));
  s.phase = "post";
  s = saveResponse(s, "post", answers("post", 2, true));
  s = finishSession(s, rubric);
  const q = sessionQuality(s);
  assert.equal(q.operational, "completed");
  assert.equal(q.coverage, 0);
  assert.ok(q.declined > 0);
  assert.equal(q.outcome_available, true);
  assert.deepEqual(q.missing_phases, ["checkpoint_20", "checkpoint_40"]);
  assert.equal(q.eligible_for_research, false);
});
test("no consensus is not an ordinal response and individual mode omits collaboration", async () => {
  let s = await createSession(context, [true, true]);
  s = saveResponse(s, "pre", {
    ...answers("pre"),
    group_confidence: "no_consensus",
  });
  assert.equal(sessionQuality(s).no_consensus, 1);
  assert.equal(
    questionsFor("checkpoint", 1).some(
      (q) => q.id === "participation_opportunity",
    ),
    false,
  );
});
test("help lifecycle cannot resolve a request before service starts", async () => {
  let s = await createSession(context, [true, true], 1000);
  s = requestHelp(s, 2000);
  const id = s.help[0].id;
  assert.throws(() => progressHelp(s, id, "resolved", 3000));
  s = progressHelp(s, id, "acknowledged", 3000);
  s = progressHelp(s, id, "started", 4000);
  s = progressHelp(s, id, "resolved", 5000);
  assert.equal(s.help[0].started_at - s.help[0].requested_at, 2000);
  assert.equal(sessionQuality(s).open_help, 0);
});
test("rubric is required and success score is independent of assistance", async () => {
  const s = await createSession(context, [true, true]);
  assert.throws(() => finishSession(s, rubric));
  s.phase = "rubric";
  assert.throws(() => finishSession(s, { ...rubric, explanation: null }));
  assert.equal(
    finishSession(s, rubric).rubric.successful_trials,
    finishSession(s, { ...rubric, interventions: 0 }).rubric.successful_trials,
  );
});
test("response sequence rejects duplicate and out-of-phase answers", async () => {
  let s = await createSession(context, [true, true]);
  assert.throws(() => saveResponse(s, "post", answers("post")));
  s = saveResponse(s, "pre", answers("pre"));
  assert.throws(() => saveResponse(s, "pre", answers("pre")));
});

test("form latency is measured from its prompt, not the last support event", async () => {
  let s = await createSession(context, [true, true], 1000);
  s = addEvent(s, "session_started", {}, 1500);
  s = saveResponse(s, "pre", answers("pre"), null, 3000);
  assert.equal(s.responses.pre.prompted_at, 1000);
  assert.equal(
    s.events.find((e) => e.event_type === "response_recorded").details
      .response_latency_ms,
    2000,
  );
  s = { ...s, phase: "post", form_prompted_at: 5000 };
  s = requestHelp(s, 7000);
  s = saveResponse(s, "post", answers("post"), null, 10000);
  assert.equal(s.events.at(-1).details.response_latency_ms, 5000);
});
