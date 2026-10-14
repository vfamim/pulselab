import React, { useCallback, useEffect, useMemo, useState } from "react";
import { deleteLocalStore } from "../lib/student-store.js";

// Página da bancada / encerramento silencioso (v3.0.2).
// Durante a aula nenhuma página precisa ficar aberta. O encerramento no PC é direto e silencioso:
// zero formulários para os alunos ou instrutor no computador da bancada.
// A avaliação pedagógica do instrutor é realizada separadamente no portal/celular.

const CLIENT_VERSION = "student-pwa/3.0.2";
const BRIDGE_URL = "http://127.0.0.1:43128";

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
        <p>oficina de robótica · v3.0.2 · {CLIENT_VERSION}</p>
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

  async function finish() {
    setStep("enviando");
    const payload = {
      session_id: current?.session_id || null
    };
    const result = await bridgePost("/v1/session/close", payload).catch(() => ({ status: 0, body: {} }));
    if (result.status === 200) {
      setStep("concluido");
      return;
    }
    if (result.status === 409) {
      // A turma mudou (encerrada pelo tempo ou outra já começou): recomeça para não gravar na turma errada.
      setNotice("A turma deste computador mudou enquanto a página estava aberta. Tente novamente.");
      await loadCurrent();
      return;
    }
    setNotice("Não foi possível encerrar agora. Tente de novo em 1 minuto.");
    setStep("confirmar");
  }

  let content;
  if (step === "carregando" || step === "enviando") {
    content = (
      <Card title={step === "enviando" ? "Encerrando..." : "Abrindo..."}>
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
          </p>
        ) : (
          <p>
            {current?.active
              ? "A gravação desta aula será finalizada imediatamente. Não há formulários ou perguntas a preencher."
              : "Nenhum programa foi salvo nesta sessão."}
          </p>
        )}
        <div className="turma-actions">
          <button className="button button--primary" type="button" onClick={() => void finish()}>Encerrar turma</button>
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
  } else {
    content = (
      <Card title="Turma encerrada">
        <p>Pode fechar esta janela. A gravação foi concluída com sucesso. A próxima turma começará automaticamente quando o primeiro programa for salvo no LEGO SPIKE.</p>
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
