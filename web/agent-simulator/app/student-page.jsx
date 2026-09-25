import React, { useEffect, useRef, useState } from "react";
import {
  INSTRUMENT,
  questionsFor,
  validateAnswers,
  knowledgeResult,
} from "../lib/protocol.js";
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
import {
  listSessions,
  saveSession,
  removeSession,
  pruneExpiredSessions,
} from "../lib/student-store.js";
import { readProjectFile, artifactSnapshot } from "../lib/spike-parser.js";
import "./pilot.css";

const EMPTY_CONTEXT = {
  site: "",
  school: "",
  workshop: "",
  class: "",
  instructor: "",
  grade_band: "fundamental-2",
  platform: "spike",
  group_size: 2,
};
const SAMPLE_CONTEXT = {
  site: "TESTE-SEDE",
  school: "TESTE-ESCOLA",
  workshop: "TESTE-OFICINA",
  class: "TESTE-TURMA",
  instructor: "TESTE-I01",
  grade_band: "fundamental-2",
  platform: "spike",
  group_size: 2,
};
const ROLE_NAMES = {
  computer: "Programação",
  assembly: "Montagem",
  testing: "Testes",
  shared: "Tarefas compartilhadas",
};
const ACTIONS = {
  repeat_sensor: "Retomar a relação entre sensor e motor",
  revise_instruction: "Rever a explicação da atividade",
  more_time: "Oferecer mais tempo para testar",
  redistribute_roles: "Redistribuir as oportunidades de participação",
  no_change: "Manter a proposta e observar a próxima oficina",
};

function download(session) {
  const url = URL.createObjectURL(
    new Blob([JSON.stringify(exportSession(session), null, 2)], {
      type: "application/json",
    }),
  );
  const link = document.createElement("a");
  link.href = url;
  link.download = "pulselab-TESTE-" + session.id + ".json";
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function Question({ question, value, onChange, groupSize }) {
  const options = question.options.filter(
    ([v]) =>
      !(groupSize === 1 && question.kind === "experience" && v === "some"),
  );
  return (
    <fieldset className="pilot-question">
      <legend>{question.text}</legend>
      <div className="pilot-options">
        {options.map(([v, label]) => (
          <button
            type="button"
            key={v}
            aria-pressed={value === v}
            className={value === v ? "selected" : ""}
            onClick={() => onChange(v)}
          >
            {label}
          </button>
        ))}
      </div>
      <div className="pilot-skip">
        <button
          type="button"
          aria-pressed={value === null}
          onClick={() => onChange(null)}
        >
          Prefiro não responder
        </button>
        {groupSize > 1 && (
          <button
            type="button"
            aria-pressed={value === "no_consensus"}
            onClick={() => onChange("no_consensus")}
          >
            Não chegamos a uma resposta conjunta
          </button>
        )}
      </div>
    </fieldset>
  );
}

function Questionnaire({ session, onSave }) {
  const phase = session.phase.startsWith("checkpoint")
    ? "checkpoint"
    : session.phase;
  const [answers, setAnswers] = useState({});
  const titles = {
    pre: "Antes de começar",
    checkpoint: "Uma pausa para contar como está",
    post: "Como foi a experiência?",
  };
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        onSave(answers);
      }}
    >
      <p className="pilot-eyebrow">
        {phase === "checkpoint"
          ? session.phase.replace("checkpoint_", "Check-in de ") + " minutos"
          : "Relato da bancada"}
      </p>
      <h1>{titles[phase]}</h1>
      <p className="pilot-muted">
        Conversem antes de escolher. Vocês podem pular qualquer pergunta ou
        indicar que pensam diferente.
      </p>
      {questionsFor(phase, session.group_size).map((question) => (
        <Question
          key={question.id}
          question={question}
          value={answers[question.id]}
          groupSize={session.group_size}
          onChange={(v) =>
            setAnswers((prev) => ({ ...prev, [question.id]: v }))
          }
        />
      ))}
      <button
        className="pilot-primary"
        disabled={!validateAnswers(phase, session.group_size, answers)}
      >
        Salvar e continuar
      </button>
    </form>
  );
}

