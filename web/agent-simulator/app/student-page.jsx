import React, { useCallback, useEffect, useMemo, useState } from "react";
import { INSTRUMENT_MANIFEST } from "../lib/contracts.js";
import { deleteLocalStore } from "../lib/student-store.js";

// Formulário final da turma (v2.4.0). Durante a aula nenhuma página fica aberta: a sessão é
// do Bridge e o ícone na bandeja abre esta página em "Encerrar turma...". Aqui só se registra a
// resposta da bancada e a avaliação do instrutor; nada fica gravado no navegador.

const CLIENT_VERSION = "student-pwa/3.0.0";
const BRIDGE_URL = "http://127.0.0.1:43128";

const BANCADA_ITEM = INSTRUMENT_MANIFEST.items.bancada.experiencia;
const RESULT_ITEM = INSTRUMENT_MANIFEST.items.instrutor.resultado;
const SUPPORT_ITEM = INSTRUMENT_MANIFEST.items.instrutor.apoio;

// Chaves das versões até 2.3.x, quando a página ficava aberta e guardava a sessão no navegador.
const LEGACY_STORAGE_KEYS = [
  "pulselab_student_active_session_v1",
  "pulselab_student_context_v1",
  "pulselab_installation_id_v1",
  "pulselab_student_installation_id_v1"
];

async function bridgeGet(path) {
  const response = await fetch(`${BRIDGE_URL}${path}`, { signal: AbortSignal.timeout(3000) });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
}

async function bridgePost(path, payload) {
  const response = await fetch(`${BRIDGE_URL}${path}`, {
    signal: AbortSignal.timeout(10000),
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  });
  const body = await response.json().catch(() => ({}));
  return { status: response.status, body };
}

function clearLegacyBrowserData() {
  try {
    for (const key of LEGACY_STORAGE_KEYS) localStorage.removeItem(key);
    sessionStorage.removeItem("pulselab_tab_session_id");
  } catch {
    // Armazenamento indisponível: nada a limpar.
  }
  void deleteLocalStore().catch(() => {});
}

function Card({ title, children, eyebrow, wide = false }) {
  return (
    <div className="turma-overlay" role="dialog" aria-modal="true" aria-labelledby="turma-title">
      <div className={`turma-card${wide ? " turma-card--bancada" : ""}`}>
        {eyebrow && <span className="eyebrow">{eyebrow}</span>}
        <h2 id="turma-title">{title}</h2>
        {children}
      </div>
    </div>
  );
}

