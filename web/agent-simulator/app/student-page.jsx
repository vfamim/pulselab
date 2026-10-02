import React, { useEffect, useMemo, useRef, useState } from "react";
import {
  CONFIG_HASH,
  INSTRUMENT_MANIFEST,
  INSTRUMENT_VERSION,
  PROTOCOL_VERSION,
  createUuid,
  formatEventName
} from "../lib/contracts.js";
import {
  listPendingEvents,
  markEventDelivered,
  markSessionEvents,
  pruneDeliveredEvents,
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
const CLIENT_VERSION = "student-pwa/2.2.0";

const DEFAULT_CONTEXT = {
  regional: "Nordeste",
  site_id: "Polo-Nordeste",
  school: "geral",
  workshop: "oficina-spike",
  class: "turma-geral",
  activity: "atividade-01-spike"
};

const PRE_DEFAULT = { experience: null };
const CHECKPOINT_DEFAULT = { impasse: null };
const POST_DEFAULT = {
  missionResult: null,
  executionScore: null,
  explanationScore: null,
  assistanceCount: null,
  nextAction: null
};

const FLOW_STEPS = [
  { id: 1, label: "Início" },
  { id: 2, label: "Atividade" },
  { id: 3, label: "Check-in" },
  { id: 4, label: "Finalizar" }
];

const EXPERIENCE_OPTIONS = [
  [1, "🐣 Primeira vez", "Ninguém na bancada mexeu com robôs"],
  [2, "🧩 Pouca prática", "Alguém já viu ou usou 1 ou 2 vezes"],
  [3, "🚀 Já praticamos", "Já montamos ou programamos antes"],
  [4, "⚡ Muita prática", "Temos facilidade com montagem e código"]
];

const IMPASSE_OPTIONS = [
  ["no", "🟢 Não", "Estávamos conseguindo tentar ideias e testar caminhos"],
  ["yes", "🛑 Sim", "Travamos sem saber o que tentar para avançar"],
  ["off_task", "💬 Fora da tarefa", "Pausa, conversa paralela ou aguardando peça/professor"],
  ["no_consensus", "🤝 Sem acordo", "O grupo não chegou a uma resposta conjunta"]
];

const MISSION_RESULT_OPTIONS = [
  ["full", "🏆 Sucesso Completo", "Robô parou a menos de 10 cm nas 3 tentativas"],
  ["partial", "🧩 Parcial", "Funcionou em 1 ou 2 tentativas"],
  ["in_progress", "⏳ Em andamento", "Ainda estávamos ajustando código ou montagem"]
];

const EXPLANATION_OPTIONS = [
  [0, "0 · Não relaciona", "Não soube associar o sensor à parada do robô"],
  [1, "1 · Identifica peças", "Reconhece o sensor e motor, mas sem explicar a lógica"],
  [2, "2 · Explica parada", "Explica que a distância menor que 10 cm aciona a parada"],
  [3, "3 · Explica parada e loop", "Explica a condição do sensor e a necessidade de repetição contínua"]
];

const NEXT_ACTION_OPTIONS = [
  ["repeat_sensor", "🔁 Repetir desafio do sensor"],
  ["more_time", "⏱️ Mais tempo de depuração autônoma"],
  ["revise_logic", "💡 Revisar lógica de repetição e condições"],
  ["advance_challenge", "🚀 Avançar para o próximo desafio"]
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

async function fetchBridgeConfig() {
  try {
    const res = await fetch(`${BRIDGE_URL}/v1/config`);
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

function getComputerId(installationId) {
  const id = installationId || getInstallationId();
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
              <span className="scale-option__icon">{icon}</span>
              <strong className="scale-option__title">{title}</strong>
              {sublabel ? <small className="scale-option__sub">{sublabel}</small> : null}
            </button>
          );
        })}
      </div>
    </fieldset>
  );
}