function Rubric({ onFinish }) {
  const [rubric, setRubric] = useState({
    successful_trials: "",
    explanation: "",
    interventions: "",
    main_issue: "",
    next_action: "",
    setup_minutes: "",
  });
  const numeric = [
    "successful_trials",
    "explanation",
    "interventions",
    "setup_minutes",
  ];
  function set(key, value) {
    setRubric((prev) => ({ ...prev, [key]: value }));
  }
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        onFinish(
          Object.fromEntries(
            Object.entries(rubric).map(([k, v]) => [
              k,
              numeric.includes(k) ? Number(v) : v,
            ]),
          ),
        );
      }}
    >
      <p className="pilot-eyebrow">Registro do instrutor · simulação</p>
      <h1>Observar, avaliar e devolver</h1>
      <p>{INSTRUMENT.activity.objective}</p>
      <label>
        Execuções bem-sucedidas em três tentativas
        <select
          required
          value={rubric.successful_trials}
          onChange={(e) => set("successful_trials", e.target.value)}
        >
          <option value="">Selecione</option>
          {[0, 1, 2, 3].map((n) => (
            <option key={n} value={n}>
              {n} de 3
            </option>
          ))}
        </select>
      </label>
      <p className="pilot-muted">
        Use as mesmas condições em cada tentativa. Conte o resultado mesmo
        quando houve ajuda.
      </p>
      <label>
        Explicação da bancada
        <select
          required
          value={rubric.explanation}
          onChange={(e) => set("explanation", e.target.value)}
        >
          <option value="">Selecione</option>
          {INSTRUMENT.rubric.explanation.map((label, n) => (
            <option key={n} value={n}>
              {n} — {label}
            </option>
          ))}
        </select>
      </label>
      <p className="pilot-muted">{INSTRUMENT.activity.explanationPrompt}</p>
      <div className="pilot-grid">
        <label>
          Intervenções do instrutor
          <input
            type="number"
            min="0"
            max="100"
            required
            value={rubric.interventions}
            onChange={(e) => set("interventions", e.target.value)}
          />
        </label>
        <label>
          Minutos de preparação desta bancada
          <input
            type="number"
            min="0"
            max="180"
            required
            value={rubric.setup_minutes}
            onChange={(e) => set("setup_minutes", e.target.value)}
          />
        </label>
      </div>
      <label>
        Principal dificuldade observada
        <select
          required
          value={rubric.main_issue}
          onChange={(e) => set("main_issue", e.target.value)}
        >
          <option value="">Selecione</option>
          {[
            ["none", "Nenhuma observada"],
            ["technical", "Equipamento ou conexão"],
            ["assembly", "Montagem"],
            ["logic", "Lógica"],
            ["sensor", "Sensor"],
            ["participation", "Oportunidades de participação"],
          ].map(([v, t]) => (
            <option value={v} key={v}>
              {t}
            </option>
          ))}
        </select>
      </label>
      <label>
        Devolutiva e próxima ação
        <select
          required
          value={rubric.next_action}
          onChange={(e) => set("next_action", e.target.value)}
        >
          <option value="">Selecione</option>
          {Object.entries(ACTIONS).map(([v, t]) => (
            <option value={v} key={v}>
              {t}
            </option>
          ))}
        </select>
      </label>
      <button
        className="pilot-primary"
        disabled={Object.values(rubric).some((v) => v === "")}
      >
        Concluir com devolutiva
      </button>
    </form>
  );
}

