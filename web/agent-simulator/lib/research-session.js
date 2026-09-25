import {
  INSTRUMENT,
  PROTOCOL_VERSION,
  instrumentHash,
  questionsFor,
  validateAnswers,
} from "./protocol.js";

export const ENVIRONMENT = "test"; // This branch cannot opt into production via URL/localStorage.
export const RETENTION_MS = INSTRUMENT.retention_days * 86400000;
const CODE_FIELDS = ["site", "school", "workshop", "class", "instructor"];

export function validContext(context) {
  return (
    CODE_FIELDS.every(
      (key) =>
        /^[A-Za-z0-9_-]{2,40}$/.test(context[key] || "") &&
        !/^(geral|turma-geral|CONFIGURE.*)$/i.test(context[key]),
    ) &&
    ["fundamental-1", "fundamental-2", "mixed-test"].includes(
      context.grade_band,
    ) &&
    ["spike", "other"].includes(context.platform) &&
    Number.isInteger(context.group_size) &&
    context.group_size >= 1 &&
    context.group_size <= 4
  );
}

export async function createSession(context, assents, now = Date.now()) {
  if (
    !validContext(context) ||
    assents.length !== context.group_size ||
    !assents.every((a) => a === true)
  ) {
    throw new Error(
      "Contexto completo e aceite de cada integrante são necessários.",
    );
  }
  return {
    id: crypto.randomUUID(),
    group_id: crypto.randomUUID(),
    environment: ENVIRONMENT,
    protocol_version: PROTOCOL_VERSION,
    instrument_version: INSTRUMENT.version,
    instrument_hash: await instrumentHash(),
    instrument: structuredClone(INSTRUMENT),
    activity: INSTRUMENT.activity,
    context: structuredClone(context),
    group_size: context.group_size,
    unit: "group",
    consent: assents.map((accepted, index) => ({
      slot: String.fromCharCode(65 + index),
      accepted,
    })),
    created_at: now,
    updated_at: now,
    expires_at: now + RETENTION_MS,
    phase: "pre",
    form_prompted_at: now,
    activity_started_at: null,
    responses: {},
    events: [],
    help: [],
    roles: Array.from({ length: context.group_size }, (_, i) => ({
      slot: String.fromCharCode(65 + i),
      role: "shared",
    })),
    rubric: null,
    artifacts: [],
    checkpoint_opened_at: null,
    completed_at: null,
  };
}

export function addEvent(session, type, details = {}, now = Date.now()) {
  if (
    !session?.consent?.every((c) => c.accepted) ||
    session.environment !== ENVIRONMENT
  )
    throw new Error("Coleta não autorizada.");
  const event = {
    event_id: crypto.randomUUID(),
    session_id: session.id,
    group_id: session.group_id,
    environment: ENVIRONMENT,
    unit: "group",
    event_type: type,
    occurred_at: now,
    elapsed_ms: session.activity_started_at
      ? Math.max(0, now - session.activity_started_at)
      : null,
    sequence: session.events.length + 1,
    details,
  };
  return { ...session, updated_at: now, events: [...session.events, event] };
}

export function saveResponse(
  session,
  phase,
  answers,
  mark = null,
  now = Date.now(),
) {
  if (session.phase !== (phase === "checkpoint" ? `checkpoint_${mark}` : phase))
    throw new Error("Etapa inválida.");
  if (!validateAnswers(phase, session.group_size, answers))
    throw new Error("Responda ou pule cada pergunta.");
  const key = phase === "checkpoint" ? `checkpoint_${mark}` : phase;
  if (session.responses[key]) throw new Error("Etapa já registrada.");
  const promptedAt =
    phase === "checkpoint"
      ? session.checkpoint_opened_at
      : session.form_prompted_at;
  const cleanAnswers = Object.fromEntries(
    questionsFor(phase, session.group_size).map((q) => [q.id, answers[q.id]]),
  );
  let next = addEvent(
    session,
    "response_recorded",
    {
      phase,
      mark,
      answers: cleanAnswers,
      response_latency_ms: Math.max(0, now - promptedAt),
    },
    now,
  );
  next.responses = {
    ...session.responses,
    [key]: {
      answers: cleanAnswers,
      responded_at: now,
      prompted_at: promptedAt,
      group_id: session.group_id,
    },
  };
  next.phase = phase === "post" ? "rubric" : "activity";
  if (phase === "pre") {
    next.activity_started_at = now;
    next = addEvent(next, "activity_started", {}, now);
  }
  return next;
}

