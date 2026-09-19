import React, { useEffect, useMemo, useRef, useState } from "react";
import {
  CONFIG_HASH,
  createUuid,
  formatEventName
} from "../lib/contracts.js";
import {
  markEventDelivered,
  markSessionEvents,
  removeSession,
  saveEvent,
  saveSession
} from "../lib/student-store.js";
import {
  flushPendingEvents,
  syncSingleEvent
} from "../lib/sync-engine.js";

const ACTIVE_SESSION_KEY = "pulselab_student_active_session_v1";
const CONTEXT_KEY = "pulselab_student_context_v1";
const INSTALLATION_KEY = "pulselab_student_installation_id_v1";
const CLIENT_VERSION = "student-pwa/1.9.0";

const DEFAULT_CONTEXT = {
  site_id: "POLO-LOCAL",
  regional: "Regional",
  school: "Escola",
  workshop: "Oficina-SPIKE",
  class: "Turma-Geral",
  activity: "atividade-01-spike"
};

const PRE_DEFAULT = { experience: null, confidence: null };
const CHECKPOINT_DEFAULT = {
  effort: null,
  progress: null,
  collaboration: null,
  help: false
};
const POST_DEFAULT = { understanding: null, affect: null, returnIntent: null };

const FLOW_STEPS = [
  { id: 1, label: "Início" },
  { id: 2, label: "Atividade" },
  { id: 3, label: "Check-in" },
  { id: 4, label: "Finalizar" }
];

const EXPERIENCE_OPTIONS = [
  [1, "Nunca usamos"],
  [2, "Usamos poucas vezes"],
  [3, "Já fizemos projetos"],
  [4, "Temos bastante prática"]
];

const CONFIDENCE_OPTIONS = [
  [1, "Pouco confiantes"],
  [2, "Razoável"],
  [3, "Confiantes"],
  [4, "Muito confiantes"]
];

const PROGRESS_OPTIONS = [
  ["needs_help_now", "Travamos", "Não sabemos como continuar"],
  ["trying_without_progress", "Começando", "Estamos tentando, mas ainda sem avanço"],
  ["progressing_with_doubt", "Avançando", "Temos uma parte funcionando, com algumas dúvidas"],
  ["progressing_independently", "Testando", "Estamos ajustando e testando autonomamente"]
];

const COLLABORATION_OPTIONS = [
  [1, "Cada um por si", "Quase não trocamos ideias"],
  [2, "Uma pessoa decide", "A participação está desigual"],
  [3, "Decidimos juntos", "Todos conseguem contribuir"],
  [4, "Revezamos bem", "Trocamos tarefas naturalmente"]
];

const BRIDGE_URL = "http://127.0.0.1:43127";

async function notifyBridgeSession(sessionId, startedAt, marks = [20, 40]) {
  try {
    await fetch(`${BRIDGE_URL}/v1/sessions`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ session_id: sessionId, started_at: startedAt, marks })
    });
  } catch {
    // Operação normal mesmo sem o Bridge
  }
}

async function notifyBridgeCheckpointAck(sessionId, mark) {
  try {
    await fetch(`${BRIDGE_URL}/v1/sessions/${sessionId}/checkpoints/${mark}/ack`, {
      method: "POST"
    });
  } catch {
    // Operação normal mesmo sem o Bridge
  }
}

async function fetchBridgeSpikeMetrics() {
  try {
    const res = await fetch(`${BRIDGE_URL}/v1/spike/metrics`);
    if (res.ok) {
      return await res.json();
    }
  } catch {
    // Bridge offline ou inacessível
  }
  return null;
}

async function notifyBridgeEvent(event) {
  try {
    await fetch(`${BRIDGE_URL}/v1/events`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(event)
    });
  } catch {
    // Operação normal mesmo sem o Bridge
  }
}

function playChimeSound() {
  try {
    const AudioCtx = window.AudioContext || window.webkitAudioContext;
    if (!AudioCtx) return;
    const ctx = new AudioCtx();
    if (ctx.state === "suspended") {
      ctx.resume().catch(() => {});
    }
    const now = ctx.currentTime;
    const notes = [523.25, 659.25, 783.99, 1046.5]; // C5, E5, G5, C6 (harmonia agradável e nítida)
    notes.forEach((freq, idx) => {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = "sine";
      osc.frequency.setValueAtTime(freq, now + idx * 0.12);
      gain.gain.setValueAtTime(0.001, now + idx * 0.12);
      gain.gain.exponentialRampToValueAtTime(0.28, now + idx * 0.12 + 0.03);
      gain.gain.exponentialRampToValueAtTime(0.001, now + idx * 0.12 + 0.45);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(now + idx * 0.12);
      osc.stop(now + idx * 0.12 + 0.45);
    });
  } catch {
    // Silencioso se navegador restringir autoplay
  }
}

async function triggerBridgeAlert(mark = 20) {
  try {
    await fetch(`${BRIDGE_URL}/v1/alert`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ mark })
    });
  } catch {
    // Operação normal mesmo sem o Bridge
  }
}

async function resetBridgeSession() {
  try {
    await fetch(`${BRIDGE_URL}/v1/sessions/reset`, {
      method: "POST"
    });
  } catch {
    // Operação normal mesmo sem o Bridge
  }
}

function requestNotificationPermission() {
  if (typeof Notification !== "undefined" && Notification.permission === "default") {
    Notification.requestPermission().catch(() => {});
  }
}

function showWebNotification(mark) {
  if (typeof Notification !== "undefined" && Notification.permission === "granted") {
    try {
      new Notification(`PulseLab: Check-in de ${mark} min!`, {
        body: "Pausa rápida de 30 segundos no robô para o grupo registrar o progresso.",
        icon: "/alunos/icon.svg"
      });
    } catch {}
  }
}