function OptionQuestion({ legend, options, value, onChange }) {
  return (
    <fieldset className="question-block">
      <legend>{legend}</legend>
      <div className="option-list">
        {options.map(([optionValue, label, hint]) => {
          const parts = String(label).match(/^(\S+)\s+(.+)$/);
          const icon = parts ? parts[1] : "•";
          const title = parts ? parts[2] : label;
          const isSelected = value === optionValue;
          return (
            <button
              className={`option-row ${isSelected ? "is-selected" : ""}`}
              key={optionValue}
              onClick={() => onChange(optionValue)}
              type="button"
              aria-pressed={isSelected}
            >
              <span className="option-row__icon">{icon}</span>
              <span className="option-row__body">
                <strong>{title}</strong>
                {hint ? <small>{hint}</small> : null}
              </span>
              <span className="option-row__radio" />
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
        <h1>{title}</h1>
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

function RegionMetadataModal({ isOpen, onClose, context, onSave, configHash, computerId, systemMetadata }) {
  const [selectedRegion, setSelectedRegion] = useState(context.regional || "Nordeste");
  useEffect(() => { setSelectedRegion(context.regional || "Nordeste"); }, [context, isOpen]);

  if (!isOpen) return null;

  return (
    <div className="alert-modal-backdrop" role="dialog" aria-modal="true">
      <div className="alert-modal" style={{ maxWidth: "520px", textAlign: "left" }}>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: "12px" }}>
          <h2 style={{ margin: 0, fontSize: "1.25rem", color: "#f8fafc" }}>📍 Região & Metadados do Computador</h2>
          <button className="topbar-btn" onClick={onClose} type="button" style={{ padding: "4px 10px" }}>✕</button>
        </div>
        <p style={{ color: "#94a3b8", fontSize: "0.85rem", marginTop: 0, marginBottom: "16px" }}>
          Selecione apenas a região de onde os dados estão vindo. Os metadados da máquina são detectados automaticamente para o comparativo.
        </p>

        <label style={{ fontSize: "0.8rem", fontWeight: 700, color: "#e2e8f0", display: "block", marginBottom: "8px" }}>
          Região de origem dos dados:
        </label>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(140px, 1fr))", gap: "8px", marginBottom: "18px" }}>
          {REGIONS.map((r) => {
            const isSel = selectedRegion === r.id;
            return (
              <button
                key={r.id}
                type="button"
                className={`scale-option ${isSel ? "is-selected" : ""}`}
                onClick={() => setSelectedRegion(r.id)}
                style={{ padding: "10px 12px", minHeight: "auto", textAlign: "left" }}
              >
                <strong style={{ fontSize: "0.92rem" }}>{r.label}</strong>
              </button>
            );
          })}
        </div>

        <div style={{ padding: "12px 14px", background: "#0f172a", border: "1px solid #1e293b", borderRadius: "10px", fontSize: "0.8rem", color: "#94a3b8" }}>
          <div style={{ color: "#38bdf8", fontWeight: 700, marginBottom: "6px" }}>💻 Metadados do Computador (automáticos):</div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "6px" }}>
            <div>ID Dispositivo: <strong style={{ color: "#f1f5f9" }}>{computerId}</strong></div>
            <div>Sistema: <strong style={{ color: "#f1f5f9" }}>{systemMetadata.os}</strong></div>
            <div>Resolução Tela: <strong style={{ color: "#f1f5f9" }}>{systemMetadata.screen_resolution}</strong></div>
            <div>Instrumento: <strong style={{ color: "#34d399" }}>SHA-256 ✓</strong></div>
          </div>
        </div>

        <div style={{ display: "flex", justifyContent: "flex-end", marginTop: "18px", gap: "10px" }}>
          <button
            type="button"
            className="inst-btn"
            onClick={onClose}
          >
            Cancelar
          </button>
          <button
            type="button"
            className="inst-btn inst-btn--accent"
            onClick={() => {
              onSave({
                ...context,
                regional: selectedRegion,
                site_id: `Polo-${selectedRegion}`
              });
              onClose();
            }}
          >
            💾 Salvar
          </button>
        </div>
      </div>
    </div>
  );
}

function PreScreen({
  answers,
  setAnswers,
  onSubmit,
  onDecline,
  resumable,
  onResume,
  teamRole,
  setTeamRole,
  assentAgreed,
  setAssentAgreed
}) {
  const ready = !assentAgreed || answers.experience !== null;
  return (
    <Card
      eyebrow="Oficina de Robótica · Início da Bancada"
      title="Como vocês chegam para esta oficina?"
      description="Respondam rapidamente para caracterizar a bancada antes de começar a montar e programar o robô LEGO SPIKE."
      footer={
        <div className="action-row">
          <span className="footer-hint">Sua resposta fica salva assim que você clica em começar.</span>
          {!assentAgreed ? (
            <button className="button button--ghost" onClick={onDecline} type="button">
              Usar apenas o robô (sem pesquisa)
            </button>
          ) : (
            <button className="button button--ghost" onClick={onDecline} type="button">
              Prefiro não responder a pesquisa
            </button>
          )}
          <button
            className="button button--primary"
            disabled={!ready}
            onClick={assentAgreed ? onSubmit : onDecline}
            type="button"
          >
            {assentAgreed ? "Começar Atividade!" : "Começar sem Pesquisa"}
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

      <div style={{ margin: "0 0 18px", padding: "14px 18px", background: assentAgreed ? "rgba(34, 197, 94, 0.08)" : "rgba(239, 68, 68, 0.08)", border: `1px solid ${assentAgreed ? "rgba(34, 197, 94, 0.3)" : "rgba(239, 68, 68, 0.3)"}`, borderRadius: "12px", display: "flex", gap: "12px", alignItems: "flex-start" }}>
        <input
          id="ethical-assent-checkbox"
          type="checkbox"
          checked={assentAgreed}
          onChange={(e) => setAssentAgreed(e.target.checked)}
          style={{ width: "20px", height: "20px", marginTop: "2px", accentColor: "#16a34a", cursor: "pointer" }}
        />
        <label htmlFor="ethical-assent-checkbox" style={{ cursor: "pointer", display: "flex", flexDirection: "column", gap: "3px" }}>
          <strong style={{ fontSize: "0.95rem", color: assentAgreed ? "#15803d" : "#b91c1c" }}>
            📋 Assentimento Voluntário e Anônimo da Pesquisa
          </strong>
          <small style={{ color: assentAgreed ? "#166534" : "#991b1b", fontSize: "0.82rem", lineHeight: "1.4" }}>
            {assentAgreed
              ? "✓ Concordamos em responder aos questionários curtos da pesquisa PulseLab (100% anônimo e voluntário)."
              : "✋ Recusa informada: A equipe prefere não participar da pesquisa científica. Vocês usarão o robô LEGO SPIKE e o cronômetro livremente sem coleta de dados."}
          </small>
        </label>
      </div>

      <div style={{ margin: "0 0 20px", padding: "14px 16px", background: "rgba(99, 102, 241, 0.06)", borderRadius: "12px", border: "1px solid rgba(99, 102, 241, 0.2)" }}>
        <span style={{ fontSize: "0.82rem", fontWeight: 800, color: "#4f46e5", textTransform: "uppercase", letterSpacing: "0.06em", display: "block", marginBottom: "8px" }}>
          👥 Composição da Equipe na Bancada
        </span>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))", gap: "8px" }}>
          {[
            ["dyad", "👫 Dupla de Trabalho", "Dois estudantes compartilhando computador e peças"],
            ["individual", "👤 Individual", "1 estudante realizando todas as etapas"],
            ["group", "👥 Bancada Coletiva", "3 a 4 estudantes colaborando no mesmo desafio"]
          ].map(([val, label, sub]) => {
            const isSel = teamRole === val;
            return (
              <button
                key={val}
                type="button"
                className={`scale-option ${isSel ? "is-selected" : ""}`}
                onClick={() => setTeamRole(val)}
                style={{ textAlign: "left", padding: "10px 12px", minHeight: "auto" }}
              >
                <strong style={{ fontSize: "0.92rem" }}>{label}</strong>
                <small style={{ fontSize: "0.76rem", color: isSel ? "inherit" : "var(--muted)", marginTop: "2px" }}>{sub}</small>
              </button>
            );
          })}
        </div>
      </div>

      {assentAgreed ? (
        <ScaleQuestion
          legend="Vocês na bancada já montaram ou programaram robôs ou blocos antes?"
          onChange={(experience) => setAnswers({ ...answers, experience })}
          options={EXPERIENCE_OPTIONS}
          value={answers.experience}
        />
      ) : null}
    </Card>
  );
}

