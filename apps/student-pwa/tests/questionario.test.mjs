import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { INSTRUMENT_MANIFEST, INSTRUMENT_VERSION, TIMELINE_EVENT_TYPES } from "../lib/contracts.js";
import { PARTES, RECUSA, RECUSA_ROTULO, ROTAS, iniciarRodada, perguntaAtual, primeiraParte, responder } from "../lib/questionario.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "../../..");
const read = (rel) => fs.readFileSync(path.join(repoRoot, rel), "utf-8");
const bridgeCode = read("runtime/windows/bridge/pulselab-bridge.ps1");
const trayCode = read("runtime/windows/bridge/pulselab-tray.ps1");
const quizCode = read("apps/student-pwa/app/questionario.jsx");
const UUID = "0f0e0d0c-0b0a-4908-8706-050403020100";

// Texto aprovado pelo pesquisador responsável: qualquer mudança de palavra quebra este teste.
const APROVADO = {
  bancada: [
    ["bancada_linha_v1", "O carrinho de vocês seguiu a linha preta até o fim da pista?", ["Sim", "Em parte", "Não"]],
    ["bancada_corrida_v1", "Como foi a corrida?", ["Ganhamos", "Terminamos, mas não ganhamos", "Não terminamos", "Não participamos"]],
    ["bancada_quiz_v1", "No jogo de perguntas, vocês acertaram...", ["Quase todas", "Metade", "Poucas", "Não teve jogo de perguntas"]]
  ],
  crianca: [
    ["crianca_gostou_v1", "Eu gostei da aula de robótica.", ["Sim", "Mais ou menos", "Não"]],
    ["crianca_outra_aula_v1", "Eu queria ter outra aula de robótica.", ["Sim", "Mais ou menos", "Não"]],
    ["crianca_confianca_antes_v1", "Antes da aula, eu achava que conseguia programar um robô.", ["Sim", "Mais ou menos", "Não"]],
    ["crianca_confianca_agora_v1", "Agora, eu acho que consigo programar um robô.", ["Sim", "Mais ou menos", "Não"]],
    ["crianca_ajudou_v1", "Na minha bancada, eu consegui ajudar a montar ou programar.", ["Sim", "Mais ou menos", "Não"]]
  ]
};

test("Manifesto: texto aprovado, ids estáveis, numeração 1 a 8 e recusa explícita", () => {
  const q = INSTRUMENT_MANIFEST.questionario_fim_aula;
  assert.equal(INSTRUMENT_VERSION, "bancada-3.2.0");
  assert.equal(q.anonymous, true);
  assert.equal(q.optional, true);
  assert.deepEqual(q.skip, ["recusou", "Não quero responder"]);
  assert.equal(q.bancada.event_type, "bancada_result_recorded");
  assert.equal(q.crianca.event_type, "student_feedback_recorded");
  assert.equal(q.bancada.once_per_session, true);
  for (const parte of ["bancada", "crianca"]) {
    assert.deepEqual(
      q[parte].items.map((i) => [i.item_id, i.text, i.options.map(([, rotulo]) => rotulo)]),
      APROVADO[parte],
      `texto da parte ${parte}`
    );
  }
  const todos = [...q.bancada.items, ...q.crianca.items];
  assert.deepEqual(todos.map((i) => i.number), [1, 2, 3, 4, 5, 6, 7, 8]);
  assert.equal(new Set(todos.map((i) => i.item_id)).size, 8);
  for (const item of todos) {
    for (const [codigo] of item.options) assert.match(codigo, /^[a-z_]+$/, `${item.item_id}: código estável em ascii`);
    assert.ok(!item.options.some(([codigo]) => codigo === RECUSA), "recusa não é uma opção de resposta");
  }
  assert.ok(TIMELINE_EVENT_TYPES.includes("bancada_result_recorded"));
  assert.ok(TIMELINE_EVENT_TYPES.includes("student_feedback_recorded"));
  // Nada que identifique a criança no instrumento
  assert.doesNotMatch(JSON.stringify(q), /\b(nome|idade|age|name|free_text|texto_livre)\b/i);
});

test("Fluxo: bancada já respondida pula para as perguntas individuais", () => {
  assert.equal(primeiraParte({ coleta_ativa: true, bancada_respondida: false }), "bancada");
  assert.equal(primeiraParte({ coleta_ativa: true, bancada_respondida: true }), "crianca");
  assert.equal(primeiraParte(null), "bancada");
});