function stepForScreen(screen) {
  if (screen === "pre") return 1;
  if (screen === "activity") return 2;
  if (screen.startsWith("checkpoint")) return 3;
  return 4;
}

function readJson(key, fallback) {
  try {
    const value = localStorage.getItem(key);
    return value ? JSON.parse(value) : fallback;
  } catch {
    return fallback;
  }
}

function getInstallationId() {
  const current = localStorage.getItem(INSTALLATION_KEY);
  if (current) return current;
  const created = createUuid();
  localStorage.setItem(INSTALLATION_KEY, created);
  return created;
}

function formatClock(milliseconds) {
  const totalSeconds = Math.max(0, Math.floor(milliseconds / 1000));
  const minutes = String(Math.floor(totalSeconds / 60)).padStart(2, "0");
  const seconds = String(totalSeconds % 60).padStart(2, "0");
  return `${minutes}:${seconds}`;
}

function ScaleQuestion({ legend, hint, options, value, onChange }) {
  return (
    <fieldset className="question-block">
      <legend>{legend}</legend>
      {hint ? <p>{hint}</p> : null}
      <div className="scale-grid">
        {options.map(([optionValue, label], index) => (
          <button
            className={`scale-option ${value === optionValue ? "is-selected" : ""}`}
            key={optionValue}
            onClick={() => onChange(optionValue)}
            type="button"
          >
            <span>{index + 1}</span>
            <small>{label}</small>
          </button>
        ))}
      </div>
    </fieldset>
  );
}

function OptionQuestion({ legend, options, value, onChange }) {
  return (
    <fieldset className="question-block">
      <legend>{legend}</legend>
      <div className="option-list">
        {options.map(([optionValue, label, hint]) => (
          <button
            className={`option-row ${value === optionValue ? "is-selected" : ""}`}
            key={optionValue}
            onClick={() => onChange(optionValue)}
            type="button"
          >
            <span className="option-row__radio" />
            <span>
              <strong>{label}</strong>
              {hint ? <small>{hint}</small> : null}
            </span>
          </button>
        ))}
      </div>
    </fieldset>
  );
}

function Card({ eyebrow, title, description, children, footer, compact = false }) {
  return (
    <section className={`flow-card ${compact ? "flow-card--compact" : ""}`}>
      <header className="flow-card__heading">
        <span className="eyebrow">{eyebrow}</span>
        <h1>{title}</h1>
        <p>{description}</p>
      </header>
      <div className="flow-card__body">{children}</div>
      {footer ? <footer className="flow-card__footer">{footer}</footer> : null}
    </section>
  );
}

function PreScreen({ answers, setAnswers, onSubmit, resumable, onResume }) {
  const ready = answers.experience !== null && answers.confidence !== null;
  return (
    <Card
      eyebrow="Oficina de Robótica · Início rápido (15 segundos)"
      title="Como vocês chegam para esta oficina?"
      description="Responda rapidamente antes de começar a montar e programar o robô LEGO SPIKE."
      footer={
        <div className="action-row">
          <span className="footer-hint">Sua resposta fica salva assim que você clica em começar.</span>
          <button className="button button--primary" disabled={!ready} onClick={onSubmit} type="button">
            Começar Atividade!
          </button>
        </div>
      }
    >
      {resumable ? (
        <div className="resume-banner">
          <div>
            <strong>Há uma atividade em andamento neste dispositivo.</strong>
            <small>Continue do ponto salvo, mesmo que a página tenha sido fechada.</small>
          </div>
          <button className="button button--ghost" onClick={onResume} type="button">
            Continuar sessão salva
          </button>
        </div>
      ) : null}

      <ScaleQuestion
        legend="Quanto o grupo já trabalhou com robótica ou programação?"
        onChange={(experience) => setAnswers({ ...answers, experience })}
        options={EXPERIENCE_OPTIONS}
        value={answers.experience}
      />
      <ScaleQuestion
        legend="Quão confiantes vocês estão para começar o desafio?"
        onChange={(confidence) => setAnswers({ ...answers, confidence })}
        options={CONFIDENCE_OPTIONS}
        value={answers.confidence}
      />
    </Card>
  );
}

function ActivityScreen({ elapsedMs, currentMark, labMode, spikeTelemetry }) {
  const targetMs = currentMark * 60 * 1000;
  const remaining = Math.max(0, targetMs - elapsedMs);
  return (
    <Card
      eyebrow="Desafio em Andamento"
      title="Pode focar no projeto do SPIKE"
      description={`Construam e programem normalmente. O próximo check-in curto será aberto automaticamente aos ${currentMark} minutos.`}
      footer={
        <div className="action-row" style={{ justifyContent: "center" }}>
          <span className="footer-hint" style={{ margin: "0 auto", textAlign: "center", fontSize: "0.95rem", color: "var(--muted)" }}>
            ⏱️ O check-in de {currentMark} minutos abrirá automaticamente nesta tela.
          </span>
        </div>
      }
    >
      <div className="activity-timer" aria-live="polite">
        <span>Tempo de atividade</span>
        <strong>{formatClock(elapsedMs)}</strong>
        <small>Próximo check-in em {formatClock(remaining)}</small>
      </div>

      {spikeTelemetry ? (
        <div style={{ background: "rgba(73, 217, 206, 0.1)", border: "1px solid rgba(73, 217, 206, 0.3)", borderRadius: "10px", padding: "12px 16px", margin: "16px 0", fontSize: "0.85rem", color: "#6ee7b7" }}>
          <span>🤖 <strong>LEGO SPIKE Conectado:</strong> {spikeTelemetry.executable_blocks || 0} blocos detectados · Estágio: <em>{spikeTelemetry.inferred_stage || "em edição"}</em></span>
        </div>
      ) : null}

      <div className="activity-instructions">
        <article>
          <span>1</span>
          <strong>Mantenha esta página aberta</strong>
          <p>Ela pode ficar em uma aba ao lado enquanto vocês usam o app do SPIKE.</p>
        </article>
        <article>
          <span>2</span>
          <strong>Programem e testem à vontade</strong>
          <p>O PulseLab captura o avanço do código do SPIKE de forma 100% segura e anônima.</p>
        </article>
        <article>
          <span>3</span>
          <strong>Respondam aos 20 e 40 minutos</strong>
          <p>Um alerta sonoro e visual avisará quando for a hora do check-in de 30 segundos.</p>
        </article>
      </div>
    </Card>
  );
}