export function openCheckpoint(
  session,
  mark,
  trigger = "scheduled",
  now = Date.now(),
) {
  if (
    session.phase !== "activity" ||
    !INSTRUMENT.checkpoints_minutes.includes(mark) ||
    session.responses[`checkpoint_${mark}`]
  )
    throw new Error("Checkpoint indisponível.");
  const scheduledAt = session.activity_started_at + mark * 60000;
  return {
    ...addEvent(
      session,
      "checkpoint_prompted",
      {
        mark,
        trigger,
        scheduled_at: scheduledAt,
        prompted_at: now,
        lateness_ms: Math.max(0, now - scheduledAt),
        early_ms: Math.max(0, scheduledAt - now),
      },
      now,
    ),
    phase: `checkpoint_${mark}`,
    checkpoint_opened_at: now,
  };
}

export function changeRoles(session, roles, now = Date.now()) {
  const allowed = ["computer", "assembly", "testing", "shared"];
  if (
    roles.length !== session.group_size ||
    roles.some(
      (r, i) => r.slot !== session.consent[i].slot || !allowed.includes(r.role),
    )
  )
    throw new Error("Papéis inválidos.");
  return {
    ...addEvent(session, "roles_confirmed", { roles }, now),
    roles: structuredClone(roles),
  };
}

export function requestHelp(session, now = Date.now()) {
  if (session.help.some((h) => h.status !== "resolved")) return session;
  const help = {
    id: crypto.randomUUID(),
    requested_at: now,
    status: "requested",
  };
  return {
    ...addEvent(session, "help_requested", { help_id: help.id }, now),
    help: [...session.help, help],
  };
}

export function progressHelp(session, id, status, now = Date.now()) {
  const nextStatus = {
    requested: "acknowledged",
    acknowledged: "started",
    started: "resolved",
  };
  const help = session.help.find((h) => h.id === id);
  if (!help || nextStatus[help.status] !== status)
    throw new Error("Transição de ajuda inválida.");
  return {
    ...addEvent(session, `help_${status}`, { help_id: id }, now),
    help: session.help.map((h) =>
      h.id === id ? { ...h, status, [`${status}_at`]: now } : h,
    ),
  };
}

export function finishSession(session, rubric, now = Date.now()) {
  if (session.phase !== "rubric")
    throw new Error("Conclua a etapa final primeiro.");
  if (
    ![rubric.successful_trials, rubric.explanation].every(
      (n) => Number.isInteger(n) && n >= 0 && n <= 3,
    ) ||
    !Number.isInteger(rubric.interventions) ||
    rubric.interventions < 0 ||
    rubric.interventions > 100 ||
    ![
      "none",
      "technical",
      "assembly",
      "logic",
      "sensor",
      "participation",
    ].includes(rubric.main_issue) ||
    ![
      "repeat_sensor",
      "revise_instruction",
      "more_time",
      "redistribute_roles",
      "no_change",
    ].includes(rubric.next_action) ||
    !Number.isInteger(rubric.setup_minutes) ||
    rubric.setup_minutes < 0 ||
    rubric.setup_minutes > 180
  )
    throw new Error("Preencha a rubrica e a devolutiva.");
  const next = addEvent(session, "rubric_recorded", rubric, now);
  return {
    ...addEvent(next, "session_completed", {}, now),
    rubric: structuredClone(rubric),
    phase: "finished",
    completed_at: now,
  };
}

export function sessionQuality(session) {
  const keys = ["pre", "checkpoint_20", "checkpoint_40", "post"];
  let answered = 0,
    declined = 0,
    noConsensus = 0,
    expected = 0;
  for (const key of keys) {
    const phase = key.startsWith("checkpoint") ? "checkpoint" : key;
    expected += questionsFor(phase, session.group_size).length;
    for (const v of Object.values(session.responses[key]?.answers || {})) {
      if (v === null) declined++;
      else if (v === "no_consensus") noConsensus++;
      else answered++;
    }
  }
  return {
    operational: session.completed_at ? "completed" : "in_progress",
    consent: "all_accepted",
    answered,
    declined,
    no_consensus: noConsensus,
    expected,
    coverage: expected ? answered / expected : 0,
    missing_phases: keys.filter((k) => !session.responses[k]),
    outcome_available: Boolean(session.rubric),
    artifacts_available: session.artifacts.length,
    open_help: session.help.filter((h) => h.status !== "resolved").length,
    timing_deviations: session.events.filter(
      (e) =>
        e.event_type === "checkpoint_prompted" &&
        (e.details.trigger !== "scheduled" || e.details.lateness_ms > 120000),
    ).length,
    eligible_for_research: false,
    reason: "test_environment_and_unvalidated_instrument",
  };
}

export function exportSession(session) {
  return {
    schema_version: 2,
    environment: ENVIRONMENT,
    exported_at: new Date().toISOString(),
    limitations: [
      "Dados de teste; não usar como resultado de pesquisa.",
      "Unidade: bancada. Não inferir aprendizagem individual ou efeito causal.",
      "Instrumento e itens de conhecimento ainda não validados.",
    ],
    instrument: session.instrument,
    quality: sessionQuality(session),
    session,
  };
}
