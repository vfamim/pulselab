"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import {
  CONFIG_HASH,
  PARTICIPANTS,
  createUuid,
  formatEventName,
  getQualityStatus,
  qualityLabel,
  roleLabel
} from "../lib/contracts.js";
import {
  STORED_CONTEXT_KEY,
  createStoredContext,
  sanitizeStoredContext
} from "../lib/context-storage.js";

const DEFAULT_CONTEXT = {
  site_id: "Juazeiro-BA",
  regional_hub: "Polo-São-Francisco",
  school_code: "ESCOLA-DEMO-01",
  workshop_code: "OFICINA-DEMO-001",
  class_code: "TURMA-DEMO-A",
  group_size: 2,
  activity_id: "atividade-01-spike",
  authorization_verified: false
};

const PRE_DEFAULT = {
  prior_robotics: null,
  self_efficacy_pre: null
};

const CHECKPOINT_DEFAULT = {
  self_reported_role: null,
  mental_effort: null,
  progress_state: "",
  collaboration: null
};

const POST_DEFAULT = {
  post_understanding: null,
  post_affects: [],
  post_return_intent: null
};

const RUBRIC_DEFAULT = {
  mission_performance: null,
  instructor_interventions: null,
  primary_issue: ""
};

const INITIAL_SESSION_ID = "00000000-0000-4000-8000-000000000001";
const INITIAL_DYAD_ID = "00000000-0000-4000-8000-000000000002";

const SCENARIOS = {
  standard: {
    label: "Fluxo padrão",
    description: "SPIKE detectado, evidência disponível e relógio dentro do limite."
  },
  late: {
    label: "Checkpoint atrasado",
    description: "A captura ocorre 3 min e 5 s depois do horário previsto."
  },
  missing_spike: {
    label: "SPIKE ausente",
    description: "A janela não é encontrada e a captura visual falha."
  },
  offline: {
    label: "Queda de rede",
    description: "Eventos ficam na fila local até a sincronização manual."
  }
};

const FLOW_STEPS = [
  { id: 1, label: "Contexto" },
  { id: 2, label: "Assentimento" },
  { id: 3, label: "Pré-oficina" },
  { id: 4, label: "Atividade" },
  { id: 5, label: "Encerramento" },
  { id: 6, label: "Revisão" }
];

const SCREEN_STEP = {
  context: 1,
  assent_a: 2, assent_b: 2, assent_c: 2, assent_d: 2, declined: 2,
  pre_a: 3, pre_b: 3, pre_c: 3, pre_d: 3,
  activity: 4,
  checkpoint_a: 4, checkpoint_b: 4, checkpoint_c: 4, checkpoint_d: 4, role_swap: 4,
  activity_end: 5, rubric: 5,
  post_a: 5, post_b: 5, post_c: 5, post_d: 5,
  summary: 6
};

const PROGRESS_OPTIONS = [
  {
    value: "progressing_independently",
    title: "Avançando sem ajuda",
    description: "Estamos conseguindo seguir sem ajuda."
  },
  {
    value: "progressing_with_doubt",
    title: "Avançando, mas com dúvida",
    description: "Estamos progredindo, mas ainda inseguros."
  },
  {
    value: "trying_without_progress",
    title: "Tentando, mas sem conseguir avançar",
    description: "Já tentamos caminhos, mas continuamos no mesmo ponto."
  },
  {
    value: "needs_help_now",
    title: "Precisamos de ajuda agora",
    description: "Queremos chamar o instrutor."
  }
];

const AFFECTS = [
  ["curious", "Curioso"],
  ["confident", "Confiante"],
  ["excited", "Animado"],
  ["frustrated", "Frustrado"],
  ["tired", "Cansado"],
  ["indifferent", "Indiferente"]
];

function LogoMark() {
  return (
    <svg viewBox="0 0 48 48" aria-hidden="true">
      <path d="M13 8h22a5 5 0 0 1 5 5v22a5 5 0 0 1-5 5H13a5 5 0 0 1-5-5V13a5 5 0 0 1 5-5Z" />
      <path d="M16 18h16M16 24h10M16 30h16" />
      <circle cx="34" cy="24" r="3" />
    </svg>
  );
}

function roleIcon(role) {
  return role === "computer" ? "⌘" : "⬡";
}