test("Fluxo: uma pergunta por vez e envio da bancada só no fim, com todos os itens", () => {
  let rodada = iniciarRodada("bancada", UUID);
  const escolhas = ["em_parte", RECUSA, "sem_quiz"];
  let envio = null;
  escolhas.forEach((valor, i) => {
    assert.equal(perguntaAtual(rodada).number, i + 1);
    ({ rodada, envio } = responder(rodada, valor));
    if (i < escolhas.length - 1) assert.equal(envio, null);
  });
  assert.equal(rodada, null);
  assert.equal(envio.rota, ROTAS.bancada);
  assert.deepEqual(envio.corpo, {
    submission_id: UUID,
    answers: [
      { item_id: "bancada_linha_v1", value: "em_parte" },
      { item_id: "bancada_corrida_v1", value: "recusou" },
      { item_id: "bancada_quiz_v1", value: "sem_quiz" }
    ]
  });
});

test("Fluxo: criança responde as perguntas 4 a 8, inclusive recusas, e o envio leva o par 6/7 junto", () => {
  let rodada = iniciarRodada("crianca", UUID);
  let envio = null;
  for (const valor of ["sim", "mais_ou_menos", "nao", "sim", RECUSA]) ({ rodada, envio } = responder(rodada, valor));
  assert.equal(envio.rota, "/v1/questionario/crianca");
  assert.equal(envio.corpo.answers.length, PARTES.crianca.length);
  const porItem = Object.fromEntries(envio.corpo.answers.map((a) => [a.item_id, a.value]));
  assert.equal(porItem.crianca_confianca_antes_v1, "nao");
  assert.equal(porItem.crianca_confianca_agora_v1, "sim");
  assert.equal(porItem.crianca_ajudou_v1, "recusou");
  assert.throws(() => responder(iniciarRodada("crianca", UUID), "talvez"), /fora do instrumento/);
  assert.throws(() => responder(iniciarRodada("bancada", UUID), "mais_ou_menos"), /fora do instrumento/);
});

test("Bridge aceita exatamente os itens e códigos do manifesto e a mesma recusa", () => {
  const lerMapa = (nome) => {
    const inicio = bridgeCode.indexOf(`$script:${nome} = [ordered]@{`);
    assert.ok(inicio !== -1, `${nome} deve existir no bridge`);
    const bloco = bridgeCode.slice(inicio, bridgeCode.indexOf("\n}", inicio));
    return Object.fromEntries([...bloco.matchAll(/"([a-z0-9_]+)" = @\(([^)]*)\)/g)].map(([, id, lista]) => [id, [...lista.matchAll(/"([^"]+)"/g)].map((m) => m[1])]));
  };
  const esperado = (parte) => Object.fromEntries(PARTES[parte].map((i) => [i.item_id, i.options.map(([c]) => c)]));
  assert.deepEqual(lerMapa("QuestionarioBancadaItems"), esperado("bancada"));
  assert.deepEqual(lerMapa("QuestionarioCriancaItems"), esperado("crianca"));
  assert.match(bridgeCode, new RegExp(`\\$script:QuestionarioRecusa = "${RECUSA}"`));
});

test("Bridge: rotas do questionário validam antes de gravar e não gravam fora de uma aula registrada", () => {
  assert.match(bridgeCode, /"\/v1\/status", "\/v1\/session\/current", "\/v1\/questionario\/estado"\)/, "estado só por GET");
  const postRoutes = bridgeCode.slice(bridgeCode.indexOf("$postRoutes = @("), bridgeCode.indexOf(")", bridgeCode.indexOf("$postRoutes = @(")));
  assert.match(postRoutes, /"\/v1\/questionario\/bancada",\s*"\/v1\/questionario\/crianca"/);
  assert.match(bridgeCode, /\$jsonBodyRoutes = @\([^)]*"\/v1\/questionario\/bancada", "\/v1\/questionario\/crianca"\)/, "Content-Type JSON e limite de corpo");
  const rota = bridgeCode.slice(bridgeCode.indexOf('if ($path -in @("/v1/questionario/bancada", "/v1/questionario/crianca")'));
  const bloco = rota.slice(0, rota.indexOf("continue\r\n            }\r\n\r\n"));
  assert.match(bloco, /Read-BoundedRequestBody -Request \$request -MaxBytes 8192/);
  const idx = (s) => bloco.indexOf(s);
  assert.ok(idx("-StatusCode 400") !== -1 && idx("-StatusCode 400") < idx("Get-BridgeQuestionarioTarget"), "400 antes de olhar a aula");
  assert.ok(idx('status = "nao_gravado"') < idx("Save-BridgeQuestionario"), "Modo Livre, pausa, não autorizada e sem aula não gravam");
  assert.ok(idx('status = "ja_respondido"') < idx("Save-BridgeQuestionario"), "bancada uma vez por aula");
  const alvo = bridgeCode.slice(bridgeCode.indexOf("function Get-BridgeQuestionarioTarget"), bridgeCode.indexOf("function Test-BridgeBancadaRespondida"));
  for (const motivo of ["modo_livre", "pausado", "nao_autorizada", "sem_aula"]) assert.match(alvo, new RegExp(`motivo = "${motivo}"`));
  assert.match(alvo, /LastClosedFile/, "sem aula ativa, vai para a última encerrada");
  assert.match(alvo, /UnauthorizedSessions\.ContainsKey\(\$sid\)/);
  const salvar = bridgeCode.slice(bridgeCode.indexOf("function Save-BridgeQuestionario"));
  assert.match(salvar, /instrument_version = \$script:InstrumentVersion/);
  assert.match(salvar, /submission_id = \$Parsed\.submission_id/);
  assert.doesNotMatch(salvar.slice(0, 3000), /\b(name|nome|idade|age)\b/i);
});

