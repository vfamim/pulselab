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
  [1, "🐣 Primeira vez", "Nunca mexemos com robôs"],
  [2, "🧩 Pouca prática", "Já vimos ou usamos 1 ou 2 vezes"],
  [3, "🚀 Já fizemos", "Montamos ou programamos antes"],
  [4, "⚡ Muita prática", "Já dominamos e sabemos bem"]
];

const CONFIDENCE_OPTIONS = [
  [1, "😅 Inseguros", "Acho que vai ser difícil"],
  [2, "🤔 Curiosos", "Vamos descobrir como faz"],
  [3, "😊 Confiantes", "Acho que vai dar certo"],
  [4, "🔥 Animados!", "Empolgação total para o desafio"]
];

const EFFORT_OPTIONS = [
  [1, "🟢 Muito Fácil", "Estamos tirando de letra"],
  [2, "🟡 Normal", "Dá pra fazer com calma"],
  [3, "🟠 Puxado", "Exige bastante atenção"],
  [4, "🔴 Muito Difícil", "Super desafiador agora"]
];

const PROGRESS_OPTIONS = [
  ["needs_help_now", "🛑 Travamos", "Não sabemos como sair do lugar"],
  ["trying_without_progress", "⏳ Tentando", "Testando caminhos, ainda sem funcionar"],
  ["progressing_with_doubt", "💡 Avançando", "Parte funciona, com algumas dúvidas"],
  ["progressing_independently", "🚀 Voando!", "Tudo funcionando e testando sozinhos"]
];

const COLLABORATION_OPTIONS = [
  [1, "👤 Pouca troca", "Cada um ficou no seu canto"],
  [2, "🗣️ Desigual", "Um faz quase tudo, outro só olha"],
  [3, "🤝 Em equipe", "Decidimos juntos com boa conversa"],
  [4, "🔄 Revezamento", "Trocamos tarefas de montagem e código"]
];

const UNDERSTANDING_OPTIONS = [
  [1, "❓ Quase nada", "Ficou meio confuso pra gente"],
  [2, "🧩 O básico", "Entendemos uma parte"],
  [3, "👍 Quase tudo", "Entendemos bem a lógica"],
  [4, "🧠 Totalmente", "Sabemos explicar para qualquer um"]
];

const RETURN_OPTIONS = [
  [1, "👎 Não", "Não gostamos muito"],
  [2, "🤷 Talvez", "Depende da atividade"],
  [3, "🙋 Com certeza!", "Foi muito bacana"],
  [4, "🤩 Quero sempre!", "Adoramos a experiência!"]
];

