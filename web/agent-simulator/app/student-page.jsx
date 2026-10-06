import React, { useEffect, useMemo, useRef, useState } from "react";
import {
  CONFIG_HASH,
  PROTOCOL_VERSION,
  createUuid,
  formatEventName
} from "../lib/contracts.js";
import {
  enforceAbsoluteRetention,
  purgeSession,
  saveEvent,
  saveSession,
  getLocalStoreSummary
} from "../lib/student-store.js";
import {
  flushPendingEvents,
  syncSingleEvent
} from "../lib/sync-engine.js";
import {
  downloadSessionData,
  isAllAssented,
  isPostScreenReady,
  resolveMemberExperiences,
  validateFinalTelemetry,
  structuralSpikeMetrics,
  validateRestoredSession
} from "../lib/evaluation.js";

const ACTIVE_SESSION_KEY = "pulselab_student_active_session_v1";
const CONTEXT_KEY = "pulselab_student_context_v1";
const INSTALLATION_KEY = "pulselab_installation_id_v1";
const LEGACY_INSTALLATION_KEY = "pulselab_student_installation_id_v1";
const CLIENT_VERSION = "student-pwa/2.2.2";

const DEFAULT_CONTEXT = {
  regional: "Nordeste",
  site_id: "Polo-Nordeste",
  school: "geral",
  workshop: "oficina-spike",
  class: "turma-geral",
  activity: "atividade-01-spike"
};

const PRE_DEFAULT = { experience: null };
const POST_DEFAULT = {
  experience: null,
  experienceSkipped: false,
  memberExperiences: [],
  raceResult: null,
  raceTimeSeconds: "",
  assemblyResult: null,
  quizCompleted: null,
  supportLevel: null
};

const EXPERIENCE_OPTIONS = [
  [1, "🐣 Primeira vez", "Ninguém na bancada mexeu com robôs"],
  [2, "🧩 Pouca prática", "Alguém já viu ou usou 1 ou 2 vezes"],
  [3, "🚀 Já praticamos", "Já montamos ou programamos antes"],
  [4, "⚡ Muita prática", "Temos facilidade com montagem e código"]
];

const POST_EXPERIENCE_OPTIONS = [
  [1, "😞 Muito ruim", "Não gostei da experiência"],
  [2, "🙁 Ruim", "Poderia ter sido melhor"],
  [3, "😐 Nem boa nem ruim", "Achei normal"],
  [4, "🙂 Boa", "Gostei da oficina"],
  [5, "😄 Muito boa", "Adorei a atividade"]
];

const RACE_RESULT_OPTIONS = [
  ["success", "🏆 Concluiu com sucesso", "Carrinho completou o percurso no circuito"],
  ["partial", "⏱️ Não concluiu o percurso", "Travou, saiu da pista ou precisou de ajuste"],
  ["tech_failure", "⚠️ Falha técnica / Bluetooth", "Problema de bateria, desconexão ou peça solta"],
  ["not_observed", "👁️ Não observado / Sem oportunidade", "Não houve teste na pista ou não foi observado"]
];

const ASSEMBLY_OPTIONS = [
  ["complete", "🧩 Concluída conforme o roteiro", "Estrutura firme, motores e rodas alinhados"],
  ["partial", "🔧 Parcial / com adaptações", "Montagem com peças faltantes ou ajustes manuais"],
  ["incomplete", "❌ Não concluída", "Não completou a estrutura básica do carrinho"],
  ["not_observed", "👁️ Não observado", "Não foi possível verificar a montagem física"]
];

const QUIZ_OPTIONS = [
  ["participated", "🎮 Realizada com botões do robô", "A bancada participou da dinâmica lúdica A/B"],
  ["skipped", "⏭️ Dinâmica não realizada", "Tempo insuficiente ou atividade não aplicada"],
  ["not_applicable", "🚫 Não aplicável", "Oficina sem previsão dessa dinâmica"]
];

const SUPPORT_OPTIONS = [
  ["independent", "🟢 Autônomo", "Trabalharam praticamente sozinhos"],
  ["occasional", "🟡 Apoio pontual", "Dúvidas breves tiradas com o instrutor"],
  ["constant", "🔴 Apoio constante", "Mediação intensiva necessária durante a oficina"],
  ["not_observed", "👁️ Não observado", "Nível de apoio não registrado"]
];

const BRIDGE_PORT = 43128;
const BRIDGE_URL = `http://127.0.0.1:${BRIDGE_PORT}`;

async function notifyBridgeSession(sessionId, startedAt, marks = [], allowed = true) {
  if (!allowed) return;
  try {
    await fetch(`${BRIDGE_URL}/v1/sessions`, {
      signal: AbortSignal.timeout(1500),
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ session_id: sessionId, started_at: startedAt, marks })
    });
  } catch {
    // Operação normal mesmo sem o Bridge
  }
}

async function fetchBridgeSpikeMetrics() {
  try {
    const res = await fetch(`${BRIDGE_URL}/v1/spike/metrics`, { signal: AbortSignal.timeout(1500) });
    if (res.ok) {
      return structuralSpikeMetrics(await res.json());
    }
  } catch {
    // Bridge offline ou inacessível
  }
  return null;
}

async function fetchBridgeConfig() {
  try {
    const res = await fetch(`${BRIDGE_URL}/v1/config`, { signal: AbortSignal.timeout(1500) });
    if (res.ok) {
      return await res.json();
    }
  } catch {
    // Bridge offline ou inacessível
  }
  return null;
}

async function notifyBridgeEvent(event, allowed = true) {
  if (!allowed) return;
  try {
    await fetch(`${BRIDGE_URL}/v1/events`, {
      signal: AbortSignal.timeout(1500),
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(event)
    });
  } catch {
    // Operação normal mesmo sem o Bridge
  }
}

async function notifyBridgeSessionSave(sessionPayload, allowed = true) {
  if (!allowed) return;
  try {
    await fetch(`${BRIDGE_URL}/v1/sessions/save`, {
      signal: AbortSignal.timeout(1500),
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(sessionPayload)
    });
  } catch {
    // Operação normal mesmo sem o Bridge
  }
}

async function resetBridgeSession(sessionId = null, options = {}) {
  const response = await fetch(`${BRIDGE_URL}/v1/sessions/reset`, {
      signal: AbortSignal.timeout(1500),
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        session_id: sessionId,
        reason: options.reason || (options.purge ? "ethical_refusal" : "prepare_next"),
        purge: Boolean(options.purge),
        completed: Boolean(options.completed)
      })
    });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || (options.purge && (payload.purged !== true || payload.remote_pending === true))) {
    throw new Error(payload.error || payload.status || `Bridge reset failed (${response.status})`);
  }
  return payload;
}

function readJson(key, fallback) {
  try {
    const value = localStorage.getItem(key);
    return value ? JSON.parse(value) : fallback;
  } catch {
    return fallback;
  }
}

function getPersistedInstallationId() {
  try {
    return localStorage.getItem(INSTALLATION_KEY) || localStorage.getItem(LEGACY_INSTALLATION_KEY) || null;
  } catch {
    return null;
  }
}

function getInstallationId(fallbackId = null) {
  return getPersistedInstallationId() || fallbackId || createUuid();
}

function getComputerId(installationId) {
  const id = installationId || getPersistedInstallationId() || "000000";
  return `PC-${id.slice(0, 6).toUpperCase()}`;
}