function ActivityScreen({
  elapsedMs,
  currentMark,
  labMode,
  spikeTelemetry,
  helpActive,
  onToggleHelp,
  onFinishActivity,
  assentAgreed
}) {
  const targetMs = currentMark * 60 * 1000;
  const remaining = Math.max(0, targetMs - elapsedMs);
  return (
    <Card
      eyebrow="Desafio em Andamento"
      title="Pode focar no projeto do SPIKE"
      description={assentAgreed
        ? `Construam e programem normalmente. O próximo check-in rápido de 15 segundos será aberto aos ${currentMark} minutos.`
        : "Construam e programem normalmente. O aplicativo está em modo pedagógico livre."
      }
      footer={
        <div className="action-row" style={{ justifyContent: "space-between", width: "100%", alignItems: "center" }}>
          <span className="footer-hint" style={{ fontSize: "0.88rem", color: "var(--muted)" }}>
            {assentAgreed ? `⏱️ Próximo check-in rápido previsto para os ${currentMark} min.` : "Oficina livre sem coleta de dados."}
          </span>
          <button
            className="button button--primary"
            onClick={onFinishActivity}
            type="button"
          >
            🏁 Finalizar Desafio da Oficina
          </button>
        </div>
      }
    >
      <div className="activity-timer" aria-live="polite">
        <span>Tempo de atividade</span>
        <strong>{formatClock(elapsedMs)}</strong>
        <small>{assentAgreed ? `Próximo check-in em ${formatClock(remaining)}` : "Atividade livre"}</small>
      </div>

      {spikeTelemetry ? (
        <div style={{ background: "rgba(73, 217, 206, 0.1)", border: "1px solid rgba(73, 217, 206, 0.3)", borderRadius: "10px", padding: "12px 16px", margin: "16px 0", fontSize: "0.85rem", color: "#6ee7b7" }}>
          <span>🤖 <strong>LEGO SPIKE Conectado:</strong> {spikeTelemetry.executable_blocks || 0} blocos detectados · Estrutura: <em>{spikeTelemetry.inferred_stage || "em edição"}</em></span>
        </div>
      ) : null}

      <button
        type="button"
        className={`help-toggle-btn ${helpActive ? "is-active" : ""}`}
        onClick={onToggleHelp}
        aria-pressed={helpActive}
        style={{ margin: "18px 0" }}
      >
        <span className="help-toggle-btn__icon">{helpActive ? "🚨" : "🙋‍♂️"}</span>
        <div className="help-toggle-btn__content">
          <strong>{helpActive ? "Ajuda solicitada ao professor!" : "Precisa de ajuda do professor na bancada?"}</strong>
          <small>{helpActive ? "Pedido registrado no sistema. Por favor, levantem a mão na sala para o professor localizar a bancada." : "Clique aqui para registrar o chamado e levantem a mão na sala para chamar o professor."}</small>
        </div>
        <span className="help-toggle-btn__badge">
          {helpActive ? "✓ PROFESSOR ATENDENDO" : "CHAMAR PROFESSOR"}
        </span>
      </button>

      <div className="activity-instructions">
        <article>
          <span>1</span>
          <strong>Mantenha esta página aberta</strong>
          <p>Ela pode ficar em uma aba ao lado enquanto vocês usam o app do SPIKE.</p>
        </article>
        <article>
          <span>2</span>
          <strong>Programem e testem à vontade</strong>
          <p>O PulseLab acompanha a estrutura do código do SPIKE de forma anônima e segura.</p>
        </article>
        <article>
          <span>3</span>
          <strong>Aviso sonoro aos 20 e 40 minutos</strong>
          <p>{assentAgreed ? "Um alerta suave indicará o momento de registrar se a bancada está conseguindo avançar." : "Use o cronômetro para controlar seu tempo de oficina."}</p>
        </article>
      </div>
    </Card>
  );
}

function CheckpointScreen({
  mark,
  answers,
  onSelectOption,
  onSkip,
  teamRole,
  currentRole,
  onRoleSwap
}) {
  return (
    <Card
      eyebrow={`Check-in de ${mark} minutos · Registro rápido da bancada`}
      title="Como esteve a bancada nos últimos instantes?"
      description="Uma única pergunta sobre os 2 minutos recentes da atividade para voltarem imediatamente ao robô."
      footer={
        <div className="action-row">
          <button
            className="button button--ghost"
            onClick={onSkip}
            type="button"
            style={{ marginRight: "auto" }}
          >
            Pular este check-in
          </button>
          <span className="footer-hint">Clique na opção para salvar e retornar à atividade na hora.</span>
        </div>
      }
    >
      <div className="checkpoint-meta">
        <span className="time-chip">{mark}:00 de atividade</span>
      </div>

      {teamRole === "dyad" ? (
        <div style={{ background: "rgba(16, 185, 129, 0.08)", border: "1px solid rgba(16, 185, 129, 0.3)", borderRadius: "12px", padding: "10px 16px", marginBottom: "16px", display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: "10px" }}>
          <div>
            <span style={{ fontSize: "0.78rem", textTransform: "uppercase", letterSpacing: "0.06em", color: "#059669", fontWeight: 800 }}>Papel Atual na Bancada:</span>
            <div style={{ fontSize: "0.95rem", fontWeight: 700, color: "#065f46" }}>
              {currentRole === "computer" ? "💻 Participante no Computador / Código" : "🛠️ Participante na Montagem / Testes"}
            </div>
          </div>
          <button
            type="button"
            className="inst-btn"
            style={{ background: "#d1fae5", color: "#065f46", borderColor: "#a7f3d0", fontWeight: 700, fontSize: "0.8rem", padding: "6px 12px" }}
            onClick={onRoleSwap}
            title="Alternar papéis voluntariamente"
          >
            🔄 Trocar Papéis (Opcional)
          </button>
        </div>
      ) : null}

      <fieldset className="question-block">
        <legend className="question-legend" style={{ fontSize: "1.1rem", marginBottom: "12px", color: "#f8fafc", fontWeight: 700 }}>
          Nos dois minutos antes deste aviso, a bancada ficou sem saber o que tentar para avançar?
        </legend>
        <div className="option-list">
          {IMPASSE_OPTIONS.map(([val, title, desc]) => {
            const isSelected = answers.impasse === val;
            return (
              <label
                key={val}
                className={`option-row ${isSelected ? "is-selected" : ""}`}
                style={{ cursor: "pointer", transition: "all 0.2s ease" }}
                onClick={() => onSelectOption(val)}
              >
                <input
                  type="radio"
                  name={`impasse-${mark}`}
                  value={val}
                  checked={isSelected}
                  onChange={() => {}}
                  style={{ display: "none" }}
                />
                <span className="option-row__body">
                  <strong style={{ fontSize: "1rem", color: "#f1f5f9" }}>{title}</strong>
                  <small style={{ color: "#94a3b8", display: "block", marginTop: "2px" }}>{desc}</small>
                </span>
                <span className="option-row__radio" />
              </label>
            );
          })}
        </div>
      </fieldset>
    </Card>
  );
}