function formatElapsed(milliseconds) {
  const totalSeconds = Math.max(0, Math.round(milliseconds / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
}

function statusTone(status) {
  if (status === "complete") return "success";
  if (status === "needs_review") return "warning";
  if (status === "aborted") return "danger";
  return "neutral";
}

function FormShell({ eyebrow, title, description, children, footer, compact = false }) {
  return (
    <section className={`flow-card ${compact ? "flow-card--compact" : ""}`}>
      <div className="flow-card__heading">
        <span className="eyebrow">{eyebrow}</span>
        <h1>{title}</h1>
        {description ? <p>{description}</p> : null}
      </div>
      <div className="flow-card__body">{children}</div>
      {footer ? <div className="flow-card__footer">{footer}</div> : null}
    </section>
  );
}

function ParticipantBadge({ participantKey }) {
  const p = PARTICIPANTS[participantKey] || { label: `Aluno ${participantKey}` };
  return (
    <div className="participant-badge">
      <span className="participant-badge__avatar">{participantKey}</span>
      <span>
        <strong>{p.label}</strong>
      </span>
    </div>
  );
}

function ScaleQuestion({ title, description, value, onChange, labels, values, icons }) {
  const columns = labels.length === 3 ? 3 : 4;
  return (
    <fieldset className="question-block">
      <legend>{title}</legend>
      {description ? <p>{description}</p> : null}
      <div className="scale-grid" style={{ gridTemplateColumns: `repeat(${columns}, 1fr)` }}>
        {labels.map((label, index) => {
          const optionValue = values ? values[index] : index + 1;
          const icon = icons ? icons[index] : null;
          return (
            <button
              key={label}
              type="button"
              className={`scale-option ${value === optionValue ? "is-selected" : ""}`}
              onClick={() => onChange(optionValue)}
              aria-pressed={value === optionValue}
            >
              <span>{icon || optionValue}</span>
              <small>{label}</small>
            </button>
          );
        })}
      </div>
    </fieldset>
  );
}

function ActionRow({ children }) {
  return <div className="action-row">{children}</div>;
}

export default function AgentSimulatorPage() {
  const [screen, setScreen] = useState("context");
  const [context, setContext] = useState(DEFAULT_CONTEXT);
  const [scenario, setScenario] = useState("standard");
  const [online, setOnline] = useState(true);
  const [installationId, setInstallationId] = useState("carregando-instalação");
  const [sessionId, setSessionId] = useState(INITIAL_SESSION_ID);
  const [dyadId, setDyadId] = useState(INITIAL_DYAD_ID);
  const [startedAt, setStartedAt] = useState(0);
  const [timeline, setTimeline] = useState([]);
  const [responses, setResponses] = useState([]);
  const [selectedEvent, setSelectedEvent] = useState(null);
  const [eventFilter, setEventFilter] = useState("timeline");
  const [elapsedMs, setElapsedMs] = useState(0);
  const [lastHeartbeatMinute, setLastHeartbeatMinute] = useState(0);
  const [currentMark, setCurrentMark] = useState(20);
  const [roles, setRoles] = useState({ A: "computer", B: "assembly" });
  const [preAnswers, setPreAnswers] = useState(PRE_DEFAULT);
  const [checkpointAnswers, setCheckpointAnswers] = useState(CHECKPOINT_DEFAULT);
  const [checkpointEvidence, setCheckpointEvidence] = useState(null);
  const [postAnswers, setPostAnswers] = useState(POST_DEFAULT);
  const [rubric, setRubric] = useState(RUBRIC_DEFAULT);
  const [savedRubric, setSavedRubric] = useState(RUBRIC_DEFAULT);
  const [assentA, setAssentA] = useState(false);
  const [toast, setToast] = useState("");
  const [contextStorageReady, setContextStorageReady] = useState(false);
  const toastTimer = useRef(null);
  const sequence = useRef(0);

  useEffect(() => {
    const storageKey = "pulselab-simulator-installation-id";
    let stored = window.localStorage.getItem(storageKey);
    if (!stored) {
      stored = createUuid();
      window.localStorage.setItem(storageKey, stored);
    }
    setInstallationId(stored);
    setSessionId(createUuid());
    setDyadId(createUuid());
    setStartedAt(Date.now());

    const storedContextRaw = window.localStorage.getItem(STORED_CONTEXT_KEY);
    if (storedContextRaw) {
      try {
        const parsed = JSON.parse(storedContextRaw);
        setContext((current) => ({
          ...current,
          ...sanitizeStoredContext(parsed),
          authorization_verified: false
        }));
      } catch (e) {}
    }
    setContextStorageReady(true);
  }, []);

  useEffect(() => {
    if (!contextStorageReady) return;
    try {
      window.localStorage.setItem(
        STORED_CONTEXT_KEY,
        JSON.stringify(createStoredContext(context))
      );
    } catch (e) {}
  }, [context, contextStorageReady]);

  useEffect(() => {
    return () => {
      if (toastTimer.current) window.clearTimeout(toastTimer.current);
    };
  }, []);

  const qualityStatus = useMemo(
    () => getQualityStatus({ timeline, responses }),
    [timeline, responses]
  );

  const queuedCount = useMemo(
    () =>
      [...timeline, ...responses].filter(
        (event) => event._delivery_state === "queued"
      ).length,
    [timeline, responses]
  );

  const visibleEvents = useMemo(() => {
    const combined = [...timeline, ...responses].sort(
      (left, right) => left._sequence - right._sequence
    );
    if (eventFilter === "all") return combined;
    if (eventFilter === "responses") {
      return combined.filter((event) => event._target_table === "research_events");
    }
    return combined.filter(
      (event) => event._target_table === "research_session_events"
    );
  }, [eventFilter, responses, timeline]);

  const activeStep = SCREEN_STEP[screen] || 1;
  const participantMatch = screen.match(/_(a|b|c|d)$/);
  const participantKey = participantMatch ? participantMatch[1].toUpperCase() : "A";

  const activeParticipants = useMemo(() => {
    const count = Math.max(1, Math.min(3, Number(context.group_size) || 2));
    return ["A", "B", "C"].slice(0, count);
  }, [context.group_size]);

  function getNextParticipant(currentKey) {
    const index = activeParticipants.indexOf(currentKey);
    if (index >= 0 && index < activeParticipants.length - 1) {
      return activeParticipants[index + 1];
    }
    return null;
  }

  function flash(message) {
    setToast(message);
    if (toastTimer.current) window.clearTimeout(toastTimer.current);
    toastTimer.current = window.setTimeout(() => setToast(""), 3200);
  }

  function eventBase(atMs, deliveryState) {
    sequence.current += 1;
    return {
      event_id: createUuid(),
      session_id: sessionId,
      dyad_id: dyadId,
      installation_id: installationId,
      site_id: context.site_id,
      regional_hub: context.regional_hub,
      school_code: context.school_code,
      workshop_code: context.workshop_code,
      class_code: context.class_code,
      activity_id: context.activity_id,
      computer_id: "SIMULADOR-WEB",
      protocol_version: "protocolo-pesquisa-v1",
      config_version: "1.4.0",
      config_hash: CONFIG_HASH,
      client_version: "web-simulator-1.0.0",
      occurred_at: new Date(startedAt + atMs).toISOString(),
      elapsed_ms: atMs,
      _delivery_state: deliveryState || (online ? "sent" : "queued"),
      _sequence: sequence.current
    };
  }

  function emitTimeline(eventType, options = {}) {
    const atMs = options.elapsedMs ?? elapsedMs;
    const event = {
      ...eventBase(atMs, options.deliveryState),
      _target_table: "research_session_events",
      event_type: eventType,
      severity: options.severity || "info",
      interval_mark: options.intervalMark ?? null,
      participant_id: options.participantId || null,
      participant_role: options.participantRole || null,
      activity_stage: options.activityStage || null,
      scheduled_at: options.scheduledAt || null,
      details: options.details || {}
    };
    setTimeline((current) => [...current, event]);
    setSelectedEvent(event);
    return event;
  }

  function emitResponse(participant, eventType, values, options = {}) {
    const atMs = options.elapsedMs ?? elapsedMs;
    const event = {
      ...eventBase(atMs, options.deliveryState),
      _target_table: "research_events",
      participant_id: `${sessionId.slice(0, 8).toUpperCase()}-${participant}`,
      participant_role: roles[participant],
      event_type: eventType,
      response_status: options.responseStatus || "completed",
      interval_mark: options.intervalMark ?? null,
      ...values
    };
    setResponses((current) => [...current, event]);
    setSelectedEvent(event);
    return event;
  }

  function beginSession() {
    if (installationId === "carregando-instalação" || startedAt === 0) {
      flash("O simulador ainda está preparando a identificação local.");
      return;
    }
    const required = [
      context.site_id,
      context.regional_hub,
      context.school_code,
      context.workshop_code,
      context.class_code,
      context.activity_id
    ];
    if (
      required.some((value) => !value.trim()) ||
      !context.authorization_verified
    ) {
      flash("Preencha os códigos e confirme a verificação das autorizações.");
      return;
    }
    setScreen("assent_a");
  }

  function acceptAssent(participant) {
    const nextKey = getNextParticipant(participant);
    if (nextKey) {
      setScreen(`assent_${nextKey.toLowerCase()}`);
      return;
    }

    emitTimeline("session_started", {
      elapsedMs: 0,
      details: {
        participant_count: activeParticipants.length,
        authorization_verified: true,
        assent_completed: true,
        expected_checkpoints: [20, 40],
        simulator: true
      }
    });
    setScreen("pre_a");
  }

  function declineAssent() {
    setTimeline([]);
    setResponses([]);
    setSelectedEvent(null);
    setScreen("declined");
  }

  function submitPre(responseStatus = "completed") {
    const participant = participantKey;
    if (
      responseStatus === "completed" &&
      (!preAnswers.prior_robotics || !preAnswers.self_efficacy_pre)
    ) {
      flash("Escolha uma opção em cada pergunta.");
      return;
    }
    emitResponse(
      participant,
      "pre",
      responseStatus === "completed" ? preAnswers : {},
      { responseStatus, elapsedMs: 0 }
    );
    setPreAnswers(PRE_DEFAULT);

    const nextKey = getNextParticipant(participant);
    if (nextKey) {
      setScreen(`pre_${nextKey.toLowerCase()}`);
      return;
    }

    emitTimeline("phase_completed", {
      elapsedMs: 0,
      activityStage: "pre",
      details: { phase: "pre" }
    });
    emitTimeline("activity_started", {
      elapsedMs: 0,
      details: {
        interval_marks_minutes: [20, 40],
        screenshot_enabled: true,
        simulator: true
      }
    });
    setScreen("activity");
  }

  function emitHeartbeatsUntil(mark, deliveryState) {
    for (
      let minute = lastHeartbeatMinute + 5;
      minute <= mark - 5;
      minute += 5
    ) {
      emitTimeline("heartbeat", {
        elapsedMs: minute * 60000,
        deliveryState,
        details: {
          app_category: scenario === "missing_spike" ? "unknown" : "spike",
          idle_seconds: minute % 10 === 0 ? 18 : 4,
          spike_window_detected: scenario !== "missing_spike",
          ending_requested: false,
          compressed_simulation: true
        }
      });
    }
    setLastHeartbeatMinute(mark);
  }

  function beginCheckpoint(mark) {
    const isOffline = scenario === "offline" || !online;
    const deliveryState = isOffline ? "queued" : "sent";
    const delayMs = scenario === "late" ? 185000 : 0;
    const targetMs = mark * 60000;
    const captureMs = targetMs + delayMs;
    const stage = mark === 20 ? "desenvolvimento" : "integracao-e-teste";
    const spikeDetected = scenario !== "missing_spike";
    const screenshotCaptured = spikeDetected;
    const screenshotUploaded = screenshotCaptured && !isOffline;
    const scheduledAt = new Date(startedAt + targetMs).toISOString();

    if (isOffline) setOnline(false);
    setElapsedMs(captureMs);
    emitHeartbeatsUntil(mark, deliveryState);
    emitTimeline("checkpoint_started", {
      elapsedMs: captureMs,
      deliveryState,
      intervalMark: mark,
      activityStage: stage,
      scheduledAt,
      details: {
        app_category: spikeDetected ? "spike" : "unknown",
        idle_seconds: 7,
        spike_window_detected: spikeDetected,
        screenshot_captured: screenshotCaptured,
        screenshot_uploaded: screenshotUploaded,
        lateness_ms: delayMs,
        simulator: true
      }
    });

    if (delayMs > 120000) {
      emitTimeline("quality_issue", {
        severity: "warning",
        elapsedMs: captureMs,
        deliveryState,
        intervalMark: mark,
        activityStage: stage,
        scheduledAt,
        details: {
          code: "checkpoint_late",
          lateness_ms: delayMs,
          threshold_ms: 120000
        }
      });
    }

    if (!spikeDetected) {
      emitTimeline("quality_issue", {
        severity: "warning",
        elapsedMs: captureMs,
        deliveryState,
        intervalMark: mark,
        activityStage: stage,
        scheduledAt,
        details: { code: "spike_window_not_found" }
      });
      emitTimeline("quality_issue", {
        severity: "warning",
        elapsedMs: captureMs,
        deliveryState,
        intervalMark: mark,
        activityStage: stage,
        scheduledAt,
        details: { code: "screenshot_not_captured" }
      });
    }

    setCheckpointEvidence({
      mark,
      targetMs,
      captureMs,
      delayMs,
      stage,
      scheduledAt,
      spikeDetected,
      screenshotCaptured,
      screenshotUploaded,
      deliveryState
    });
    setCheckpointAnswers(CHECKPOINT_DEFAULT);
    setScreen("checkpoint_a");
  }

  function submitCheckpoint(responseStatus = "completed") {
    const participant = participantKey;
    const collaborationRequired = currentMark === 40;
    if (
      responseStatus === "completed" &&
      (!checkpointAnswers.self_reported_role ||
        !checkpointAnswers.mental_effort ||
        !checkpointAnswers.progress_state ||
        (collaborationRequired && !checkpointAnswers.collaboration))
    ) {
      flash("Responda às perguntas exibidas antes de continuar.");
      return;
    }

    const participantOffset = participant === "A" ? 28000 : 56000;
    const responseElapsed = checkpointEvidence.captureMs + participantOffset;
    const values =
      responseStatus === "completed"
        ? {
            mental_effort: checkpointAnswers.mental_effort,
            progress_state: checkpointAnswers.progress_state,
            collaboration: collaborationRequired
              ? checkpointAnswers.collaboration
              : null,
            help_requested:
              checkpointAnswers.progress_state === "needs_help_now",
            activity_stage: checkpointEvidence.stage,
            telemetry_window_title: null,
            telemetry_foreground_app: checkpointEvidence.spikeDetected
              ? "spike"
              : "unknown",
            telemetry_idle_seconds: 7,
            telemetry_file_size_kb: currentMark === 20 ? 146.8 : 208.3,
            screenshot_path: checkpointEvidence.screenshotCaptured
              ? `${installationId}/${context.workshop_code}/${sessionId}/checkpoint-${currentMark}.jpg`
              : null,
            response_latency_ms: participantOffset,
            checkpoint_lateness_ms:
              checkpointEvidence.delayMs + participantOffset,
            scheduled_at: checkpointEvidence.scheduledAt,
            prompted_at: new Date(
              startedAt + checkpointEvidence.captureMs
            ).toISOString(),
            captured_at: new Date(
              startedAt + checkpointEvidence.captureMs
            ).toISOString()
          }
        : {
            activity_stage: checkpointEvidence.stage,
            checkpoint_lateness_ms:
              checkpointEvidence.delayMs + participantOffset,
            scheduled_at: checkpointEvidence.scheduledAt,
            prompted_at: new Date(
              startedAt + checkpointEvidence.captureMs
            ).toISOString(),
            captured_at: new Date(
              startedAt + checkpointEvidence.captureMs
            ).toISOString()
          };

    emitResponse(participant, "checkpoint", values, {
      intervalMark: currentMark,
      responseStatus,
      elapsedMs: responseElapsed,
      deliveryState: checkpointEvidence.deliveryState
    });

    if (
      responseStatus === "completed" &&
      checkpointAnswers.progress_state === "needs_help_now"
    ) {
      emitTimeline("help_requested", {
        severity: "warning",
        elapsedMs: responseElapsed,
        deliveryState: checkpointEvidence.deliveryState,
        intervalMark: currentMark,
        participantId: `${sessionId.slice(0, 8).toUpperCase()}-${participant}`,
        participantRole: roles[participant],
        activityStage: checkpointEvidence.stage,
        scheduledAt: checkpointEvidence.scheduledAt,
        details: { source: "participant_self_report" }
      });
      flash("O instrutor receberia agora um alerta de ajuda.");
    }

    setCheckpointAnswers(CHECKPOINT_DEFAULT);
    const nextKey = getNextParticipant(participant);
    if (nextKey) {
      setScreen(`checkpoint_${nextKey.toLowerCase()}`);
      return;
    }

    const completedElapsed = checkpointEvidence.captureMs + 65000;
    setElapsedMs(completedElapsed);
    emitTimeline("checkpoint_completed", {
      elapsedMs: completedElapsed,
      deliveryState: checkpointEvidence.deliveryState,
      intervalMark: currentMark,
      activityStage: checkpointEvidence.stage,
      scheduledAt: checkpointEvidence.scheduledAt,
      details: {
        participant_a_status: "recorded",
        participant_b_status: "recorded"
      }
    });

    if (currentMark === 20) {
      setCurrentMark(40);
      setScreen("activity");
    } else {
      setScreen("post_a");
    }
  }

  function confirmRoleSwap(confirmed) {
    if (confirmed) {
      const nextRoles = { A: roles.B, B: roles.A };
      setRoles(nextRoles);
      emitTimeline("role_swapped", {
        elapsedMs,
        intervalMark: 20,
        activityStage: "desenvolvimento",
        details: {
          participant_a_role: nextRoles.A,
          participant_b_role: nextRoles.B
        }
      });
      flash("Troca confirmada e registrada na linha do tempo.");
    } else {
      emitTimeline("quality_issue", {
        severity: "warning",
        elapsedMs,
        intervalMark: 20,
        activityStage: "desenvolvimento",
        details: { code: "role_swap_not_confirmed" }
      });
    }
    setCurrentMark(40);
    setScreen("activity");
  }

  function beginEnding() {
    emitTimeline("ending_requested", {
      elapsedMs,
      details: {
        requested_at: new Date(startedAt + elapsedMs).toISOString(),
        simulator: true
      }
    });
    setScreen("rubric");
  }

  function submitRubric() {
    if (
      rubric.mission_performance === null ||
      rubric.instructor_interventions === null ||
      !rubric.primary_issue
    ) {
      flash("Complete os três campos da rubrica.");
      return;
    }
    setSavedRubric(rubric);
    emitTimeline("rubric_completed", {
      elapsedMs: elapsedMs + 15000,
      details: {
        mission_performance: rubric.mission_performance,
        interventions_band: rubric.instructor_interventions,
        primary_issue: rubric.primary_issue
      }
    });
    setPostAnswers(POST_DEFAULT);
    setScreen("post_a");
  }

  function abortAtRubric() {
    emitTimeline("session_aborted", {
      severity: "warning",
      elapsedMs,
      details: { reason: "instructor_rubric_canceled", simulator: true }
    });
    setScreen("summary");
  }

  function toggleAffect(value) {
    setPostAnswers((current) => {
      if (current.post_affects.includes(value)) {
        return {
          ...current,
          post_affects: current.post_affects.filter((item) => item !== value)
        };
      }
      if (current.post_affects.length >= 2) {
        flash("Escolha no máximo duas opções.");
        return current;
      }
      return { ...current, post_affects: [...current.post_affects, value] };
    });
  }

  function submitPost(responseStatus = "completed") {
    const participant = participantKey;
    if (
      responseStatus === "completed" &&
      (!postAnswers.post_understanding ||
        !postAnswers.post_return_intent ||
        postAnswers.post_affects.length < 1)
    ) {
      flash("Responda às três perguntas do encerramento.");
      return;
    }

    const participantOffset = participant === "A" ? 35000 : 70000;
    emitResponse(
      participant,
      "post",
      responseStatus === "completed"
        ? {
            ...postAnswers,
            mission_performance: savedRubric.mission_performance,
            instructor_interventions:
              savedRubric.instructor_interventions,
            primary_issue: savedRubric.primary_issue,
            response_latency_ms: participantOffset
          }
        : {
            mission_performance: savedRubric.mission_performance,
            instructor_interventions:
              savedRubric.instructor_interventions,
            primary_issue: savedRubric.primary_issue,
            response_latency_ms: participantOffset
          },
      {
        responseStatus,
        elapsedMs: elapsedMs + participantOffset
      }
    );
    setPostAnswers(POST_DEFAULT);

    const nextKey = getNextParticipant(participant);
    if (nextKey) {
      setScreen(`post_${nextKey.toLowerCase()}`);
      return;
    }

    const finalElapsed = elapsedMs + 80000;
    setElapsedMs(finalElapsed);
    emitTimeline("phase_completed", {
      elapsedMs: finalElapsed,
      activityStage: "post",
      details: { phase: "post" }
    });
    emitTimeline("session_completed", {
      elapsedMs: finalElapsed,
      details: {
        checkpoint_count: timeline.filter(
          (event) => event.event_type === "checkpoint_completed"
        ).length,
        simulator: true
      }
    });
    setScreen("finished");
  }

  function syncQueue() {
    if (!queuedCount) {
      flash("A fila local já está vazia.");
      return;
    }
    setTimeline((current) =>
      current.map((event) =>
        event._delivery_state === "queued"
          ? { ...event, _delivery_state: "synced" }
          : event
      )
    );
    setResponses((current) =>
      current.map((event) =>
        event._delivery_state === "queued"
          ? { ...event, _delivery_state: "synced" }
          : event
      )
    );
    setOnline(true);
    window.setTimeout(() => {
      emitTimeline("heartbeat", {
        elapsedMs,
        deliveryState: "sent",
        details: {
          sync_recovered: true,
          synced_event_count: queuedCount,
          simulator: true
        }
      });
    }, 0);
    flash(`${queuedCount} evento(s) sincronizado(s).`);
  }

  function resetSimulation() {
    sequence.current = 0;
    setScreen("context");
    setSessionId(createUuid());
    setDyadId(createUuid());
    setStartedAt(Date.now());
    setTimeline([]);
    setResponses([]);
    setSelectedEvent(null);
    setElapsedMs(0);
    setLastHeartbeatMinute(0);
    setCurrentMark(20);
    setRoles({ A: "computer", B: "assembly" });
    setPreAnswers(PRE_DEFAULT);
    setCheckpointAnswers(CHECKPOINT_DEFAULT);
    setCheckpointEvidence(null);
    setPostAnswers(POST_DEFAULT);
    setRubric(RUBRIC_DEFAULT);
    setSavedRubric(RUBRIC_DEFAULT);
    setAssentA(false);
    setOnline(true);
    setContext((current) => ({
      ...current,
      authorization_verified: false
    }));
    flash("Nova sessão de validação preparada.");
  }

  function downloadSession() {
    const data = {
      simulator: true,
      exported_at: new Date().toISOString(),
      quality_status: qualityStatus,
      context: {
        ...context,
        authorization_verified: Boolean(context.authorization_verified)
      },
      session: {
        session_id: sessionId,
        dyad_id: dyadId,
        installation_id: installationId
      },
      research_session_events: timeline,
      research_events: responses
    };
    const blob = new Blob([JSON.stringify(data, null, 2)], {
      type: "application/json"
    });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `pulselab-simulacao-${sessionId.slice(0, 8)}.json`;
    link.click();
    URL.revokeObjectURL(url);
  }

  function ContextScreen() {
    return (
      <FormShell
        eyebrow="Etapa 1 de 6 · preparação"
        title="Contexto da oficina"
        description="Use códigos institucionais. O simulador não solicita nem armazena nomes de estudantes."
        footer={
          <ActionRow>
            <span className="footer-hint">
              Os dados operacionais são pré-salvos neste navegador. Confirme as autorizações em cada oficina.
            </span>
            <button className="button button--primary" onClick={beginSession}>
              Confirmar e iniciar
            </button>
          </ActionRow>
        }
      >
        <div className="form-grid">
          <label>
            <span>Sede</span>
            <select
              value={context.site_id}
              onChange={(event) =>
                setContext({ ...context, site_id: event.target.value })
              }
            >
              <option>Juazeiro-BA</option>
              <option>Paulo Afonso-BA</option>
              <option>Sobradinho-BA</option>
              <option>Outra sede</option>
            </select>
          </label>
          <label>
            <span>Polo ou regional</span>
            <input
              value={context.regional_hub}
              onChange={(event) =>
                setContext({ ...context, regional_hub: event.target.value })
              }
            />
          </label>
          <label>
            <span>Código da escola</span>
            <input
              value={context.school_code}
              onChange={(event) =>
                setContext({ ...context, school_code: event.target.value })
              }
            />
          </label>
          <label>
            <span>Código da oficina</span>
            <input
              value={context.workshop_code}
              onChange={(event) =>
                setContext({ ...context, workshop_code: event.target.value })
              }
            />
          </label>
          <label>
            <span>Código da turma</span>
            <input
              value={context.class_code}
              onChange={(event) =>
                setContext({ ...context, class_code: event.target.value })
              }
            />
          </label>
          <label>
            <span>Integrantes por grupo (máx 3)</span>
            <input
              type="number"
              min="1"
              max="3"
              value={context.group_size ?? 2}
              onChange={(event) =>
                setContext({ ...context, group_size: Math.max(1, Math.min(3, Number(event.target.value))) })
              }
            />
          </label>
          <label className="form-grid__wide">
            <span>Código da atividade</span>
            <input
              value={context.activity_id}
              onChange={(event) =>
                setContext({ ...context, activity_id: event.target.value })
              }
            />
          </label>
        </div>
        <label className="consent-check">
          <input
            type="checkbox"
            checked={context.authorization_verified}
            onChange={(event) =>
              setContext({
                ...context,
                authorization_verified: event.target.checked
              })
            }
          />
          <span>
            <strong>Verificação institucional concluída</strong>
            <small>
              Confirmo que a equipe verificou as autorizações e o consentimento
              aplicáveis para esta dupla.
            </small>
          </span>
        </label>
      </FormShell>
    );
  }

  function AssentScreen({ participant }) {
    return (
      <FormShell
        eyebrow="Etapa 2 de 6 · decisão individual"
        title="Convite para participar"
        description="A escolha deve ser feita individualmente, sem pressão da equipe ou da outra pessoa da dupla."
        compact
      >
        <ParticipantBadge participantKey={participant} />
        <div className="assent-copy">
          <div className="assent-copy__icon">?</div>
          <div>
            <h2>Você decide</h2>
            <p>
              Durante a oficina, o PulseLab fará perguntas curtas e registrará
              sinais do computador, como uso do SPIKE, tempo sem mexer e imagens
              da janela do projeto quando autorizadas.
            </p>
            <p>
              Se escolher não participar, você continuará fazendo a oficina
              normalmente. Isso não muda sua nota ou seu atendimento.
            </p>
          </div>
        </div>
        <ActionRow>
          <button className="button button--ghost" onClick={declineAssent}>
            Não quero participar
          </button>
          <button
            className="button button--primary"
            onClick={() => acceptAssent(participant)}
          >
            Quero participar
          </button>
        </ActionRow>
      </FormShell>
    );
  }

  function PreScreen({ participant }) {
    return (
      <FormShell
        eyebrow="Etapa 3 de 6 · antes da atividade"
        title="Antes de começar"
        description="Responda sozinho. Não existem respostas certas ou erradas."
        footer={
          <ActionRow>
            <button
              className="button button--ghost"
              onClick={() => submitPre("declined")}
            >
              Prefiro não responder
            </button>
            <button className="button button--primary" onClick={() => submitPre()}>
              Salvar e continuar
            </button>
          </ActionRow>
        }
      >
        <ParticipantBadge participantKey={participant} />
        <ScaleQuestion
          title="Antes de hoje, você já tinha montado ou programado um robô?"
          value={preAnswers.prior_robotics}
          onChange={(value) =>
            setPreAnswers((current) => ({
              ...current,
              prior_robotics: value
            }))
          }
          labels={["Nunca", "Uma vez", "Algumas vezes", "Muitas vezes"]}
        />
        <ScaleQuestion
          title="Eu acho que consigo fazer um robô cumprir uma missão."
          value={preAnswers.self_efficacy_pre}
          onChange={(value) =>
            setPreAnswers((current) => ({
              ...current,
              self_efficacy_pre: value
            }))
          }
          labels={[
            "Discordo muito",
            "Discordo",
            "Concordo",
            "Concordo muito"
          ]}
        />
      </FormShell>
    );
  }

  function SpikeWorkspace() {
    return (
      <FormShell
        eyebrow={`Etapa 4 de 6 · relógio acelerado · próximo marco ${currentMark} min`}
        title="Atividade LEGO SPIKE"
        description="Esta tela representa o período em que o agente real ficaria minimizado enquanto a dupla trabalha."
        footer={
          <ActionRow>
            <button className="button button--ghost" onClick={beginEnding}>
              Encerrar antecipadamente
            </button>
            <button
              className="button button--primary"
              onClick={() => beginCheckpoint(currentMark)}
            >
              Simular checkpoint de {currentMark} min
            </button>
          </ActionRow>
        }
      >
        <div className="workspace">
          <div className="workspace__toolbar">
            <div className="workspace__traffic">
              <i />
              <i />
              <i />
            </div>
            <strong>Missão: robô autônomo</strong>
            <span className="workspace__clock">{formatElapsed(elapsedMs)}</span>
          </div>
          <div className="workspace__canvas">
            <div className="blocks">
              <div className="code-block code-block--start">
                <span>▶</span> quando o programa iniciar
              </div>
              <div className="code-block code-block--motion">
                mover para frente por <b>40 cm</b>
              </div>
              <div className="code-block code-block--sensor">
                esperar até sensor detectar <b>azul</b>
              </div>
              <div className="code-block code-block--motion">
                virar à direita <b>90°</b>
              </div>
            </div>
            <div className="robot-preview">
              <div className="robot-preview__grid" />
              <div className="robot">
                <span className="robot__hub">SPIKE</span>
                <i className="robot__wheel robot__wheel--left" />
                <i className="robot__wheel robot__wheel--right" />
                <i className="robot__sensor" />
              </div>
              <div className="robot-preview__route" />
            </div>
          </div>
          <div className="workspace__status">
            <span className={scenario === "missing_spike" ? "is-danger" : ""}>
              <i /> Janela SPIKE{" "}
              {scenario === "missing_spike" ? "não detectada" : "detectada"}
            </span>
            {activeParticipants.map((key) => (
              <span key={key}>
                <i /> Participante {key}: {roleLabel(roles[key])}
              </span>
            ))}
          </div>
        </div>
        <div className="simulation-note">
          <strong>O que está sendo simulado?</strong>
          <span>
            O clique acima avança o relógio, gera heartbeats, captura um contexto
            técnico fictício e abre o instrumento do checkpoint.
          </span>
        </div>
      </FormShell>
    );
  }

  function CheckpointScreen({ participant }) {
    const collaborationRequired = currentMark === 40;
    return (
      <FormShell
        eyebrow={`Etapa 4 de 6 · checkpoint ${currentMark} min`}
        title="Como está a atividade agora?"
        description="A evidência técnica foi registrada antes desta tela. A resposta é individual."
        footer={
          <ActionRow>
            <button
              className="button button--ghost"
              onClick={() => submitCheckpoint("declined")}
            >
              Prefiro não responder
            </button>
            <button
              className="button button--primary"
              onClick={() => submitCheckpoint()}
            >
              Registrar resposta
            </button>
          </ActionRow>
        }
      >
        <div className="checkpoint-meta">
          <ParticipantBadge participantKey={participant} />
          <span className="time-chip">
            alvo {currentMark}:00 · captura{" "}
            {formatElapsed(checkpointEvidence?.captureMs || 0)}
          </span>
        </div>
        <ScaleQuestion
          title="O que você mais fez desde o último checkpoint?"
          value={checkpointAnswers.self_reported_role}
          onChange={(value) =>
            setCheckpointAnswers((current) => ({
              ...current,
              self_reported_role: value
            }))
          }
          labels={[
            "Computador / Programação",
            "Montagem das peças",
            "Ambos / Fizemos juntos"
          ]}
          values={["computer", "assembly", "both"]}
          icons={[
            <svg key="comp" width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><rect x="2" y="3" width="20" height="14" rx="2" ry="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/></svg>,
            <svg key="assy" width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/></svg>,
            <svg key="both" width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
          ]}
        />
        <ScaleQuestion
          title="Quanto você precisou pensar para fazer a parte em que estava agora?"
          value={checkpointAnswers.mental_effort}
          onChange={(value) =>
            setCheckpointAnswers((current) => ({
              ...current,
              mental_effort: value
            }))
          }
          labels={["Muito pouco", "Pouco", "Bastante", "Muito"]}
        />
        <fieldset className="question-block">
          <legend>Neste momento, como vocês estão?</legend>
          <div className="option-list">
            {PROGRESS_OPTIONS.map((option) => (
              <button
                key={option.value}
                type="button"
                className={`option-row ${
                  checkpointAnswers.progress_state === option.value
                    ? "is-selected"
                    : ""
                }`}
                onClick={() =>
                  setCheckpointAnswers((current) => ({
                    ...current,
                    progress_state: option.value
                  }))
                }
              >
                <span className="option-row__radio" />
                <span>
                  <strong>{option.title}</strong>
                  <small>{option.description}</small>
                </span>
              </button>
            ))}
          </div>
        </fieldset>
        {collaborationRequired ? (
          <ScaleQuestion
            title="Nós dois tivemos oportunidade de dar ideias e participar da tarefa."
            value={checkpointAnswers.collaboration}
            onChange={(value) =>
              setCheckpointAnswers((current) => ({
                ...current,
                collaboration: value
              }))
            }
            labels={[
              "Discordo muito",
              "Discordo",
              "Concordo",
              "Concordo muito"
            ]}
          />
        ) : null}
      </FormShell>
    );
  }

  function RoleSwapScreen() {
    return (
      <FormShell
        eyebrow="Etapa 4 de 6 · equilíbrio de participação"
        title="Troquem os papéis"
        description="A troca ajuda as duas pessoas a experimentar partes diferentes da atividade."
        compact
      >
        <div className="swap-visual">
          <div>
            <span>A</span>
            <strong>{roleLabel(roles.A)}</strong>
            <small>agora vai para {roleLabel(roles.B)}</small>
          </div>
          <div className="swap-visual__arrow">⇄</div>
          <div>
            <span>B</span>
            <strong>{roleLabel(roles.B)}</strong>
            <small>agora vai para {roleLabel(roles.A)}</small>
          </div>
        </div>
        <ActionRow>
          <button
            className="button button--ghost"
            onClick={() => confirmRoleSwap(false)}
          >
            Não foi possível trocar
          </button>
          <button
            className="button button--primary"
            onClick={() => confirmRoleSwap(true)}
          >
            Papéis trocados · continuar
          </button>
        </ActionRow>
      </FormShell>
    );
  }

  function ActivityEndScreen() {
    return (
      <FormShell
        eyebrow="Etapa 5 de 6 · atividade concluída"
        title="Checkpoints finalizados"
        description="No agente real, o ícone permaneceria ativo até o instrutor solicitar o encerramento."
        compact
      >
        <div className="ending-hero">
          <div className="ending-hero__check">✓</div>
          <div>
            <h2>Os dois checkpoints foram registrados</h2>
            <p>
              Continue quando a missão terminar e a dupla estiver pronta para a
              avaliação final.
            </p>
          </div>
        </div>
        <ActionRow>
          <span className="footer-hint">
            Tempo simulado: {formatElapsed(elapsedMs)}
          </span>
          <button className="button button--primary" onClick={beginEnding}>
            Concluir oficina
          </button>
        </ActionRow>
      </FormShell>
    );
  }

  function RubricScreen() {
    return (
      <FormShell
        eyebrow="Etapa 5 de 6 · somente instrutor"
        title="Registro do instrutor"
        description="Avalie a dupla antes de chamar os participantes para o encerramento."
        footer={
          <ActionRow>
            <button className="button button--ghost" onClick={abortAtRubric}>
              Abortar sessão
            </button>
            <button className="button button--primary" onClick={submitRubric}>
              Salvar avaliação da dupla
            </button>
          </ActionRow>
        }
      >
        <div className="rubric-grid">
          <label>
            <span>Desempenho da missão</span>
            <select
              value={rubric.mission_performance ?? ""}
              onChange={(event) =>
                setRubric((current) => ({
                  ...current,
                  mission_performance: Number(event.target.value)
                }))
              }
            >
              <option value="">Selecione</option>
              <option value="0">0 · Não executou a missão</option>
              <option value="1">1 · Executou parcialmente</option>
              <option value="2">2 · Concluiu com muita ajuda</option>
              <option value="3">3 · Concluiu com pouca ou nenhuma ajuda</option>
            </select>
          </label>
          <label>
            <span>Quantidade aproximada de intervenções</span>
            <select
              value={rubric.instructor_interventions ?? ""}
              onChange={(event) =>
                setRubric((current) => ({
                  ...current,
                  instructor_interventions: Number(event.target.value)
                }))
              }
            >
              <option value="">Selecione</option>
              <option value="0">0</option>
              <option value="1">1</option>
              <option value="2">2</option>
              <option value="3">3 ou mais</option>
            </select>
          </label>
          <label>
            <span>Principal dificuldade observada</span>
            <select
              value={rubric.primary_issue}
              onChange={(event) =>
                setRubric((current) => ({
                  ...current,
                  primary_issue: event.target.value
                }))
              }
            >
              <option value="">Selecione</option>
              <option value="none">Nenhuma</option>
              <option value="assembly">Montagem</option>
              <option value="logic">Lógica de programação</option>
              <option value="sensor">Sensor</option>
              <option value="technical">Problema técnico</option>
              <option value="collaboration">Colaboração</option>
              <option value="other">Outra</option>
            </select>
          </label>
        </div>
        <div className="privacy-callout">
          <span>i</span>
          <p>
            A rubrica descreve o desempenho da dupla. Ela não substitui
            observação detalhada nem mede aprendizagem isoladamente.
          </p>
        </div>
      </FormShell>
    );
  }

  function PostScreen({ participant }) {
    return (
      <FormShell
        eyebrow="Etapa 5 de 6 · encerramento individual"
        title="Como foi a oficina?"
        description="Responda sozinho. Escolha uma ou duas emoções."
        footer={
          <ActionRow>
            <button
              className="button button--ghost"
              onClick={() => submitPost("declined")}
            >
              Prefiro não responder
            </button>
            <button className="button button--primary" onClick={() => submitPost()}>
              Salvar e concluir
            </button>
          </ActionRow>
        }
      >
        <ParticipantBadge participantKey={participant} />
        <ScaleQuestion
          title="Eu conseguiria explicar para outra pessoa como fizemos o robô funcionar."
          value={postAnswers.post_understanding}
          onChange={(value) =>
            setPostAnswers((current) => ({
              ...current,
              post_understanding: value
            }))
          }
          labels={[
            "Discordo muito",
            "Discordo",
            "Concordo",
            "Concordo muito"
          ]}
        />
        <fieldset className="question-block">
          <legend>Como você se sentiu na maior parte da oficina?</legend>
          <p>Escolha uma ou duas opções.</p>
          <div className="affect-grid">
            {AFFECTS.map(([value, label]) => (
              <button
                type="button"
                key={value}
                className={
                  postAnswers.post_affects.includes(value) ? "is-selected" : ""
                }
                onClick={() => toggleAffect(value)}
              >
                <span>{postAnswers.post_affects.includes(value) ? "✓" : ""}</span>
                {label}
              </button>
            ))}
          </div>
        </fieldset>
        <ScaleQuestion
          title="Você gostaria de participar de outra oficina de robótica?"
          value={postAnswers.post_return_intent}
          onChange={(value) =>
            setPostAnswers((current) => ({
              ...current,
              post_return_intent: value
            }))
          }
          labels={["Não", "Talvez não", "Talvez sim", "Sim"]}
        />
      </FormShell>
    );
  }

  function SummaryScreen() {
    const issueCount = timeline.filter(
      (event) => event.event_type === "quality_issue"
    ).length;
    const checkpointCount = timeline.filter(
      (event) => event.event_type === "checkpoint_completed"
    ).length;
    return (
      <FormShell
        eyebrow="Etapa 6 de 6 · revisão técnica"
        title="Sessão reconstruída"
        description="O resumo mostra o que a coordenação central receberia para decidir se a sessão pode entrar na análise."
      >
        <div className={`summary-status summary-status--${statusTone(qualityStatus)}`}>
          <div className="summary-status__mark">
            {qualityStatus === "complete"
              ? "✓"
              : qualityStatus === "needs_review"
                ? "!"
                : qualityStatus === "aborted"
                  ? "×"
                  : "…"}
          </div>
          <div>
            <span>Status de qualidade</span>
            <h2>{qualityLabel(qualityStatus)}</h2>
            <p>
              {qualityStatus === "complete"
                ? "O conjunto técnico mínimo está presente e não há alertas automáticos."
                : qualityStatus === "needs_review"
                  ? "A sessão terminou, mas possui alertas ou etapas ausentes."
                  : qualityStatus === "aborted"
                    ? "O fluxo foi interrompido depois do início autorizado."
                    : "A sessão ainda não registrou um desfecho."}
            </p>
          </div>
        </div>
        <div className="metric-grid">
          <article>
            <span>{timeline.length}</span>
            <small>eventos na linha do tempo</small>
          </article>
          <article>
            <span>{responses.length}</span>
            <small>respostas individuais</small>
          </article>
          <article>
            <span>{checkpointCount}/2</span>
            <small>checkpoints concluídos</small>
          </article>
          <article className={issueCount ? "has-warning" : ""}>
            <span>{issueCount}</span>
            <small>alertas de qualidade</small>
          </article>
        </div>
        <div className="review-checklist">
          <h3>Leitura recomendada</h3>
          <ul>
            <li className={responses.filter((item) => item.event_type === "pre").length === 2 ? "is-ok" : ""}>
              <span />
              Duas respostas pré-oficina
            </li>
            <li className={checkpointCount === 2 ? "is-ok" : ""}>
              <span />
              Checkpoints 20 e 40 reconstruídos
            </li>
            <li className={responses.filter((item) => item.event_type === "post").length === 2 ? "is-ok" : ""}>
              <span />
              Duas respostas pós-oficina
            </li>
            <li className={issueCount === 0 ? "is-ok" : ""}>
              <span />
              Nenhum alerta automático
            </li>
          </ul>
        </div>
        <ActionRow>
          <button className="button button--ghost" onClick={resetSimulation}>
            Iniciar nova validação
          </button>
          <button className="button button--primary" onClick={downloadSession}>
            Baixar sessão em JSON
          </button>
        </ActionRow>
      </FormShell>
    );
  }

  function FinishedScreen() {
    return (
      <FormShell
        eyebrow="Oficina Concluída"
        title="Muito obrigado por sua participação! 🚀"
        description="A sua participação foi registrada com sucesso. A atividade de robótica pode continuar normalmente."
        compact
      >
        <div className="decline-message">
          <span style={{ background: "rgba(0, 167, 160, 0.15)", color: "var(--aqua)" }}>✓</span>
          <div>
            <h2>Todas as etapas foram finalizadas</h2>
            <p>
              As respostas foram salvas com sucesso no projeto PulseLab.
            </p>
          </div>
        </div>
        <ActionRow>
          <button className="button button--ghost" onClick={() => setScreen("summary")}>
            Ver Resumo Técnico
          </button>
          <button className="button button--primary" onClick={resetSimulation}>
            Nova Simulação
          </button>
        </ActionRow>
      </FormShell>
    );
  }

  function renderScreen() {
    if (screen === "context") return <ContextScreen />;
    if (screen === "declined") {
      return (
        <FormShell
          eyebrow="Coleta encerrada"
          title="A oficina pode continuar"
          description="Como um integrante do grupo não quis participar, nenhum evento de pesquisa foi produzido."
          compact
        >
          <div className="decline-message">
            <span>♡</span>
            <div>
              <h2>Escolha respeitada</h2>
              <p>
                O grupo continua a atividade normalmente, sem prejuízo de nota,
                atendimento ou participação.
              </p>
            </div>
          </div>
          <ActionRow>
            <button className="button button--primary" onClick={resetSimulation}>
              Preparar outra simulação
            </button>
          </ActionRow>
        </FormShell>
      );
    }
    if (screen === "finished") return <FinishedScreen />;
    if (screen.startsWith("assent_")) return <AssentScreen participant={participantKey} />;
    if (screen.startsWith("pre_")) return <PreScreen participant={participantKey} />;
    if (screen === "activity") return <SpikeWorkspace />;
    if (screen.startsWith("checkpoint_")) return <CheckpointScreen participant={participantKey} />;
    if (screen === "role_swap") return <RoleSwapScreen />;
    if (screen === "activity_end") return <ActivityEndScreen />;
    if (screen === "rubric") return <RubricScreen />;
    if (screen.startsWith("post_")) return <PostScreen participant={participantKey} />;
    if (screen === "summary") return <SummaryScreen />;
    return <ContextScreen />;
  }

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <span className="brand__mark">
            <LogoMark />
          </span>
          <span>
            <strong>PulseLab</strong>
            <small>simulador do agente · v1.4</small>
          </span>
        </div>
        <div className="topbar__notice">
          <span>SIMULAÇÃO</span>
          <p>Sem captura real, sem Supabase e sem dados pessoais</p>
        </div>
        <div className="topbar__session">
          <span>Sessão</span>
          <code>{sessionId.slice(0, 8).toUpperCase()}</code>
        </div>
      </header>

      <div className="workspace-shell">
        <aside className="flow-sidebar">
          <div className="flow-sidebar__header">
            <span>Roteiro de validação</span>
            <strong>{activeStep}/6</strong>
          </div>
          <nav aria-label="Etapas do simulador">
            {FLOW_STEPS.map((step) => (
              <div
                key={step.id}
                className={`flow-step ${
                  step.id === activeStep
                    ? "is-active"
                    : step.id < activeStep
                      ? "is-complete"
                      : ""
                }`}
              >
                <span>{step.id < activeStep ? "✓" : step.id}</span>
                <strong>{step.label}</strong>
              </div>
            ))}
          </nav>
          <div className="scenario-panel">
            <label>
              <span>Cenário técnico</span>
              <select
                value={scenario}
                onChange={(event) => setScenario(event.target.value)}
              >
                {Object.entries(SCENARIOS).map(([value, item]) => (
                  <option value={value} key={value}>
                    {item.label}
                  </option>
                ))}
              </select>
            </label>
            <p>{SCENARIOS[scenario].description}</p>
          </div>
          <div className="sidebar-context">
            <span>Local da simulação</span>
            <strong>{context.site_id}</strong>
            <small>{context.workshop_code}</small>
          </div>
          <button className="sidebar-reset" onClick={resetSimulation}>
            ↻ Reiniciar sessão
          </button>
        </aside>

        <section className="simulator-stage" data-screen={screen}>
          <div className="stage-toolbar">
            <div>
              <span className={`connection-dot ${online ? "is-online" : ""}`} />
              <strong>{online ? "Conectado" : "Sem conexão"}</strong>
              <small>
                {queuedCount
                  ? `${queuedCount} evento(s) na fila local`
                  : "fila local vazia"}
              </small>
            </div>
            <button
              className="toolbar-button"
              onClick={() => setOnline((current) => !current)}
            >
              {online ? "Simular queda" : "Restaurar rede"}
            </button>
            {queuedCount ? (
              <button className="toolbar-button is-accent" onClick={syncQueue}>
                Sincronizar fila
              </button>
            ) : null}
          </div>
          <div className="stage-scroll">{renderScreen()}</div>
        </section>

        <aside className="evidence-panel">
          <div className="evidence-panel__header">
            <div>
              <span>Observabilidade</span>
              <h2>Evidências da sessão</h2>
            </div>
            <span className={`quality-pill quality-pill--${statusTone(qualityStatus)}`}>
              {qualityLabel(qualityStatus)}
            </span>
          </div>
          <div className="evidence-tabs">
            <button
              className={eventFilter === "timeline" ? "is-active" : ""}
              onClick={() => setEventFilter("timeline")}
            >
              Linha do tempo
            </button>
            <button
              className={eventFilter === "responses" ? "is-active" : ""}
              onClick={() => setEventFilter("responses")}
            >
              Respostas
            </button>
            <button
              className={eventFilter === "all" ? "is-active" : ""}
              onClick={() => setEventFilter("all")}
            >
              Tudo
            </button>
          </div>
          <div className="event-list">
            {visibleEvents.length ? (
              [...visibleEvents].reverse().map((event) => (
                <button
                  key={event.event_id}
                  className={`event-row ${
                    selectedEvent?.event_id === event.event_id ? "is-selected" : ""
                  }`}
                  onClick={() => setSelectedEvent(event)}
                >
                  <span
                    className={`event-row__icon event-row__icon--${
                      event.event_type === "quality_issue"
                        ? "warning"
                        : event._target_table === "research_events"
                          ? "response"
                          : "timeline"
                    }`}
                  >
                    {event.event_type === "quality_issue"
                      ? "!"
                      : event._target_table === "research_events"
                        ? "R"
                        : "E"}
                  </span>
                  <span>
                    <strong>
                      {event._target_table === "research_events"
                        ? `${event.event_type} · ${event.participant_id?.slice(-1)}`
                        : formatEventName(event.event_type)}
                    </strong>
                    <small>
                      {formatElapsed(event.elapsed_ms)}
                      {event.interval_mark !== null
                        ? ` · marco ${event.interval_mark}`
                        : ""}
                    </small>
                  </span>
                  <i className={`delivery delivery--${event._delivery_state}`}>
                    {event._delivery_state === "queued"
                      ? "fila"
                      : event._delivery_state === "synced"
                        ? "sincronizado"
                        : "enviado"}
                  </i>
                </button>
              ))
            ) : (
              <div className="empty-events">
                <span>◎</span>
                <p>Os eventos aparecerão aqui conforme o fluxo avançar.</p>
              </div>
            )}
          </div>
          <div className="payload-viewer">
            <div>
              <span>Payload selecionado</span>
              {selectedEvent ? (
                <code>{selectedEvent._target_table}</code>
              ) : null}
            </div>
            <pre>
              {selectedEvent
                ? JSON.stringify(selectedEvent, null, 2)
                : "{\n  \"aguardando\": \"primeiro evento\"\n}"}
            </pre>
          </div>
        </aside>
      </div>

      {toast ? (
        <div className="toast" role="status">
          <span>✓</span>
          {toast}
        </div>
      ) : null}
    </main>
  );
}