function getSystemMetadata() {
  if (typeof window === "undefined") return { os: "Desktop", screen_resolution: "1920x1080" };
  const userAgent = navigator.userAgent || "";
  let os = "Desktop";
  if (userAgent.includes("Windows")) os = "Windows";
  else if (userAgent.includes("Linux")) os = "Linux";
  else if (userAgent.includes("Android")) os = "Android";
  else if (userAgent.includes("Mac")) os = "macOS";
  else if (userAgent.includes("CrOS")) os = "ChromeOS";

  return {
    os,
    screen_resolution: `${window.screen?.width || 0}x${window.screen?.height || 0}`
  };
}

function ScaleQuestion({ legend, hint, options, value, onChange }) {
  return (
    <fieldset className="question-block">
      <legend>{legend}</legend>
      {hint ? <p>{hint}</p> : null}
      <div className="scale-grid">
        {options.map(([optionValue, label, sublabel], index) => {
          const parts = String(label).match(/^(\S+)\s+(.+)$/);
          const icon = parts ? parts[1] : (index + 1);
          const title = parts ? parts[2] : label;
          const isSelected = value === optionValue;
          return (
            <button
              className={`scale-option ${isSelected ? "is-selected" : ""}`}
              key={optionValue}
              onClick={() => onChange(optionValue)}
              type="button"
              aria-pressed={isSelected}
            >
              <span className="scale-option__icon" aria-hidden="true">{icon}</span>
              <strong className="scale-option__title">{title}</strong>
              {sublabel ? <small className="scale-option__sub">{sublabel}</small> : null}
            </button>
          );
        })}
      </div>
    </fieldset>
  );
}

function Card({ eyebrow, title, description, children, footer, compact = false }) {
  return (
    <section className={`flow-card ${compact ? "flow-card--compact" : ""}`}>
      <header className="flow-card__heading">
        <span className="eyebrow">{eyebrow}</span>
        <h1 tabIndex={-1} data-stage-heading>{title}</h1>
        <p>{description}</p>
      </header>
      <div className="flow-card__body">{children}</div>
      {footer ? <footer className="flow-card__footer">{footer}</footer> : null}
    </section>
  );
}

const REGIONS = [
  { id: "Nordeste", label: "☀️ Nordeste", desc: "Polo Regional Nordeste" },
  { id: "Sudeste", label: "🏙️ Sudeste", desc: "Polo Regional Sudeste" },
  { id: "Sul", label: "❄️ Sul", desc: "Polo Regional Sul" },
  { id: "Norte", label: "🌿 Norte", desc: "Polo Regional Norte" },
  { id: "Centro-Oeste", label: "🌾 Centro-Oeste", desc: "Polo Regional Centro-Oeste" }
];

function RegionMetadataModal({ isOpen, onClose, context, onSave, computerId, systemMetadata }) {
  const [selectedRegion, setSelectedRegion] = useState(context.regional || "Nordeste");
  const dialogRef = useRef(null);
  useEffect(() => {
    if (!isOpen) return;
    const previous = document.activeElement;
    const dialog = dialogRef.current;
    setSelectedRegion(context.regional || "Nordeste");
    dialog.showModal();
    return () => {
      dialog.close();
      previous?.focus();
    };
  }, [isOpen, context.regional]);
  return (
    <dialog ref={dialogRef} className="settings-dialog" aria-labelledby="region-modal-title"
      onKeyDown={(event) => {
        if (event.key !== "Tab") return;
        const buttons = dialogRef.current.querySelectorAll("button:not(:disabled)");
        const first = buttons[0], last = buttons[buttons.length - 1];
        if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
        else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
      }}
      onCancel={(event) => { event.preventDefault(); onClose(); }}>
      <h2 id="region-modal-title">Configuração da oficina</h2>
      <fieldset className="question-block">
        <legend>Região</legend>
        <div className="region-options">
          {REGIONS.map((region) => (
            <button key={region.id} type="button" className={`scale-option ${selectedRegion === region.id ? "is-selected" : ""}`}
              aria-pressed={selectedRegion === region.id} onClick={() => setSelectedRegion(region.id)}>{region.id}</button>
          ))}
        </div>
      </fieldset>
      <p>Computador: {computerId} · {systemMetadata.os} · {systemMetadata.screen_resolution}</p>
      <div className="action-row">
        <button className="button button--ghost" onClick={onClose} type="button">Cancelar</button>
        <button className="button button--primary" type="button" onClick={() => {
          onSave({ ...context, regional: selectedRegion, site_id: `Polo-${selectedRegion}` });
          onClose();
        }}>Salvar</button>
      </div>
    </dialog>
  );
}

function PreScreen({ answers, setAnswers, onSubmit, onDecline, teamSize, setTeamSize, memberAssents, setMemberAssents }) {
  const allAssented = isAllAssented(teamSize, memberAssents);
  const ready = !allAssented || answers.experience !== null;
  return (
    <Card eyebrow="1 de 3 · Antes de começar" title="Vamos montar e programar?"
      description="Robótica para todos. A pesquisa é opcional."
      footer={<div className="action-row">
        {allAssented && <button className="button button--ghost" onClick={onDecline} type="button">Começar sem pesquisa</button>}
        <button className="button button--primary" disabled={!ready} onClick={allAssented ? onSubmit : onDecline} type="button"
          aria-describedby={allAssented && !ready ? "experience-hint" : undefined}>
          {allAssented ? "Começar atividade" : "Começar sem pesquisa"}
        </button>
      </div>}>
      <fieldset className="question-block team-choice">
        <legend>Quantas pessoas na bancada?</legend>
        <div className="team-options">
          {[1, 2, 3, 4].map((size) => <button key={size} type="button"
            className={`scale-option ${teamSize === size ? "is-selected" : ""}`} aria-pressed={teamSize === size}
            aria-label={`${size} ${size === 1 ? "pessoa" : "pessoas"}`}
            onClick={() => setTeamSize(size)}><span>{size}</span><span className="team-option__unit">{size === 1 ? "pessoa" : "pessoas"}</span></button>)}
        </div>
      </fieldset>
      <fieldset className={`assent-panel ${allAssented ? "assent-panel--accepted" : "assent-panel--pending"}`} aria-describedby="assent-explanation">
        <legend>Vocês querem participar da pesquisa?</legend>
        <p id="assent-explanation">Cada pessoa decide e não usamos nomes. Se alguém não quiser, todos usam o LEGO SPIKE em <strong>Modo Livre: sem gravação nem envio de dados</strong>. Podem desistir e apagar os dados a qualquer momento.</p>
        <div className="assent-members">
          {Array.from({ length: teamSize }, (_, index) => {
            const member = index + 1;
            const accepted = memberAssents[member] === true;
            const id = member === 1 ? "ethical-assent-checkbox" : `ethical-assent-member-${member}`;
            return <label key={member} htmlFor={id} className={`assent-member ${accepted ? "assent-member--accepted" : ""}`}>
              <input id={id} type="checkbox" checked={accepted}
                onChange={(event) => setMemberAssents((prev) => ({ ...prev, [member]: event.target.checked }))} />
              <span><strong>Pessoa {member}:</strong> aceito</span>
            </label>;
          })}
        </div>
        <p className="assent-status" role="status">{allAssented ? "Todos aceitaram participar." : "Aguardando a escolha de cada pessoa."}</p>
        <details className="research-details">
          <summary>Sobre os dados da pesquisa</summary>
          <p>Os registros descrevem a bancada, sem identificar estudantes. Os dados locais são apagados em até 7 dias.
            Durante a oficina, use “Parar de participar e apagar meus dados” para sair da pesquisa.</p>
        </details>
      </fieldset>
      {allAssented && <>
        <ScaleQuestion legend="Já montaram ou programaram robôs ou blocos?"
          options={EXPERIENCE_OPTIONS} value={answers.experience} onChange={(experience) => setAnswers({ ...answers, experience })} />
        {answers.experience === null && <p id="experience-hint" className="choice-hint">Escolham uma opção ou comecem sem pesquisa.</p>}
      </>}
    </Card>
  );
}