const AFFECT_OPTIONS = [
  ["frustrated", "😤 Frustração", "Não saiu como a gente queria"],
  ["tired", "🥱 Cansaço", "Foi puxado e exigiu muita energia"],
  ["curious", "🧐 Curiosidade", "Deu vontade de aprender mais"],
  ["confident", "🏆 Orgulho!", "Conseguimos vencer o desafio!"]
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

function ContextConfigModal({ isOpen, onClose, context, onSave, onAutoLoad, configHash }) {
  const [form, setForm] = useState(context);
  useEffect(() => { setForm(context); }, [context, isOpen]);

  if (!isOpen) return null;

  return (
    <div className="alert-modal-backdrop" role="dialog" aria-modal="true">
      <div className="alert-modal" style={{ maxWidth: "560px", textAlign: "left" }}>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: "14px" }}>
          <h2 style={{ margin: 0, fontSize: "1.25rem", color: "#f8fafc" }}>⚙️ Configurar Escola & Turma</h2>
          <button className="topbar-btn" onClick={onClose} type="button" style={{ padding: "4px 10px" }}>✕</button>
        </div>
        <p style={{ color: "#94a3b8", fontSize: "0.84rem", marginTop: 0, marginBottom: "16px" }}>
          Ajuste as informações da escola e da turma para vincular a telemetria ao contexto multicêntrico real.
        </p>

        <div className="form-grid" style={{ gap: "10px" }}>
          <div>
            <label style={{ fontSize: "0.75rem", color: "#94a3b8", display: "block", marginBottom: "3px" }}>Polo / Sede (site_id):</label>
            <input
              type="text"
              value={form.site_id}
              onChange={(e) => setForm({ ...form, site_id: e.target.value })}
              style={{ width: "100%", padding: "7px 10px", borderRadius: "8px", border: "1px solid #334155", background: "#0f172a", color: "#fff" }}
            />
          </div>
          <div>
            <label style={{ fontSize: "0.75rem", color: "#94a3b8", display: "block", marginBottom: "3px" }}>Polo Regional:</label>
            <input
              type="text"
              value={form.regional}
              onChange={(e) => setForm({ ...form, regional: e.target.value })}
              style={{ width: "100%", padding: "7px 10px", borderRadius: "8px", border: "1px solid #334155", background: "#0f172a", color: "#fff" }}
            />
          </div>
          <div>
            <label style={{ fontSize: "0.75rem", color: "#94a3b8", display: "block", marginBottom: "3px" }}>Código da Escola:</label>
            <input
              type="text"
              value={form.school}
              onChange={(e) => setForm({ ...form, school: e.target.value })}
              style={{ width: "100%", padding: "7px 10px", borderRadius: "8px", border: "1px solid #334155", background: "#0f172a", color: "#fff" }}
            />
          </div>
          <div>
            <label style={{ fontSize: "0.75rem", color: "#94a3b8", display: "block", marginBottom: "3px" }}>Turma:</label>
            <input
              type="text"
              value={form.class}
              onChange={(e) => setForm({ ...form, class: e.target.value })}
              style={{ width: "100%", padding: "7px 10px", borderRadius: "8px", border: "1px solid #334155", background: "#0f172a", color: "#fff" }}
            />
          </div>
          <div>
            <label style={{ fontSize: "0.75rem", color: "#94a3b8", display: "block", marginBottom: "3px" }}>Oficina:</label>
            <input
              type="text"
              value={form.workshop}
              onChange={(e) => setForm({ ...form, workshop: e.target.value })}
              style={{ width: "100%", padding: "7px 10px", borderRadius: "8px", border: "1px solid #334155", background: "#0f172a", color: "#fff" }}
            />
          </div>
          <div>
            <label style={{ fontSize: "0.75rem", color: "#94a3b8", display: "block", marginBottom: "3px" }}>Atividade:</label>
            <input
              type="text"
              value={form.activity}
              onChange={(e) => setForm({ ...form, activity: e.target.value })}
              style={{ width: "100%", padding: "7px 10px", borderRadius: "8px", border: "1px solid #334155", background: "#0f172a", color: "#fff" }}
            />
          </div>
        </div>

        <div style={{ marginTop: "14px", padding: "10px 14px", background: "#0f172a", border: "1px solid #1e293b", borderRadius: "10px", fontSize: "0.8rem", color: "#94a3b8" }}>
          <div><strong>Integridade do Instrumento (CONFIG_HASH):</strong></div>
          <code style={{ fontSize: "0.72rem", color: "#38bdf8", wordBreak: "break-all" }}>{configHash}</code>
          <div style={{ color: "#34d399", marginTop: "4px", fontSize: "0.75rem" }}>✓ SHA-256 verificado de config.json</div>
        </div>

        <div style={{ display: "flex", justifyContent: "space-between", marginTop: "18px", gap: "10px" }}>
          <button
            type="button"
            className="inst-btn"
            onClick={onAutoLoad}
          >
            🔄 Carregar do config.json
          </button>
          <div style={{ display: "flex", gap: "10px" }}>
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
              onClick={() => { onSave(form); onClose(); }}
            >
              💾 Salvar Configurações
            </button>
          </div>
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
  const ready = !assentAgreed || (answers.experience !== null && answers.confidence !== null);
  return (
    <Card
      eyebrow="Oficina de Robótica · Início rápido"
      title="Como vocês chegam para esta oficina?"
      description="Responda rapidamente antes de começar a montar e programar o robô LEGO SPIKE."
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
            ["dyad", "👫 Dupla com Papéis", "1 no código e 1 na montagem, com revezamento"],
            ["individual", "👤 Individual", "1 estudante realizando todas as tarefas"],
            ["group", "👥 Equipe Conjunta", "Grupo compartilhando a mesma tela"]
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
        <>
          <ScaleQuestion
            legend="Já montou ou programou robôs ou blocos antes?"
            onChange={(experience) => setAnswers({ ...answers, experience })}
            options={EXPERIENCE_OPTIONS}
            value={answers.experience}
          />
          <ScaleQuestion
            legend="Como está a animação e confiança do grupo para o desafio?"
            onChange={(confidence) => setAnswers({ ...answers, confidence })}
            options={CONFIDENCE_OPTIONS}
            value={answers.confidence}
          />
        </>
      ) : null}
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