function PostScreen({ answers, setAnswers, onSubmit, onDecline }) {
  const ready = answers.missionResult !== null || answers.executionScore !== null;
  return (
    <Card
      eyebrow="Encerramento da Oficina · Avaliação Pedagógica"
      title="Desfecho do Desafio & Rubrica do Instrutor"
      description="Registro objetivo da execução física do robô e avaliação conceitual da bancada."
      footer={
        <div className="action-row">
          <button
            className="button button--ghost"
            onClick={onDecline}
            type="button"
            style={{ marginRight: "auto" }}
          >
            Pular rubrica e finalizar
          </button>
          <button className="button button--primary" disabled={!ready} onClick={onSubmit} type="button">
            Concluir e Salvar Oficina
          </button>
        </div>
      }
    >
      <fieldset className="question-block">
        <legend className="question-legend" style={{ fontSize: "1.05rem", color: "#f8fafc", fontWeight: 700, marginBottom: "10px" }}>
          1. Desfecho da Bancada: O robô conseguiu parar diante do obstáculo a menos de 10 cm?
        </legend>
        <div className="option-list">
          {MISSION_RESULT_OPTIONS.map(([val, title, desc]) => {
            const isSelected = answers.missionResult === val;
            return (
              <label key={val} className={`option-row ${isSelected ? "is-selected" : ""}`} style={{ cursor: "pointer" }}>
                <input
                  type="radio"
                  name="mission-result"
                  value={val}
                  checked={isSelected}
                  onChange={() => setAnswers({ ...answers, missionResult: val })}
                  style={{ display: "none" }}
                />
                <span className="option-row__body">
                  <strong style={{ fontSize: "0.95rem", color: "#f1f5f9" }}>{title}</strong>
                  <small style={{ color: "#94a3b8" }}>{desc}</small>
                </span>
                <span className="option-row__radio" />
              </label>
            );
          })}
        </div>
      </fieldset>

      <div style={{ marginTop: "24px", padding: "16px 18px", background: "rgba(36, 86, 77, 0.15)", border: "1px solid rgba(73, 217, 206, 0.3)", borderRadius: "14px" }}>
        <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "14px" }}>
          <span style={{ fontSize: "1.2rem" }}>📋</span>
          <strong style={{ fontSize: "1rem", color: "#49d9ce" }}>Rubrica de Observação do Instrutor / Monitor</strong>
        </div>

        <div style={{ marginBottom: "16px" }}>
          <label style={{ display: "block", fontSize: "0.85rem", fontWeight: 700, color: "#e2e8f0", marginBottom: "8px" }}>
            Tentativas bem-sucedidas em 3 testes idênticos na pista (0 a 3):
          </label>
          <div style={{ display: "flex", gap: "8px" }}>
            {[0, 1, 2, 3].map((score) => {
              const isSelected = answers.executionScore === score;
              return (
                <button
                  key={score}
                  type="button"
                  className={`scale-option ${isSelected ? "is-selected" : ""}`}
                  style={{ padding: "8px 16px", minHeight: "auto", textAlign: "center", flex: 1 }}
                  onClick={() => setAnswers({ ...answers, executionScore: score })}
                >
                  <strong style={{ fontSize: "1.1rem" }}>{score}</strong>
                  <small style={{ fontSize: "0.75rem", display: "block" }}>{score === 3 ? "Perfeito" : `${score} acerto(s)`}</small>
                </button>
              );
            })}
          </div>
        </div>

        <div style={{ marginBottom: "16px" }}>
          <label style={{ display: "block", fontSize: "0.85rem", fontWeight: 700, color: "#e2e8f0", marginBottom: "8px" }}>
            Nível de explicação conceitual demonstrado pela bancada:
          </label>
          <div className="option-list">
            {EXPLANATION_OPTIONS.map(([score, title, desc]) => {
              const isSelected = answers.explanationScore === score;
              return (
                <label key={score} className={`option-row ${isSelected ? "is-selected" : ""}`} style={{ cursor: "pointer", padding: "8px 12px" }}>
                  <input
                    type="radio"
                    name="explanation-score"
                    value={score}
                    checked={isSelected}
                    onChange={() => setAnswers({ ...answers, explanationScore: score })}
                    style={{ display: "none" }}
                  />
                  <span className="option-row__body">
                    <strong style={{ fontSize: "0.88rem", color: "#f1f5f9" }}>{title}</strong>
                    <small style={{ color: "#94a3b8", fontSize: "0.78rem" }}>{desc}</small>
                  </span>
                  <span className="option-row__radio" />
                </label>
              );
            })}
          </div>
        </div>

        <div>
          <label style={{ display: "block", fontSize: "0.85rem", fontWeight: 700, color: "#e2e8f0", marginBottom: "8px" }}>
            Próxima ação pedagógica recomendada para esta bancada:
          </label>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "8px" }}>
            {NEXT_ACTION_OPTIONS.map(([actKey, label]) => {
              const isSelected = answers.nextAction === actKey;
              return (
                <button
                  key={actKey}
                  type="button"
                  className={`scale-option ${isSelected ? "is-selected" : ""}`}
                  style={{ padding: "8px 12px", minHeight: "auto", textAlign: "left", fontSize: "0.82rem" }}
                  onClick={() => setAnswers({ ...answers, nextAction: actKey })}
                >
                  <strong style={{ fontSize: "0.84rem" }}>{label}</strong>
                </button>
              );
            })}
          </div>
        </div>
      </div>
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

