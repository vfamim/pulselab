import React, { useCallback, useEffect, useMemo, useState } from "react";
import { deleteLocalStore } from "../lib/student-store.js";
import { bridgeGet, bridgePost } from "../lib/bridge-client.js";
import Questionario from "./questionario.jsx";

// Página da bancada em http://127.0.0.1:43128/alunos/.
// Rota padrão: questionário do fim da aula (opcional e sem nome), aberto numa aba pela bandeja.
// A criança não encerra a aula por aqui: o encerramento fica no menu da bandeja e, para
// diagnóstico, em ?encerrar=1. Encerrar a turma só fecha a sessão: o PulseLab continua ligado.
// ?lab=1 mostra o painel de diagnóstico do laboratório.

const CLIENT_VERSION = `student-pwa/${__PULSELAB_VERSION__}`;

// Chaves das versões até 2.3.x, quando a página ficava aberta e guardava a sessão no navegador.
const LEGACY_STORAGE_KEYS = [
  "pulselab_student_active_session_v1",
  "pulselab_student_context_v1",
  "pulselab_installation_id_v1",
  "pulselab_student_installation_id_v1"
];

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
  const [loaded, setLoaded] = useState(false);
  const [message, setMessage] = useState("");

  const refresh = useCallback(async () => {
    try {
      setStatus(await bridgeGet("/v1/status"));
    } catch (e) {
      // Sem resposta: não mostrar o último status como se fosse o atual.
      setStatus(null);
      setMessage(`Erro: ${e.message}`);
    }
    setLoaded(true);
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  async function testPause() {
    setMessage("Pausando registro...");
    try {
      const res = await bridgePost("/v1/session/pause", {});
      setMessage(res.status === 200
        ? `Pausado (aula marcada como não autorizada: ${res.body.marked ? "sim" : "não havia aula"}).`
        : `Falha ao pausar (HTTP ${res.status}).`);
    } catch (e) {
      setMessage(`Erro ao pausar: ${e.message}`);
    }
    await refresh();
  }

  return (
    <aside className="lab-diagnostic" aria-label="Painel de Diagnóstico do Laboratório">
      <div className="lab-diagnostic__card">
        <span className="eyebrow">Diagnóstico de Laboratório</span>
        <h2>Modo de Inspeção (?lab=1)</h2>
        <p>oficina de robótica · v{__PULSELAB_VERSION__} · {CLIENT_VERSION}</p>
        <div className="lab-diagnostic__status">
          {status ? (
            <>
              <div><strong>Status:</strong> {status.status}</div>
              <div><strong>Versão:</strong> {status.version}</div>
              <div><strong>Pesquisa Ativa:</strong> {status.research_active ? "Sim" : "Não"}</div>
              <div><strong>Pausado:</strong> {status.paused ? "Sim" : "Não"}</div>
              <div><strong>Sessão ID:</strong> {status.session?.session_id || "nenhuma"}</div>
            </>
          ) : (
            <p>{loaded ? "Bridge indisponível." : "Carregando status do Bridge..."}</p>
          )}
        </div>
        <div className="turma-actions">
          <button className="button button--ghost" type="button" onClick={() => void refresh()}>Atualizar</button>
          <button className="button button--ghost" type="button" onClick={() => void testPause()}>Testar "Não registrar esta turma"</button>
        </div>
        {message && <p>{message}</p>}
      </div>
    </aside>
  );
}

// Encerramento da turma por esta página: só em ?encerrar=1 (diagnóstico). O instrutor encerra pela bandeja.
function EncerramentoTurma() {
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

  return <main className="app-shell student-app student-app--silent">{content}</main>;
}

export default function StudentPage() {
  const modo = useMemo(() => {
    if (typeof window === "undefined") return "questionario";
    const params = new URLSearchParams(window.location.search);
    if (params.get("lab") === "1") return "lab";
    if (params.get("encerrar") === "1") return "encerrar";
    return "questionario";
  }, []);

  useEffect(() => {
    clearLegacyBrowserData();
  }, []);

  if (modo === "lab") {
    return (
      <main className="app-shell student-app student-app--lab">
        <LabPanel />
      </main>
    );
  }
  if (modo === "encerrar") return <EncerramentoTurma />;
  return <Questionario />;
}