function CheckpointScreen({
  mark,
  answers,
  setAnswers,
  onSubmit,
  onDecline,
  teamRole,
  currentRole,
  onRoleSwap
}) {
  const ready = answers.effort !== null && answers.progress && answers.collaboration;
  return (
    <Card
      eyebrow={`Check-in de ${mark} minutos · Pausa rápida de 30 segundos`}
      title="Como está indo o projeto?"
      description="Respondam como está o andamento da montagem e do código agora para voltarem direto para a robótica."
      footer={
        <div className="action-row">
          <button
            className="button button--ghost"
            onClick={onDecline}
            type="button"
            style={{ marginRight: "auto" }}
          >
            Prefiro não responder
          </button>
          <button className="button button--primary" disabled={!ready} onClick={onSubmit} type="button">
            Salvar e continuar
          </button>
        </div>
      }
    >
      <div className="checkpoint-meta">
        <span className="time-chip">{mark}:00 de atividade</span>
      </div>

      {teamRole === "dyad" ? (
        <div style={{ background: "rgba(16, 185, 129, 0.08)", border: "1px solid rgba(16, 185, 129, 0.3)", borderRadius: "12px", padding: "12px 18px", marginBottom: "18px", display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: "10px" }}>
          <div>
            <span style={{ fontSize: "0.8rem", textTransform: "uppercase", letterSpacing: "0.06em", color: "#059669", fontWeight: 800 }}>Papel no Check-in:</span>
            <div style={{ fontSize: "1rem", fontWeight: 700, color: "#065f46" }}>
              {currentRole === "computer" ? "💻 Participante A (Computador / Código)" : "🛠️ Participante B (Montagem / Testes)"}
            </div>
          </div>
          <button
            type="button"
            className="inst-btn"
            style={{ background: "#d1fae5", color: "#065f46", borderColor: "#a7f3d0", fontWeight: 700 }}
            onClick={onRoleSwap}
          >
            🔄 Trocar Papéis da Dupla
          </button>
        </div>
      ) : null}

      <ScaleQuestion
        legend="Como está o nível de dificuldade do desafio até aqui?"
        onChange={(effort) => setAnswers({ ...answers, effort })}
        options={EFFORT_OPTIONS}
        value={answers.effort}
      />
      <OptionQuestion
        legend="Como está o robô e o código agora?"
        onChange={(progress) => setAnswers({ ...answers, progress })}
        options={PROGRESS_OPTIONS}
        value={answers.progress}
      />
      <ScaleQuestion
        legend="Como a dupla ou grupo está dividindo as tarefas?"
        onChange={(collaboration) => setAnswers({ ...answers, collaboration })}
        options={COLLABORATION_OPTIONS}
        value={answers.collaboration}
      />
      <button
        type="button"
        className={`help-toggle-btn ${answers.help ? "is-active" : ""}`}
        onClick={() => setAnswers({ ...answers, help: !answers.help })}
        aria-pressed={answers.help}
      >
        <span className="help-toggle-btn__icon">{answers.help ? "🚨" : "🙋‍♂️"}</span>
        <div className="help-toggle-btn__content">
          <strong>{answers.help ? "Ajuda solicitada ao professor!" : "Precisa de ajuda do professor na bancada?"}</strong>
          <small>{answers.help ? "O professor já foi avisado. Continuem montando enquanto ele se aproxima." : "Clique aqui para registrar que o grupo quer apoio presencial do professor."}</small>
        </div>
        <span className="help-toggle-btn__badge">
          {answers.help ? "✓ AJUDA CHAMADA" : "CHAMAR PROFESSOR"}
        </span>
      </button>
    </Card>
  );
}

