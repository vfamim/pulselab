import React, { useEffect, useMemo, useRef, useState } from "react";
import {
  CONFIG_HASH,
  PARTICIPANTS,
  createUuid,
  formatEventName,
  roleLabel
} from "../lib/contracts.js";
import {
  markSessionEvents,
  removeSession,
  saveEvent,
  saveSession
} from "../lib/student-store.js";

const ACTIVE_SESSION_KEY = "pulselab_student_active_session_v1";
const CONTEXT_KEY = "pulselab_student_context_v1";
const INSTALLATION_KEY = "pulselab_student_installation_id_v1";
const CLIENT_VERSION = "student-pwa/0.1.0";

const EMPTY_CONTEXT = {
  site_id: "",
  regional: "",
  school: "",
  workshop: "",
  class: "",
  group_size: 2,
  activity: "atividade-01-spike"
};

const DEMO_CONTEXT = {
  site_id: "SITE-DEMO",
  regional: "Juazeiro",
  school: "Escola piloto",
  workshop: "Oficina 01",
  class: "Turma A",
  group_size: 2,
  activity: "atividade-01-spike"
};

const PRE_DEFAULT = { experience: null, confidence: null };
const CHECKPOINT_DEFAULT = {
  effort: null,
  progress: null,
  collaboration: null,
  role: null,
  help: false
};
const POST_DEFAULT = { understanding: null, affect: null, returnIntent: null };

const FLOW_STEPS = [
  { id: 1, label: "Preparar" },
  { id: 2, label: "Antes" },
  { id: 3, label: "Atividade" },
  { id: 4, label: "Durante" },
  { id: 5, label: "Finalizar" }
];

const EXPERIENCE_OPTIONS = [
  [1, "Nunca usei"],
  [2, "Usei poucas vezes"],
  [3, "Já fiz projetos"],
  [4, "Tenho bastante prática"]
];

const CONFIDENCE_OPTIONS = [
  [1, "Nada confiante"],
  [2, "Pouco confiante"],
  [3, "Confiante"],
  [4, "Muito confiante"]
];

const PROGRESS_OPTIONS = [
  ["needs_help_now", "Travamos", "Não sabemos como continuar"],
  ["trying_without_progress", "Começando", "Estamos tentando, mas ainda sem avanço"],
  ["progressing_with_doubt", "Avançando", "Temos uma parte funcionando, com algumas dúvidas"],
  ["progressing_independently", "Testando", "Estamos ajustando sem precisar de ajuda"]
];

const COLLABORATION_OPTIONS = [
  [1, "Cada um por si", "Quase não trocamos ideias"],
  [2, "Uma pessoa decide", "A participação está desigual"],
  [3, "Decidimos juntos", "Todos conseguem contribuir"],
  [4, "Revezamos bem", "Trocamos tarefas naturalmente"]
];