function LabPanel() {
  const [status, setStatus] = useState(null);
  const [message, setMessage] = useState("");

  const refresh = useCallback(async () => {
    try {
      setStatus(await bridgeGet("/v1/status"));
    } catch {
      setStatus(null);
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  async function testPause() {
    const { status: code, body } = await bridgePost("/v1/session/pause", {}).catch(() => ({ status: 0, body: {} }));
    setMessage(code === 200 ? `Pausado (dados apagados: ${body.purged_session ? "sim" : "não havia turma"}).` : "Falha ao pausar.");
    void refresh();
  }

  return (
    <aside className="lab-diagnostic" aria-label="Diagnóstico de laboratório">
      <div className="lab-diagnostic__card">
        <span className="eyebrow">Diagnóstico de Laboratório</span>
        <h2>Modo de Inspeção (?lab=1)</h2>
        <p>oficina de robótica · v3.0.0 · {CLIENT_VERSION}</p>
        <div className="lab-diagnostic__status">
          {status ? (
            <>
              <div>Pesquisa: {status.research_active ? "autorizada" : "Modo Livre (sem pesquisa)"}{status.paused ? " · pausada" : ""}</div>
              <div>Turma: {status.session ? `${status.session.session_id} · ${status.session.elapsed_min} min` : "nenhuma"}</div>
              <div>Telemetria SPIKE: {status.session ? status.session.telemetry_events : 0} · pasta: {status.spike_environment?.status}</div>
              <div>Pendentes de envio: {status.pending_sync}</div>
            </>
          ) : (
            <div>Bridge indisponível.</div>
          )}
        </div>
        <div className="action-row">
          <button className="button button--ghost" type="button" onClick={() => void refresh()}>Atualizar</button>
          <button className="button button--ghost" type="button" onClick={() => void testPause()}>Testar "Não registrar esta turma"</button>
        </div>
        {message && <p>{message}</p>}
      </div>
    </aside>
  );
}

export default function StudentPage() {
  const labMode = useMemo(() => {
    if (typeof window === "undefined") return false;
    return new URLSearchParams(window.location.search).get("lab") === "1";
  }, []);

  const [step, setStep] = useState("carregando");
  const [current, setCurrent] = useState(null);
  const [experience, setExperience] = useState(null);
  const [assessment, setAssessment] = useState({ result: null, support: null });
  const [notice, setNotice] = useState("");

  const loadCurrent = useCallback(async () => {
    try {
      const data = await bridgeGet("/v1/session/current");
      setCurrent(data);
      if (data.paused) setStep("pausado");
      else setStep("confirmar");
    } catch {
      setStep("indisponivel");
    }
  }, []);

  useEffect(() => {
    clearLegacyBrowserData();
    void loadCurrent();
  }, [loadCurrent]);

  function answerBancada(option) {
    setExperience(option ? { value: option[0], label: option[2], refused: false } : { value: null, label: null, refused: true });
    setAssessment({ result: null, support: null });
    setStep("instrutor");
  }

  async function finish({ skipped }) {
    setStep("enviando");
    const payload = {
      session_id: current?.session_id || null,
      experience,
      rubric: skipped
        ? { skipped: true }
        : { skipped: false, result_level: assessment.result, support_level: assessment.support }
    };
    const result = await bridgePost("/v1/session/close", payload).catch(() => ({ status: 0, body: {} }));
    if (result.status === 200) {
      setStep("concluido");
      return;
    }
    if (result.status === 409) {
      // A turma mudou (encerrada pelo tempo ou outra já começou): recomeça para não gravar na turma errada.
      setNotice("A turma deste computador mudou enquanto o formulário estava aberto. Responda de novo, por favor.");
      setExperience(null);
      await loadCurrent();
      return;
    }
    setNotice("Não foi possível registrar agora. Tente de novo em 1 minuto.");
    setStep("instrutor");
  }

  let content;
  if (step === "carregando" || step === "enviando") {
    content = (
      <Card title={step === "enviando" ? "Registrando..." : "Abrindo..."}>
        <p>Um instante.</p>
      </Card>
    );
  } else if (step === "indisponivel") {
    content = (
      <Card title="O PulseLab não está respondendo">
        <p>Aguarde 1 minuto e abra de novo pelo ícone do PulseLab na bandeja, perto do relógio.</p>
      </Card>
    );
  } else if (step === "sem_pesquisa") {
    content = (
      <Card title="Nada a encerrar">
        <p>Este computador não registra dados de pesquisa. Pode fechar esta janela.</p>
      </Card>
    );
  } else if (step === "pausado") {
    content = (
      <Card title="Esta turma não está sendo registrada">
        <p>O registro foi pausado em "Não registrar esta turma" e volta na próxima aula. Pode fechar esta janela.</p>
      </Card>
    );
  } else if (step === "confirmar") {
    const isFreeMode = current && !current.research_active;
    content = (
      <Card title={isFreeMode ? "Encerrar oficina (Modo Livre)?" : "Encerrar a turma desta bancada?"}>
        {notice && <p role="status">{notice}</p>}
        {isFreeMode ? (
          <p>
            Este computador opera em Modo Livre (sem gravação de pesquisa).
            A dinâmica de encerramento da bancada e a avaliação do instrutor podem ser realizadas normalmente.
          </p>
        ) : (
          <p>
            {current?.active
              ? "Use no fim da aula. Primeiro a bancada responde uma pergunta; depois o instrutor avalia."
              : "Nenhum programa foi salvo desde a turma anterior. As respostas serão registradas mesmo assim."}
          </p>
        )}
        <div className="turma-actions">
          <button className="button button--primary" type="button" onClick={() => { setNotice(""); setStep("bancada"); }}>Encerrar turma</button>
          <button className="button button--ghost" type="button" onClick={() => setStep("cancelado")}>Agora não</button>
        </div>
      </Card>
    );
  } else if (step === "cancelado") {
    content = (
      <Card title="A turma continua registrada">
        <p>Pode fechar esta janela.</p>
      </Card>
    );
  } else if (step === "bancada") {
    content = (
      <Card title={BANCADA_ITEM.legend} wide>
        <div className="face-options">
          {BANCADA_ITEM.options.map((option) => (
            <button key={option[0]} className="face-option" type="button" onClick={() => answerBancada(option)}>
              <span className="face-option__face" aria-hidden="true">{option[1]}</span>
              <span>{option[2]}</span>
            </button>
          ))}
        </div>
        <button className="turma-skip" type="button" onClick={() => answerBancada(null)}>
          {BANCADA_ITEM.action_skip}
        </button>
      </Card>
    );
  } else if (step === "instrutor") {
    const ready = assessment.result !== null && assessment.support !== null;
    content = (
      <Card title="Como foi esta bancada?" eyebrow="Para o instrutor">
        {notice && <p role="status">{notice}</p>}
        <fieldset className="choice-group">
          <legend>{RESULT_ITEM.legend}</legend>
          {RESULT_ITEM.options.map((option) => (
            <button
              key={option[0]}
              type="button"
              className={`choice${assessment.result === option[0] ? " choice--selected" : ""}`}
              aria-pressed={assessment.result === option[0]}
              onClick={() => setAssessment({ ...assessment, result: option[0] })}
            >
              {option[1]}
            </button>
          ))}
        </fieldset>
        <fieldset className="choice-group">
          <legend>{SUPPORT_ITEM.legend}</legend>
          {SUPPORT_ITEM.options.map((option) => (
            <button
              key={option[0]}
              type="button"
              className={`choice${assessment.support === option[0] ? " choice--selected" : ""}`}
              aria-pressed={assessment.support === option[0]}
              onClick={() => setAssessment({ ...assessment, support: option[0] })}
            >
              {option[1]}
            </button>
          ))}
        </fieldset>
        <div className="turma-actions">
          <button className="button button--primary" type="button" disabled={!ready} onClick={() => void finish({ skipped: false })}>
            Registrar
          </button>
          <button className="button button--ghost" type="button" onClick={() => void finish({ skipped: true })}>
            {INSTRUMENT_MANIFEST.items.instrutor.action_skip}
          </button>
        </div>
      </Card>
    );
  } else {
    content = (
      <Card title="Turma encerrada">
        <p>Pode fechar esta janela. A próxima turma começa a ser registrada quando salvar o primeiro programa no LEGO SPIKE.</p>
      </Card>
    );
  }

  return (
    <main className={`app-shell student-app ${labMode ? "student-app--lab" : "student-app--silent"}`}>
      {content}
      {labMode && <LabPanel />}
    </main>
  );
}