function CheckpointScreen({ mark, answers, setAnswers, onSubmit }) {
  const ready = answers.effort !== null && answers.progress && answers.collaboration;
  return (
    <Card
      eyebrow={`Check-in de ${mark} minutos · 20 segundos`}
      title="Como está indo o projeto?"
      description="Responda rapidamente como o grupo está trabalhando agora e volte direto para a robótica."
      footer={
        <div className="action-row">
          <button className="button button--primary" disabled={!ready} onClick={onSubmit} type="button">
            Salvar e continuar
          </button>
        </div>
      }
    >
      <div className="checkpoint-meta">
        <span className="time-chip">{mark}:00 de atividade</span>
      </div>
      <ScaleQuestion
        legend="Quanto esforço mental esta atividade está exigindo?"
        onChange={(effort) => setAnswers({ ...answers, effort })}
        options={[
          [1, "Muito pouco"],
          [2, "Pouco"],
          [3, "Bastante"],
          [4, "Muito"]
        ]}
        value={answers.effort}
      />
      <OptionQuestion
        legend="Em que situação o grupo está?"
        onChange={(progress) => setAnswers({ ...answers, progress })}
        options={PROGRESS_OPTIONS}
        value={answers.progress}
      />
      <OptionQuestion
        legend="Como o grupo está trabalhando junto?"
        onChange={(collaboration) => setAnswers({ ...answers, collaboration })}
        options={COLLABORATION_OPTIONS}
        value={answers.collaboration}
      />
      <label className="help-check">
        <input
          checked={answers.help}
          onChange={(event) => setAnswers({ ...answers, help: event.target.checked })}
          type="checkbox"
        />
        <span>
          <strong>Nosso grupo precisa de ajuda do professor agora.</strong>
          <small>Isso registra um aviso para que o apoio seja oferecido durante a aula.</small>
        </span>
      </label>
    </Card>
  );
}

function PostScreen({ answers, setAnswers, onSubmit }) {
  const ready =
    answers.understanding !== null &&
    answers.returnIntent !== null &&
    answers.affect;
  return (
    <Card
      eyebrow="Depois da atividade · finalização rápida"
      title="Como foi a experiência do grupo?"
      description="Últimas 3 perguntas sobre a oficina de hoje."
      footer={
        <div className="action-row">
          <button className="button button--primary" disabled={!ready} onClick={onSubmit} type="button">
            Concluir Oficina
          </button>
        </div>
      }
    >
      <ScaleQuestion
        legend="Quanto o grupo entende sobre o que foi montado e programado?"
        onChange={(understanding) => setAnswers({ ...answers, understanding })}
        options={[
          [1, "Ainda não entendemos"],
          [2, "Entendemos um pouco"],
          [3, "Entendemos bem"],
          [4, "Conseguimos explicar"]
        ]}
        value={answers.understanding}
      />
      <ScaleQuestion
        legend="Quanto vocês gostariam de participar de outra atividade como esta?"
        onChange={(returnIntent) => setAnswers({ ...answers, returnIntent })}
        options={[
          [1, "Não gostaríamos"],
          [2, "Talvez não"],
          [3, "Talvez sim"],
          [4, "Gostaríamos muito"]
        ]}
        value={answers.returnIntent}
      />
      <OptionQuestion
        legend="Qual palavra melhor resume a sensação do grupo agora?"
        onChange={(affect) => setAnswers({ ...answers, affect })}
        options={[
          ["frustrated", "Frustração"],
          ["tired", "Cansaço"],
          ["curious", "Curiosidade"],
          ["confident", "Orgulho e confiança"]
        ]}
        value={answers.affect}
      />
    </Card>
  );
}

function FinishedScreen({ pendingCount, onDownload, onRestart }) {
  return (
    <Card
      compact
      eyebrow="Tudo pronto"
      title="Oficina concluída com sucesso!"
      description="Todas as respostas e a telemetria do grupo foram salvas com segurança no dispositivo."
      footer={
        <div className="action-row">
          <button className="button button--ghost" onClick={onDownload} type="button">
            Baixar cópia local (.json)
          </button>
          <button className="button button--primary" onClick={onRestart} type="button">
            Preparar Nova Oficina
          </button>
        </div>
      }
    >
      <div className="summary-status summary-status--success">
        <span className="summary-status__mark">✓</span>
        <div>
          <span>Sessão concluída</span>
          <h2>Parabéns pelo trabalho!</h2>
          {pendingCount === 0 ? (
            <p>Todos os registros foram sincronizados com a nuvem da pesquisa com sucesso.</p>
          ) : (
            <p>{pendingCount} registro(s) salvos no computador. Serão sincronizados automaticamente com a nuvem assim que houver conexão à internet.</p>
          )}
        </div>
      </div>
    </Card>
  );
}