const ROLE_OPTIONS = [
  ["computer", "Computador e programação"],
  ["assembly", "Montagem e testes"],
  ["both", "Um pouco de cada"],
  ["testing", "Testes e apoio"]
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

function participantKeys(groupSize) {
  return ["A", "B", "C"].slice(0, Number(groupSize));
}

function rolesForGroup(groupSize) {
  if (Number(groupSize) === 1) return { A: "individual", B: "assembly", C: "member_3" };
  return { A: "computer", B: "assembly", C: "member_3" };
}

function screenFor(stage, participant) {
  return `${stage}_${participant}`;
}

function screenParticipant(screen) {
  return screen.match(/_(A|B|C)$/)?.[1] || null;
}

function stepForScreen(screen, handoff) {
  const target = screen === "handoff" ? handoff?.nextScreen || "" : screen;
  if (target === "context" || target.startsWith("assent")) return 1;
  if (target.startsWith("pre")) return 2;
  if (target === "activity" || target === "role_swap") return 3;
  if (target.startsWith("checkpoint")) return 4;
  return 5;
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

function ParticipantBadge({ participant, instruction }) {
  return (
    <div className="participant-badge">
      <span className="participant-badge__avatar">{participant}</span>
      <span>
        <strong>{PARTICIPANTS[participant].label}</strong>
        <small>{instruction}</small>
      </span>
    </div>
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

function ContextScreen({ context, setContext, authorized, setAuthorized, onStart, resumable, onResume, labMode }) {
  const ready =
    context.site_id.trim() &&
    context.regional.trim() &&
    context.school.trim() &&
    context.workshop.trim() &&
    context.class.trim() &&
    authorized;

  return (
    <Card
      eyebrow="Preparação rápida · adulto responsável"
      title="Deixe a atividade pronta para os alunos"
      description="Informe somente os códigos da aula. Depois disso, cada participante responde sua própria etapa sem informar nome, e-mail ou matrícula."
      footer={
        <div className="action-row">
          <span className="footer-hint">Os dados ficam salvos neste dispositivo até a sincronização.</span>
          <button className="button button--primary" disabled={!ready} onClick={onStart} type="button">
            Chamar participante A
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

      <div className="form-grid">
        <label>
          <span>Código do polo</span>
          <input
            aria-label="Código do polo"
            onChange={(event) => setContext({ ...context, site_id: event.target.value })}
            placeholder="Ex.: POLO-01"
            value={context.site_id}
          />
        </label>
        <label>
          <span>Regional / município</span>
          <input
            aria-label="Regional ou município"
            onChange={(event) => setContext({ ...context, regional: event.target.value })}
            placeholder="Ex.: Juazeiro"
            value={context.regional}
          />
        </label>
        <label className="form-grid__wide">
          <span>Escola</span>
          <input
            aria-label="Escola"
            onChange={(event) => setContext({ ...context, school: event.target.value })}
            placeholder="Nome ou código da escola"
            value={context.school}
          />
        </label>
        <label>
          <span>Oficina</span>
          <input
            aria-label="Oficina"
            onChange={(event) => setContext({ ...context, workshop: event.target.value })}
            placeholder="Ex.: Oficina 01"
            value={context.workshop}
          />
        </label>
        <label>
          <span>Turma</span>
          <input
            aria-label="Turma"
            onChange={(event) => setContext({ ...context, class: event.target.value })}
            placeholder="Ex.: Turma A"
            value={context.class}
          />
        </label>
        <label>
          <span>Participantes neste grupo</span>
          <select
            aria-label="Participantes neste grupo"
            onChange={(event) => setContext({ ...context, group_size: Number(event.target.value) })}
            value={context.group_size}
          >
            <option value="1">1 participante</option>
            <option value="2">2 participantes</option>
            <option value="3">3 participantes</option>
          </select>
        </label>
        <label>
          <span>Atividade</span>
          <select
            aria-label="Atividade"
            onChange={(event) => setContext({ ...context, activity: event.target.value })}
            value={context.activity}
          >
            <option value="atividade-01-spike">Atividade 01 · SPIKE</option>
            <option value="atividade-02-spike">Atividade 02 · SPIKE</option>
            <option value="atividade-03-spike">Atividade 03 · SPIKE</option>
          </select>
        </label>
      </div>

      <label className="consent-check">
        <input checked={authorized} onChange={(event) => setAuthorized(event.target.checked)} type="checkbox" />
        <span>
          <strong>Confirmo que a coleta desta aula foi autorizada.</strong>
          <small>O consentimento de cada aluno ainda será solicitado individualmente antes de registrar qualquer resposta.</small>
        </span>
      </label>

      {labMode ? <p className="lab-footnote">Modo de laboratório: os campos de demonstração foram preenchidos automaticamente.</p> : null}
    </Card>
  );
}

function AssentScreen({ participant, onAccept, onDecline }) {
  return (
    <Card
      compact
      eyebrow="Sua escolha"
      title={`${PARTICIPANTS[participant].label}, você quer participar?`}
      description="Leia com calma. Você pode escolher não participar, sem precisar explicar o motivo."
      footer={
        <div className="action-row">
          <button className="button button--ghost" onClick={onDecline} type="button">
            Prefiro não participar
          </button>
          <button className="button button--primary" onClick={onAccept} type="button">
            Sim, quero participar
          </button>
        </div>
      }
    >
      <ParticipantBadge participant={participant} instruction="Esta tela é só sua." />
      <div className="assent-copy">
        <span className="assent-copy__icon">i</span>
        <div>
          <h2>O que será registrado?</h2>
          <p>Suas respostas curtas antes, durante e depois da atividade, além do horário em que cada etapa foi concluída.</p>
          <p>Não pedimos seu nome, não tiramos fotos da tela e não observamos quais programas você usa.</p>
          <p>Se você aceitar agora, ainda pode pedir para parar durante a atividade.</p>
        </div>
      </div>
    </Card>
  );
}

function HandoffScreen({ handoff, onContinue }) {
  return (
    <Card
      compact
      eyebrow="Privacidade entre participantes"
      title={`Agora é a vez do participante ${handoff.participant}`}
      description="As respostas são individuais. Entregue o dispositivo à pessoa indicada e dê espaço para ela responder."
      footer={
        <div className="action-row">
          <button className="button button--primary" onClick={onContinue} type="button">
            Sou o participante {handoff.participant} · continuar
          </button>
        </div>
      }
    >
      <div className="handoff-hero" aria-label={`Entregue ao participante ${handoff.participant}`}>
        <span>{handoff.participant}</span>
        <div>
          <strong>Entregue o dispositivo</strong>
          <p>{handoff.message}</p>
        </div>
      </div>
      <div className="privacy-callout">
        <span>i</span>
        <p>A próxima tela não mostra as respostas da pessoa anterior.</p>
      </div>
    </Card>
  );
}

function PreScreen({ participant, answers, setAnswers, onSubmit }) {
  const ready = answers.experience !== null && answers.confidence !== null;
  return (
    <Card
      eyebrow="Antes da atividade · leva cerca de 20 segundos"
      title="Como você chega para esta atividade?"
      description="Não existe resposta certa. Escolha o que combina mais com você agora."
      footer={
        <div className="action-row">
          <span className="footer-hint">Sua resposta fica salva assim que você avança.</span>
          <button className="button button--primary" disabled={!ready} onClick={onSubmit} type="button">
            Salvar e continuar
          </button>
        </div>
      }
    >
      <ParticipantBadge participant={participant} instruction="Responda sem conversar com o restante do grupo." />
      <ScaleQuestion
        legend="Quanto você já trabalhou com atividades de robótica?"
        onChange={(experience) => setAnswers({ ...answers, experience })}
        options={EXPERIENCE_OPTIONS}
        value={answers.experience}
      />
      <ScaleQuestion
        legend="Quão confiante você está para começar?"
        onChange={(confidence) => setAnswers({ ...answers, confidence })}
        options={CONFIDENCE_OPTIONS}
        value={answers.confidence}
      />
    </Card>
  );
}

function ActivityScreen({ elapsedMs, currentMark, labMode, onOpenCheckpoint }) {
  const targetMs = currentMark * 60 * 1000;
  const remaining = Math.max(0, targetMs - elapsedMs);
  return (
    <Card
      eyebrow="Atividade em grupo"
      title="Pode voltar para o projeto"
      description={`O próximo check-in será aberto aos ${currentMark} minutos. Esta página pode ficar em uma janela ao lado enquanto o grupo trabalha.`}
      footer={
        labMode ? (
          <div className="action-row">
            <span className="footer-hint">No laboratório, não é necessário esperar o relógio real.</span>
            <button className="button button--primary" onClick={onOpenCheckpoint} type="button">
              Abrir checkpoint de {currentMark} min
            </button>
          </div>
        ) : null
      }
    >
      <div className="activity-timer" aria-live="polite">
        <span>Tempo de atividade</span>
        <strong>{formatClock(elapsedMs)}</strong>
        <small>Próximo check-in em {formatClock(remaining)}</small>
      </div>
      <div className="activity-instructions">
        <article>
          <span>1</span>
          <strong>Mantenha esta página aberta</strong>
          <p>Não precisa ficar em tela cheia nem por cima dos outros programas.</p>
        </article>
        <article>
          <span>2</span>
          <strong>Continue usando o SPIKE normalmente</strong>
          <p>O PulseLab não captura sua tela nem monitora o aplicativo.</p>
        </article>
        <article>
          <span>3</span>
          <strong>Responda quando for chamado</strong>
          <p>O check-in curto abre automaticamente no momento combinado.</p>
        </article>
      </div>
    </Card>
  );
}

function CheckpointScreen({ participant, mark, answers, setAnswers, onSubmit }) {
  const ready = answers.effort !== null && answers.progress && answers.collaboration && answers.role;
  return (
    <Card
      eyebrow={`Check-in de ${mark} minutos · leva cerca de 30 segundos`}
      title="Como está indo agora?"
      description="Responda pensando neste momento da atividade. Depois você volta direto para o projeto."
      footer={
        <div className="action-row">
          <button className="button button--primary" disabled={!ready} onClick={onSubmit} type="button">
            Salvar meu check-in
          </button>
        </div>
      }
    >
      <div className="checkpoint-meta">
        <ParticipantBadge participant={participant} instruction="Esta resposta é individual." />
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
      <OptionQuestion
        legend="Qual papel você está fazendo mais neste momento?"
        onChange={(role) => setAnswers({ ...answers, role })}
        options={ROLE_OPTIONS}
        value={answers.role}
      />
      <label className="help-check">
        <input
          checked={answers.help}
          onChange={(event) => setAnswers({ ...answers, help: event.target.checked })}
          type="checkbox"
        />
        <span>
          <strong>Nosso grupo precisa de ajuda agora.</strong>
          <small>Isso registra o pedido para que o apoio possa ser oferecido durante a aula.</small>
        </span>
      </label>
    </Card>
  );
}

function RoleSwapScreen({ roles, onConfirm }) {
  return (
    <Card
      compact
      eyebrow="Metade da atividade"
      title="Hora de trocar os papéis"
      description="Quem estava mais no computador vai para montagem e testes. Quem estava na montagem assume o computador."
      footer={
        <div className="action-row">
          <button className="button button--primary" onClick={onConfirm} type="button">
            Trocamos os papéis
          </button>
        </div>
      }
    >
      <div className="swap-visual">
        <div>
          <span>A</span>
          <strong>{PARTICIPANTS.A.label}</strong>
          <small>{roleLabel(roles.A)}</small>
        </div>
        <div className="swap-visual__arrow">⇄</div>
        <div>
          <span>B</span>
          <strong>{PARTICIPANTS.B.label}</strong>
          <small>{roleLabel(roles.B)}</small>
        </div>
      </div>
    </Card>
  );
}

function ActivityEndScreen({ onContinue }) {
  return (
    <Card
      compact
      eyebrow="Atividade concluída"
      title="Bom trabalho, grupo"
      description="Agora cada participante fará uma última resposta individual. Leva menos de um minuto."
      footer={
        <div className="action-row">
          <button className="button button--primary" onClick={onContinue} type="button">
            Chamar participante A
          </button>
        </div>
      }
    >
      <div className="ending-hero">
        <span className="ending-hero__check">✓</span>
        <div>
          <h2>O projeto pode ser salvo no SPIKE.</h2>
          <p>O PulseLab já guardou todas as respostas anteriores neste dispositivo.</p>
        </div>
      </div>
    </Card>
  );
}

function PostScreen({ participant, answers, setAnswers, onSubmit }) {
  const ready =
    answers.understanding !== null &&
    answers.returnIntent !== null &&
    answers.affect;
  return (
    <Card
      eyebrow="Depois da atividade · última etapa"
      title="Como foi para você?"
      description="Responda sobre sua própria experiência. Ninguém do grupo precisa ver suas escolhas."
      footer={
        <div className="action-row">
          <button className="button button--primary" disabled={!ready} onClick={onSubmit} type="button">
            Salvar resposta final
          </button>
        </div>
      }
    >
      <ParticipantBadge participant={participant} instruction="Esta é sua última resposta." />
      <ScaleQuestion
        legend="Quanto você entende agora sobre o que foi trabalhado?"
        onChange={(understanding) => setAnswers({ ...answers, understanding })}
        options={[
          [1, "Ainda não entendo"],
          [2, "Entendo um pouco"],
          [3, "Entendo bem"],
          [4, "Consigo explicar"]
        ]}
        value={answers.understanding}
      />
      <ScaleQuestion
        legend="Quanto você gostaria de participar de outra atividade como esta?"
        onChange={(returnIntent) => setAnswers({ ...answers, returnIntent })}
        options={[
          [1, "Não gostaria"],
          [2, "Talvez não"],
          [3, "Talvez sim"],
          [4, "Gostaria muito"]
        ]}
        value={answers.returnIntent}
      />
      <OptionQuestion
        legend="Qual palavra combina mais com o que você sente agora?"
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
      title="As respostas do grupo foram salvas"
      description="A atividade pode ser encerrada. Se a internet cair, os dados permanecem neste dispositivo para sincronizar depois."
      footer={
        <div className="action-row">
          <button className="button button--ghost" onClick={onDownload} type="button">
            Baixar cópia local
          </button>
          <button className="button button--primary" onClick={onRestart} type="button">
            Preparar novo grupo
          </button>
        </div>
      }
    >
      <div className="summary-status summary-status--success">
        <span className="summary-status__mark">✓</span>
        <div>
          <span>Sessão concluída</span>
          <h2>Obrigado por participar.</h2>
          <p>{pendingCount} registro(s) aguardando sincronização segura.</p>
        </div>
      </div>
    </Card>
  );
}

function DeclinedScreen({ onRestart }) {
  return (
    <Card
      compact
      eyebrow="Escolha respeitada"
      title="A participação foi encerrada"
      description="Nenhuma resposta desta tentativa foi registrada. Chame um adulto responsável para decidir como continuar a atividade."
      footer={
        <div className="action-row">
          <button className="button button--primary" onClick={onRestart} type="button">
            Voltar à preparação
          </button>
        </div>
      }
    >
      <div className="decline-message">
        <span>×</span>
        <div>
          <h2>Tudo bem não participar.</h2>
          <p>Você pode continuar a aula seguindo as orientações do adulto responsável.</p>
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
              <small>{event.participant_id || event.activity_stage || "sessão"}</small>
            </span>
            <span className={`delivery delivery--${event._delivery_state}`}>{event._delivery_state}</span>
          </article>
        )) : (
          <div className="empty-events">
            <span>○</span>
            <p>Os eventos aparecerão aqui depois do consentimento.</p>
          </div>
        )}
      </div>
    </aside>
  );
}

export default function StudentPage() {
  const labMode = useMemo(() => new URLSearchParams(window.location.search).get("lab") === "1", []);
  const [context, setContext] = useState(() => readJson(CONTEXT_KEY, labMode ? DEMO_CONTEXT : EMPTY_CONTEXT));
  const [authorized, setAuthorized] = useState(false);
  const [screen, setScreen] = useState("context");
  const [handoff, setHandoff] = useState(null);
  const [resumable, setResumable] = useState(() => readJson(ACTIVE_SESSION_KEY, null));
  const [sessionId, setSessionId] = useState(createUuid);
  const [groupId, setGroupId] = useState(createUuid);
  const [installationId] = useState(getInstallationId);
  const [startedAt, setStartedAt] = useState(Date.now);
  const [activityStartedAt, setActivityStartedAt] = useState(null);
  const [elapsedMs, setElapsedMs] = useState(0);
  const [currentMark, setCurrentMark] = useState(20);
  const [timeline, setTimeline] = useState([]);
  const [responses, setResponses] = useState([]);
  const [assented, setAssented] = useState([]);
  const [roles, setRoles] = useState(() => rolesForGroup(context.group_size));
  const [preAnswers, setPreAnswers] = useState({ A: PRE_DEFAULT, B: PRE_DEFAULT, C: PRE_DEFAULT });
  const [checkpointAnswers, setCheckpointAnswers] = useState({ A: CHECKPOINT_DEFAULT, B: CHECKPOINT_DEFAULT, C: CHECKPOINT_DEFAULT });
  const [postAnswers, setPostAnswers] = useState({ A: POST_DEFAULT, B: POST_DEFAULT, C: POST_DEFAULT });
  const [online, setOnline] = useState(() => navigator.onLine);
  const [toast, setToast] = useState("");
  const sequenceRef = useRef(0);
  const checkpointOpeningRef = useRef(false);

  const participants = participantKeys(context.group_size);
  const allEvents = [...timeline, ...responses];
  const pendingCount = allEvents.filter((event) => event._delivery_state === "queued").length;
  const activeStep = stepForScreen(screen, handoff);

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

  function persist(event) {
    void saveEvent(event).catch(() => flash("Não foi possível salvar no armazenamento local deste navegador."));
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

  function emitResponse(eventType, participant, overrides = {}) {
    const event = eventBase(eventType, {
      _target_table: "research_events",
      participant_id: `${sessionId.slice(0, 8).toUpperCase()}-${participant}`,
      participant_role: roles[participant],
      response_status: "completed",
      interval_mark: null,
      group_size: participants.length,
      activity_stage: null,
      ...overrides
    });
    setResponses((current) => [...current, event]);
    persist(event);
    return event;
  }

  function movePrivately(participant, nextScreen, message) {
    if (participants.length === 1) {
      setScreen(nextScreen);
      return;
    }
    setHandoff({ participant, nextScreen, message });
    setScreen("handoff");
  }

  function startFreshSession() {
    const nextSessionId = createUuid();
    const nextGroupId = createUuid();
    const nextStartedAt = Date.now();
    localStorage.setItem(CONTEXT_KEY, JSON.stringify(context));
    setSessionId(nextSessionId);
    setGroupId(nextGroupId);
    setStartedAt(nextStartedAt);
    setActivityStartedAt(null);
    setElapsedMs(0);
    setCurrentMark(20);
    setTimeline([]);
    setResponses([]);
    setAssented([]);
    setRoles(rolesForGroup(context.group_size));
    setPreAnswers({ A: PRE_DEFAULT, B: PRE_DEFAULT, C: PRE_DEFAULT });
    setCheckpointAnswers({ A: CHECKPOINT_DEFAULT, B: CHECKPOINT_DEFAULT, C: CHECKPOINT_DEFAULT });
    setPostAnswers({ A: POST_DEFAULT, B: POST_DEFAULT, C: POST_DEFAULT });
    sequenceRef.current = 0;
    checkpointOpeningRef.current = false;
    setResumable(null);
    setScreen("assent_A");
  }

  function resumeSession() {
    if (!resumable) return;
    setContext(resumable.context);
    setSessionId(resumable.sessionId);
    setGroupId(resumable.groupId);
    setStartedAt(resumable.startedAt);
    setActivityStartedAt(resumable.activityStartedAt);
    setElapsedMs(resumable.elapsedMs || 0);
    setCurrentMark(resumable.currentMark || 20);
    setTimeline(resumable.timeline || []);
    setResponses(resumable.responses || []);
    setAssented(resumable.assented || []);
    setRoles(resumable.roles || rolesForGroup(resumable.context.group_size));
    setPreAnswers(resumable.preAnswers || { A: PRE_DEFAULT, B: PRE_DEFAULT, C: PRE_DEFAULT });
    setCheckpointAnswers(resumable.checkpointAnswers || { A: CHECKPOINT_DEFAULT, B: CHECKPOINT_DEFAULT, C: CHECKPOINT_DEFAULT });
    setPostAnswers(resumable.postAnswers || { A: POST_DEFAULT, B: POST_DEFAULT, C: POST_DEFAULT });
    setHandoff(resumable.handoff || null);
    sequenceRef.current = resumable.sequence || 0;
    setScreen(resumable.screen);
    flash("Sessão retomada do armazenamento local.");
  }

  function acceptAssent(participant) {
    const nextAssented = [...assented, participant];
    setAssented(nextAssented);
    const index = participants.indexOf(participant);
    const next = participants[index + 1];

    if (next) {
      movePrivately(next, screenFor("assent", next), "Peça para a próxima pessoa ler e escolher se quer participar.");
      return;
    }

    emitTimeline("session_started", {
      activity_stage: "consent",
      details: { runtime: "browser_pwa", participant_count: participants.length, consent_complete: true }
    });
    movePrivately("A", "pre_A", "O participante A começa as perguntas antes da atividade.");
  }

  function declineAssent() {
    localStorage.removeItem(ACTIVE_SESSION_KEY);
    void removeSession(sessionId).catch(() => {});
    setTimeline([]);
    setResponses([]);
    setScreen("declined");
  }

  function submitPre(participant) {
    const answers = preAnswers[participant];
    emitResponse("pre", participant, {
      activity_stage: "pre",
      prior_robotics: answers.experience,
      self_efficacy_pre: answers.confidence
    });
    const index = participants.indexOf(participant);
    const next = participants[index + 1];

    if (next) {
      movePrivately(next, screenFor("pre", next), "É a vez da próxima pessoa responder antes da atividade.");
      return;
    }

    const activityStart = Date.now();
    setActivityStartedAt(activityStart);
    setElapsedMs(0);
    void notifyBridgeSession(sessionId, activityStart, [20, 40]);
    emitTimeline("phase_completed", { activity_stage: "pre" });
    emitTimeline("activity_started", {
      activity_stage: "activity",
      details: { runtime: "browser_pwa", checkpoints_minutes: [20, 40] }
    });
    setScreen("activity");
  }

  function openCheckpoint(mark = currentMark) {
    if (checkpointOpeningRef.current) return;
    checkpointOpeningRef.current = true;
    const checkpointElapsed = labMode ? mark * 60 * 1000 : elapsedMs;
    if (labMode) setElapsedMs(checkpointElapsed);
    void notifyBridgeCheckpointAck(sessionId, mark);
    emitTimeline("checkpoint_started", {
      activity_stage: `checkpoint_${mark}`,
      interval_mark: mark,
      elapsed_ms: checkpointElapsed,
      details: {
        runtime: "browser_pwa",
        scheduled_minute: mark,
        lateness_ms: Math.max(0, checkpointElapsed - mark * 60 * 1000)
      }
    });
    setCheckpointAnswers({ A: CHECKPOINT_DEFAULT, B: CHECKPOINT_DEFAULT, C: CHECKPOINT_DEFAULT });
    movePrivately("A", `checkpoint${mark}_A`, `O participante A responde o check-in de ${mark} minutos primeiro.`);
  }

  function submitCheckpoint(participant, mark) {
    const answers = checkpointAnswers[participant];
    emitResponse("checkpoint", participant, {
      activity_stage: `checkpoint_${mark}`,
      interval_mark: mark,
      mental_effort: answers.effort,
      progress_state: answers.progress,
      collaboration: answers.collaboration,
      self_reported_role: answers.role,
      help_requested: answers.help
    });
    if (answers.help) {
      emitTimeline("help_requested", {
        activity_stage: `checkpoint_${mark}`,
        details: { runtime: "browser_pwa", participant: participant }
      });
    }

    const index = participants.indexOf(participant);
    const next = participants[index + 1];
    if (next) {
      movePrivately(next, `checkpoint${mark}_${next}`, `É a vez da próxima pessoa responder o check-in de ${mark} minutos.`);
      return;
    }

    void notifyBridgeCheckpointAck(sessionId, mark);
    emitTimeline("checkpoint_completed", {
      activity_stage: `checkpoint_${mark}`,
      interval_mark: mark,
      elapsed_ms: elapsedMs,
      details: { runtime: "browser_pwa", participant_count: participants.length }
    });
    checkpointOpeningRef.current = false;
    setScreen(mark === 20 && participants.length > 1 ? "role_swap" : mark === 20 ? "activity" : "activity_end");
    if (mark === 20) setCurrentMark(40);
  }

  function confirmRoleSwap() {
    const nextRoles = { ...roles, A: roles.B, B: roles.A };
    setRoles(nextRoles);
    emitTimeline("role_swapped", {
      activity_stage: "role_swap",
      details: { runtime: "browser_pwa", roles: nextRoles }
    });
    setScreen("activity");
  }

  function beginPost() {
    emitTimeline("ending_requested", { activity_stage: "post" });
    movePrivately("A", "post_A", "O participante A começa a resposta final.");
  }

  function submitPost(participant) {
    const answers = postAnswers[participant];
    emitResponse("post", participant, {
      activity_stage: "post",
      post_understanding: answers.understanding,
      post_affects: [answers.affect],
      post_return_intent: answers.returnIntent
    });
    const index = participants.indexOf(participant);
    const next = participants[index + 1];
    if (next) {
      movePrivately(next, screenFor("post", next), "É a vez da próxima pessoa dar sua resposta final.");
      return;
    }

    emitTimeline("phase_completed", { activity_stage: "post" });
    emitTimeline("session_completed", {
      activity_stage: "completed",
      details: { runtime: "browser_pwa", participant_count: participants.length }
    });
    localStorage.removeItem(ACTIVE_SESSION_KEY);
    setScreen("finished");
  }

  function resetToContext() {
    localStorage.removeItem(ACTIVE_SESSION_KEY);
    setAuthorized(false);
    setScreen("context");
    setHandoff(null);
    setResumable(null);
  }

  function downloadSession() {
    const payload = JSON.stringify({ session_id: sessionId, context, events: allEvents }, null, 2);
    const blob = new Blob([payload], { type: "application/json" });
    const link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = `pulselab-${sessionId.slice(0, 8)}.json`;
    link.click();
    URL.revokeObjectURL(link.href);
  }

  async function simulateSync() {
    await markSessionEvents(sessionId, "synced");
    setTimeline((events) => events.map((event) => ({ ...event, _delivery_state: "synced" })));
    setResponses((events) => events.map((event) => ({ ...event, _delivery_state: "synced" })));
    flash("Laboratório: envio simulado concluído.");
  }

  useEffect(() => {
    const updateOnline = () => setOnline(navigator.onLine);
    window.addEventListener("online", updateOnline);
    window.addEventListener("offline", updateOnline);
    return () => {
      window.removeEventListener("online", updateOnline);
      window.removeEventListener("offline", updateOnline);
    };
  }, []);

  useEffect(() => {
    if (screen !== "activity" || !activityStartedAt || labMode) return undefined;
    const tick = () => {
      const nextElapsed = Math.max(0, Date.now() - activityStartedAt);
      setElapsedMs(nextElapsed);
      if (nextElapsed >= currentMark * 60 * 1000 && !checkpointOpeningRef.current) {
        openCheckpoint(currentMark);
      }
    };
    tick();
    const timer = window.setInterval(tick, 1000);
    return () => window.clearInterval(timer);
  }, [activityStartedAt, currentMark, labMode, screen]);

  useEffect(() => {
    if (["context", "declined", "finished"].includes(screen)) return;
    const snapshot = {
      sessionId,
      groupId,
      context,
      startedAt,
      activityStartedAt,
      elapsedMs,
      currentMark,
      screen,
      handoff,
      timeline,
      responses,
      assented,
      roles,
      preAnswers,
      checkpointAnswers,
      postAnswers,
      sequence: sequenceRef.current,
      savedAt: new Date().toISOString()
    };
    localStorage.setItem(ACTIVE_SESSION_KEY, JSON.stringify(snapshot));
    void saveSession({ session_id: sessionId, status: "in_progress", ...snapshot }).catch(() => {});
  }, [activityStartedAt, assented, checkpointAnswers, context, currentMark, elapsedMs, groupId, handoff, postAnswers, preAnswers, responses, roles, screen, sessionId, startedAt, timeline]);

  const participant = screenParticipant(screen);
  let content;

  if (screen === "context") {
    content = <ContextScreen {...{ context, setContext, authorized, setAuthorized, resumable, labMode }} onStart={startFreshSession} onResume={resumeSession} />;
  } else if (screen.startsWith("assent_")) {
    content = <AssentScreen participant={participant} onAccept={() => acceptAssent(participant)} onDecline={declineAssent} />;
  } else if (screen === "handoff") {
    content = <HandoffScreen handoff={handoff} onContinue={() => setScreen(handoff.nextScreen)} />;
  } else if (screen.startsWith("pre_")) {
    content = (
      <PreScreen
        answers={preAnswers[participant]}
        participant={participant}
        setAnswers={(answers) => setPreAnswers({ ...preAnswers, [participant]: answers })}
        onSubmit={() => submitPre(participant)}
      />
    );
  } else if (screen === "activity") {
    content = <ActivityScreen currentMark={currentMark} elapsedMs={elapsedMs} labMode={labMode} onOpenCheckpoint={() => openCheckpoint(currentMark)} />;
  } else if (screen.startsWith("checkpoint")) {
    const mark = Number(screen.match(/^checkpoint(20|40)_/)?.[1]);
    content = (
      <CheckpointScreen
        answers={checkpointAnswers[participant]}
        mark={mark}
        participant={participant}
        setAnswers={(answers) => setCheckpointAnswers({ ...checkpointAnswers, [participant]: answers })}
        onSubmit={() => submitCheckpoint(participant, mark)}
      />
    );
  } else if (screen === "role_swap") {
    content = <RoleSwapScreen roles={roles} onConfirm={confirmRoleSwap} />;
  } else if (screen === "activity_end") {
    content = <ActivityEndScreen onContinue={beginPost} />;
  } else if (screen.startsWith("post_")) {
    content = (
      <PostScreen
        answers={postAnswers[participant]}
        participant={participant}
        setAnswers={(answers) => setPostAnswers({ ...postAnswers, [participant]: answers })}
        onSubmit={() => submitPost(participant)}
      />
    );
  } else if (screen === "declined") {
    content = <DeclinedScreen onRestart={resetToContext} />;
  } else {
    content = <FinishedScreen pendingCount={pendingCount} onDownload={downloadSession} onRestart={resetToContext} />;
  }

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <span className="brand__mark" aria-hidden="true">P</span>
          <span>
            <strong>PulseLab</strong>
            <small>atividade dos alunos · PWA</small>
          </span>
        </div>
        <div className="topbar__notice">
          <span>{labMode ? "LAB" : "PRIVACIDADE"}</span>
          <p>{labMode ? "Modo acelerado para testes locais" : "Sem nomes, imagens ou monitoramento de aplicativos"}</p>
        </div>
        <div className="topbar__session">
          <span>Sessão</span>
          <code>{screen === "context" ? "aguardando" : sessionId.slice(0, 8).toUpperCase()}</code>
        </div>
      </header>

      <div className={`workspace-shell ${labMode ? "workspace-shell--lab" : "workspace-shell--student"}`}>
        <aside className="flow-sidebar">
          <div className="flow-sidebar__header">
            <span>Jornada do aluno</span>
            <strong>{activeStep}/5</strong>
          </div>
          <nav aria-label="Etapas da atividade">
            {FLOW_STEPS.map((step) => (
              <div className={`flow-step ${step.id === activeStep ? "is-active" : ""} ${step.id < activeStep ? "is-complete" : ""}`} key={step.id}>
                <span>{step.id < activeStep ? "✓" : step.id}</span>
                <strong>{step.label}</strong>
              </div>
            ))}
          </nav>
          {screen !== "context" ? (
            <div className="sidebar-context">
              <span>Grupo atual</span>
              <strong>{context.class}</strong>
              <small>{context.workshop} · {participants.length} participante(s)</small>
            </div>
          ) : null}
        </aside>

        <section className="simulator-stage">
          <div className="stage-toolbar">
            <div>
              <span className={`connection-dot ${online ? "is-online" : ""}`} />
              <strong>{online ? "Salvo localmente" : "Funcionando sem internet"}</strong>
              <small>{pendingCount} registro(s) aguardando sincronização</small>
            </div>
            {labMode ? (
              <>
                <button className="toolbar-button" onClick={() => setOnline((value) => !value)} type="button">Alternar rede</button>
                <button className="toolbar-button is-accent" disabled={!pendingCount} onClick={simulateSync} type="button">Simular envio</button>
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