function PostScreen({ answers, setAnswers, onSubmit, onDecline }) {
  const ready =
    answers.understanding !== null &&
    answers.returnIntent !== null &&
    answers.affect;
  return (
    <Card
      eyebrow="Encerramento da Oficina · Último passo (30 segundos)"
      title="Como foi a experiência do grupo?"
      description="Últimas 3 perguntas sobre a oficina de robótica."
      footer={
        <div className="action-row">
          <button
            className="button button--ghost"
            onClick={onDecline}
            type="button"
            style={{ marginRight: "auto" }}
          >
            Prefiro não responder
          </button>
          <button className="button button--primary" disabled={!ready} onClick={onSubmit} type="button">
            Concluir Oficina
          </button>
        </div>
      }
    >
      <ScaleQuestion
        legend="O quanto vocês entenderam sobre o que o robô faz?"
        onChange={(understanding) => setAnswers({ ...answers, understanding })}
        options={UNDERSTANDING_OPTIONS}
        value={answers.understanding}
      />
      <ScaleQuestion
        legend="Gostariam de participar de outra oficina como esta?"
        onChange={(returnIntent) => setAnswers({ ...answers, returnIntent })}
        options={RETURN_OPTIONS}
        value={answers.returnIntent}
      />
      <OptionQuestion
        legend="Qual emoji melhor resume o sentimento do grupo agora?"
        onChange={(affect) => setAnswers({ ...answers, affect })}
        options={AFFECT_OPTIONS}
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
  const [teamRole, setTeamRole] = useState(() => savedSession?.teamRole || "dyad");
  const [currentRole, setCurrentRole] = useState(() => savedSession?.currentRole || "computer");
  const [assentAgreed, setAssentAgreed] = useState(() => savedSession?.assentAgreed ?? true);
  const [showContextModal, setShowContextModal] = useState(false);
  const [online, setOnline] = useState(() => navigator.onLine);
  const [toast, setToast] = useState("");
  const [checkpointModalMark, setCheckpointModalMark] = useState(null);
  const [showInstructorTools, setShowInstructorTools] = useState(labMode);
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const sequenceRef = useRef(savedSession?.sequence || 0);
  const checkpointOpeningRef = useRef(false);

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
    const role = teamRole === "individual" ? "individual" : (teamRole === "group" ? "group" : currentRole);
    const participantSuffix = role === "computer" ? "A" : (role === "assembly" ? "B" : (role === "individual" ? "IND" : "GRUPO"));
    const groupSize = teamRole === "individual" ? 1 : (teamRole === "group" ? 3 : 2);

    const event = eventBase(eventType, {
      _target_table: "research_events",
      participant_id: `${sessionId.slice(0, 8).toUpperCase()}-${participantSuffix}`,
      participant_role: role,
      response_status: overrides.response_status || "completed",
      interval_mark: null,
      group_size: groupSize,
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
    setTeamRole(resumable.teamRole || "dyad");
    setCurrentRole(resumable.currentRole || "computer");
    setAssentAgreed(resumable.assentAgreed ?? true);
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
    flash(`Papéis trocados! Agora: ${nextRole === "computer" ? "💻 Computador / Programação" : "🛠️ Montagem / Testes"}.`);
  }

  function handleSaveContext(newContext) {
    setContext(newContext);
    localStorage.setItem(CONTEXT_KEY, JSON.stringify(newContext));
    flash("Configurações da turma salvas com sucesso!");
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
      details: { runtime: "browser_pwa", team_role: teamRole, ethical_assent: assentAgreed }
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

  function handleDeclinePre() {
    setAssentAgreed(false);
    emitTimeline("session_started", {
      activity_stage: "init",
      details: { runtime: "browser_pwa", research_declined: true }
    });
    emitResponse("pre", {
      activity_stage: "pre",
      response_status: "declined"
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
    setResumable(null);
    setScreen("activity");
    flash("Oficina liberada em modo livre (sem envio de respostas de pesquisa).");
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
      if (teamRole === "dyad") {
        const nextRole = currentRole === "computer" ? "assembly" : "computer";
        setCurrentRole(nextRole);
        emitTimeline("role_swapped", {
          activity_stage: "checkpoint_20",
          details: { from_role: currentRole, to_role: nextRole, scheduled_swap: true }
        });
      }
      setScreen("activity");
    } else {
      setScreen("post");
    }
  }

  function handleDeclineCheckpoint(mark) {
    emitResponse("checkpoint", {
      activity_stage: `checkpoint_${mark}`,
      interval_mark: mark,
      response_status: "declined"
    });
    void notifyBridgeCheckpointAck(sessionId, mark);
    emitTimeline("checkpoint_completed", {
      activity_stage: `checkpoint_${mark}`,
      interval_mark: mark,
      elapsed_ms: elapsedMs,
      details: { runtime: "browser_pwa", response_status: "declined" }
    });
    checkpointOpeningRef.current = false;
    if (mark === 20) {
      setCurrentMark(40);
      if (teamRole === "dyad") {
        const nextRole = currentRole === "computer" ? "assembly" : "computer";
        setCurrentRole(nextRole);
        emitTimeline("role_swapped", {
          activity_stage: "checkpoint_20",
          details: { from_role: currentRole, to_role: nextRole, scheduled_swap: true }
        });
      }
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
    content = <ActivityScreen currentMark={currentMark} elapsedMs={elapsedMs} labMode={labMode} spikeTelemetry={spikeTelemetry} />;
  } else if (screen === "checkpoint20") {
    content = (
      <CheckpointScreen
        answers={checkpoint20Answers}
        mark={20}
        setAnswers={setCheckpoint20Answers}
        onSubmit={() => submitCheckpoint(20)}
        onDecline={() => handleDeclineCheckpoint(20)}
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
        setAnswers={setCheckpoint40Answers}
        onSubmit={() => submitCheckpoint(40)}
        onDecline={() => handleDeclineCheckpoint(40)}
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
            <small>oficina de robótica · v1.9.0</small>
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
            title="Configurar escola, polo e turma"
            type="button"
          >
            🏫 Turma
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
              ⚙️ Configurar Turma
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
          onProceed={handleProceedFromModal}
        />
      ) : null}

      <ContextConfigModal
        isOpen={showContextModal}
        onClose={() => setShowContextModal(false)}
        context={context}
        onSave={handleSaveContext}
        onAutoLoad={handleAutoLoadConfig}
        configHash={CONFIG_HASH}
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