function EvidencePanel({ events }) {
  const ordered = [...events].sort((left, right) => right._sequence - left._sequence);
  return (
    <aside className="evidence-panel">
      <header className="evidence-panel__header">
        <div>
          <span>Somente laboratório</span>
          <h2>Outbox local</h2>
        </div>
        <span className="quality-pill quality-pill--neutral">{events.length} eventos</span>
      </header>
      <div className="event-list">
        {ordered.length ? ordered.map((event) => (
          <article className="event-row" key={event.event_id}>
            <span className={`event-row__icon ${event.participant_id ? "event-row__icon--response" : ""}`}>•</span>
            <span>
              <strong>{formatEventName(event.event_type)}</strong>
              <small>{event.activity_stage || "sessão"}</small>
            </span>
            <span className={`delivery delivery--${event._delivery_state}`}>
              {event._delivery_state === "delivered" || event._delivery_state === "synced" ? "nuvem ✓" : "pendente ⏳"}
            </span>
          </article>
        )) : (
          <div className="empty-events">
            <span>○</span>
            <p>Os eventos da oficina aparecerão aqui.</p>
          </div>
        )}
      </div>
    </aside>
  );
}

function CheckpointAlertModal({ mark, onProceed }) {
  return (
    <div className="alert-modal-backdrop" role="dialog" aria-modal="true">
      <div className="alert-modal">
        <div className="alert-modal__icon">🤖</div>
        <span className="alert-modal__eyebrow">Aviso da Oficina · PulseLab</span>
        <h2>Hora do Check-in de {mark} minutos!</h2>
        <p>Pausa rápida de 30 segundos na montagem e programação do robô LEGO SPIKE para vocês registrarem como está o progresso.</p>
        <div className="alert-modal__actions">
          <button className="button button--primary button--pulse" onClick={onProceed} type="button" autoFocus>
            Responder Check-in Agora (30s)
          </button>
        </div>
      </div>
    </div>
  );
}

