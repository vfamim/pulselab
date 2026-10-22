import React, { useCallback, useEffect, useRef, useState } from "react";
import { createUuid } from "../lib/contracts.js";
import { bridgeGet, bridgePost } from "../lib/bridge-client.js";
import { PARTES, RECUSA, RECUSA_ROTULO, iniciarRodada, perguntaAtual, primeiraParte, responder } from "../lib/questionario.js";

// Questionário do fim da aula, aberto numa aba pela bandeja quando o PulseLab inicia.
// Opcional e sem nome: sem nome, idade ou texto livre. Uma pergunta por tela; ao tocar numa
// resposta a tela avança e a escolha não aparece de novo (sem "voltar" e sem resumo).

const ROBO = "/alunos/robot.png";
// Criança que saiu no meio: as respostas dela são descartadas e a tela volta ao início.
export const INATIVIDADE_MS = 120_000;
// Toques logo depois de a pergunta mudar (duplo toque) não contam como resposta.
const TRAVA_TOQUE_MS = 400;

function Icone({ nome }) {
  const comum = { width: 48, height: 48, viewBox: "0 0 48 48", "aria-hidden": "true", focusable: "false", className: "quiz-option__icon" };
  const traco = { fill: "none", stroke: "currentColor", strokeWidth: 3, strokeLinecap: "round", strokeLinejoin: "round" };
  const polegar = (
    <g {...traco}>
      <path d="M8 22h7v18H8z" />
      <path d="M15 22l7-13c3 0 5 2 4 6l-2 6h11c3 0 5 3 4 6l-3 11c-1 2-2 3-4 3H15" />
    </g>
  );
  const barras = (cheias) => (
    <g {...traco}>
      {[0, 1, 2, 3].map((i) => (
        <rect key={i} x={7 + i * 9.5} y={34 - i * 6} width="6" height={8 + i * 6} rx="1.5" fill={i < cheias ? "currentColor" : "none"} />
      ))}
    </g>
  );
  const desenhos = {
    sim: polegar,
    nao: <g transform="rotate(180 24 24)">{polegar}</g>,
    mais_ou_menos: (
      <g {...traco}>
        <path d="M8 26c4-7 8-7 12 0s8 7 12 0 6-4 8-2" />
      </g>
    ),
    em_parte: (
      <g {...traco}>
        <circle cx="24" cy="24" r="16" />
        <path d="M24 8a16 16 0 0 1 0 32z" fill="currentColor" />
      </g>
    ),
    ganhamos: (
      <g {...traco}>
        <path d="M15 8h18v9a9 9 0 0 1-18 0z" />
        <path d="M15 11H9c0 6 3 9 7 9M33 11h6c0 6-3 9-7 9M24 26v8M17 40h14M20 34h8" />
      </g>
    ),
    terminamos_sem_ganhar: (
      <g {...traco}>
        <path d="M12 42V7" />
        <path d="M12 9h22l-5 7 5 7H12" />
      </g>
    ),
    nao_terminamos: (
      <g {...traco}>
        <path d="M6 30h7M18 30h7" />
        <circle cx="33" cy="30" r="4" />
        <path d="M30 14l6 6M36 14l-6 6" />
      </g>
    ),
    nao_participamos: (
      <g {...traco}>
        <circle cx="24" cy="24" r="16" />
        <path d="M15 24h18" />
      </g>
    ),
    quase_todas: barras(4),
    metade: barras(2),
    poucas: barras(1),
    sem_quiz: (
      <g {...traco}>
        <circle cx="24" cy="24" r="16" />
        <path d="M13 35L35 13" />
      </g>
    ),
    [RECUSA]: (
      <g {...traco}>
        <path d="M8 24h24M24 14l10 10-10 10" />
        <path d="M40 12v24" />
      </g>
    )
  };
  return <svg {...comum}>{desenhos[nome] || null}</svg>;
}

function Mascote({ pequeno = false }) {
  return <img className={`quiz-mascot${pequeno ? " quiz-mascot--small" : ""}`} src={ROBO} alt="Robô do PulseLab" width="764" height="680" />;
}

function Aviso({ titulo, children, acao, tituloRef }) {
  return (
    <section className="quiz-center" aria-labelledby="quiz-title">
      <Mascote />
      <h1 id="quiz-title" className="quiz-title" tabIndex={-1} data-stage-heading ref={tituloRef}>{titulo}</h1>
      {children}
      {acao}
    </section>
  );
}