test("Página: recusa com o mesmo destaque, sem voltar, sem resumo e sem mostrar a escolha", () => {
  assert.match(quizCode, /className="quiz-option quiz-option--skip"/, "Não quero responder é um cartão como as respostas");
  assert.match(quizCode, /\{RECUSA_ROTULO\}/);
  assert.equal(RECUSA_ROTULO, "Não quero responder");
  assert.doesNotMatch(quizCode, />\s*Voltar|is-selected|aria-pressed|aria-selected|aria-checked/);
  assert.match(quizCode, /Questionário do fim da aula/);
  assert.match(quizCode, /Responda quando o instrutor avisar/);
  assert.match(quizCode, /Obrigado! Chame o próximo colega\./);
  assert.match(quizCode, /src=\{ROBO\}/, "mascote nas telas de entrada e final");
  assert.doesNotMatch(quizCode, /\/v1\/session\/close|\/v1\/shutdown/, "a criança não encerra a aula pela aba");
  assert.doesNotMatch(quizCode, /<input|<textarea/, "sem texto livre");
});

test("Bandeja abre a aba uma vez, depois do /health e só com a coleta ativa", () => {
  assert.match(trayCode, /\$script:QuestionarioUrl = "\$\(\$script:BaseUrl\)\/alunos\/"/);
  const fn = trayCode.slice(trayCode.indexOf("function Open-QuestionarioOnce"), trayCode.indexOf("function Restart-PulseLab"));
  const i = (s) => fn.indexOf(s);
  assert.ok(i('Invoke-TrayApi "/health"') !== -1 && i('Invoke-TrayApi "/health"') < i("Start-Process"), "abre depois do /health");
  assert.ok(i("research_active") < i("Start-Process"), "só com a coleta de pesquisa ativa");
  assert.ok(i("$script:QuestionarioPendente = $false") < i("Start-Process"), "uma vez só");
  assert.match(fn, /Start-Process \$script:QuestionarioUrl/);
  assert.match(trayCode, /\$timer\.add_Tick\(\{\s*Update-TrayStatus\s*Open-QuestionarioOnce\s*\}\)/);
  assert.doesNotMatch(read("runtime/windows/pulselab.ps1"), /questionario|alunos\//i, "launcher protegido não muda");
});

test("Instalador cria o atalho Questionário PulseLab (.url) e preserva CRLF e o título com a versão", () => {
  const bat = read("runtime/windows/Instalar-PulseLab.bat");
  const version = read("VERSION").trim();
  assert.ok(!/(?<!\r)\n/.test(bat), "CRLF");
  assert.ok(/^[\x00-\x7F]*$/.test(bat), "instalador continua ASCII: o acento do nome vem do PowerShell");
  assert.match(bat, new RegExp(`title PulseLab - Instalador Local \\(v${version.replace(/\./g, "\\.")}\\)`));
  assert.match(bat, /'Question' \+ \[char\]0x00E1 \+ 'rio PulseLab\.url'/);
  assert.match(bat, /'URL=http:\/\/127\.0\.0\.1:43128\/alunos\/'/);
  assert.match(bat, /\[InternetShortcut\]/);
});