export default function StudentPage() {
  const labMode = useMemo(() => new URLSearchParams(window.location.search).get("lab") === "1", []);
  const savedSession = useMemo(() => readJson(ACTIVE_SESSION_KEY, null), []);

  const [context, setContext] = useState(() => readJson(CONTEXT_KEY, DEFAULT_CONTEXT));
  const [resumable, setResumable] = useState(savedSession);
  const VALID_SCREENS = ["pre", "activity", "checkpoint20", "checkpoint40", "post", "finished"];
  const [screen, setScreen] = useState(() => {
    if (savedSession?.screen && VALID_SCREENS.includes(savedSession.screen)) {
      return savedSession.screen;
    }
    return "pre";
  });
  const [sessionId, setSessionId] = useState(() => savedSession?.sessionId || createUuid());
  const [groupId, setGroupId] = useState(() => savedSession?.groupId || createUuid());
  const [installationId] = useState(getInstallationId);
  const [startedAt, setStartedAt] = useState(() => savedSession?.startedAt || Date.now());
  const [activityStartedAt, setActivityStartedAt] = useState(() => savedSession?.activityStartedAt || null);
  const [elapsedMs, setElapsedMs] = useState(() => {
    if (savedSession?.activityStartedAt) {
      return Math.max(0, Date.now() - savedSession.activityStartedAt);
    }
    return savedSession?.elapsedMs || 0;
  });
  const [currentMark, setCurrentMark] = useState(() => savedSession?.currentMark || 20);
  const [timeline, setTimeline] = useState(() => savedSession?.timeline || []);
  const [responses, setResponses] = useState(() => savedSession?.responses || []);
  const [spikeTelemetry, setSpikeTelemetry] = useState(() => savedSession?.spikeTelemetry || null);
  const [preAnswers, setPreAnswers] = useState(() => ({
    ...PRE_DEFAULT,
    ...(savedSession?.preAnswers && typeof savedSession.preAnswers === "object" ? savedSession.preAnswers : {})
  }));
  const [checkpoint20Answers, setCheckpoint20Answers] = useState(() => ({
    ...CHECKPOINT_DEFAULT,
    ...(savedSession?.checkpoint20Answers && typeof savedSession.checkpoint20Answers === "object" ? savedSession.checkpoint20Answers : {})
  }));
  const [checkpoint40Answers, setCheckpoint40Answers] = useState(() => ({
    ...CHECKPOINT_DEFAULT,
    ...(savedSession?.checkpoint40Answers && typeof savedSession.checkpoint40Answers === "object" ? savedSession.checkpoint40Answers : {})
  }));
  const [postAnswers, setPostAnswers] = useState(() => ({
    ...POST_DEFAULT,
    ...(savedSession?.postAnswers && typeof savedSession.postAnswers === "object" ? savedSession.postAnswers : {})
  }));
  const [online, setOnline] = useState(() => navigator.onLine);
  const [toast, setToast] = useState("");
  const [checkpointModalMark, setCheckpointModalMark] = useState(null);
  const [showInstructorTools, setShowInstructorTools] = useState(labMode);
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const sequenceRef = useRef(savedSession?.sequence || 0);
  const checkpointOpeningRef = useRef(false);

  const allEvents = [...timeline, ...responses];
  const pendingCount = allEvents.filter((event) => event._delivery_state === "queued").length;
  const activeStep = stepForScreen(screen);

  function flash(message) {
    setToast(message);
    window.setTimeout(() => setToast(""), 3200);
  }

  function eventBase(eventType, overrides = {}) {
    const now = Date.now();
    sequenceRef.current += 1;
    return {
      event_id: createUuid(),
      session_id: sessionId,
      dyad_id: groupId,
      installation_id: installationId,
      site_id: context.site_id,
      regional_hub: context.regional,
      school_code: context.school,
      workshop_code: context.workshop,
      class_code: context.class,
      activity_id: context.activity,
      computer_id: "BROWSER-PWA",
      protocol_version: "protocolo-pesquisa-v1",
      occurred_at: new Date(now).toISOString(),
      elapsed_ms: Math.max(0, now - startedAt),
      client_version: CLIENT_VERSION,
      config_version: "student-pwa-v1",
      config_hash: CONFIG_HASH,
      _delivery_state: "queued",
      _sequence: sequenceRef.current,
      _client_occurred_at: new Date(now).toISOString(),
      event_type: eventType,
      ...overrides
    };
  }

  function updateEventDeliveryState(eventId, state) {
    setTimeline((prev) =>
      prev.map((ev) => (ev.event_id === eventId ? { ...ev, _delivery_state: state } : ev))
    );
    setResponses((prev) =>
      prev.map((ev) => (ev.event_id === eventId ? { ...ev, _delivery_state: state } : ev))
    );
  }

  function persist(event) {
    void saveEvent(event).catch(() =>
      flash("Não foi possível salvar no armazenamento local deste navegador.")
    );
    void notifyBridgeEvent(event);
    if (typeof navigator !== "undefined" && navigator.onLine) {
      void syncSingleEvent(event).then((synced) => {
        if (synced) {
          updateEventDeliveryState(event.event_id, "delivered");
        }
      });
    }
  }

  function emitTimeline(eventType, overrides = {}) {
    const event = eventBase(eventType, {
      _target_table: "research_session_events",
      severity: "info",
      interval_mark: null,
      participant_id: null,
      participant_role: null,
      activity_stage: null,
      scheduled_at: null,
      details: { runtime: "browser_pwa" },
      ...overrides
    });
    setTimeline((current) => [...current, event]);
    persist(event);
    return event;
  }

  function emitResponse(eventType, overrides = {}) {
    const event = eventBase(eventType, {
      _target_table: "research_events",
      participant_id: `${sessionId.slice(0, 8).toUpperCase()}-GRUPO`,
      participant_role: "group",
      response_status: "completed",
      interval_mark: null,
      group_size: 2,
      activity_stage: null,
      ...overrides
    });
    setResponses((current) => [...current, event]);
    persist(event);
    return event;
  }

  async function captureSpikeTelemetry(stageLabel) {
    const metrics = await fetchBridgeSpikeMetrics();
    if (metrics && metrics.project_saved !== false) {
      setSpikeTelemetry(metrics);
      emitTimeline("spike_telemetry", {
        activity_stage: stageLabel,
        details: {
          executable_blocks: metrics.executable_blocks,
          inferred_stage: metrics.inferred_stage,
          uses_motor: metrics.uses_motor,
          uses_sensor: metrics.uses_sensor,
          uses_loop: metrics.uses_loop,
          uses_condition: metrics.uses_condition
        }
      });
    }
  }

  function resumeSession() {
    if (!resumable) return;
    setContext(resumable.context || DEFAULT_CONTEXT);
    setSessionId(resumable.sessionId);
    setGroupId(resumable.groupId);
    setStartedAt(resumable.startedAt);
    setActivityStartedAt(resumable.activityStartedAt);
    setElapsedMs(resumable.activityStartedAt ? Math.max(0, Date.now() - resumable.activityStartedAt) : (resumable.elapsedMs || 0));
    setCurrentMark(resumable.currentMark || 20);
    setTimeline(resumable.timeline || []);
    setResponses(resumable.responses || []);
    setSpikeTelemetry(resumable.spikeTelemetry || null);
    setPreAnswers(resumable.preAnswers || PRE_DEFAULT);
    setCheckpoint20Answers(resumable.checkpoint20Answers || CHECKPOINT_DEFAULT);
    setCheckpoint40Answers(resumable.checkpoint40Answers || CHECKPOINT_DEFAULT);
    setPostAnswers(resumable.postAnswers || POST_DEFAULT);
    sequenceRef.current = resumable.sequence || 0;
    setScreen(resumable.screen);
    flash("Sessão retomada do armazenamento local.");
  }

  function submitPre() {
    requestNotificationPermission();

    emitTimeline("session_started", {
      activity_stage: "init",
      details: { runtime: "browser_pwa" }
    });

    emitResponse("pre", {
      activity_stage: "pre",
      prior_robotics: preAnswers.experience,
      self_efficacy_pre: preAnswers.confidence
    });

    const activityStart = Date.now();
    setActivityStartedAt(activityStart);
    setElapsedMs(0);
    void notifyBridgeSession(sessionId, activityStart, [20, 40]);
    emitTimeline("phase_completed", { activity_stage: "pre" });
    emitTimeline("activity_started", {
      activity_stage: "activity",
      details: { runtime: "browser_pwa", checkpoints_minutes: [20, 40] }
    });
    void captureSpikeTelemetry("activity_start");
    setResumable(null);
    setScreen("activity");
  }

  function triggerCheckpointAlert(mark = currentMark) {
    if (checkpointOpeningRef.current) return;
    playChimeSound();
    showWebNotification(mark);
    void triggerBridgeAlert(mark);
    setCheckpointModalMark(mark);

    if (document.hidden) {
      let toggle = false;
      const originalTitle = document.title;
      const titleTimer = window.setInterval(() => {
        document.title = toggle ? `🔔 [Check-in ${mark}m] PulseLab` : "PulseLab - Oficina de Robótica";
        toggle = !toggle;
      }, 1000);

      const onFocus = () => {
        window.clearInterval(titleTimer);
        document.title = originalTitle;
        window.removeEventListener("focus", onFocus);
      };
      window.addEventListener("focus", onFocus);
    }
  }

  function handleProceedFromModal() {
    const markToOpen = checkpointModalMark || currentMark;
    setCheckpointModalMark(null);
    openCheckpoint(markToOpen);
  }

  function openCheckpoint(mark = currentMark) {
    if (checkpointOpeningRef.current) return;
    checkpointOpeningRef.current = true;
    setCheckpointModalMark(null);
    const checkpointElapsed = Math.max(elapsedMs, mark * 60 * 1000);
    setElapsedMs(checkpointElapsed);
    void notifyBridgeCheckpointAck(sessionId, mark);
    emitTimeline("checkpoint_started", {
      activity_stage: `checkpoint_${mark}`,
      interval_mark: mark,
      elapsed_ms: checkpointElapsed,
      details: {
        runtime: "browser_pwa",
        scheduled_minute: mark
      }
    });
    void captureSpikeTelemetry(`checkpoint_${mark}`);
    setScreen(mark === 20 ? "checkpoint20" : "checkpoint40");
  }

  function submitCheckpoint(mark) {
    const answers = mark === 20 ? checkpoint20Answers : checkpoint40Answers;
    emitResponse("checkpoint", {
      activity_stage: `checkpoint_${mark}`,
      interval_mark: mark,
      mental_effort: answers.effort,
      progress_state: answers.progress,
      collaboration: answers.collaboration,
      help_requested: answers.help
    });

    if (answers.help) {
      emitTimeline("help_requested", {
        activity_stage: `checkpoint_${mark}`,
        details: { runtime: "browser_pwa" }
      });
    }

    void notifyBridgeCheckpointAck(sessionId, mark);
    emitTimeline("checkpoint_completed", {
      activity_stage: `checkpoint_${mark}`,
      interval_mark: mark,
      elapsed_ms: elapsedMs,
      details: { runtime: "browser_pwa" }
    });

    void captureSpikeTelemetry(`checkpoint_${mark}_done`);
    checkpointOpeningRef.current = false;

    if (mark === 20) {
      setCurrentMark(40);
      setScreen("activity");
    } else {
      setScreen("post");
    }
  }

  function submitPost() {
    emitResponse("post", {
      activity_stage: "post",
      post_understanding: postAnswers.understanding,
      post_affects: [postAnswers.affect],
      post_return_intent: postAnswers.returnIntent
    });

    emitTimeline("phase_completed", { activity_stage: "post" });
    emitTimeline("session_completed", {
      activity_stage: "completed",
      details: { runtime: "browser_pwa" }
    });

    void captureSpikeTelemetry("session_completed");
    localStorage.removeItem(ACTIVE_SESSION_KEY);
    void runSync(true);
    setScreen("finished");
  }

  function resetToPre() {
    localStorage.removeItem(ACTIVE_SESSION_KEY);
    void resetBridgeSession();
    const nextSessionId = createUuid();
    const nextGroupId = createUuid();
    setSessionId(nextSessionId);
    setGroupId(nextGroupId);
    setStartedAt(Date.now());
    setActivityStartedAt(null);
    setElapsedMs(0);
    setCurrentMark(20);
    setTimeline([]);
    setResponses([]);
    setSpikeTelemetry(null);
    setPreAnswers(PRE_DEFAULT);
    setCheckpoint20Answers(CHECKPOINT_DEFAULT);
    setCheckpoint40Answers(CHECKPOINT_DEFAULT);
    setPostAnswers(POST_DEFAULT);
    setCheckpointModalMark(null);
    sequenceRef.current = 0;
    checkpointOpeningRef.current = false;
    setResumable(null);
    setScreen("pre");
    flash("Oficina reiniciada do zero com sucesso.");
  }

  function handleConfirmReset() {
    const confirmed = window.confirm(
      "Deseja realmente reiniciar a oficina do zero?\n\nIsso apagará a sessão atual neste computador e iniciará uma nova oficina limpa."
    );
    if (!confirmed) return;
    resetToPre();
  }

  function forceCheckpoint(mark = currentMark) {
    if (screen === "pre") {
      const now = Date.now();
      setActivityStartedAt(now);
      setElapsedMs(mark * 60 * 1000);
      setScreen("activity");
    }
    triggerCheckpointAlert(mark);
  }

  function forcePost() {
    checkpointOpeningRef.current = false;
    setCheckpointModalMark(null);
    setScreen("post");
    flash("Avançado para a finalização pós-oficina.");
  }

  function addMinutes(minutes = 5) {
    if (!activityStartedAt) {
      const now = Date.now();
      setActivityStartedAt(now - minutes * 60 * 1000);
      setElapsedMs(minutes * 60 * 1000);
    } else {
      setActivityStartedAt((prev) => prev - minutes * 60 * 1000);
      setElapsedMs((prev) => prev + minutes * 60 * 1000);
    }
    flash(`Cronômetro adiantado em +${minutes} minutos.`);
  }

  function testSoundAndAlert() {
    triggerCheckpointAlert(currentMark);
    flash("Som e Pop-up disparados para demonstração!");
  }

  function autoFillCurrentStep() {
    if (screen === "pre") {
      setPreAnswers({ experience: 2, confidence: 3 });
      flash("Início preenchido. Clique em 'Começar Atividade!'");
    } else if (screen === "activity") {
      triggerCheckpointAlert(currentMark);
    } else if (screen === "checkpoint20") {
      setCheckpoint20Answers({ effort: 2, progress: "progressing_with_doubt", collaboration: 3, help: false });
      flash("Check-in 20m preenchido. Clique em 'Salvar e continuar'");
    } else if (screen === "checkpoint40") {
      setCheckpoint40Answers({ effort: 3, progress: "progressing_independently", collaboration: 4, help: false });
      flash("Check-in 40m preenchido. Clique em 'Salvar e continuar'");
    } else if (screen === "post") {
      setPostAnswers({ understanding: 3, affect: "confident", returnIntent: 4 });
      flash("Finalização preenchida. Clique em 'Concluir Oficina'");
    }
  }

  function downloadSession() {
    const payload = JSON.stringify({ session_id: sessionId, context, events: allEvents, spike_telemetry: spikeTelemetry }, null, 2);
    const blob = new Blob([payload], { type: "application/json" });
    const link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = `pulselab-${sessionId.slice(0, 8)}.json`;
    link.click();
    URL.revokeObjectURL(link.href);
  }

  async function runSync(showFeedback = false) {
    if (typeof navigator !== "undefined" && !navigator.onLine) return;
    try {
      const result = await flushPendingEvents((syncedId) => {
        updateEventDeliveryState(syncedId, "delivered");
      });
      if (result.synced > 0 && showFeedback) {
        flash(`Sincronizados ${result.synced} registro(s) com a nuvem da pesquisa.`);
      }
    } catch {
      // Falha silenciosa de rede
    }
  }

  async function syncNow() {
    if (!navigator.onLine) {
      flash("Computador sem conexão com a internet no momento. Os registros continuam salvos com segurança no dispositivo.");
      return;
    }
    flash("Sincronizando com a nuvem da pesquisa...");
    const result = await flushPendingEvents((syncedId) => {
      updateEventDeliveryState(syncedId, "delivered");
    });
    if (result.synced > 0) {
      flash(`Sucesso! ${result.synced} registro(s) sincronizados com o Supabase.`);
    } else if (result.remaining === 0) {
      flash("Todos os registros já estão sincronizados com a nuvem da pesquisa!");
    } else {
      flash("Tentativa concluída. Eventos pendentes continuarão sendo enviados automaticamente.");
    }
  }

  useEffect(() => {
    const handleOnline = () => {
      setOnline(true);
      void runSync(true);
    };
    const handleOffline = () => setOnline(false);

    window.addEventListener("online", handleOnline);
    window.addEventListener("offline", handleOffline);

    // Sincroniza eventos pendentes logo na inicialização
    void runSync(false);

    // Varredura periódica a cada 20 segundos
    const syncTimer = window.setInterval(() => {
      if (typeof navigator !== "undefined" && navigator.onLine) {
        void runSync(false);
      }
    }, 20000);

    return () => {
      window.removeEventListener("online", handleOnline);
      window.removeEventListener("offline", handleOffline);
      window.clearInterval(syncTimer);
    };
  }, []);

  useEffect(() => {
    if (screen !== "activity" || !activityStartedAt) return undefined;
    const tick = () => {
      const nextElapsed = Math.max(0, Date.now() - activityStartedAt);
      setElapsedMs(nextElapsed);
      if (nextElapsed >= currentMark * 60 * 1000 && !checkpointOpeningRef.current && checkpointModalMark === null) {
        triggerCheckpointAlert(currentMark);
      }
    };
    tick();
    const timer = window.setInterval(tick, 1000);
    return () => window.clearInterval(timer);
  }, [activityStartedAt, checkpointModalMark, currentMark, screen]);

  useEffect(() => {
    if (screen === "finished") return;
    const snapshot = {
      sessionId,
      groupId,
      context,
      startedAt,
      activityStartedAt,
      elapsedMs,
      currentMark,
      screen,
      timeline,
      responses,
      spikeTelemetry,
      preAnswers,
      checkpoint20Answers,
      checkpoint40Answers,
      postAnswers,
      sequence: sequenceRef.current,
      savedAt: new Date().toISOString()
    };
    localStorage.setItem(ACTIVE_SESSION_KEY, JSON.stringify(snapshot));
    void saveSession({ session_id: sessionId, status: "in_progress", ...snapshot }).catch(() => {});
  }, [activityStartedAt, checkpoint20Answers, checkpoint40Answers, context, currentMark, elapsedMs, groupId, postAnswers, preAnswers, responses, screen, sessionId, spikeTelemetry, startedAt, timeline]);

  let content;

  if (screen === "pre") {
    content = (
      <PreScreen
        answers={preAnswers}
        resumable={resumable}
        onResume={resumeSession}
        setAnswers={setPreAnswers}
        onSubmit={submitPre}
      />
    );
  } else if (screen === "activity") {
    content = <ActivityScreen currentMark={currentMark} elapsedMs={elapsedMs} labMode={labMode} spikeTelemetry={spikeTelemetry} />;
  } else if (screen === "checkpoint20") {
    content = (
      <CheckpointScreen
        answers={checkpoint20Answers}
        mark={20}
        setAnswers={setCheckpoint20Answers}
        onSubmit={() => submitCheckpoint(20)}
      />
    );
  } else if (screen === "checkpoint40") {
    content = (
      <CheckpointScreen
        answers={checkpoint40Answers}
        mark={40}
        setAnswers={setCheckpoint40Answers}
        onSubmit={() => submitCheckpoint(40)}
      />
    );
  } else if (screen === "post") {
    content = (
      <PostScreen
        answers={postAnswers}
        setAnswers={setPostAnswers}
        onSubmit={submitPost}
      />
    );
  } else {
    content = <FinishedScreen pendingCount={pendingCount} onDownload={downloadSession} onRestart={resetToPre} />;
  }

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <span className="brand__mark" aria-hidden="true">
            <img src="/alunos/robot.png" alt="Robô PulseLab" style={{ width: "32px", height: "32px", objectFit: "contain" }} />
          </span>
          <span>
            <strong>PulseLab</strong>
            <small>oficina de robótica · v1.9.0</small>
          </span>
        </div>
        <div className="topbar__notice">
          <span>{labMode ? "LAB" : "OFFLINE"}</span>
          <p>{labMode ? "Modo acelerado para testes" : "Sem burocracia · telemetria automática do SPIKE"}</p>
        </div>
        <div className="topbar__controls">
          <button
            className={`topbar-btn ${sidebarOpen ? "is-active" : ""}`}
            onClick={() => setSidebarOpen((v) => !v)}
            title="Ver etapas da oficina (barra lateral retrátil)"
            type="button"
          >
            🧭 Etapas ({activeStep}/4)
          </button>
          <div className="topbar__session">
            <span>Sessão</span>
            <code>{sessionId.slice(0, 8).toUpperCase()}</code>
          </div>
          <button
            className={`topbar-btn ${showInstructorTools ? "is-active" : ""}`}
            onClick={() => setShowInstructorTools((v) => !v)}
            title="Abrir controles do instrutor e demonstração rápida"
            type="button"
          >
            ⚙️ Controles
          </button>
          <button
            className="topbar-btn topbar-btn--danger"
            onClick={handleConfirmReset}
            title="Reiniciar oficina do zero"
            type="button"
          >
            🔄 Reiniciar
          </button>
        </div>
      </header>

      {showInstructorTools ? (
        <div className="instructor-banner">
          <div className="instructor-banner__info">
            <strong>🛠️ Controles de Demonstração & Instrutor</strong>
            <span>Avance etapas instantaneamente ou teste os alertas sonoros e visuais</span>
          </div>
          <div className="instructor-banner__actions">
            <button className="inst-btn" onClick={() => forceCheckpoint(20)} type="button">
              ⏩ Check-in 20m
            </button>
            <button className="inst-btn" onClick={() => forceCheckpoint(40)} type="button">
              ⏩ Check-in 40m
            </button>
            <button className="inst-btn" onClick={forcePost} type="button">
              🏁 Ir para Finalizar
            </button>
            <button className="inst-btn" onClick={() => addMinutes(5)} type="button">
              ⏱️ +5 min relógio
            </button>
            <button className="inst-btn inst-btn--accent" onClick={testSoundAndAlert} type="button">
              🔔 Testar Som & Pop-up
            </button>
            <button className="inst-btn" onClick={autoFillCurrentStep} type="button">
              ✨ Preencher teste
            </button>
            <button className="inst-btn inst-btn--accent" onClick={syncNow} type="button">
              ☁️ Sincronizar Nuvem
            </button>
            <button className="inst-btn inst-btn--danger" onClick={handleConfirmReset} type="button">
              🔄 Reiniciar Oficina
            </button>
          </div>
        </div>
      ) : null}

      {checkpointModalMark ? (
        <CheckpointAlertModal
          mark={checkpointModalMark}
          onProceed={handleProceedFromModal}
        />
      ) : null}

      {sidebarOpen ? (
        <div
          className="sidebar-backdrop"
          onClick={() => setSidebarOpen(false)}
          aria-hidden="true"
        />
      ) : null}

      <aside className={`flow-sidebar ${sidebarOpen ? "is-open" : ""}`}>
        <div className="flow-sidebar__header">
          <div>
            <span>Progresso da oficina</span>
            <strong>{activeStep}/4</strong>
          </div>
          <button
            className="sidebar-close-btn"
            onClick={() => setSidebarOpen(false)}
            title="Fechar etapas"
            type="button"
            aria-label="Fechar etapas"
          >
            ✕
          </button>
        </div>
        <nav aria-label="Etapas da atividade">
          {FLOW_STEPS.map((step) => (
            <div className={`flow-step ${step.id === activeStep ? "is-active" : ""} ${step.id < activeStep ? "is-complete" : ""}`} key={step.id}>
              <span>{step.id < activeStep ? "✓" : step.id}</span>
              <strong>{step.label}</strong>
            </div>
          ))}
        </nav>
        <div className="sidebar-context">
          <span>Oficina LEGO SPIKE</span>
          <strong>Desafio Ativo</strong>
          <small>Coleta anônima por grupo</small>
        </div>
      </aside>

      <div className={`workspace-shell ${labMode ? "workspace-shell--lab" : "workspace-shell--student"}`}>
        <section className="simulator-stage">
          <div className="stage-toolbar">
            <div>
              <span className={`connection-dot ${online ? "is-online" : ""}`} />
              <strong>{online ? (pendingCount === 0 ? "Nuvem Conectada · Sincronizado" : "Conectado · Sincronizando...") : "Funcionando 100% offline"}</strong>
              <small>{pendingCount === 0 ? "Todos os registros salvos na nuvem" : `${pendingCount} registro(s) pendente(s)`}</small>
            </div>
            {labMode ? (
              <>
                <button className="toolbar-button" onClick={() => setOnline((value) => !value)} type="button">Alternar rede</button>
                <button className="toolbar-button is-accent" onClick={syncNow} type="button">☁️ Sincronizar Nuvem</button>
              </>
            ) : null}
          </div>
          <div className="stage-scroll">{content}</div>
        </section>

        {labMode ? <EvidencePanel events={allEvents} /> : null}
      </div>

      {toast ? <div className="toast"><span>✓</span>{toast}</div> : null}
    </main>
  );
}