function CheckpointAlertModal({ mark, onSelectOption, onSkip }) {
  return (
    <div className="alert-modal-backdrop" role="dialog" aria-modal="true" aria-labelledby="checkpoint-modal-title">
      <div className="alert-modal" style={{ maxWidth: "580px", width: "92%", padding: "26px 24px" }}>
        <div className="alert-modal__icon">🤖</div>
        <span className="alert-modal__eyebrow">Check-in de {mark} minutos · Registro Rápido</span>
        <h2 id="checkpoint-modal-title" style={{ fontSize: "1.25rem", margin: "10px 0 6px" }}>
          Hora do Check-in ({mark} min)
        </h2>
        <p style={{ fontSize: "0.95rem", color: "#cbd5e1", marginBottom: "16px", lineHeight: "1.45" }}>
          <strong>Nos dois minutos antes deste aviso, a bancada ficou sem saber o que tentar para avançar?</strong>
        </p>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "10px", marginBottom: "16px" }}>
          {IMPASSE_OPTIONS.map(([val, title, desc]) => (
            <button
              key={val}
              type="button"
              className="scale-option"
              onClick={() => onSelectOption(val)}
              style={{
                textAlign: "left",
                padding: "10px 12px",
                minHeight: "auto",
                border: "1px solid rgba(255, 255, 255, 0.12)",
                background: "rgba(255, 255, 255, 0.05)",
                borderRadius: "10px",
                cursor: "pointer",
                transition: "all 0.15s ease"
              }}
            >
              <strong style={{ fontSize: "0.94rem", display: "block", color: "#f8fafc", marginBottom: "3px" }}>{title}</strong>
              <small style={{ fontSize: "0.75rem", color: "#94a3b8", display: "block", lineHeight: "1.3" }}>{desc}</small>
            </button>
          ))}
        </div>
        <div style={{ display: "flex", justifyContent: "center" }}>
          <button
            className="button button--ghost"
            onClick={onSkip}
            type="button"
            style={{ fontSize: "0.86rem", padding: "8px 18px", color: "var(--muted)" }}
          >
            Pular este check-in
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
  const [teamRole, setTeamRole] = useState(() => savedSession?.teamRole || "dyad");
  const [currentRole, setCurrentRole] = useState(() => savedSession?.currentRole || "computer");
  const [assentAgreed, setAssentAgreed] = useState(() => savedSession?.assentAgreed ?? true);
  const [helpActive, setHelpActive] = useState(() => savedSession?.helpActive || false);
  const [isSyntheticSession, setIsSyntheticSession] = useState(() => savedSession?.isSyntheticSession || false);
  const [showContextModal, setShowContextModal] = useState(false);
  const [online, setOnline] = useState(() => navigator.onLine);
  const [toast, setToast] = useState("");
  const [checkpointModalMark, setCheckpointModalMark] = useState(null);
  const [showInstructorTools, setShowInstructorTools] = useState(labMode);
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const sequenceRef = useRef(savedSession?.sequence || 0);
  const checkpointOpeningRef = useRef(false);
  const checkpointPromptedAtRef = useRef(null);
  const lastCheckpointCompletedAtRef = useRef(0);
  const isSyntheticSessionRef = useRef(savedSession?.isSyntheticSession || false);


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

  const refreshPendingCount = React.useCallback(async () => {
    try {
      const pending = await listPendingEvents();
      setDbPendingCount(pending.length);
    } catch {
      // IndexedDB indisponível em fallback
    }
  }, []);

  useEffect(() => {
    pruneDeliveredEvents(7).catch(() => {});
    refreshPendingCount();
  }, [refreshPendingCount]);

  const allEvents = [...timeline, ...responses];
  const memoryPendingCount = allEvents.filter((event) => event._delivery_state === "queued").length;
  const pendingCount = Math.max(memoryPendingCount, dbPendingCount);
  const activeStep = stepForScreen(screen);

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
      elapsed_ms: Math.max(0, now - startedAt),
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
    void saveEvent(event).then(() => {
      void refreshPendingCount();
    }).catch(() =>
      flash("Não foi possível salvar no armazenamento local deste navegador.")
    );
    void notifyBridgeEvent(event);
    if (typeof navigator !== "undefined" && navigator.onLine) {
      void syncSingleEvent(event).then((synced) => {
        if (synced) {
          updateEventDeliveryState(event.event_id, "delivered");
        }
        void refreshPendingCount();
      });
    }
  }

  function emitTimeline(eventType, overrides = {}) {
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
        ...(isSyntheticSessionRef.current || isSyntheticSession ? { is_synthetic: true } : {})
      },
      ...overrides
    });
    setTimeline((current) => [...current, event]);
    persist(event);
    return event;
  }

  function emitResponse(eventType, overrides = {}) {
    const sysMeta = getSystemMetadata();
    const role = teamRole === "individual" ? "individual" : (teamRole === "group" ? "group" : currentRole);
    const participantSuffix = teamRole === "individual" ? "IND" : (teamRole === "group" ? "GRUPO" : "BANCADA");
    const groupSize = teamRole === "individual" ? 1 : (teamRole === "group" ? 3 : 2);

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
    setTeamRole(resumable.teamRole || "dyad");
    setCurrentRole(resumable.currentRole || "computer");
    setAssentAgreed(resumable.assentAgreed ?? true);
    setHelpActive(resumable.helpActive || false);
    setIsSyntheticSession(resumable.isSyntheticSession || false);
    sequenceRef.current = resumable.sequence || 0;
    setScreen(resumable.screen);
    flash("Sessão retomada do armazenamento local.");
  }

  function handleRoleSwap() {
    const nextRole = currentRole === "computer" ? "assembly" : "computer";
    setCurrentRole(nextRole);
    emitTimeline("role_swapped", {
      activity_stage: screen,
      details: {
        from_role: currentRole,
        to_role: nextRole,
        scheduled_swap: false
      }
    });
    flash(`Papéis trocados! Agora: ${nextRole === "computer" ? "💻 Computador / Código" : "🛠️ Montagem / Testes"}.`);
  }

  function handleSaveContext(newContext) {
    setContext(newContext);
    localStorage.setItem(CONTEXT_KEY, JSON.stringify(newContext));
    flash(`Região salva com sucesso: ${newContext.regional}!`);
  }

  async function handleAutoLoadConfig() {
    flash("Consultando config.json do bridge...");
    const cfg = await fetchBridgeConfig();
    if (cfg && (cfg.site_id || cfg.school_code)) {
      const merged = {
        ...context,
        site_id: cfg.site_id && cfg.site_id !== "CONFIGURE_SEDE" ? cfg.site_id : context.site_id,
        regional: cfg.regional_hub || context.regional,
        school: cfg.school_code && cfg.school_code !== "CONFIGURE_ESCOLA" ? cfg.school_code : context.school,
        workshop: cfg.workshop_code && cfg.workshop_code !== "CONFIGURE_OFICINA" ? cfg.workshop_code : context.workshop,
        class: cfg.class_code && cfg.class_code !== "CONFIGURE_TURMA" ? cfg.class_code : context.class,
        activity: cfg.activity_id || context.activity
      };
      setContext(merged);
      localStorage.setItem(CONTEXT_KEY, JSON.stringify(merged));
      flash("Configurações importadas do config.json com sucesso!");
    } else {
      flash("Não foi possível carregar do config.json (Bridge offline ou arquivo padrão).");
    }
  }

  function submitPre() {
    requestNotificationPermission();

    emitTimeline("session_started", {
      activity_stage: "init",
      details: {
        runtime: "browser_pwa",
        team_role: teamRole,
        ethical_assent: assentAgreed,
        participant_count: teamRole === "individual" ? 1 : (teamRole === "group" ? 3 : 2),
        expected_checkpoints: assentAgreed ? [20, 40] : []
      }
    });

    emitResponse("pre", {
      activity_stage: "pre",
      prior_robotics: preAnswers.experience,
      response_status: "completed"
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

  function handleDeclinePre() {
    setAssentAgreed(false);
    emitTimeline("session_started", {
      activity_stage: "init",
      details: {
        runtime: "browser_pwa",
        research_declined: true,
        participant_count: teamRole === "individual" ? 1 : (teamRole === "group" ? 3 : 2),
        expected_checkpoints: []
      }
    });
    emitResponse("pre", {
      activity_stage: "pre",
      response_status: "declined"
    });
    const activityStart = Date.now();
    setActivityStartedAt(activityStart);
    setElapsedMs(0);
    void notifyBridgeSession(sessionId, activityStart, []);
    emitTimeline("phase_completed", { activity_stage: "pre" });
    emitTimeline("activity_started", {
      activity_stage: "activity",
      details: { runtime: "browser_pwa", free_pedagogical_mode: true }
    });
    setResumable(null);
    setScreen("activity");
    flash("Oficina liberada em modo livre (sem avisos ou registros de pesquisa).");
  }

  function triggerCheckpointAlert(mark = currentMark) {
    if (!assentAgreed) return;
    if (checkpointOpeningRef.current) return;
    checkpointPromptedAtRef.current = Date.now();
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

  function handleSelectImpasse(mark, impasseChoice) {
    const now = Date.now();
    const promptedMs = checkpointPromptedAtRef.current || now;
    const scheduledMs = activityStartedAt ? activityStartedAt + mark * 60 * 1000 : now;
    const responseLatencyMs = Math.max(0, now - promptedMs);
    const checkpointLatenessMs = Math.max(0, promptedMs - scheduledMs);
    const scheduledAt = new Date(scheduledMs).toISOString();
    const promptedAt = new Date(promptedMs).toISOString();
    const capturedAt = new Date(now).toISOString();
    checkpointPromptedAtRef.current = null;
    lastCheckpointCompletedAtRef.current = now;

    if (mark === 20) {
      setCheckpoint20Answers({ impasse: impasseChoice });
    } else {
      setCheckpoint40Answers({ impasse: impasseChoice });
    }

    const progressMap = {
      no: "progressing_independently",
      yes: "needs_help_now",
      off_task: "trying_without_progress",
      no_consensus: "progressing_with_doubt"
    };

    emitResponse("checkpoint", {
      activity_stage: `checkpoint_${mark}`,
      interval_mark: mark,
      progress_state: progressMap[impasseChoice] || "trying_without_progress",
      scheduled_at: scheduledAt,
      prompted_at: promptedAt,
      captured_at: capturedAt,
      response_latency_ms: responseLatencyMs,
      checkpoint_lateness_ms: checkpointLatenessMs,
      knowledge_answers: {
        target_construct: "impasse_percebido",
        recall_window: "2_minutes",
        impasse_state: impasseChoice
      },
      response_status: "completed"
    });

    void notifyBridgeCheckpointAck(sessionId, mark);
    emitTimeline("checkpoint_completed", {
      activity_stage: `checkpoint_${mark}`,
      interval_mark: mark,
      elapsed_ms: elapsedMs,
      scheduled_at: scheduledAt,
      details: {
        runtime: "browser_pwa",
        impasse_state: impasseChoice,
        response_latency_ms: responseLatencyMs,
        checkpoint_lateness_ms: checkpointLatenessMs
      }
    });

    void captureSpikeTelemetry(`checkpoint_${mark}_done`);
    checkpointOpeningRef.current = false;
    setCheckpointModalMark(null);

    if (mark === 20) {
      setCurrentMark(40);
    }
    setScreen("activity");
    flash("Registro da bancada salvo com sucesso!");
  }

  function handleSkipCheckpoint(mark) {
    const now = Date.now();
    const promptedMs = checkpointPromptedAtRef.current || now;
    const scheduledMs = activityStartedAt ? activityStartedAt + mark * 60 * 1000 : now;
    const responseLatencyMs = Math.max(0, now - promptedMs);
    const checkpointLatenessMs = Math.max(0, promptedMs - scheduledMs);
    const scheduledAt = new Date(scheduledMs).toISOString();
    const promptedAt = new Date(promptedMs).toISOString();
    const capturedAt = new Date(now).toISOString();
    checkpointPromptedAtRef.current = null;
    lastCheckpointCompletedAtRef.current = now;

    emitResponse("checkpoint", {
      activity_stage: `checkpoint_${mark}`,
      interval_mark: mark,
      scheduled_at: scheduledAt,
      prompted_at: promptedAt,
      captured_at: capturedAt,
      response_latency_ms: responseLatencyMs,
      checkpoint_lateness_ms: checkpointLatenessMs,
      response_status: "declined",
      knowledge_answers: {
        target_construct: "impasse_percebido",
        action: "skipped"
      }
    });
    void notifyBridgeCheckpointAck(sessionId, mark);
    emitTimeline("checkpoint_completed", {
      activity_stage: `checkpoint_${mark}`,
      interval_mark: mark,
      elapsed_ms: elapsedMs,
      scheduled_at: scheduledAt,
      details: {
        runtime: "browser_pwa",
        response_status: "skipped",
        response_latency_ms: responseLatencyMs,
        checkpoint_lateness_ms: checkpointLatenessMs
      }
    });
    checkpointOpeningRef.current = false;
    setCheckpointModalMark(null);
    if (mark === 20) {
      setCurrentMark(40);
    }
    setScreen("activity");
    flash("Check-in pulado. Retornando ao desafio.");
  }

  function handleFinishActivity() {
    checkpointOpeningRef.current = false;
    setCheckpointModalMark(null);
    setScreen("post");
    flash("Desafio concluído na bancada. Prosseguindo para a rubrica do instrutor.");
  }

  function handleToggleHelp() {
    const nextState = !helpActive;
    setHelpActive(nextState);
    if (nextState) {
      emitTimeline("help_requested", {
        activity_stage: "activity",
        details: { runtime: "browser_pwa", requested_by: "student_button" }
      });
      flash("🚨 Ajuda solicitada! Levantem a mão na sala para o professor localizar a bancada.");
    } else {
      emitTimeline("help_resolved", {
        activity_stage: "activity",
        details: { runtime: "browser_pwa", resolved_by: "student_button" }
      });
      flash("✓ Ajuda marcada como atendida pelo professor.");
    }
  }

  function submitPost() {
    const issueMap = {
      repeat_sensor: "sensor",
      more_time: "technical",
      revise_logic: "logic",
      advance_challenge: "none"
    };

    emitResponse("post", {
      activity_stage: "post",
      mission_performance: postAnswers.executionScore !== null ? postAnswers.executionScore : null,
      primary_issue: issueMap[postAnswers.nextAction] || "none",
      knowledge_answers: {
        mission_result: postAnswers.missionResult,
        execution_score: postAnswers.executionScore,
        explanation_score: postAnswers.explanationScore,
        assistance_count: postAnswers.assistanceCount,
        next_action: postAnswers.nextAction
      },
      response_status: "completed"
    });

    emitTimeline("rubric_completed", {
      activity_stage: "post",
      details: {
        runtime: "browser_pwa",
        mission_result: postAnswers.missionResult,
        execution_score: postAnswers.executionScore,
        explanation_score: postAnswers.explanationScore,
        next_action: postAnswers.nextAction
      }
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

  function handleDeclinePost() {
    emitResponse("post", {
      activity_stage: "post",
      response_status: "declined"
    });
    emitTimeline("phase_completed", { activity_stage: "post" });
    emitTimeline("session_completed", {
      activity_stage: "completed",
      details: { runtime: "browser_pwa", response_status: "declined" }
    });
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
    setHelpActive(false);
    isSyntheticSessionRef.current = false;
    setIsSyntheticSession(false);
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
    isSyntheticSessionRef.current = true;
    setIsSyntheticSession(true);
    if (screen === "pre") {
      setPreAnswers({ experience: 2 });
      flash("Início preenchido com dados sintéticos de teste. Clique em 'Começar Atividade!'");
    } else if (screen === "activity") {
      triggerCheckpointAlert(currentMark);
    } else if (screen.startsWith("checkpoint")) {
      const mark = screen === "checkpoint20" ? 20 : 40;
      handleSelectImpasse(mark, "no");
      flash(`Check-in de ${mark}m preenchido com dados sintéticos.`);
    } else if (screen === "post") {
      setPostAnswers({
        missionResult: "full",
        executionScore: 3,
        explanationScore: 3,
        assistanceCount: 1,
        nextAction: "advance_challenge"
      });
      flash("Rubrica pós-oficina preenchida com dados sintéticos. Clique em 'Concluir e Salvar'");
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
      await refreshPendingCount();
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
    await refreshPendingCount();
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

      // Verificação de expiração de modal aberto há mais de 10 minutos
      if (checkpointModalMark !== null && checkpointPromptedAtRef.current) {
        const timeInModal = Date.now() - checkpointPromptedAtRef.current;
        if (timeInModal >= 10 * 60 * 1000) {
          const expiredMark = checkpointModalMark;
          const scheduledMs = activityStartedAt + expiredMark * 60 * 1000;
          emitTimeline("checkpoint_expired", {
            activity_stage: `checkpoint_${expiredMark}`,
            interval_mark: expiredMark,
            elapsed_ms: nextElapsed,
            scheduled_at: new Date(scheduledMs).toISOString(),
            details: { runtime: "browser_pwa", reason: "modal_timeout_10_minutes" }
          });
          emitResponse("checkpoint", {
            activity_stage: `checkpoint_${expiredMark}`,
            interval_mark: expiredMark,
            scheduled_at: new Date(scheduledMs).toISOString(),
            prompted_at: new Date(checkpointPromptedAtRef.current).toISOString(),
            captured_at: new Date().toISOString(),
            response_status: "timeout",
            knowledge_answers: { target_construct: "impasse_percebido", reason: "modal_timeout" }
          });
          setCheckpointModalMark(null);
          checkpointPromptedAtRef.current = null;
          checkpointOpeningRef.current = false;
          lastCheckpointCompletedAtRef.current = Date.now();
          if (expiredMark === 20) {
            setCurrentMark(40);
          }
          flash(`Check-in de ${expiredMark}m expirou após 10 minutos sem resposta.`);
          return;
        }
      }

      // Disparo de novo checkpoint se o tempo atingiu a marca e respeitou intervalo mínimo
      if (
        nextElapsed >= currentMark * 60 * 1000 &&
        !checkpointOpeningRef.current &&
        checkpointModalMark === null
      ) {
        const msSinceLast = Date.now() - lastCheckpointCompletedAtRef.current;
        if (lastCheckpointCompletedAtRef.current === 0 || msSinceLast >= 10 * 60 * 1000) {
          const lateness = nextElapsed - currentMark * 60 * 1000;
          if (lateness > 10 * 60 * 1000) {
            emitTimeline("checkpoint_expired", {
              activity_stage: `checkpoint_${currentMark}`,
              interval_mark: currentMark,
              elapsed_ms: nextElapsed,
              details: { runtime: "browser_pwa", reason: "scheduled_window_passed", lateness_ms: lateness }
            });
            if (currentMark === 20) {
              setCurrentMark(40);
            }
          } else {
            triggerCheckpointAlert(currentMark);
          }
        }
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
      teamRole,
      currentRole,
      assentAgreed,
      sequence: sequenceRef.current,
      savedAt: new Date().toISOString()
    };
    localStorage.setItem(ACTIVE_SESSION_KEY, JSON.stringify(snapshot));
    void saveSession({ session_id: sessionId, status: "in_progress", ...snapshot }).catch(() => {});
  }, [activityStartedAt, assentAgreed, checkpoint20Answers, checkpoint40Answers, context, currentMark, currentRole, elapsedMs, groupId, postAnswers, preAnswers, responses, screen, sessionId, spikeTelemetry, startedAt, teamRole, timeline]);

  let content;

  if (screen === "pre") {
    content = (
      <PreScreen
        answers={preAnswers}
        resumable={resumable}
        onResume={resumeSession}
        setAnswers={setPreAnswers}
        onSubmit={submitPre}
        onDecline={handleDeclinePre}
        teamRole={teamRole}
        setTeamRole={setTeamRole}
        assentAgreed={assentAgreed}
        setAssentAgreed={setAssentAgreed}
      />
    );
  } else if (screen === "activity") {
    content = (
      <ActivityScreen
        currentMark={currentMark}
        elapsedMs={elapsedMs}
        labMode={labMode}
        spikeTelemetry={spikeTelemetry}
        helpActive={helpActive}
        onToggleHelp={handleToggleHelp}
        onFinishActivity={handleFinishActivity}
        assentAgreed={assentAgreed}
      />
    );
  } else if (screen === "checkpoint20") {
    content = (
      <CheckpointScreen
        answers={checkpoint20Answers}
        mark={20}
        onSelectOption={(val) => handleSelectImpasse(20, val)}
        onSkip={() => handleSkipCheckpoint(20)}
        teamRole={teamRole}
        currentRole={currentRole}
        onRoleSwap={handleRoleSwap}
      />
    );
  } else if (screen === "checkpoint40") {
    content = (
      <CheckpointScreen
        answers={checkpoint40Answers}
        mark={40}
        onSelectOption={(val) => handleSelectImpasse(40, val)}
        onSkip={() => handleSkipCheckpoint(40)}
        teamRole={teamRole}
        currentRole={currentRole}
        onRoleSwap={handleRoleSwap}
      />
    );
  } else if (screen === "post") {
    content = (
      <PostScreen
        answers={postAnswers}
        setAnswers={setPostAnswers}
        onSubmit={submitPost}
        onDecline={handleDeclinePost}
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
            <small>oficina de robótica · v2.1.0</small>
          </span>
        </div>
        <div className="topbar__notice">
          <span>{labMode ? "LAB" : "OFFLINE"}</span>
          <p>{labMode ? "Modo acelerado para testes" : "Sem burocracia · telemetria automática do SPIKE"}</p>
        </div>
        <div className="topbar__controls">
          <button
            className={`topbar-btn ${showContextModal ? "is-active" : ""}`}
            onClick={() => setShowContextModal(true)}
            title="Configurar região do computador"
            type="button"
          >
            📍 Região: {context.regional || "Nordeste"}
          </button>
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
            <button className="inst-btn inst-btn--accent" onClick={() => setShowContextModal(true)} type="button">
              📍 Região ({context.regional || "Nordeste"})
            </button>
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
          onSelectOption={(val) => handleSelectImpasse(checkpointModalMark, val)}
          onSkip={() => handleSkipCheckpoint(checkpointModalMark)}
        />
      ) : null}

      <RegionMetadataModal
        isOpen={showContextModal}
        onClose={() => setShowContextModal(false)}
        context={context}
        onSave={handleSaveContext}
        configHash={CONFIG_HASH}
        computerId={getComputerId(installationId)}
        systemMetadata={getSystemMetadata()}
      />

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
              <strong>{online ? (pendingCount === 0 ? "Dispositivo Conectado · Sincronizado" : "Dispositivo Conectado · Enviando dados...") : "Modo Offline (salvando localmente)"}</strong>
              <small>{pendingCount === 0 ? "Todos os registros salvos na nuvem da pesquisa" : `${pendingCount} registro(s) pendente(s) de envio`}</small>
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