function Summary({ session, onNew }) {
  const quality = sessionQuality(session),
    pre = knowledgeResult("pre", session.responses.pre?.answers),
    post = knowledgeResult("post", session.responses.post?.answers);
  const seconds = Math.round(
    session.events
      .filter((e) => e.event_type === "response_recorded")
      .reduce((s, e) => s + e.details.response_latency_ms, 0) / 1000,
  );
  return (
    <>
      <p className="pilot-eyebrow">Devolutiva da bancada</p>
      <h1>Oficina concluída</h1>
      <p className="pilot-lead">{ACTIONS[session.rubric.next_action]}</p>
      <div className="pilot-stats">
        <div>
          <strong>{session.rubric.successful_trials}/3</strong>
          <span>execuções bem-sucedidas</span>
        </div>
        <div>
          <strong>{session.rubric.interventions}</strong>
          <span>intervenções registradas</span>
        </div>
        <div>
          <strong>
            {quality.answered}/{quality.expected}
          </strong>
          <span>perguntas respondidas</span>
        </div>
      </div>
      <p>
        O grupo demonstrou:{" "}
        {INSTRUMENT.rubric.explanation[
          session.rubric.explanation
        ].toLowerCase()}
        .
      </p>
      <details>
        <summary>Conferir qualidade e limites dos registros</summary>
        <dl className="pilot-quality">
          <dt>Procedimento</dt>
          <dd>Encerrado com rubrica</dd>
          <dt>Não respostas</dt>
          <dd>
            {quality.declined} recusas de item · {quality.no_consensus} sem
            consenso
          </dd>
          <dt>Etapas ausentes</dt>
          <dd>{quality.missing_phases.join(", ") || "Nenhuma"}</dd>
          <dt>Tempos</dt>
          <dd>
            {quality.timing_deviations} checkpoints antecipados, manuais ou
            atrasados
          </dd>
          <dt>Ajuda</dt>
          <dd>{quality.open_help} pedidos ainda sem resolução registrada</dd>
          <dt>Artefatos</dt>
          <dd>{quality.artifacts_available} leituras estruturais</dd>
          <dt>Tempo de resposta observado</dt>
          <dd>{seconds} segundos, incluindo pausas com o formulário aberto</dd>
          <dt>Itens de conhecimento</dt>
          <dd>
            Pré: {pre.correct}/{pre.answered} respondidos. Pós: {post.correct}/
            {post.answered} respondidos.
          </dd>
        </dl>
        <p>
          As formas pré e pós são experimentais. Estes dados de teste não medem
          ganho individual, retenção, impacto social ou efeito causal. Recusar
          uma pergunta é uma escolha legítima; não é uma falha da criança.
        </p>
      </details>
      <div className="pilot-actions">
        <button className="pilot-primary" onClick={() => download(session)}>
          Exportar dados de teste
        </button>
        <button onClick={onNew}>Preparar outra bancada</button>
      </div>
      <p className="pilot-muted">
        Registros locais expiram em{" "}
        {new Date(session.expires_at).toLocaleDateString("pt-BR")}. Arquivos
        exportados ficam sob sua responsabilidade.
      </p>
    </>
  );
}