export default function Questionario() {
  const [tela, setTela] = useState("carregando");
  const [rodada, setRodada] = useState(null);
  const [enviando, setEnviando] = useState(false);
  const mostradaEm = useRef(0);
  const tituloRef = useRef(null);

  const carregarEstado = useCallback(async () => {
    try {
      return await bridgeGet("/v1/questionario/estado");
    } catch {
      return null;
    }
  }, []);

  // Decide a tela a partir do estado do bridge: sem coleta, só agradece; senão começa a parte certa.
  const comecar = useCallback(async ({ parteSeFalhar = null } = {}) => {
    const estado = await carregarEstado();
    if (!estado) {
      if (parteSeFalhar) {
        setRodada(iniciarRodada(parteSeFalhar, createUuid()));
        setTela("pergunta");
      } else {
        setTela("indisponivel");
      }
      return;
    }
    if (!estado.coleta_ativa) {
      setTela("sem_registro");
      return;
    }
    setRodada(iniciarRodada(primeiraParte(estado), createUuid()));
    setTela("pergunta");
  }, [carregarEstado]);

  const abrir = useCallback(async () => {
    setTela("carregando");
    const estado = await carregarEstado();
    if (!estado) setTela("indisponivel");
    else if (!estado.coleta_ativa) setTela("sem_registro");
    else setTela("entrada");
  }, [carregarEstado]);

  useEffect(() => {
    void abrir();
  }, [abrir]);

  const perguntaKey = rodada ? `${rodada.submissionId}-${rodada.parte}-${rodada.indice}` : tela;

  // Foco no título a cada tela: o leitor de tela anuncia a pergunta e nenhum botão fica
  // destacado no lugar da resposta anterior.
  useEffect(() => {
    mostradaEm.current = Date.now();
    tituloRef.current?.focus({ preventScroll: true });
  }, [perguntaKey]);

  // Sem resposta por um tempo no meio das perguntas: volta ao início e descarta a rodada.
  useEffect(() => {
    if (tela !== "pergunta") return undefined;
    const timer = setTimeout(() => {
      setRodada(null);
      setTela("entrada");
    }, INATIVIDADE_MS);
    return () => clearTimeout(timer);
  }, [tela, perguntaKey]);

  async function enviar(envio) {
    setEnviando(true);
    let resultado = await bridgePost(envio.rota, envio.corpo).catch(() => null);
    if (!resultado || resultado.status >= 500) {
      await new Promise((resolve) => setTimeout(resolve, 1000));
      resultado = await bridgePost(envio.rota, envio.corpo).catch(() => null);
    }
    setEnviando(false);
    if (resultado && resultado.status === 200 && resultado.body?.status === "nao_gravado") {
      setRodada(null);
      setTela("sem_registro");
      return;
    }
    if (envio.parte === "bancada") {
      setRodada(iniciarRodada("crianca", createUuid()));
      setTela("pergunta");
    } else {
      setRodada(null);
      setTela("fim");
    }
  }

  function escolher(valor) {
    if (!rodada || enviando || Date.now() - mostradaEm.current < TRAVA_TOQUE_MS) return;
    const { rodada: proxima, envio } = responder(rodada, valor);
    if (envio) {
      setRodada({ ...rodada, indice: rodada.indice, enviando: true });
      void enviar(envio);
    } else {
      setRodada(proxima);
    }
  }

  let conteudo;
  if (tela === "carregando") {
    conteudo = (
      <section className="quiz-center" aria-live="polite">
        <Mascote pequeno />
        <p className="quiz-lead">Abrindo...</p>
      </section>
    );
  } else if (tela === "indisponivel") {
    conteudo = (
      <Aviso
        tituloRef={tituloRef}
        titulo="O questionário não abriu"
        acao={<button className="quiz-start" type="button" onClick={() => void abrir()}>Tentar de novo</button>}
      >
        <p className="quiz-lead">Avise o instrutor.</p>
      </Aviso>
    );
  } else if (tela === "sem_registro") {
    conteudo = (
      <Aviso tituloRef={tituloRef} titulo="Obrigado!">
        <p className="quiz-lead">Hoje não há questionário neste computador.</p>
      </Aviso>
    );
  } else if (tela === "entrada") {
    conteudo = (
      <Aviso
        tituloRef={tituloRef}
        titulo="Questionário do fim da aula"
        acao={<button className="quiz-start" type="button" onClick={() => void comecar()}>Começar</button>}
      >
        <p className="quiz-lead">Responda quando o instrutor avisar</p>
        <p className="quiz-note">Responder é opcional e ninguém precisa dizer o nome.</p>
      </Aviso>
    );
  } else if (tela === "fim") {
    conteudo = (
      <Aviso
        tituloRef={tituloRef}
        titulo="Obrigado! Chame o próximo colega."
        acao={<button className="quiz-start" type="button" onClick={() => void comecar({ parteSeFalhar: "crianca" })}>Próximo colega</button>}
      />
    );
  } else if (rodada) {
    const item = perguntaAtual(rodada);
    const total = PARTES[rodada.parte].length;
    const daBancada = rodada.parte === "bancada";
    conteudo = (
      <section className="quiz-question" key={perguntaKey} aria-labelledby="quiz-title">
        <div className="quiz-question__meta">
          <span className={`quiz-chip ${daBancada ? "quiz-chip--bancada" : "quiz-chip--crianca"}`}>
            {daBancada ? "Pergunta da bancada: respondam juntos" : "Pergunta só sua"}
          </span>
          <span className="quiz-progress">Pergunta {rodada.indice + 1} de {total}</span>
        </div>
        <h1 id="quiz-title" className="quiz-title quiz-title--question" tabIndex={-1} data-stage-heading ref={tituloRef}>{item.text}</h1>
        <div className={`quiz-options quiz-options--${item.options.length + 1}`} role="group" aria-labelledby="quiz-title">
          {item.options.map(([codigo, rotulo]) => (
            <button key={codigo} className="quiz-option" type="button" disabled={rodada.enviando} onClick={() => escolher(codigo)}>
              <Icone nome={codigo} />
              <span className="quiz-option__label">{rotulo}</span>
            </button>
          ))}
          <button className="quiz-option quiz-option--skip" type="button" disabled={rodada.enviando} onClick={() => escolher(RECUSA)}>
            <Icone nome={RECUSA} />
            <span className="quiz-option__label">{RECUSA_ROTULO}</span>
          </button>
        </div>
      </section>
    );
  }

  return (
    <main className="student-app quiz" aria-busy={tela === "carregando" || enviando}>
      <div className="quiz-frame">{conteudo}</div>
    </main>
  );
}