function ActivityScreen({ onAdvanceToFinalChallenge, isFreeMode }) {
  return <Card eyebrow="2 de 3 · Mãos à obra" title="Montem, programem e testem o robô"
    description="Usem o kit e o aplicativo LEGO SPIKE para criar e testar o carrinho."
    footer={<div className="action-row"><button className="button button--primary" type="button" onClick={onAdvanceToFinalChallenge}>Ir para o desafio final</button></div>}>
    <div className="activity-guide">
      <p>Sigam a atividade e peçam ajuda ao educador quando precisarem.</p>
      <p>Voltem aqui para testar o carrinho na pista.</p>
    </div>
    {isFreeMode && <p className="free-mode-note">Modo Livre: a aula continua sem guardar dados da pesquisa.</p>}
  </Card>;
}

function RubricQuestion({ legend, name, options, value, onChange }) {
  return <fieldset className="question-block rubric-question"><legend>{legend}</legend>
    <div className="option-list">{options.map(([optionValue, label, hint]) => (
      <label key={optionValue} className={`option-row ${value === optionValue ? "is-selected" : ""}`}>
        <input type="radio" name={name} value={optionValue} checked={value === optionValue} onChange={() => onChange(optionValue)} />
        <span className="option-row__body"><strong>{label}</strong><small>{hint}</small></span>
      </label>
    ))}</div>
  </fieldset>;
}

function PostScreen({ answers, setAnswers, onSubmit, onDecline, teamSize, memberAssents, isFreeMode, submitting }) {
  const experiences = useMemo(() => resolveMemberExperiences(teamSize, memberAssents, answers.memberExperiences), [teamSize, memberAssents, answers.memberExperiences]);
  const ready = isPostScreenReady(teamSize, experiences);
  function updateMember(memberIndex, patch) {
    setAnswers({ ...answers, memberExperiences: experiences.map((member) => member.memberIndex === memberIndex ? { ...member, ...patch } : member) });
  }
  return <Card eyebrow="3 de 3 · Desafio final" title="Testem o carrinho na pista"
    description={isFreeMode ? "Façam o desafio com o educador e concluam a oficina." : "Façam o desafio com o educador. Depois, cada pessoa escolhe se quer avaliar a oficina."}
    footer={<div className="action-row">
      {!isFreeMode && <button className="button button--ghost" onClick={onDecline} disabled={submitting} type="button">Pular avaliação e concluir</button>}
      <button className="button button--primary" onClick={() => onSubmit()} disabled={submitting || (!isFreeMode && !ready)} type="button">{submitting ? "Concluindo…" : "Concluir oficina"}</button>
    </div>}>
    {!isFreeMode && <>
      <div className="member-evaluations">
        {experiences.map((member) => <fieldset className="question-block member-evaluation" key={member.memberIndex}>
          <legend>Pessoa {member.memberIndex}: como foi a oficina de robótica hoje?</legend>
          <div className="member-evaluation__actions"><button type="button" className="button button--ghost" aria-pressed={member.skipped}
            onClick={() => updateMember(member.memberIndex, { rating: null, skipped: !member.skipped })}>
            {member.skipped ? "Responder à avaliação" : "Prefiro não responder"}
          </button></div>
          {member.skipped ? <p>Você escolheu não responder. Tudo bem.</p> : <div className="scale-grid experience-grid">
            {POST_EXPERIENCE_OPTIONS.map(([value, label, hint]) => <button key={value} className={`scale-option ${member.rating === value ? "is-selected" : ""}`}
              type="button" aria-pressed={member.rating === value} onClick={() => updateMember(member.memberIndex, { rating: value, skipped: false })}>
              <span className="scale-option__icon" aria-hidden="true">{label.split(" ")[0]}</span>
              <strong className="scale-option__title">{label.slice(label.indexOf(" ") + 1)}</strong>
              <small className="scale-option__sub">{hint}</small>
            </button>)}
          </div>}
        </fieldset>)}
      </div>
      <details className="educator-rubric"><summary>Educador: observações do desafio</summary>
        <p>Registre o que observou. Todos os campos são opcionais.</p>
        <RubricQuestion legend="Desfecho do desafio da pista" name="race-result" options={RACE_RESULT_OPTIONS} value={answers.raceResult} onChange={(raceResult) => setAnswers({ ...answers, raceResult })} />
        <label className="race-time" htmlFor="race-time-input">Tempo da corrida em segundos (opcional)
          <input id="race-time-input" type="number" step="0.1" min="0" value={answers.raceTimeSeconds || ""}
            onChange={(event) => setAnswers({ ...answers, raceTimeSeconds: event.target.value })} />
        </label>
        <RubricQuestion legend="Montagem do carrinho" name="assembly-result" options={ASSEMBLY_OPTIONS} value={answers.assemblyResult} onChange={(assemblyResult) => setAnswers({ ...answers, assemblyResult })} />
        <ScaleQuestion legend="Dinâmica com os botões do robô" options={QUIZ_OPTIONS} value={answers.quizCompleted} onChange={(quizCompleted) => setAnswers({ ...answers, quizCompleted })} />
        <RubricQuestion legend="Apoio do educador" name="support-level" options={SUPPORT_OPTIONS} value={answers.supportLevel} onChange={(supportLevel) => setAnswers({ ...answers, supportLevel })} />
      </details>
    </>}
    {isFreeMode && <p className="free-mode-note">Modo Livre: a aula continua sem guardar dados da pesquisa.</p>}
  </Card>;
}

