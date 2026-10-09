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
  deleteSessionEvents,
  listPendingEvents,
  listQuarantinedEvents,
  markEventDelivered,
  markSessionEvents,
  pruneDeliveredEvents,
  enforceAbsoluteRetention,
  purgeSession,
  removeSession,
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
  quizCompleted: "participated",
  supportLevel: null
};

const FLOW_STEPS = [
  { id: 1, label: "Início" },
  { id: 2, label: "Oficina com Robô" },
  { id: 3, label: "Desafio & Avaliação" }
];

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

async function notifyBridgeEvent(event, allowed = true) {
  if (!allowed) return;
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

async function notifyBridgeSessionSave(sessionPayload, allowed = true) {
  if (!allowed) return;
  try {
    await fetch(`${BRIDGE_URL}/v1/sessions/save`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(sessionPayload)
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

async function resetBridgeSession(sessionId = null, options = {}) {
  try {
    await fetch(`${BRIDGE_URL}/v1/sessions/reset`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        session_id: sessionId,
        reason: options.reason || (options.purge ? "ethical_refusal" : "prepare_next"),
        purge: Boolean(options.purge),
        completed: Boolean(options.completed)
      })
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

function stepForState(screen) {
  if (screen === "pre") return 1;
  if (screen === "activity") return 2;
  return 3;
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
  const modalRef = useRef(null);
  const previouslyFocusedElementRef = useRef(null);

  useEffect(() => {
    setSelectedRegion(context.regional || "Nordeste");
  }, [context, isOpen]);

  useEffect(() => {
    if (!isOpen) return;

    previouslyFocusedElementRef.current = document.activeElement;

    const focusTimer = setTimeout(() => {
      if (modalRef.current) {
        const focusable = modalRef.current.querySelectorAll(
          'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
        );
        if (focusable.length > 0) {
          focusable[0].focus();
        }
      }
    }, 30);

    function handleKeyDown(e) {
      if (e.key === "Escape") {
        e.preventDefault();
        onClose();
        return;
      }
      if (e.key === "Tab") {
        if (!modalRef.current) return;
        const focusables = Array.from(
          modalRef.current.querySelectorAll(
            'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
          )
        );
        if (focusables.length === 0) return;
        const first = focusables[0];
        const last = focusables[focusables.length - 1];

        if (e.shiftKey) {
          if (document.activeElement === first) {
            e.preventDefault();
            last.focus();
          }
        } else {
          if (document.activeElement === last) {
            e.preventDefault();
            first.focus();
          }
        }
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => {
      clearTimeout(focusTimer);
      window.removeEventListener("keydown", handleKeyDown);
      if (previouslyFocusedElementRef.current && typeof previouslyFocusedElementRef.current.focus === "function") {
        previouslyFocusedElementRef.current.focus();
      }
    };
  }, [isOpen, onClose]);

  if (!isOpen) return null;

  return (
    <div className="alert-modal-backdrop" role="dialog" aria-modal="true" aria-labelledby="region-modal-title">
      <div className="alert-modal" ref={modalRef} style={{ maxWidth: "520px", textAlign: "left" }}>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: "12px" }}>
          <h2 id="region-modal-title" style={{ margin: 0, fontSize: "1.25rem", color: "#f8fafc" }}>📍 Região & Metadados do Computador</h2>
          <button className="topbar-btn" onClick={onClose} type="button" aria-label="Fechar" style={{ padding: "4px 10px" }}>✕</button>
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
  teamSize,
  setTeamSize,
  assentAgreed,
  memberAssents = { 1: false, 2: false, 3: false, 4: false },
  setMemberAssents
}) {
  const allAssented = isAllAssented(teamSize, memberAssents);
  const ready = !allAssented || answers.experience !== null;

  function toggleMemberAssent(memberIndex, checked) {
    if (typeof setMemberAssents === "function") {
      setMemberAssents((prev) => ({
        ...prev,
        [memberIndex]: checked
      }));
    }
  }

  return (
    <Card
      eyebrow="Etapa 1 de 3 · Início da Bancada"
      title="Como vocês chegam para esta oficina?"
      description="Respondam rapidamente para caracterizar a bancada antes de começar a montar e programar o robô LEGO SPIKE."
      footer={
        <div className="action-row">
          <span className="footer-hint">Sua resposta fica salva assim que você clica em começar.</span>
          {!allAssented ? (
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
            onClick={allAssented ? onSubmit : onDecline}
            type="button"
          >
            {allAssented ? "Começar Atividade!" : "Começar sem Pesquisa"}
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

      {/* Composição da Bancada com Acessibilidade Semântica */}
      <div style={{ margin: "0 0 20px", padding: "14px 16px", background: "rgba(99, 102, 241, 0.06)", borderRadius: "12px", border: "1px solid rgba(99, 102, 241, 0.2)" }}>
        <span style={{ fontSize: "0.82rem", fontWeight: 800, color: "#4f46e5", textTransform: "uppercase", letterSpacing: "0.06em", display: "block", marginBottom: "8px" }}>
          👥 Composição da Equipe na Bancada
        </span>
        <div
          role="group"
          aria-label="Composição da Equipe na Bancada"
          style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))", gap: "8px" }}
        >
          {[
            [1, "👤 1 Aluno", "Individual"],
            [2, "👫 2 Alunos", "Dupla"],
            [3, "👥 3 Alunos", "Trio"],
            [4, "👥 4 Alunos", "Quarteto"]
          ].map(([val, label, sub]) => {
            const isSel = teamSize === val;
            return (
              <button
                key={val}
                type="button"
                aria-pressed={isSel}
                className={`scale-option ${isSel ? "is-selected" : ""}`}
                onClick={() => setTeamSize(val)}
                style={{ textAlign: "left", padding: "10px 12px", minHeight: "auto" }}
              >
                <strong style={{ fontSize: "0.92rem" }}>{label}</strong>
                <small style={{ fontSize: "0.76rem", color: isSel ? "inherit" : "var(--muted)", marginTop: "2px" }}>{sub}</small>
              </button>
            );
          })}
        </div>
      </div>

      {/* Assentimento Ético Obrigatório Individual por Participante */}
      <div style={{ margin: "0 0 18px", padding: "14px 18px", background: allAssented ? "rgba(34, 197, 94, 0.08)" : "rgba(239, 68, 68, 0.08)", border: `1px solid ${allAssented ? "rgba(34, 197, 94, 0.3)" : "rgba(239, 68, 68, 0.3)"}`, borderRadius: "12px" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "10px", flexWrap: "wrap", gap: "8px" }}>
          <strong style={{ fontSize: "0.95rem", color: allAssented ? "#15803d" : "#b91c1c" }}>
            📋 Assentimento Voluntário por Participante
          </strong>
        </div>

        <p style={{ fontSize: "0.82rem", color: allAssented ? "#166534" : "#991b1b", margin: "0 0 12px", lineHeight: "1.4" }}>
          {allAssented
            ? "✓ Participação voluntária e anônima: Todos os integrantes da bancada concordaram individualmente em participar da pesquisa anônima."
            : "✋ Modo Livre: Como a bancada compartilha a montagem, o projeto e a telemetria do robô, se qualquer integrante não concordar, a bancada inteira usará o robô LEGO SPIKE livremente, com zero gravação de pesquisa e zero telemetria."}
        </p>

        <div style={{ display: "flex", flexDirection: "column", gap: "8px" }}>
          {Array.from({ length: teamSize }, (_, idx) => {
            const memberIdx = idx + 1;
            const isAssented = Boolean(memberAssents[memberIdx]);
            const memberLabel = teamSize === 1 ? "Estudante da Bancada" : `Estudante ${memberIdx} de ${teamSize}`;

            return (
              <label
                key={memberIdx}
                htmlFor={memberIdx === 1 ? "ethical-assent-checkbox" : `ethical-assent-member-${memberIdx}`}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: "10px",
                  padding: "8px 12px",
                  borderRadius: "8px",
                  background: isAssented ? "rgba(34, 197, 94, 0.12)" : "rgba(255, 255, 255, 0.03)",
                  border: `1px solid ${isAssented ? "rgba(34, 197, 94, 0.4)" : "rgba(255, 255, 255, 0.08)"}`,
                  cursor: "pointer"
                }}
              >
                <input
                  id={memberIdx === 1 ? "ethical-assent-checkbox" : `ethical-assent-member-${memberIdx}`}
                  type="checkbox"
                  checked={isAssented}
                  onChange={(e) => toggleMemberAssent(memberIdx, e.target.checked)}
                  style={{ width: "18px", height: "18px", accentColor: "#16a34a", cursor: "pointer" }}
                />
                <span style={{ fontSize: "0.86rem", color: isAssented ? "#15803d" : "inherit" }}>
                  <strong>{memberLabel}</strong>: {isAssented ? "Concorda em participar da pesquisa anônima" : "Prefere não responder questionários"}
                </span>
              </label>
            );
          })}
        </div>
      </div>

      {allAssented ? (
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
  labMode,
  spikeTelemetry,
  onAdvanceToFinalChallenge,
  assentAgreed,
  isFreeMode,
  onRefreshTelemetry
}) {
  const isFree = Boolean(isFreeMode || !assentAgreed);
  const hasSpikeCode = Boolean(spikeTelemetry && (spikeTelemetry.executable_blocks > 0 || spikeTelemetry.project_saved));

  return (
    <Card
      eyebrow="Etapa 2 de 3 · Oficina Prática com Robô"
      title="Construção, Programação & Testes do Robô"
      description="Usem o kit LEGO SPIKE Prime e o aplicativo oficial em tela cheia para montar, programar e testar o carrinho no circuito."
      footer={
        <div className="action-row" style={{ justifyContent: "space-between", width: "100%", alignItems: "center" }}>
          <span className="footer-hint" style={{ fontSize: "0.88rem", color: "var(--muted)" }}>
            {isFree ? "Oficina livre sem coleta de dados (Modo Livre · Zero gravação)." : "⏱️ Coleta contínua e silenciosa em segundo plano."}
          </span>
          <button
            className="button button--primary"
            onClick={onAdvanceToFinalChallenge}
            type="button"
          >
            🏁 Finalizar Oficina & Ir para Corrida ➔
          </button>
        </div>
      }
    >
      <div className="activity-timer" aria-live="polite">
        <span>Tempo total de oficina</span>
        <strong>{formatClock(elapsedMs)}</strong>
        <small>{isFree ? "Modo Livre pedagógico · Zero coleta de dados" : "Coleta silenciosa em segundo plano · Sem interrupções"}</small>
      </div>

      {isFree ? (
        <div style={{ background: "rgba(56, 189, 248, 0.08)", border: "1px solid rgba(56, 189, 248, 0.3)", borderRadius: "12px", padding: "14px 18px", margin: "16px 0" }}>
          <span style={{ fontSize: "0.88rem", color: "#7dd3fc" }}>
            🤖 <strong>Modo Livre Pedagógico:</strong> O robô LEGO SPIKE funciona livremente. Nenhuma telemetria, código ou evento é gravado nesta oficina.
          </span>
        </div>
      ) : (
        <div style={{ background: hasSpikeCode ? "rgba(16, 185, 129, 0.08)" : "rgba(56, 189, 248, 0.08)", border: `1px solid ${hasSpikeCode ? "rgba(16, 185, 129, 0.3)" : "rgba(56, 189, 248, 0.3)"}`, borderRadius: "12px", padding: "14px 18px", margin: "16px 0", display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: "10px" }}>
          <div>
            <span style={{ fontSize: "0.88rem", color: hasSpikeCode ? "#6ee7b7" : "#7dd3fc" }}>
              🤖 <strong>Telemetria LEGO SPIKE:</strong>{" "}
              {hasSpikeCode
                ? `${spikeTelemetry.executable_blocks || 0} blocos detectados · Estrutura: ${spikeTelemetry.inferred_stage || "em edição"} · ${spikeTelemetry.file_name || "projeto .llsp3"}`
                : "Aguardando projeto salvo no app LEGO SPIKE (.llsp3)"}
            </span>
            {hasSpikeCode && (
              <small style={{ display: "block", color: "rgba(255, 255, 255, 0.6)", marginTop: "4px", fontSize: "0.78rem" }}>
                Início da programação detectado automaticamente · Coletando deltas de código em silêncio
              </small>
            )}
          </div>
          <button
            type="button"
            className="inst-btn"
            onClick={onRefreshTelemetry}
            style={{ fontSize: "0.78rem", padding: "4px 10px", background: "rgba(255, 255, 255, 0.08)", color: "#e2e8f0", borderColor: "rgba(255, 255, 255, 0.2)" }}
          >
            🔄 Atualizar telemetria
          </button>
        </div>
      )}

      <div className="activity-instructions">
        <article>
          <span>1</span>
          <strong>Foco Total no Robô LEGO</strong>
          <p>Trabalhem na montagem física e abram o app oficial LEGO SPIKE em tela cheia para programar e testar.</p>
        </article>
        <article>
          <span>2</span>
          <strong>{isFree ? "Uso Livre do Robô" : "Telemetria 100% Silenciosa"}</strong>
          <p>
            {isFree
              ? "Montem e programem livremente. Nesta bancada, nenhuma telemetria ou código é coletado ou gravado."
              : "O PulseLab acompanha o tempo e detecta os blocos de código em segundo plano, sem travar nem pedir confirmações."}
          </p>
        </article>
        <article>
          <span>3</span>
          <strong>Desafio Final & Corrida</strong>
          <p>Ao terminar a montagem e os testes, cliquem no botão abaixo para registrar a corrida na pista e a avaliação final.</p>
        </article>
      </div>
    </Card>
  );
}

function PostScreen({
  answers,
  setAnswers,
  onSubmit,
  onDecline,
  teamSize = 2,
  memberAssents = { 1: false, 2: false, 3: false, 4: false }
}) {
  const experiences = useMemo(() => {
    return resolveMemberExperiences(teamSize, memberAssents, answers.memberExperiences);
  }, [answers.memberExperiences, teamSize, memberAssents]);

  const ready = isPostScreenReady(teamSize, experiences);

  function handleMemberRating(memberIndex, rating) {
    const updated = experiences.map((m) =>
      m.memberIndex === memberIndex ? { ...m, rating, skipped: false } : m
    );
    setAnswers({ ...answers, memberExperiences: updated });
  }

  function handleToggleMemberSkip(memberIndex) {
    const updated = experiences.map((m) =>
      m.memberIndex === memberIndex ? { ...m, rating: null, skipped: !m.skipped } : m
    );
    setAnswers({ ...answers, memberExperiences: updated });
  }

  return (
    <Card
      eyebrow="Etapa 3 de 3 · Desafio da Corrida & Avaliação Final"
      title="Desafio da Corrida & Avaliação Final"
      description="Avaliação estruturada em dois eixos independentes: a experiência subjetiva dos alunos e os resultados objetivos da bancada na pista."
      footer={
        <div className="action-row">
          <button
            className="button button--ghost"
            onClick={onDecline}
            type="button"
            style={{ marginRight: "auto" }}
          >
            Pular avaliação e finalizar
          </button>
          <button
            className="button button--primary"
            disabled={!ready}
            onClick={() => onSubmit()}
            type="button"
          >
            Concluir e Salvar Oficina
          </button>
        </div>
      }
    >
      {/* Eixo 1: Experiência Subjetiva Individual de Cada Integrante */}
      <fieldset className="question-block" style={{ marginBottom: "26px" }}>
        <legend className="question-legend" style={{ fontSize: "1.1rem", color: "#f8fafc", fontWeight: 700, marginBottom: "4px" }}>
          ✨ Eixo 1: Como foi participar da oficina de robótica de hoje?
        </legend>
        <p style={{ color: "#94a3b8", fontSize: "0.85rem", marginTop: 0, marginBottom: "16px" }}>
          Avaliação individual da experiência da oficina. Cada integrante responde de forma independente, sem exigir consenso na bancada.
        </p>

        <div style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
          {experiences.map((member) => {
            const memberLabel =
              teamSize === 1
                ? "Avaliação do Estudante"
                : `Estudante ${member.memberIndex} de ${teamSize}`;

            return (
              <div
                key={member.memberIndex}
                style={{
                  padding: "14px 16px",
                  background: "rgba(255, 255, 255, 0.03)",
                  border: "1px solid rgba(255, 255, 255, 0.1)",
                  borderRadius: "12px"
                }}
              >
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "10px", flexWrap: "wrap", gap: "8px" }}>
                  <strong style={{ fontSize: "0.95rem", color: "#e2e8f0" }}>
                    👤 {memberLabel}:
                  </strong>
                  {!member.declinedAssent ? (
                    <button
                      type="button"
                      className="button button--ghost"
                      onClick={() => handleToggleMemberSkip(member.memberIndex)}
                      style={{
                        fontSize: "0.78rem",
                        padding: "3px 10px",
                        borderColor: member.skipped ? "#38bdf8" : "rgba(255, 255, 255, 0.2)",
                        color: member.skipped ? "#38bdf8" : "#94a3b8"
                      }}
                    >
                      {member.skipped ? "✓ Optou por não responder" : "Prefiro não responder"}
                    </button>
                  ) : null}
                </div>

                {member.declinedAssent ? (
                  <div style={{ padding: "8px 12px", background: "rgba(239, 68, 68, 0.08)", border: "1px dashed rgba(239, 68, 68, 0.3)", borderRadius: "8px", color: "#f87171", fontSize: "0.82rem" }}>
                    Estudante optou por não participar da pesquisa no início da oficina. Nenhuma resposta é coletada para esta posição.
                  </div>
                ) : !member.skipped ? (
                  <div className="scale-grid">
                    {POST_EXPERIENCE_OPTIONS.map(([optionValue, label, sublabel]) => {
                      const parts = String(label).match(/^(\S+)\s+(.+)$/);
                      const icon = parts ? parts[1] : optionValue;
                      const title = parts ? parts[2] : label;
                      const isSelected = member.rating === optionValue;
                      return (
                        <button
                          className={`scale-option ${isSelected ? "is-selected" : ""}`}
                          key={optionValue}
                          onClick={() => handleMemberRating(member.memberIndex, optionValue)}
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
                ) : (
                  <div style={{ padding: "8px 12px", background: "rgba(56, 189, 248, 0.08)", border: "1px dashed rgba(56, 189, 248, 0.3)", borderRadius: "8px", color: "#38bdf8", fontSize: "0.82rem" }}>
                    Estudante optou por não responder a avaliação de experiência.
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </fieldset>

      {/* Eixo 2: Resultados Práticos Imediatos & Apoio do Instrutor */}
      <div style={{ padding: "18px 20px", background: "rgba(36, 86, 77, 0.15)", border: "1px solid rgba(73, 217, 206, 0.3)", borderRadius: "16px", marginTop: "10px" }}>
        <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "16px" }}>
          <span style={{ fontSize: "1.2rem" }}>🏁</span>
          <strong style={{ fontSize: "1.05rem", color: "#49d9ce" }}>
            Eixo 2: Resultados Práticos da Bancada & Observação do Instrutor
          </strong>
        </div>

        {/* 1. Corrida / Desafio da Pista */}
        <div style={{ marginBottom: "20px" }}>
          <label style={{ display: "block", fontSize: "0.9rem", fontWeight: 700, color: "#e2e8f0", marginBottom: "8px" }}>
            1. Desfecho do Desafio da Pista / Corrida do Robô:
          </label>
          <div className="option-list">
            {RACE_RESULT_OPTIONS.map(([val, title, desc]) => {
              const isSelected = answers.raceResult === val;
              return (
                <label key={val} className={`option-row ${isSelected ? "is-selected" : ""}`} style={{ cursor: "pointer" }}>
                  <input
                    type="radio"
                    name="race-result"
                    value={val}
                    checked={isSelected}
                    onChange={() => setAnswers({ ...answers, raceResult: val })}
                    style={{ position: "absolute", width: "1px", height: "1px", padding: 0, margin: "-1px", overflow: "hidden", clip: "rect(0, 0, 0, 0)", whiteSpace: "nowrap", border: 0, opacity: 0.001 }}
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

          <div style={{ marginTop: "10px", display: "flex", alignItems: "center", gap: "10px" }}>
            <label htmlFor="race-time-input" style={{ fontSize: "0.82rem", color: "#cbd5e1" }}>
              ⏱️ Tempo da corrida (segundos, opcional):
            </label>
            <input
              id="race-time-input"
              type="number"
              step="0.1"
              min="0"
              placeholder="Ex: 12.5"
              value={answers.raceTimeSeconds || ""}
              onChange={(e) => setAnswers({ ...answers, raceTimeSeconds: e.target.value })}
              style={{
                width: "110px",
                padding: "6px 10px",
                background: "#0f172a",
                border: "1px solid rgba(255, 255, 255, 0.15)",
                borderRadius: "8px",
                color: "#f8fafc",
                fontSize: "0.88rem"
              }}
            />
          </div>
        </div>

        {/* 2. Montagem Física */}
        <div style={{ marginBottom: "20px" }}>
          <label style={{ display: "block", fontSize: "0.9rem", fontWeight: 700, color: "#e2e8f0", marginBottom: "8px" }}>
            2. Critérios de Montagem do Carrinho (tutorial com peças LEGO):
          </label>
          <div className="option-list">
            {ASSEMBLY_OPTIONS.map(([val, title, desc]) => {
              const isSelected = answers.assemblyResult === val;
              return (
                <label key={val} className={`option-row ${isSelected ? "is-selected" : ""}`} style={{ cursor: "pointer", padding: "8px 12px" }}>
                  <input
                    type="radio"
                    name="assembly-result"
                    value={val}
                    checked={isSelected}
                    onChange={() => setAnswers({ ...answers, assemblyResult: val })}
                    style={{ position: "absolute", width: "1px", height: "1px", padding: 0, margin: "-1px", overflow: "hidden", clip: "rect(0, 0, 0, 0)", whiteSpace: "nowrap", border: 0, opacity: 0.001 }}
                  />
                  <span className="option-row__body">
                    <strong style={{ fontSize: "0.9rem", color: "#f1f5f9" }}>{title}</strong>
                    <small style={{ color: "#94a3b8", fontSize: "0.78rem" }}>{desc}</small>
                  </span>
                  <span className="option-row__radio" />
                </label>
              );
            })}
          </div>
        </div>

        {/* 3. Dinâmica Lúdica do Quiz A/B */}
        <div style={{ marginBottom: "20px" }}>
          <label style={{ display: "block", fontSize: "0.9rem", fontWeight: 700, color: "#e2e8f0", marginBottom: "4px" }}>
            3. Dinâmica Lúdica do Quiz A/B pelos Botões do Robô:
          </label>
          <span style={{ fontSize: "0.78rem", color: "#94a3b8", display: "block", marginBottom: "8px" }}>
            Brincadeira de entretenimento de encerramento (não utilizada como avaliação de aprendizagem).
          </span>
          <div role="group" aria-label="Dinâmica Lúdica do Quiz A/B pelos Botões do Robô" style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "8px" }}>
            {QUIZ_OPTIONS.map(([val, label]) => {
              const isSelected = answers.quizCompleted === val;
              return (
                <button
                  key={val}
                  type="button"
                  aria-pressed={isSelected}
                  className={`scale-option ${isSelected ? "is-selected" : ""}`}
                  style={{ padding: "8px 12px", minHeight: "auto", textAlign: "left", fontSize: "0.82rem" }}
                  onClick={() => setAnswers({ ...answers, quizCompleted: val })}
                >
                  <strong style={{ fontSize: "0.84rem" }}>{label}</strong>
                </button>
              );
            })}
          </div>
        </div>

        {/* 4. Nível de Apoio do Instrutor */}
        <div>
          <label style={{ display: "block", fontSize: "0.9rem", fontWeight: 700, color: "#e2e8f0", marginBottom: "8px" }}>
            4. Nível de Apoio Pedagógico Recebido pela Bancada:
          </label>
          <div className="option-list">
            {SUPPORT_OPTIONS.map(([val, title, desc]) => {
              const isSelected = answers.supportLevel === val;
              return (
                <label key={val} className={`option-row ${isSelected ? "is-selected" : ""}`} style={{ cursor: "pointer", padding: "8px 12px" }}>
                  <input
                    type="radio"
                    name="support-level"
                    value={val}
                    checked={isSelected}
                    onChange={() => setAnswers({ ...answers, supportLevel: val })}
                    style={{ position: "absolute", width: "1px", height: "1px", padding: 0, margin: "-1px", overflow: "hidden", clip: "rect(0, 0, 0, 0)", whiteSpace: "nowrap", border: 0, opacity: 0.001 }}
                  />
                  <span className="option-row__body">
                    <strong style={{ fontSize: "0.9rem", color: "#f1f5f9" }}>{title}</strong>
                    <small style={{ color: "#94a3b8", fontSize: "0.78rem" }}>{desc}</small>
                  </span>
                  <span className="option-row__radio" />
                </label>
              );
            })}
          </div>
        </div>
      </div>
    </Card>
  );
}

function FreeModeFinishedScreen({ onRestart }) {
  return (
    <Card
      compact
      eyebrow="Oficina Livre"
      title="Oficina concluída com sucesso!"
      description="A atividade prática foi realizada livremente sem questionários ou telemetria de pesquisa."
      footer={
        <div className="action-row">
          <button className="button button--primary" onClick={onRestart} type="button">
            Preparar Nova Oficina
          </button>
        </div>
      }
    >
      <div className="summary-status summary-status--success">
        <span className="summary-status__mark">✓</span>
        <div>
          <span>Modo Livre Pedagógico</span>
          <h2>Parabéns pelo trabalho na oficina!</h2>
          <p>
            Esta atividade ocorreu em modo pedagógico livre. Nenhuma informação pessoal, resposta ou telemetria foi salva ou transmitida.
          </p>
        </div>
      </div>
    </Card>
  );
}

function FinishedScreen({ pendingCount, quarantinedCount = 0, totalSavedCount = 0, onDownload, onRestart }) {
  const displayCount = totalSavedCount > 0 ? totalSavedCount : pendingCount;
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
          {quarantinedCount > 0 ? (
            <p style={{ color: "#f87171" }}>
              ⚠️ {quarantinedCount} registro(s) em quarentena local para análise do pesquisador. Os demais registros estão salvos no computador.
            </p>
          ) : (
            <p>
              {displayCount} registro(s) salvos no computador com segurança (armazenamento offline-first). Os dados serão consolidados pelo pesquisador via pendrive ou importador autorizado.
            </p>
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


export default function StudentPage() {
  const labMode = useMemo(() => new URLSearchParams(window.location.search).get("lab") === "1", []);
  const rawSavedSession = useMemo(() => readJson(ACTIVE_SESSION_KEY, null), []);
  const savedSession = useMemo(() => {
    if (!rawSavedSession) return null;
    const validated = validateRestoredSession(rawSavedSession);
    if (!validated) {
      try {
        localStorage.removeItem(ACTIVE_SESSION_KEY);
      } catch {}
      return null;
    }
    return validated;
  }, [rawSavedSession]);

  const [context, setContext] = useState(() => readJson(CONTEXT_KEY, DEFAULT_CONTEXT));
  const [resumable, setResumable] = useState(savedSession);
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
  const [startedAt, setStartedAt] = useState(() => savedSession?.startedAt || Date.now());
  const [activityStartedAt, setActivityStartedAt] = useState(() => savedSession?.activityStartedAt || null);
  const [elapsedMs, setElapsedMs] = useState(() => {
    if (savedSession?.activityStartedAt) {
      return Math.max(0, Date.now() - savedSession.activityStartedAt);
    }
    return savedSession?.elapsedMs || 0;
  });
  const [timeline, setTimeline] = useState(() => savedSession?.timeline || []);
  const [responses, setResponses] = useState(() => savedSession?.responses || []);
  const [spikeTelemetry, setSpikeTelemetry] = useState(() => savedSession?.spikeTelemetry || null);
  const [preAnswers, setPreAnswers] = useState(() => ({
    ...PRE_DEFAULT,
    ...(savedSession?.preAnswers && typeof savedSession.preAnswers === "object" ? savedSession.preAnswers : {})
  }));
  const [postAnswers, setPostAnswers] = useState(() => ({
    ...POST_DEFAULT,
    ...(savedSession?.postAnswers && typeof savedSession.postAnswers === "object" ? savedSession.postAnswers : {})
  }));
  const [teamSize, setTeamSize] = useState(() => savedSession?.teamSize || 2);
  const [currentRole, setCurrentRole] = useState(() => savedSession?.currentRole || "computer");
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
    setMemberAssentsState((prev) => {
      const next = typeof valOrFn === "function" ? valOrFn(prev) : valOrFn;
      memberAssentsRef.current = next;
      const allAssented = isAllAssented(teamSize, next);
      assentAgreedRef.current = allAssented;
      setAssentAgreedState(allAssented);
      return next;
    });
  }

  function handleTeamSizeChange(newSize) {
    setTeamSize(newSize);
    const allAssented = isAllAssented(newSize, memberAssentsRef.current);
    assentAgreedRef.current = allAssented;
    setAssentAgreedState(allAssented);
  }
  const [isSyntheticSession, setIsSyntheticSession] = useState(() => savedSession?.isSyntheticSession || false);
  const [showContextModal, setShowContextModal] = useState(false);
  const [online, setOnline] = useState(() => navigator.onLine);
  const [toast, setToast] = useState("");
  const [showInstructorTools, setShowInstructorTools] = useState(labMode);
  const sequenceRef = useRef(savedSession?.sequence || 0);
  const isSyntheticSessionRef = useRef(savedSession?.isSyntheticSession || false);
  const isSubmittingRef = useRef(false);


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
  const memoryPendingCount = allEvents.filter((event) => event._delivery_state === "queued").length;
  const pendingCount = Math.max(memoryPendingCount, dbPendingCount);
  const memoryQuarantinedCount = allEvents.filter((event) => event._delivery_state === "quarantined").length;
  const quarantinedCount = Math.max(memoryQuarantinedCount, dbQuarantinedCount);
  const memoryStoredCount = allEvents.length + (screen !== "pre" && assentAgreed ? 1 : 0);
  const totalSavedCount = Math.max(memoryStoredCount, dbTotalStoredCount, pendingCount);
  const activeStep = stepForState(screen, activityStage);

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
    if (!assentAgreedRef.current || isFreeMode) return;
    void saveEvent(event).then(() => {
      void refreshDeliveryCounts();
    }).catch(() =>
      flash("Não foi possível salvar no armazenamento local deste navegador.")
    );
    void notifyBridgeEvent(event);
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
      const metrics = await fetchBridgeSpikeMetrics();
      if (metrics && metrics.project_saved !== false) {
        setSpikeTelemetry(metrics);
        const event = emitTimeline("spike_telemetry", {
          activity_stage: stageLabel,
          details: {
            executable_blocks: metrics.executable_blocks,
            top_level_stacks: metrics.top_level_stacks,
            uses_motor: metrics.uses_motor,
            uses_sensor: metrics.uses_sensor,
            uses_loop: metrics.uses_loop,
            uses_condition: metrics.uses_condition,
            file_name: metrics.file_name
          }
        });
        return { metrics, event };
      }
      return { metrics: metrics || null, event: null };
    } catch {
      return { metrics: null, event: null };
    }
  }

  function resumeSession() {
    if (!resumable) return;
    const valid = validateRestoredSession(resumable);
    if (!valid) {
      localStorage.removeItem(ACTIVE_SESSION_KEY);
      setResumable(null);
      flash("Sessão salva corrompida ou inválida descartada por segurança.");
      return;
    }
    setContext(valid.context || DEFAULT_CONTEXT);
    setSessionId(valid.sessionId);
    setGroupId(valid.groupId);
    setStartedAt(valid.startedAt);
    setActivityStartedAt(valid.activityStartedAt);
    setElapsedMs(valid.activityStartedAt ? Math.max(0, Date.now() - valid.activityStartedAt) : (valid.elapsedMs || 0));
    setActivityStage(valid.activityStage || 2);
    setTimeline(valid.timeline || []);
    setResponses(valid.responses || []);
    setSpikeTelemetry(valid.spikeTelemetry || null);
    setPreAnswers(valid.preAnswers || PRE_DEFAULT);
    setPostAnswers(valid.postAnswers || POST_DEFAULT);
    const restoredTeamSize = valid.teamSize;
    setTeamSize(restoredTeamSize);
    setCurrentRole(valid.currentRole || "computer");
    const restoredAssents = valid.memberAssents || { 1: false, 2: false, 3: false, 4: false };
    setMemberAssentsState(restoredAssents);
    memberAssentsRef.current = restoredAssents;
    const allAssented = isAllAssented(restoredTeamSize, restoredAssents);
    assentAgreedRef.current = allAssented;
    setAssentAgreedState(allAssented);
    if (allAssented) {
      const validInstId = valid.installation_id || getPersistedInstallationId() || installationId;
      setInstallationId(validInstId);
      try {
        localStorage.setItem(INSTALLATION_KEY, validInstId);
      } catch {}
    } else {
      try {
        localStorage.removeItem(INSTALLATION_KEY);
        localStorage.removeItem(LEGACY_INSTALLATION_KEY);
      } catch {}
    }
    setIsSyntheticSession(valid.isSyntheticSession || false);
    sequenceRef.current = valid.sequence || 0;
    setScreen(valid.screen);
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

    const activityStart = Date.now();
    setActivityStartedAt(activityStart);
    setElapsedMs(0);
    setActivityStage(2);
    void notifyBridgeSession(sessionId, activityStart, [], assentAgreedRef.current);
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
    setResumable(null);
    setScreen("activity");
  }

  async function handleDeclinePre() {
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
    await resetBridgeSession(sessionId, { reason: "ethical_refusal", purge: true });
    setIsFreeMode(true);
    assentAgreedRef.current = false;
    setAssentAgreedState(false);
    setTimeline([]);
    setResponses([]);
    setSpikeTelemetry(null);
    setResumable(null);
    const activityStart = Date.now();
    setActivityStartedAt(activityStart);
    setElapsedMs(0);
    setActivityStage(2);
    setScreen("activity");
    flash("Oficina liberada em modo livre (sem questionários e sem coleta de dados).");
  }

  function handleAdvanceToFinalChallenge() {
    if (!isFreeMode && assentAgreedRef.current) {
      emitTimeline("phase_completed", {
        activity_stage: "2. Oficina Prática",
        details: { elapsed_ms: elapsedMs }
      });
      emitTimeline("phase_transition", {
        activity_stage: "3. Desafio da Corrida",
        details: {
          runtime: "browser_pwa",
          from_stage: "2. Oficina Prática",
          to_stage: "3. Desafio da Corrida",
          elapsed_ms: elapsedMs
        }
      });
      void captureSpikeTelemetry("final_challenge_start");
    }
    setScreen("post");
    flash("Avançado para o Desafio da Corrida & Avaliação Final.");
  }

  async function submitPost(answersOverride = null) {
    isSubmittingRef.current = true;
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
          participant_id: `${groupId.slice(0, 8).toUpperCase()}-MEMBER-${member.memberIndex}`,
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

    await notifyBridgeSessionSave(fullSession, assentAgreedRef.current);
    await saveSession(fullSession).catch(() => {});

    localStorage.removeItem(ACTIVE_SESSION_KEY);
    void runSync(true);
    setScreen("finished");
  }

  async function handleDeclinePost() {
    isSubmittingRef.current = true;
    if (!assentAgreedRef.current || isFreeMode) {
      try {
        localStorage.removeItem(INSTALLATION_KEY);
        localStorage.removeItem(LEGACY_INSTALLATION_KEY);
      } catch {}
      localStorage.removeItem(ACTIVE_SESSION_KEY);
      setScreen("finished");
      return;
    }

    const finalEvents = [];
    finalEvents.push(emitResponse("post", {
      activity_stage: "3. Desafio da Corrida",
      response_status: "declined"
    }));
    finalEvents.push(emitTimeline("phase_completed", { activity_stage: "3. Desafio da Corrida" }));

    // Ordem estrita: a telemetria terminal entra ANTES do encerramento final da sessão
    const { metrics: rawFinalMetrics, event: finalTelemetryEvent } = await captureSpikeTelemetry("session_completed");
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
      group_size: teamSize,
      team_size: teamSize,
      team_role: teamSize === 1 ? "individual" : "group",
      status: "declined",
      pre_answers: preAnswers,
      post_answers: postAnswers,
      events: [...timeline, ...responses, ...finalEvents],
      spike_telemetry: effectiveTelemetry,
      telemetry_status: technicalStatus
    };

    await notifyBridgeSessionSave(fullSession, assentAgreedRef.current);
    await saveSession(fullSession).catch(() => {});

    localStorage.removeItem(ACTIVE_SESSION_KEY);
    void runSync(true);
    setScreen("finished");
  }

  async function prepareNextWorkshop() {
    isSubmittingRef.current = false;
    try {
      localStorage.removeItem(INSTALLATION_KEY);
      localStorage.removeItem(LEGACY_INSTALLATION_KEY);
    } catch {}
    localStorage.removeItem(ACTIVE_SESSION_KEY);
    await resetBridgeSession(sessionId, { reason: "prepare_next", purge: false, completed: true });
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
    isSyntheticSessionRef.current = false;
    setIsSyntheticSession(false);
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
    setResumable(null);
    setScreen("pre");
    flash("Nova oficina preparada! Pronto para a próxima bancada.");
  }

  async function resetToPre() {
    isSubmittingRef.current = false;
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
    await resetBridgeSession(sessionId, { reason: "abandonment", purge: true });
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
    isSyntheticSessionRef.current = false;
    setIsSyntheticSession(false);
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
    setResumable(null);
    setScreen("pre");
    flash("Oficina reiniciada do zero com sucesso.");
  }

  function handleConfirmReset() {
    if (screen === "finished") {
      prepareNextWorkshop();
      return;
    }
    const confirmed = window.confirm(
      "Deseja realmente reiniciar a oficina do zero?\n\nIsso apagará a sessão atual neste computador e iniciará uma nova oficina limpa."
    );
    if (!confirmed) return;
    resetToPre();
  }

  function forceStage(stageNum) {
    if (stageNum === 1) {
      setScreen("pre");
    } else if (stageNum === 2) {
      if (screen === "pre") {
        setActivityStartedAt(Date.now());
        setElapsedMs(0);
      }
      setActivityStage(2);
      setScreen("activity");
      flash("Navegado para a Oficina Prática (Robô LEGO SPIKE).");
    } else if (stageNum === 3) {
      setScreen("post");
      flash("Avançado para o Desafio da Corrida & Avaliação Final.");
    }
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

  function autoFillCurrentStep() {
    isSyntheticSessionRef.current = true;
    setIsSyntheticSession(true);
    if (screen === "pre") {
      setPreAnswers({ experience: 2 });
      flash("Início preenchido com dados sintéticos de teste. Clique em 'Começar Atividade!'");
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
    if (screen !== "activity" || !activityStartedAt || isFreeMode || !assentAgreedRef.current) return undefined;
    const tick = () => {
      const nextElapsed = Math.max(0, Date.now() - activityStartedAt);
      setElapsedMs(nextElapsed);
    };
    tick();
    const timer = window.setInterval(tick, 1000);

    // Coleta silenciosa e periódica da telemetria do LEGO SPIKE a cada 10 segundos
    const pollSpike = async () => {
      if (isFreeMode || !assentAgreedRef.current) return;
      try {
        const metrics = await fetchBridgeSpikeMetrics();
        if (metrics && metrics.project_saved !== false) {
          setSpikeTelemetry((prev) => {
            const isFirstDetection = !prev || (!prev.executable_blocks && metrics.executable_blocks > 0);
            const blocksChanged = prev && prev.executable_blocks !== metrics.executable_blocks;
            if (isFirstDetection || blocksChanged) {
              emitTimeline("spike_telemetry", {
                activity_stage: isFirstDetection ? "primeira_programacao_detectada" : "atualizacao_codigo_spike",
                details: {
                  executable_blocks: metrics.executable_blocks,
                  inferred_stage: metrics.inferred_stage,
                  uses_motor: metrics.uses_motor,
                  uses_sensor: metrics.uses_sensor,
                  file_name: metrics.file_name,
                  first_coding_detected: isFirstDetection,
                  elapsed_ms: Math.max(0, Date.now() - activityStartedAt)
                }
              });
            }
            return metrics;
          });
        }
      } catch {
        // Falha silenciosa
      }
    };

    const firstCheck = window.setTimeout(pollSpike, 2000);
    const spikeInterval = window.setInterval(pollSpike, 10000);

    return () => {
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
      savedAt: new Date().toISOString()
    };
    localStorage.setItem(ACTIVE_SESSION_KEY, JSON.stringify(snapshot));
    void saveSession({ session_id: sessionId, status: "in_progress", ...snapshot }).catch(() => {});
  }, [activityStartedAt, activityStage, assentAgreed, context, currentRole, elapsedMs, groupId, installationId, isFreeMode, memberAssents, postAnswers, preAnswers, responses, screen, sessionId, spikeTelemetry, startedAt, teamSize, timeline]);

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
        teamSize={teamSize}
        setTeamSize={handleTeamSizeChange}
        assentAgreed={assentAgreed}
        memberAssents={memberAssents}
        setMemberAssents={setMemberAssents}
      />
    );
  } else if (screen === "activity") {
    content = (
      <ActivityScreen
        elapsedMs={elapsedMs}
        labMode={labMode}
        spikeTelemetry={spikeTelemetry}
        onAdvanceToFinalChallenge={handleAdvanceToFinalChallenge}
        assentAgreed={assentAgreed}
        isFreeMode={isFreeMode}
        onRefreshTelemetry={() => void captureSpikeTelemetry("manual_refresh")}
      />
    );
  } else if (screen === "post") {
    content = (
      <PostScreen
        answers={postAnswers}
        setAnswers={setPostAnswers}
        onSubmit={submitPost}
        onDecline={handleDeclinePost}
        teamSize={teamSize}
        memberAssents={memberAssents}
      />
    );
  } else if (isFreeMode || !assentAgreed) {
    content = <FreeModeFinishedScreen onRestart={prepareNextWorkshop} />;
  } else {
    content = (
      <FinishedScreen
        pendingCount={pendingCount}
        quarantinedCount={quarantinedCount}
        totalSavedCount={totalSavedCount}
        onDownload={downloadSession}
        onRestart={prepareNextWorkshop}
      />
    );
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
            <small>oficina de robótica · v2.2.2</small>

          </span>
        </div>
        <div className="topbar__notice">
          <span>{isFreeMode ? "MODO LIVRE" : (labMode ? "LAB" : "OFFLINE")}</span>
          <p>{isFreeMode ? "Zero coleta de dados · Uso livre do robô" : (labMode ? "Modo acelerado para testes" : "Sem burocracia · telemetria automática do SPIKE")}</p>
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
          <div className="topbar__step-badge" title="Etapa atual da oficina">
            🧭 Etapa {activeStep}/3 · {FLOW_STEPS.find((s) => s.id === activeStep)?.label}
          </div>
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
            <span>Avance entre as etapas da oficina ou sincronize com a nuvem</span>
          </div>
          <div className="instructor-banner__actions">
            <button className="inst-btn inst-btn--accent" onClick={() => setShowContextModal(true)} type="button">
              📍 Região ({context.regional || "Nordeste"})
            </button>
            <button className="inst-btn" onClick={() => forceStage(2)} type="button">
              🤖 2. Oficina Prática
            </button>
            <button className="inst-btn" onClick={() => forceStage(3)} type="button">
              🏁 3. Desafio da Corrida
            </button>
            <button className="inst-btn" onClick={() => addMinutes(5)} type="button">
              ⏱️ +5 min relógio
            </button>
            <button className="inst-btn" onClick={autoFillCurrentStep} type="button">
              ✨ Preencher teste
            </button>
            {!isFreeMode && assentAgreed ? (
              <button className="inst-btn" onClick={downloadSession} type="button" title="Baixar arquivo JSON desta oficina">
                💾 Exportar (.json)
              </button>
            ) : null}
            <button className="inst-btn inst-btn--accent" onClick={syncNow} type="button">
              ☁️ Sincronizar Nuvem
            </button>
            <button className="inst-btn inst-btn--danger" onClick={handleConfirmReset} type="button">
              🔄 Reiniciar Oficina
            </button>
          </div>
        </div>
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

      <div className={`workspace-shell ${labMode ? "workspace-shell--lab" : "workspace-shell--student"}`}>
        <section className="simulator-stage">
          <div className="stage-toolbar">
            <div>
              <span className={`connection-dot ${online ? "is-online" : ""}`} />
              {isFreeMode ? (
                <>
                  <strong>Modo Livre (sem coleta de pesquisa)</strong>
                  <small>Oficina sem gravação de questionários ou telemetria por escolha inicial da bancada</small>
                </>
              ) : screen === "pre" ? (
                <>
                  <strong>Dispositivo Pronto · Armazenamento Local Seguro</strong>
                  <small>
                    {totalSavedCount > 0
                      ? `${totalSavedCount} registro(s) salvos no dispositivo (offline-first)`
                      : "Aguardando início da bancada · Salvamento automático após assentimento"}
                  </small>
                </>
              ) : (
                <>
                  <strong>{quarantinedCount > 0 ? "Atenção · Registros em Quarentena" : (online ? "Dispositivo Pronto · Armazenamento Local Seguro" : "Modo Offline (salvando localmente)")}</strong>
                  <small>
                    {quarantinedCount > 0
                      ? `${quarantinedCount} registro(s) em quarentena local para análise do pesquisador`
                      : `${totalSavedCount} registro(s) salvos no dispositivo (offline-first)`}
                  </small>
                </>
              )}
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