export default function StudentPage() {
  const [session, setSession] = useState(null),
    sessionRef = useRef(null);
  const [screen, setScreen] = useState("setup"),
    [context, setContext] = useState(EMPTY_CONTEXT);
  const [assents, setAssents] = useState([]),
    [testConfirmed, setTestConfirmed] = useState(false);
  const [history, setHistory] = useState([]),
    [busy, setBusy] = useState(true),
    busyRef = useRef(false);
  const [error, setError] = useState(""),
    [notice, setNotice] = useState(""),
    [now, setNow] = useState(Date.now());
  const [roles, setRoles] = useState([]),
    [artifactConfirmed, setArtifactConfirmed] = useState(false);
  const [tabLocked, setTabLocked] = useState(false);
  const phase = session?.phase || screen;
  const generation = useRef(0);

  useEffect(() => {
    let alive = true,
      release;
    if (navigator.locks)
      navigator.locks.request(
        "pulselab-test-v2-editor",
        { ifAvailable: true },
        (lock) => {
          if (!alive) return;
          if (!lock) {
            setTabLocked(true);
            return;
          }
          return new Promise((resolve) => {
            release = resolve;
          });
        },
      );
    (async () => {
      try {
        await pruneExpiredSessions();
        const saved = await listSessions();
        if (alive) setHistory(saved);
      } catch {
        if (alive)
          setError(
            "Não foi possível abrir o armazenamento local. Habilite o armazenamento deste navegador para testar.",
          );
      } finally {
        if (alive) setBusy(false);
      }
    })();
    const timer = setInterval(() => {
      if (alive) setNow(Date.now());
    }, 1000);
    return () => {
      alive = false;
      release?.();
      clearInterval(timer);
    };
  }, []);

  useEffect(() => {
    if (session && now >= session.expires_at && !busyRef.current) {
      void run(async () => {
        await removeSession(session.id);
        generation.current++;
        sessionRef.current = null;
        setSession(null);
        setHistory(await listSessions());
        setScreen("setup");
        setNotice(
          "O prazo de sete dias terminou. Os registros locais desta sessão foram apagados.",
        );
      });
    }
  }, [now, session]);

  useEffect(() => {
    if (!session || session.phase !== "activity" || busyRef.current) return;
    const mark = INSTRUMENT.checkpoints_minutes.find(
      (m) =>
        !session.responses["checkpoint_" + m] &&
        now >= session.activity_started_at + m * 60000,
    );
    if (mark) void run(() => commit(openCheckpoint(sessionRef.current, mark)));
  }, [now, session]);

  async function run(action) {
    if (busyRef.current || tabLocked) return;
    busyRef.current = true;
    setBusy(true);
    setError("");
    try {
      await action();
    } catch (e) {
      setError(e.message || "Não foi possível gravar. Tente novamente.");
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }

  async function commit(next) {
    await saveSession(next);
    sessionRef.current = next;
    setSession(next);
    setRoles(next.roles);
  }

  async function start() {
    await run(async () => {
      const created = await createSession(context, assents);
      await commit(
        addEvent(created, "session_started", {
          participant_count: context.group_size,
          response_unit: "group",
        }),
      );
    });
  }

  async function withdraw() {
    if (
      session &&
      !window.confirm(
        "Parar os registros e apagar os dados locais desta sessão? A atividade pode continuar. Arquivos já exportados não serão apagados.",
      )
    )
      return;
    await run(async () => {
      generation.current++;
      if (sessionRef.current) await removeSession(sessionRef.current.id);
      sessionRef.current = null;
      setSession(null);
      setAssents([]);
      setHistory(await listSessions());
      setScreen("free");
      setNotice(
        "Atividade livre. Nenhuma resposta, evento ou projeto será registrado.",
      );
    });
  }

  function reset() {
    generation.current++;
    sessionRef.current = null;
    setSession(null);
    setAssents([]);
    setTestConfirmed(false);
    setContext(EMPTY_CONTEXT);
    setScreen("setup");
    void listSessions().then(setHistory);
  }
  const elapsed = session?.activity_started_at
    ? Math.max(0, Math.floor((now - session.activity_started_at) / 1000))
    : 0;
  const clock =
    String(Math.floor(elapsed / 60)).padStart(2, "0") +
    ":" +
    String(elapsed % 60).padStart(2, "0");
  const activeHelp = session?.help.find((h) => h.status !== "resolved");

  if (tabLocked)
    return (
      <main className="pilot">
        <section className="pilot-card">
          <h1>Uma bancada já está aberta</h1>
          <p>
            Use a outra aba deste navegador ou feche-a e recarregue esta página.
          </p>
        </section>
      </main>
    );

  return (
    <main className="pilot">
      <header className="pilot-header">
        <a className="pilot-brand" href="/alunos/">
          <img src="/alunos/robot.png" alt="" />
          PulseLab <span>Oficina de robótica</span>
        </a>
        <span className="pilot-badge">Versão de teste · dados fictícios</span>
      </header>
      <div className="pilot-banner">
        Teste local: nenhum dado é enviado à nuvem. Use esta versão para avaliar
        o fluxo antes de qualquer pesquisa com participantes.
      </div>
      <div className="pilot-layout">
        <aside className="pilot-sidebar">
          <p className="pilot-eyebrow">A jornada da bancada</p>
          <ol>
            {[
              "Preparar",
              "Escolher participar",
              "Começar",
              "Construir e conversar",
              "Avaliar e devolver",
            ].map((t, i) => (
              <li
                key={t}
                className={
                  (phase === "setup"
                    ? 0
                    : phase === "consent"
                      ? 1
                      : phase === "pre"
                        ? 2
                        : ["post", "rubric", "finished"].includes(phase)
                          ? 4
                          : 3) === i
                    ? "active"
                    : ""
                }
              >
                {t}
              </li>
            ))}
          </ol>
          <p>
            Um projeto, uma bancada.
            <br />
            Cada integrante tem voz e pode parar de participar.
          </p>
          {session && (
            <>
              <div className="pilot-clock" aria-label="Tempo real de atividade">
                {clock}
              </div>
              <button
                className="pilot-danger"
                disabled={busy}
                onClick={withdraw}
              >
                Parar registros e apagar sessão
              </button>
            </>
          )}
        </aside>
        <section className="pilot-card" aria-busy={busy}>
          {error && (
            <p className="pilot-error" role="alert">
              {error}
            </p>
          )}
          {notice && (
            <p className="pilot-notice" role="status">
              {notice}
            </p>
          )}
          <fieldset className="pilot-workspace" disabled={busy}>
            {phase === "setup" && (
              <form
                onSubmit={(e) => {
                  e.preventDefault();
                  setAssents(Array(context.group_size).fill(false));
                  setScreen("consent");
                  setNotice("");
                }}
              >
                <p className="pilot-eyebrow">Preparação pelo instrutor</p>
                <h1>Uma oficina, perguntas com propósito.</h1>
                <p className="pilot-lead">
                  Vamos testar como registrar a experiência da bancada e
                  transformar observações em uma próxima ação.
                </p>
                <button
                  type="button"
                  onClick={() => setContext(SAMPLE_CONTEXT)}
                >
                  Preencher contexto fictício
                </button>
                <div className="pilot-grid">
                  {[
                    ["site", "Código da sede"],
                    ["school", "Código da escola"],
                    ["workshop", "Código da oficina"],
                    ["class", "Código da turma"],
                    ["instructor", "Código do instrutor"],
                  ].map(([key, label]) => (
                    <label key={key}>
                      {label}
                      <input
                        required
                        pattern="[A-Za-z0-9_-]{2,40}"
                        maxLength={40}
                        value={context[key]}
                        onChange={(e) =>
                          setContext((prev) => ({
                            ...prev,
                            [key]: e.target.value,
                          }))
                        }
                        placeholder="Use um código, sem nomes"
                      />
                    </label>
                  ))}
                  <label>
                    Faixa escolar
                    <select
                      value={context.grade_band}
                      onChange={(e) =>
                        setContext((prev) => ({
                          ...prev,
                          grade_band: e.target.value,
                        }))
                      }
                    >
                      <option value="fundamental-1">
                        Ensino fundamental — anos iniciais
                      </option>
                      <option value="fundamental-2">
                        Ensino fundamental — anos finais
                      </option>
                      <option value="mixed-test">
                        Mista (somente simulação)
                      </option>
                    </select>
                  </label>
                  <label>
                    Integrantes na bancada
                    <select
                      value={context.group_size}
                      onChange={(e) =>
                        setContext((prev) => ({
                          ...prev,
                          group_size: Number(e.target.value),
                        }))
                      }
                    >
                      {[1, 2, 3, 4].map((n) => (
                        <option value={n} key={n}>
                          {n}
                        </option>
                      ))}
                    </select>
                  </label>
                  <label>
                    Plataforma
                    <select
                      value={context.platform}
                      onChange={(e) =>
                        setContext((prev) => ({
                          ...prev,
                          platform: e.target.value,
                        }))
                      }
                    >
                      <option value="spike">LEGO SPIKE — blocos</option>
                      <option value="other">
                        Outra plataforma (sem análise de arquivo)
                      </option>
                    </select>
                  </label>
                </div>
                <div className="pilot-mission">
                  <strong>{INSTRUMENT.activity.title}</strong>
                  <p>{INSTRUMENT.activity.objective}</p>
                </div>
                <label className="pilot-checkbox">
                  <input
                    type="checkbox"
                    checked={testConfirmed}
                    onChange={(e) => setTestConfirmed(e.target.checked)}
                    required
                  />
                  Estou testando com dados fictícios, sem participantes reais.
                </label>
                <button className="pilot-primary" disabled={!testConfirmed}>
                  Preparar convite
                </button>
              </form>
            )}
            {phase === "consent" && (
              <>
                <p className="pilot-eyebrow">Escolha de cada integrante</p>
                <h1>Vocês querem registrar esta experiência?</h1>
                <p>
                  Vamos fazer perguntas curtas sobre a atividade. Cada pessoa
                  pode dizer não, pular perguntas ou pedir para parar. Isso não
                  muda a participação na oficina.
                </p>
                <p>
                  Nesta simulação, os registros ficam neste navegador por até
                  sete dias. Um código liga as respostas à bancada; não pedimos
                  nomes. O instrutor pode exportar os registros. Não são dados
                  completamente anônimos.
                </p>
                <p>
                  O arquivo do robô só será lido se for escolhido manualmente.
                  Guardamos contagens de blocos, sem guardar o arquivo, seu nome
                  ou o código.
                </p>
                {assents.map((accepted, i) => (
                  <label className="pilot-checkbox" key={i}>
                    <input
                      type="checkbox"
                      checked={accepted}
                      onChange={(e) =>
                        setAssents((prev) =>
                          prev.map((v, n) => (n === i ? e.target.checked : v)),
                        )
                      }
                    />
                    Participante {String.fromCharCode(65 + i)} quer participar
                    dos registros.
                  </label>
                ))}
                <div className="pilot-actions">
                  <button
                    className="pilot-primary"
                    disabled={!assents.length || !assents.every(Boolean)}
                    onClick={start}
                  >
                    Todos aceitaram: começar registros
                  </button>
                  <button onClick={withdraw}>Continuar sem registros</button>
                </div>
              </>
            )}
            {phase === "free" && (
              <>
                <p className="pilot-eyebrow">
                  A escolha de vocês foi respeitada
                </p>
                <h1>Podem continuar a oficina</h1>
                <p>{INSTRUMENT.activity.objective}</p>
                <p>
                  Não há questionários, leitura de projetos ou gravação de dados
                  neste modo.
                </p>
                <button onClick={reset}>Voltar à preparação</button>
              </>
            )}
            {session &&
              ["pre", "checkpoint_20", "checkpoint_40", "post"].includes(
                phase,
              ) && (
                <Questionnaire
                  key={phase}
                  session={session}
                  onSave={(answers) =>
                    run(() =>
                      commit(
                        saveResponse(
                          sessionRef.current,
                          phase.startsWith("checkpoint") ? "checkpoint" : phase,
                          answers,
                          phase.startsWith("checkpoint")
                            ? Number(phase.split("_")[1])
                            : null,
                        ),
                      ),
                    )
                  }
                />
              )}
            {phase === "activity" && (
              <>
                <p className="pilot-eyebrow">Hora de construir</p>
                <h1>O projeto está com vocês.</h1>
                <p className="pilot-lead">{INSTRUMENT.activity.objective}</p>
                <p>
                  Os check-ins aparecem aos 20 e 40 minutos. O tempo continua
                  correndo durante as pausas.
                </p>
                <div className="pilot-actions">
                  <button
                    className="pilot-primary"
                    onClick={() =>
                      run(() =>
                        commit({
                          ...addEvent(sessionRef.current, "activity_ended"),
                          phase: "post",
                          form_prompted_at: Date.now(),
                        }),
                      )
                    }
                  >
                    Encerrar atividade
                  </button>
                </div>
                <details>
                  <summary>Controles do teste: abrir um check-in agora</summary>
                  <p>
                    Antecipar registra um desvio de tempo; o relógio real não é
                    alterado.
                  </p>
                  <div className="pilot-actions">
                    {[20, 40].map((mark) => (
                      <button
                        key={mark}
                        disabled={Boolean(
                          session.responses["checkpoint_" + mark],
                        )}
                        onClick={() =>
                          run(() =>
                            commit(
                              openCheckpoint(
                                sessionRef.current,
                                mark,
                                "manual_test",
                              ),
                            ),
                          )
                        }
                      >
                        Abrir check-in {mark}
                      </button>
                    ))}
                  </div>
                </details>
              </>
            )}
            {session && !["pre", "rubric", "finished"].includes(phase) && (
              <div className="pilot-support">
                <h2>Apoio durante a atividade</h2>
                {!activeHelp ? (
                  <button
                    onClick={() =>
                      run(() => commit(requestHelp(sessionRef.current)))
                    }
                  >
                    Precisamos de ajuda
                  </button>
                ) : (
                  <p role="status">
                    Ajuda registrada. Levantem a mão para chamar o instrutor.
                    Este teste não envia alertas para outro computador.
                  </p>
                )}
                <details>
                  <summary>Área do instrutor: ajuda e papéis</summary>
                  {activeHelp && (
                    <button
                      onClick={() =>
                        run(() =>
                          commit(
                            progressHelp(
                              sessionRef.current,
                              activeHelp.id,
                              {
                                requested: "acknowledged",
                                acknowledged: "started",
                                started: "resolved",
                              }[activeHelp.status],
                            ),
                          ),
                        )
                      }
                    >
                      {
                        {
                          requested: "Confirmar que vi o pedido",
                          acknowledged: "Iniciar atendimento",
                          started: "Registrar resolução",
                        }[activeHelp.status]
                      }
                    </button>
                  )}
                  <p>
                    Confirmem quem faz cada tarefa agora. O sistema não troca os
                    papéis sozinho.
                  </p>
                  <div className="pilot-grid">
                    {roles.map((r, i) => (
                      <label key={r.slot}>
                        Participante {r.slot}
                        <select
                          value={r.role}
                          onChange={(e) =>
                            setRoles((prev) =>
                              prev.map((v, n) =>
                                n === i ? { ...v, role: e.target.value } : v,
                              ),
                            )
                          }
                        >
                          {Object.entries(ROLE_NAMES).map(([v, t]) => (
                            <option key={v} value={v}>
                              {t}
                            </option>
                          ))}
                        </select>
                      </label>
                    ))}
                  </div>
                  <button
                    onClick={() =>
                      run(() => commit(changeRoles(sessionRef.current, roles)))
                    }
                  >
                    Confirmar papéis atuais
                  </button>
                </details>
                {context.platform === "spike" && (
                  <details>
                    <summary>
                      Ler estrutura de um projeto salvo (opcional)
                    </summary>
                    <p>
                      Selecione o projeto desta bancada. A leitura não verifica
                      execução nem aprendizagem. Cada leitura será vinculada à
                      sessão e ao momento atual.
                    </p>
                    <label className="pilot-checkbox">
                      <input
                        type="checkbox"
                        checked={artifactConfirmed}
                        onChange={(e) => setArtifactConfirmed(e.target.checked)}
                      />
                      Confirmei que este é o projeto desta bancada e desta
                      sessão, o mesmo das leituras anteriores (se houver).
                    </label>
                    <label>
                      Arquivo SPIKE ou Scratch
                      <input
                        type="file"
                        accept=".llsp3,.llsp,.sb3,.json"
                        disabled={!artifactConfirmed}
                        onChange={(e) => {
                          const file = e.target.files?.[0];
                          e.target.value = "";
                          if (!file) return;
                          const currentGeneration = generation.current;
                          void run(async () => {
                            const metrics = await readProjectFile(file);
                            if (
                              currentGeneration !== generation.current ||
                              !sessionRef.current
                            )
                              return;
                            const current = sessionRef.current,
                              previous = current.artifacts.at(-1);
                            const snapshot = {
                              ...artifactSnapshot(metrics, previous),
                              artifact_id:
                                previous?.artifact_id || crypto.randomUUID(),
                              session_id: current.id,
                              captured_at: Date.now(),
                              phase: current.phase,
                            };
                            await commit({
                              ...addEvent(
                                current,
                                "artifact_recorded",
                                snapshot,
                              ),
                              artifacts: [...current.artifacts, snapshot],
                            });
                            setArtifactConfirmed(false);
                            setNotice(
                              "Estrutura lida. Arquivo, nome e código não foram guardados.",
                            );
                          });
                        }}
                      />
                    </label>
                    {session.artifacts.length > 0 && (
                      <p>
                        {session.artifacts.at(-1).non_shadow_blocks} blocos não
                        sombra. Variação líquida desde a leitura anterior:{" "}
                        {session.artifacts.at(-1).net_block_count_change ??
                          "sem comparação"}
                        . Isso não indica estágio de aprendizagem.
                      </p>
                    )}
                  </details>
                )}
              </div>
            )}
            {phase === "rubric" && (
              <Rubric
                onFinish={(rubric) =>
                  run(() => commit(finishSession(sessionRef.current, rubric)))
                }
              />
            )}
            {phase === "finished" && (
              <Summary session={session} onNew={reset} />
            )}
          </fieldset>
        </section>
      </div>
      {screen === "setup" && !session && history.length > 0 && (
        <section className="pilot-history">
          <h2>Sessões de teste neste navegador</h2>
          <p>
            Guardadas por até sete dias desde o início, incluindo eventos e
            respostas. A limpeza acontece ao abrir o aplicativo.
          </p>
          {history.map((saved) => (
            <div key={saved.id}>
              <span>
                {saved.context.school} ·{" "}
                {new Date(saved.created_at).toLocaleString("pt-BR")} ·{" "}
                {saved.completed_at ? "encerrada" : "em andamento"}
              </span>
              <button
                disabled={busy}
                onClick={() => {
                  setContext(saved.context);
                  sessionRef.current = saved;
                  setSession(saved);
                  setRoles(saved.roles);
                  setNotice("Sessão retomada com seu contexto original.");
                }}
              >
                Abrir sessão
              </button>
              <button disabled={busy} onClick={() => download(saved)}>
                Exportar
              </button>
              <button
                disabled={busy}
                onClick={() => {
                  if (
                    window.confirm(
                      "Apagar permanentemente os registros locais desta sessão de teste?",
                    )
                  )
                    void run(async () => {
                      await removeSession(saved.id);
                      setHistory(await listSessions());
                      setNotice(
                        "Sessão de teste apagada deste navegador. Não é recuperável aqui.",
                      );
                    });
                }}
              >
                Apagar
              </button>
            </div>
          ))}
        </section>
      )}
      <footer className="pilot-footer">
        PulseLab · Instrumento experimental em validação · Bancada como unidade
        de análise · Retenção local de 7 dias
      </footer>
    </main>
  );
}