function FinishedScreen({ onRestart, isFreeMode }) {
  return <Card compact eyebrow="Tudo pronto" title="Oficina concluída!"
    description="Obrigado por participar da aula de robótica."
    footer={<div className="action-row"><button className="button button--primary" onClick={onRestart} type="button">Preparar nova oficina</button></div>}>
    {isFreeMode && <p className="free-mode-note">Modo Livre: nenhum dado da pesquisa foi guardado.</p>}
  </Card>;
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
            <span className={`delivery delivery--${event._delivery_state}`}>{event._delivery_state}</span>
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


export default function StudentPage() {
  const labMode = useMemo(() => new URLSearchParams(window.location.search).get("lab") === "1", []);
  const rawSavedSession = useMemo(() => readJson(ACTIVE_SESSION_KEY, null), []);
  const savedSession = useMemo(() => {
    if (!rawSavedSession) return null;
    const validated = validateRestoredSession(rawSavedSession);
    if (!validated) {
      if (typeof rawSavedSession.sessionId === "string") void purgeSession(rawSavedSession.sessionId);
      try {
        localStorage.removeItem(ACTIVE_SESSION_KEY);
      } catch {}
      return null;
    }
    return validated;
  }, [rawSavedSession]);

  const [context, setContext] = useState(() => readJson(CONTEXT_KEY, DEFAULT_CONTEXT));
  const VALID_SCREENS = ["pre", "activity", "post", "finished"];
  const [screen, setScreen] = useState(() => {
    if (savedSession?.screen && VALID_SCREENS.includes(savedSession.screen)) {
      return savedSession.screen;
    }
    return "pre";
  });
  const [activityStage, setActivityStage] = useState(() => savedSession?.activityStage || 2);
  const [sessionId, setSessionId] = useState(() => savedSession?.sessionId || createUuid());
  const [groupId, setGroupId] = useState(() => savedSession?.groupId || createUuid());
  const [installationId, setInstallationId] = useState(() => {
    if (savedSession && isAllAssented(savedSession.teamSize, savedSession.memberAssents)) {
      return savedSession.installation_id || getPersistedInstallationId() || createUuid();
    }
    return createUuid();
  });
  const [startedAt, setStartedAt] = useState(() => savedSession?.startedAt || null);
  const [activityStartedAt, setActivityStartedAt] = useState(() => savedSession?.activityStartedAt || null);
  const [elapsedMs, setElapsedMs] = useState(() => {
    if (savedSession?.screen === "activity" && savedSession?.activityStartedAt) {
      return Math.max(0, Date.now() - savedSession.activityStartedAt);
    }
    return savedSession?.elapsedMs || 0;
  });
  const [timeline, setTimeline] = useState(() => savedSession?.timeline || []);
  const [responses, setResponses] = useState(() => savedSession?.responses || []);
  const [spikeTelemetry, setSpikeTelemetry] = useState(() => structuralSpikeMetrics(savedSession?.spikeTelemetry));
  const [preAnswers, setPreAnswers] = useState(() => ({
    ...PRE_DEFAULT,
    ...(savedSession?.preAnswers && typeof savedSession.preAnswers === "object" ? savedSession.preAnswers : {})
  }));
  const [postAnswers, setPostAnswers] = useState(() => ({
    ...POST_DEFAULT,
    ...(savedSession?.postAnswers && typeof savedSession.postAnswers === "object" ? savedSession.postAnswers : {})
  }));
  const [teamSize, setTeamSize] = useState(() => savedSession?.teamSize || 2);
  const [currentRole] = useState(() => savedSession?.currentRole || "computer");
  const [memberAssents, setMemberAssentsState] = useState(() => savedSession?.memberAssents || { 1: false, 2: false, 3: false, 4: false });
  const memberAssentsRef = useRef(savedSession?.memberAssents || { 1: false, 2: false, 3: false, 4: false });
  const [assentAgreed, setAssentAgreedState] = useState(() => {
    if (savedSession?.memberAssents) {
      return isAllAssented(savedSession?.teamSize || 2, savedSession.memberAssents);
    }
    return false;
  });
  const assentAgreedRef = useRef(assentAgreed);
  const [isFreeMode, setIsFreeMode] = useState(() => savedSession?.isFreeMode || false);

  function setMemberAssents(valOrFn) {
    const next = typeof valOrFn === "function" ? valOrFn(memberAssentsRef.current) : valOrFn;
    memberAssentsRef.current = next;
    setMemberAssentsState(next);
    const allAssented = isAllAssented(teamSize, next);
    assentAgreedRef.current = allAssented;
    setAssentAgreedState(allAssented);
  }

  function handleTeamSizeChange(newSize) {
    if (newSize === teamSize) return;
    setTeamSize(newSize);
    const empty = { 1: false, 2: false, 3: false, 4: false };
    memberAssentsRef.current = empty;
    setMemberAssentsState(empty);
    assentAgreedRef.current = false;
    setAssentAgreedState(false);
    setPreAnswers(PRE_DEFAULT);
  }
  const [isSyntheticSession, setIsSyntheticSession] = useState(() => savedSession?.isSyntheticSession || labMode);
  const [showContextModal, setShowContextModal] = useState(false);
  const [toast, setToast] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [storageError, setStorageError] = useState("");
  const sequenceRef = useRef(savedSession?.sequence || 0);
  const isSyntheticSessionRef = useRef(savedSession?.isSyntheticSession || labMode);
  const isSubmittingRef = useRef(false);
  const writesRef = useRef(new Set());
  const bridgeWritesRef = useRef(new Set());
  const generationRef = useRef(0);
  const withdrawalChannelRef = useRef(null);
  const telemetryRef = useRef(savedSession?.spikeTelemetry || null);
  const startedAtRef = useRef(savedSession?.startedAt || null);

  function trackWrite(promise) {
    writesRef.current.add(promise);
    promise.then(() => writesRef.current.delete(promise), () => writesRef.current.delete(promise));
    return promise;
  }

  function trackBridgeWrite(promise) {
    bridgeWritesRef.current.add(promise);
    promise.then(() => bridgeWritesRef.current.delete(promise), () => bridgeWritesRef.current.delete(promise));
    return promise;
  }

  function reportStorageError() {
    setStorageError("Não foi possível guardar todas as respostas neste computador. Chamem o educador; vocês podem continuar a aula.");
  }

  async function withdrawSession(broadcast = true) {
    // Revoke permission synchronously, before any await, including late requests.
    assentAgreedRef.current = false;
    generationRef.current += 1;
    isSubmittingRef.current = true;
    setAssentAgreedState(false);
    setIsFreeMode(true);
    setSubmitting(false);
    setTimeline([]);
    setResponses([]);
    setSpikeTelemetry(null);
    telemetryRef.current = null;
    setPreAnswers(PRE_DEFAULT);
    setPostAnswers(POST_DEFAULT);
    startedAtRef.current = null;
    const empty = { 1: false, 2: false, 3: false, 4: false };
    memberAssentsRef.current = empty;
    setMemberAssentsState(empty);
    try {
      localStorage.removeItem(ACTIVE_SESSION_KEY);
      localStorage.removeItem(INSTALLATION_KEY);
      localStorage.removeItem(LEGACY_INSTALLATION_KEY);
    } catch { reportStorageError(); }
    if (broadcast) withdrawalChannelRef.current?.postMessage({ type: "withdraw", sessionId });
    isSubmittingRef.current = false;
    setScreen("activity");
    // Drain writes already in flight so that deletion is terminal.
    await Promise.allSettled([...writesRef.current]);
    await purgeSession(sessionId).catch(reportStorageError);
    void refreshDeliveryCounts();
    await Promise.allSettled([...bridgeWritesRef.current]);
    try {
      await resetBridgeSession(sessionId, { reason: "ethical_withdrawal", purge: true });
    } catch {
      setStorageError("Os dados deste navegador foram apagados, mas o computador ainda precisa confirmar a exclusão completa. Chamem o educador e mantenham o PulseLab aberto para tentar novamente.");
    }
  }

  useEffect(() => {
    const channel = new BroadcastChannel("pulselab-session-control");
    withdrawalChannelRef.current = channel;
    channel.onmessage = ({ data }) => {
      if (data?.type === "withdraw" && data.sessionId === sessionId) void withdrawSession(false);
    };
    return () => { channel.close(); withdrawalChannelRef.current = null; };
  }, [sessionId]);

  useEffect(() => {
    if (screen === "pre" || isFreeMode || !assentAgreed) return;
    const remaining = startedAt + 7 * 24 * 60 * 60 * 1000 - Date.now();
    const expiry = window.setTimeout(() => void withdrawSession(), Math.max(0, remaining));
    return () => window.clearTimeout(expiry);
  }, [startedAt, screen, isFreeMode, assentAgreed]);


  useEffect(() => {
    if (!savedSession || !isAllAssented(savedSession.teamSize, savedSession.memberAssents)) {
      try {
        localStorage.removeItem(INSTALLATION_KEY);
        localStorage.removeItem(LEGACY_INSTALLATION_KEY);
      } catch {}
    }
  }, [savedSession]);

  useEffect(() => {
    const storedContext = localStorage.getItem(CONTEXT_KEY);
    if (!storedContext) {
      fetchBridgeConfig().then((cfg) => {
        if (cfg && (cfg.site_id || cfg.school_code)) {
          setContext((prev) => ({
            ...prev,
            site_id: cfg.site_id && cfg.site_id !== "CONFIGURE_SEDE" ? cfg.site_id : prev.site_id,
            regional: cfg.regional_hub || prev.regional,
            school: cfg.school_code && cfg.school_code !== "CONFIGURE_ESCOLA" ? cfg.school_code : prev.school,
            workshop: cfg.workshop_code && cfg.workshop_code !== "CONFIGURE_OFICINA" ? cfg.workshop_code : prev.workshop,
            class: cfg.class_code && cfg.class_code !== "CONFIGURE_TURMA" ? cfg.class_code : prev.class,
            activity: cfg.activity_id || prev.activity
          }));
        }
      });
    }
  }, []);

  const [dbPendingCount, setDbPendingCount] = useState(0);
  const [dbQuarantinedCount, setDbQuarantinedCount] = useState(0);
  const [dbTotalStoredCount, setDbTotalStoredCount] = useState(0);

  const refreshDeliveryCounts = React.useCallback(async () => {
    try {
      const summary = await getLocalStoreSummary();
      setDbPendingCount(summary.pendingCount);
      setDbQuarantinedCount(summary.quarantinedCount);
      setDbTotalStoredCount(summary.totalRecords);
    } catch {
      // IndexedDB indisponível em fallback
    }
  }, []);

  const refreshPendingCount = refreshDeliveryCounts;

  useEffect(() => {
    enforceAbsoluteRetention(7).catch(() => {});
    refreshDeliveryCounts();
    const interval = setInterval(() => {
      enforceAbsoluteRetention(7).catch(() => {});
    }, 60 * 60 * 1000);
    return () => clearInterval(interval);
  }, [refreshDeliveryCounts]);

  const allEvents = [...timeline, ...responses];
  function flash(message) {
    setToast(message);
    window.setTimeout(() => setToast(""), 3200);
  }

  function eventBase(eventType, overrides = {}) {
    const now = Date.now();
    sequenceRef.current += 1;
    const sysMeta = getSystemMetadata();
    return {
      event_id: createUuid(),
      session_id: sessionId,
      dyad_id: groupId,
      group_id: groupId,
      installation_id: installationId,
      site_id: context.site_id || `Polo-${context.regional || "Nordeste"}`,
      regional_hub: context.regional || "Nordeste",
      school_code: context.school || "geral",
      workshop_code: context.workshop || "oficina-spike",
      class_code: context.class || "turma-geral",
      activity_id: context.activity || "atividade-01-spike",
      computer_id: getComputerId(installationId),
      protocol_version: PROTOCOL_VERSION,
      occurred_at: new Date(now).toISOString(),
      elapsed_ms: startedAtRef.current ? Math.max(0, now - startedAtRef.current) : 0,
      client_version: CLIENT_VERSION,
      config_version: "student-pwa-v2",
      config_hash: CONFIG_HASH,
      _delivery_state: "queued",
      _sequence: sequenceRef.current,
      _client_occurred_at: new Date(now).toISOString(),
      event_type: eventType,
      ...(isSyntheticSessionRef.current || isSyntheticSession ? { is_synthetic: true } : {}),
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
    void refreshPendingCount();
  }

  function persist(event) {
    if (!assentAgreedRef.current || isFreeMode) return;
    void trackWrite(saveEvent(event)).then(() => {
      void refreshDeliveryCounts();
    }).catch(reportStorageError);
    void trackBridgeWrite(notifyBridgeEvent(event));
    if (typeof navigator !== "undefined" && navigator.onLine) {
      void syncSingleEvent(event).then((result) => {
        if (result && result.success === true) {
          updateEventDeliveryState(event.event_id, "delivered");
        } else if (result && result.quarantined) {
          updateEventDeliveryState(event.event_id, "quarantined");
        }
        void refreshDeliveryCounts();
      });
    }
  }

  function emitTimeline(eventType, overrides = {}) {
    if (isFreeMode || !assentAgreedRef.current) return null;
    const sysMeta = getSystemMetadata();
    const event = eventBase(eventType, {
      _target_table: "research_session_events",
      severity: "info",
      interval_mark: null,
      participant_id: null,
      participant_role: null,
      activity_stage: null,
      scheduled_at: null,
      details: {
        runtime: "browser_pwa",
        os: sysMeta.os,
        screen_resolution: sysMeta.screen_resolution,
        ...(isSyntheticSessionRef.current || isSyntheticSession ? { is_synthetic: true } : {}),
        ...overrides.details
      },
      ...overrides
    });
    setTimeline((current) => [...current, event]);
    persist(event);
    return event;
  }

  function emitResponse(eventType, overrides = {}) {
    if (isFreeMode || !assentAgreedRef.current) return null;
    const sysMeta = getSystemMetadata();
    const role = teamSize === 1 ? "individual" : "group";
    const participantSuffix = "BANCADA";
    const groupSize = teamSize;

    const event = eventBase(eventType, {
      _target_table: "research_events",
      participant_id: `${groupId.slice(0, 8).toUpperCase()}-${participantSuffix}`,
      participant_role: role,
      response_status: overrides.response_status || "completed",
      interval_mark: null,
      group_size: groupSize,
      activity_stage: null,
      telemetry_window_title: `Res: ${sysMeta.screen_resolution}`,
      telemetry_foreground_app: sysMeta.os,
      ...(isSyntheticSessionRef.current || isSyntheticSession ? { is_synthetic: true } : {}),
      ...overrides
    });
    setResponses((current) => [...current, event]);
    persist(event);
    return event;
  }

  async function captureSpikeTelemetry(stageLabel) {
    if (isFreeMode || !assentAgreedRef.current) return { metrics: null, event: null };
    try {
      const generation = generationRef.current;
      const metrics = await fetchBridgeSpikeMetrics();
      if (generation !== generationRef.current || !assentAgreedRef.current || (isSubmittingRef.current && stageLabel !== "session_completed")) return { metrics: null, event: null };
      if (metrics && metrics.project_saved !== false) {
        telemetryRef.current = metrics;
        setSpikeTelemetry(metrics);
        const event = emitTimeline("spike_telemetry", {
          activity_stage: stageLabel,
          details: {
            executable_blocks: metrics.executable_blocks,
            top_level_stacks: metrics.top_level_stacks,
            uses_motor: metrics.uses_motor,
            uses_sensor: metrics.uses_sensor,
            uses_loop: metrics.uses_loop,
            uses_condition: metrics.uses_condition
          }
        });
        return { metrics, event };
      }
      return { metrics: metrics || null, event: null };
    } catch {
      return { metrics: null, event: null };
    }
  }

  function handleSaveContext(newContext) {
    setContext(newContext);
    try { localStorage.setItem(CONTEXT_KEY, JSON.stringify(newContext)); } catch { reportStorageError(); }
    flash(`Região salva com sucesso: ${newContext.regional}!`);
  }

  function submitPre() {
    if (!assentAgreedRef.current || isFreeMode || preAnswers.experience === null) return;

    const activityStart = Date.now();
    startedAtRef.current = activityStart;
    setStartedAt(activityStart);

    if (assentAgreedRef.current) {
      try {
        localStorage.setItem(INSTALLATION_KEY, installationId);
      } catch {}
    }

    emitTimeline("session_started", {
      activity_stage: "1. Introdução",
      details: {
        runtime: "browser_pwa",
        team_role: teamSize === 1 ? "individual" : "group",
        ethical_assent: assentAgreed,
        participant_count: teamSize,
        expected_checkpoints: []
      }
    });

    emitResponse("pre", {
      activity_stage: "1. Introdução",
      prior_robotics: preAnswers.experience,
      response_status: "completed"
    });

    setActivityStartedAt(activityStart);
    setElapsedMs(0);
    setActivityStage(2);
    void trackBridgeWrite(notifyBridgeSession(sessionId, activityStart, [], assentAgreedRef.current));
    emitTimeline("phase_completed", { activity_stage: "1. Início" });
    emitTimeline("phase_transition", {
      activity_stage: "2. Oficina Prática",
      details: { runtime: "browser_pwa", from_stage: "1. Início", to_stage: "2. Oficina Prática" }
    });
    emitTimeline("activity_started", {
      activity_stage: "2. Oficina Prática",
      details: { runtime: "browser_pwa", stage: "pratica" }
    });
    void captureSpikeTelemetry("pratica_start");
    setScreen("activity");
  }

  async function handleDeclinePre() {
    assentAgreedRef.current = false;
    setAssentAgreedState(false);
    setIsFreeMode(true);
    try {
      await purgeSession(sessionId);
    } catch (e) {
      console.warn("Erro ao expurgar sessão no IndexedDB:", e);
    }
    try {
      localStorage.removeItem(INSTALLATION_KEY);
      localStorage.removeItem(LEGACY_INSTALLATION_KEY);
    } catch {}
    localStorage.removeItem(ACTIVE_SESSION_KEY);
    try {
      await resetBridgeSession(sessionId, { reason: "ethical_refusal", purge: true });
    } catch {
      setStorageError("Nenhum dado novo será guardado. O computador ainda precisa confirmar a limpeza local; chamem o educador e mantenham o PulseLab aberto.");
    }
    setIsFreeMode(true);
    assentAgreedRef.current = false;
    setAssentAgreedState(false);
    setTimeline([]);
    setResponses([]);
    setSpikeTelemetry(null);
    const activityStart = Date.now();
    setActivityStartedAt(activityStart);
    setElapsedMs(0);
    setActivityStage(2);
    setScreen("activity");

  }

  function handleAdvanceToFinalChallenge() {
    const activityElapsed = activityStartedAt ? Math.max(0, Date.now() - activityStartedAt) : 0;
    setElapsedMs(activityElapsed);
    if (!isFreeMode && assentAgreedRef.current) {
      emitTimeline("phase_completed", {
        activity_stage: "2. Oficina Prática",
        details: { elapsed_ms: activityElapsed }
      });
      emitTimeline("phase_transition", {
        activity_stage: "3. Desafio da Corrida",
        details: {
          runtime: "browser_pwa",
          from_stage: "2. Oficina Prática",
          to_stage: "3. Desafio da Corrida",
          elapsed_ms: activityElapsed
        }
      });
      void captureSpikeTelemetry("final_challenge_start");
    }
    setScreen("post");

  }

  async function submitPost(answersOverride = null) {
    if (isSubmittingRef.current) return;
    isSubmittingRef.current = true;
    setSubmitting(true);
    const generation = generationRef.current;
    const isSyntheticEvent = answersOverride && (
      answersOverride.nativeEvent ||
      typeof answersOverride.preventDefault === "function" ||
      typeof answersOverride.stopPropagation === "function" ||
      Boolean(answersOverride.target)
    );
    const answers = (!isSyntheticEvent && answersOverride) ? answersOverride : postAnswers;

    if (!assentAgreedRef.current || isFreeMode) {
      localStorage.removeItem(ACTIVE_SESSION_KEY);
      setScreen("finished");
      return;
    }

    const finalEvents = [];

    const missionPerf = answers.raceResult === "success" ? 1 : (answers.raceResult === "partial" || answers.raceResult === "tech_failure" ? 0 : null);
    const primaryIssue = answers.raceResult === "tech_failure" ? "technical" : (answers.raceResult === "not_observed" ? "not_observed" : "none");

    const resolvedExperiences = resolveMemberExperiences(teamSize, memberAssents, answers.memberExperiences);

    finalEvents.push(emitResponse("post", {
      activity_stage: "3. Desafio da Corrida",
      mission_performance: missionPerf,
      primary_issue: primaryIssue,
      knowledge_answers: {
        target_constructs: ["experiencia_participacao", "resultados_praticos_bancada", "apoio_instrutor"],
        member_experiences: resolvedExperiences,
        race_result: answers.raceResult,
        race_time_seconds: answers.raceTimeSeconds ? parseFloat(answers.raceTimeSeconds) : null,
        assembly_result: answers.assemblyResult,
        quiz_completed: answers.quizCompleted,
        support_level: answers.supportLevel
      },
      response_status: "completed"
    }));

    // Eixo 1: Registra a experiência individual de cada aluno da bancada que avaliou ou optou por não responder a avaliação
    for (const member of resolvedExperiences) {
      if (member.rating !== null || member.skipped) {
        finalEvents.push(emitTimeline("experience_recorded", {
          activity_stage: "3. Desafio da Corrida",
          participant_id: null,
          details: {
            runtime: "browser_pwa",
            member_index: member.memberIndex,
            rating: member.rating,
            skipped: Boolean(member.skipped)
          }
        }));
      }
    }

    if (answers.raceResult !== null) {
      finalEvents.push(emitTimeline("race_recorded", {
        activity_stage: "3. Desafio da Corrida",
        details: {
          runtime: "browser_pwa",
          race_result: answers.raceResult,
          race_time_seconds: answers.raceTimeSeconds ? parseFloat(answers.raceTimeSeconds) : null
        }
      }));
    }

    finalEvents.push(emitTimeline("rubric_completed", {
      activity_stage: "3. Desafio da Corrida",
      details: {
        runtime: "browser_pwa",
        assembly_result: answers.assemblyResult,
        quiz_completed: answers.quizCompleted,
        support_level: answers.supportLevel
      }
    }));

    finalEvents.push(emitTimeline("phase_completed", { activity_stage: "3. Desafio da Corrida" }));

    // Ordem estrita: a telemetria terminal entra ANTES do encerramento final da sessão
    const { metrics: rawFinalMetrics, event: finalTelemetryEvent } = await captureSpikeTelemetry("session_completed");
    if (generation !== generationRef.current || !assentAgreedRef.current) return;
    if (finalTelemetryEvent) {
      finalEvents.push(finalTelemetryEvent);
    }

    finalEvents.push(emitTimeline("session_completed", {
      activity_stage: "completed",
      details: { runtime: "browser_pwa" }
    }));

    const { effectiveTelemetry, technicalStatus } = validateFinalTelemetry(rawFinalMetrics, spikeTelemetry);

    const fullSession = {
      session_id: sessionId,
      group_id: groupId,
      installation_id: installationId,
      site_id: context.site_id || `Polo-${context.regional || "Nordeste"}`,
      regional_hub: context.regional || "Nordeste",
      school_code: context.school || "geral",
      workshop_code: context.workshop || "oficina-spike",
      class_code: context.class || "turma-geral",
      activity_id: context.activity || "atividade-01-spike",
      started_at: new Date(startedAt).toISOString(),
      completed_at: new Date().toISOString(),
      duration_seconds: Math.round(elapsedMs / 1000),
      is_synthetic: isSyntheticSessionRef.current,
      group_size: teamSize,
      team_size: teamSize,
      team_role: teamSize === 1 ? "individual" : "group",
      status: "completed",
      pre_answers: preAnswers,
      post_answers: answers,
      events: [...timeline, ...responses, ...finalEvents],
      spike_telemetry: effectiveTelemetry,
      telemetry_status: technicalStatus
    };

    await Promise.allSettled([...writesRef.current]);
    if (generation !== generationRef.current || !assentAgreedRef.current) return;
    await trackWrite(saveSession(fullSession)).catch(reportStorageError);
    if (generation !== generationRef.current || !assentAgreedRef.current) return;
    void trackBridgeWrite(notifyBridgeSessionSave(fullSession, assentAgreedRef.current));

    localStorage.removeItem(ACTIVE_SESSION_KEY);
    void runSync(false);
    setScreen("finished");
  }

  async function handleDeclinePost() {
    if (isSubmittingRef.current) return;
    isSubmittingRef.current = true;
    setSubmitting(true);
    const generation = generationRef.current;
    if (!assentAgreedRef.current || isFreeMode) {
      try {
        localStorage.removeItem(INSTALLATION_KEY);
        localStorage.removeItem(LEGACY_INSTALLATION_KEY);
      } catch {}
      localStorage.removeItem(ACTIVE_SESSION_KEY);
      setScreen("finished");
      return;
    }

    setPostAnswers(POST_DEFAULT);
    const finalEvents = [];
    finalEvents.push(emitResponse("post", {
      activity_stage: "3. Desafio da Corrida",
      response_status: "declined"
    }));
    finalEvents.push(emitTimeline("phase_completed", { activity_stage: "3. Desafio da Corrida" }));

    // Ordem estrita: a telemetria terminal entra ANTES do encerramento final da sessão
    const { metrics: rawFinalMetrics, event: finalTelemetryEvent } = await captureSpikeTelemetry("session_completed");
    if (generation !== generationRef.current || !assentAgreedRef.current) return;
    if (finalTelemetryEvent) {
      finalEvents.push(finalTelemetryEvent);
    }

    finalEvents.push(emitTimeline("session_completed", {
      activity_stage: "completed",
      details: { runtime: "browser_pwa", response_status: "declined" }
    }));

    const { effectiveTelemetry, technicalStatus } = validateFinalTelemetry(rawFinalMetrics, spikeTelemetry);

    const fullSession = {
      session_id: sessionId,
      group_id: groupId,
      installation_id: installationId,
      site_id: context.site_id || `Polo-${context.regional || "Nordeste"}`,
      regional_hub: context.regional || "Nordeste",
      school_code: context.school || "geral",
      workshop_code: context.workshop || "oficina-spike",
      class_code: context.class || "turma-geral",
      activity_id: context.activity || "atividade-01-spike",
      started_at: new Date(startedAt).toISOString(),
      completed_at: new Date().toISOString(),
      duration_seconds: Math.round(elapsedMs / 1000),
      is_synthetic: isSyntheticSessionRef.current,
      group_size: teamSize,
      team_size: teamSize,
      team_role: teamSize === 1 ? "individual" : "group",
      status: "declined",
      pre_answers: preAnswers,
      post_answers: POST_DEFAULT,
      events: [...timeline, ...responses, ...finalEvents],
      spike_telemetry: effectiveTelemetry,
      telemetry_status: technicalStatus
    };

    await Promise.allSettled([...writesRef.current]);
    if (generation !== generationRef.current || !assentAgreedRef.current) return;
    await trackWrite(saveSession(fullSession)).catch(reportStorageError);
    if (generation !== generationRef.current || !assentAgreedRef.current) return;
    void trackBridgeWrite(notifyBridgeSessionSave(fullSession, assentAgreedRef.current));

    localStorage.removeItem(ACTIVE_SESSION_KEY);
    void runSync(false);
    setScreen("finished");
  }

  async function prepareNextWorkshop() {
    isSubmittingRef.current = false;
    setSubmitting(false);
    setStorageError("");
    generationRef.current += 1;
    try {
      localStorage.removeItem(INSTALLATION_KEY);
      localStorage.removeItem(LEGACY_INSTALLATION_KEY);
    } catch {}
    localStorage.removeItem(ACTIVE_SESSION_KEY);
    void resetBridgeSession(sessionId, { reason: "prepare_next", purge: false, completed: true });
    const nextSessionId = createUuid();
    const nextGroupId = createUuid();
    setSessionId(nextSessionId);
    setGroupId(nextGroupId);
    setInstallationId(createUuid());
    setStartedAt(Date.now());
    setActivityStartedAt(null);
    setElapsedMs(0);
    setActivityStage(1);
    setTimeline([]);
    setResponses([]);
    setSpikeTelemetry(null);
    telemetryRef.current = null;
    isSyntheticSessionRef.current = labMode;
    setIsSyntheticSession(labMode);
    setIsFreeMode(false);
    setPreAnswers(PRE_DEFAULT);
    setPostAnswers(POST_DEFAULT);
    assentAgreedRef.current = false;
    setAssentAgreedState(false);
    const initialAssents = { 1: false, 2: false, 3: false, 4: false };
    memberAssentsRef.current = initialAssents;
    setMemberAssentsState(initialAssents);
    setTeamSize(2);
    sequenceRef.current = 0;
    setScreen("pre");

  }

  function autoFillCurrentStep() {
    if (!labMode) return;
    isSyntheticSessionRef.current = true;
    setIsSyntheticSession(true);
    if (screen === "pre") {
      setPreAnswers({ experience: 2 });
      flash("Início preenchido com dados sintéticos de teste.");
    } else if (screen === "activity") {
      handleAdvanceToFinalChallenge();
    } else if (screen === "post") {
      const synthetic = {
        experience: 5,
        experienceSkipped: false,
        raceResult: "success",
        raceTimeSeconds: "12.4",
        assemblyResult: "complete",
        quizCompleted: "participated",
        supportLevel: "occasional"
      };
      setPostAnswers(synthetic);
      submitPost(synthetic);
      flash("Avaliação preenchida com sucesso e oficina concluída!");
    }
  }

  function downloadSession() {
    const rawData = {
      session_id: sessionId,
      group_id: groupId,
      installation_id: installationId,
      site_id: context.site_id || `Polo-${context.regional || "Nordeste"}`,
      regional_hub: context.regional || "Nordeste",
      school_code: context.school || "geral",
      workshop_code: context.workshop || "oficina-spike",
      class_code: context.class || "turma-geral",
      activity_id: context.activity || "atividade-01-spike",
      started_at: new Date(startedAt).toISOString(),
      completed_at: new Date().toISOString(),
      duration_seconds: Math.round(elapsedMs / 1000),
      is_synthetic: isSyntheticSessionRef.current,
      team_size: teamSize,
      team_role: teamSize === 1 ? "individual" : "group",
      status: screen === "finished" ? "completed" : "in_progress",
      pre_answers: preAnswers,
      post_answers: postAnswers,
      spike_telemetry: spikeTelemetry,
      telemetry_status: spikeTelemetry ? (spikeTelemetry.project_saved !== false ? "ok" : "project_not_saved") : "no_telemetry",
      events: allEvents
    };

    const validated = downloadSessionData(rawData, { isFreeMode, assentAgreed });
    if (!validated) {
      flash("Exportação de dados bloqueada no Modo Livre ou sem assentimento ético.");
      return;
    }

    const payload = JSON.stringify(validated, null, 2);
    const blob = new Blob([payload], { type: "application/json" });
    const link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = `sessao-${sessionId.slice(0, 8)}.json`;
    link.click();
    URL.revokeObjectURL(link.href);
    flash("💾 Sessão exportada com sucesso em arquivo .json!");
  }

  async function runSync(showFeedback = false) {
    if (typeof navigator !== "undefined" && !navigator.onLine) return;
    try {
      const result = await flushPendingEvents((syncedId) => {
        updateEventDeliveryState(syncedId, "delivered");
      });
      await refreshPendingCount();
      if (result.synced > 0 && showFeedback) {
        flash(`Sincronizados ${result.synced} registro(s) com a nuvem da pesquisa.`);
      }
    } catch {
      // Falha silenciosa de rede
    }
  }

  useEffect(() => {
    const handleOnline = () => {
      void runSync(false);
    };

    window.addEventListener("online", handleOnline);

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
      window.clearInterval(syncTimer);
    };
  }, []);

  useEffect(() => {
    if (screen !== "activity" || !activityStartedAt || isFreeMode || !assentAgreedRef.current) return undefined;
    const tick = () => {
      const nextElapsed = Math.max(0, Date.now() - activityStartedAt);
      setElapsedMs(nextElapsed);
    };
    tick();
    const timer = window.setInterval(tick, 1000);

    // Coleta silenciosa e periódica da telemetria do LEGO SPIKE a cada 10 segundos
    let cancelled = false;
    const generation = generationRef.current;
    const pollSpike = async () => {
      if (isFreeMode || !assentAgreedRef.current || isSubmittingRef.current) return;
      const metrics = await fetchBridgeSpikeMetrics();
      if (cancelled || generation !== generationRef.current || !assentAgreedRef.current || isSubmittingRef.current) return;
      if (metrics && metrics.project_saved !== false) {
        const previous = telemetryRef.current;
        const first = !previous || (!previous.executable_blocks && metrics.executable_blocks > 0);
        if (first || previous.executable_blocks !== metrics.executable_blocks) {
          emitTimeline("spike_telemetry", {
            activity_stage: first ? "primeira_programacao_detectada" : "atualizacao_codigo_spike",
            details: {
              executable_blocks: metrics.executable_blocks,
              uses_motor: metrics.uses_motor,
              uses_sensor: metrics.uses_sensor,
              first_coding_detected: first,
              elapsed_ms: Math.max(0, Date.now() - activityStartedAt)
            }
          });
        }
        telemetryRef.current = metrics;
        setSpikeTelemetry(metrics);
      }
    };

    const firstCheck = window.setTimeout(pollSpike, 2000);
    const spikeInterval = window.setInterval(pollSpike, 10000);

    return () => {
      cancelled = true;
      window.clearInterval(timer);
      window.clearTimeout(firstCheck);
      window.clearInterval(spikeInterval);
    };
  }, [activityStartedAt, screen, isFreeMode, assentAgreed]);

  useEffect(() => {
    if (screen === "finished" || screen === "pre" || !assentAgreedRef.current || isFreeMode || isSubmittingRef.current) return;
    const snapshot = {
      sessionId,
      groupId,
      installation_id: installationId,
      context,
      startedAt,
      activityStartedAt,
      elapsedMs,
      activityStage,
      screen,
      timeline,
      responses,
      spikeTelemetry,
      preAnswers,
      postAnswers,
      teamSize,
      group_size: teamSize,
      team_size: teamSize,
      team_role: teamSize === 1 ? "individual" : "group",
      currentRole,
      assentAgreed,
      memberAssents: memberAssentsRef.current,
      sequence: sequenceRef.current,
      isSyntheticSession: isSyntheticSessionRef.current,
      savedAt: new Date().toISOString()
    };
    try { localStorage.setItem(ACTIVE_SESSION_KEY, JSON.stringify(snapshot)); } catch { reportStorageError(); }
    void trackWrite(saveSession({ session_id: sessionId, status: "in_progress", ...snapshot })).catch(reportStorageError);
  }, [activityStartedAt, activityStage, assentAgreed, context, currentRole, elapsedMs, groupId, installationId, isFreeMode, memberAssents, postAnswers, preAnswers, responses, screen, sessionId, spikeTelemetry, startedAt, teamSize, timeline]);

  useEffect(() => {
    document.querySelector("[data-stage-heading]")?.focus();
  }, [screen, isFreeMode]);

  let content;

  if (screen === "pre") {
    content = <PreScreen answers={preAnswers} setAnswers={setPreAnswers} onSubmit={submitPre} onDecline={handleDeclinePre}
      teamSize={teamSize} setTeamSize={handleTeamSizeChange} memberAssents={memberAssents} setMemberAssents={setMemberAssents} />;
  } else if (screen === "activity") {
    content = <ActivityScreen onAdvanceToFinalChallenge={handleAdvanceToFinalChallenge} isFreeMode={isFreeMode} />;
  } else if (screen === "post") {
    content = <PostScreen answers={postAnswers} setAnswers={setPostAnswers} onSubmit={submitPost} onDecline={handleDeclinePost}
      teamSize={teamSize} memberAssents={memberAssents} isFreeMode={isFreeMode} submitting={submitting} />;
  } else {
    content = <FinishedScreen onRestart={prepareNextWorkshop} isFreeMode={isFreeMode} />;
  }

  return (
    <main className="app-shell student-app">
      <header className="student-header">
        <span className="student-brand">
          <svg className="student-brand__mark" viewBox="0 0 32 32" aria-hidden="true" focusable="false">
            <path d="M3 17h6l4-9 6 16 4-7h6" />
            <circle cx="3" cy="17" r="2" /><circle cx="29" cy="17" r="2" />
          </svg>
          <span><strong>PulseLab</strong><span className="student-brand__caption">Oficina de robótica</span></span>
        </span>
        {screen !== "pre" && !isFreeMode && <button className="button button--ghost withdrawal-button" type="button" onClick={withdrawSession}>Parar de participar e apagar meus dados</button>}
      </header>
      {storageError && <div className="storage-notice" role="alert">{storageError}</div>}
      <div className="student-content">{content}</div>
      <aside className="educator-area" aria-label="Área do educador">
        <details key={`${screen}-${sessionId}`}>
          <summary>Área do educador</summary>
          <div className="educator-tools">
            <p>oficina de robótica · v2.2.2</p>
            <p>Registros no dispositivo: {dbTotalStoredCount}. Pendentes: {dbPendingCount}. Em quarentena: {dbQuarantinedCount}.</p>
            <p>A consolidação dos dados é feita pelo pesquisador. Internet não é necessária para a aula.</p>
            <div className="action-row">
              <button className="button button--ghost" onClick={() => setShowContextModal(true)} type="button">Configurar oficina</button>
              {!isFreeMode && assentAgreed && screen !== "pre" && <button className="button button--ghost" onClick={downloadSession} type="button">Baixar cópia local (.json)</button>}
              {isFreeMode && screen !== "finished" && <button className="button button--ghost" onClick={prepareNextWorkshop} type="button">Preparar nova oficina</button>}
            </div>
            {labMode && <section aria-label="Laboratório" className="lab-tools">
              <h2>Laboratório · dados sintéticos</h2>
              <button className="button button--ghost" onClick={autoFillCurrentStep} type="button">Preencher teste</button>
              <EvidencePanel events={allEvents} />
            </section>}
          </div>
        </details>
      </aside>
      <RegionMetadataModal isOpen={showContextModal} onClose={() => setShowContextModal(false)} context={context}
        onSave={handleSaveContext} computerId={getComputerId(installationId)} systemMetadata={getSystemMetadata()} />
      {toast && <div className="toast" role="status">{toast}</div>}
    </main>
  );
}
