// Fluxo do questionário do fim da aula, sem React: qual parte começa, a pergunta seguinte e o envio.
// Uma pergunta por tela; a resposta escolhida não volta para a tela e não há resumo no fim.
import { INSTRUMENT_MANIFEST } from "./contracts.js";

export const QUESTIONARIO = INSTRUMENT_MANIFEST.questionario_fim_aula;
export const [RECUSA, RECUSA_ROTULO] = QUESTIONARIO.skip;
export const PARTES = {
  bancada: QUESTIONARIO.bancada.items,
  crianca: QUESTIONARIO.crianca.items
};
export const ROTAS = {
  bancada: "/v1/questionario/bancada",
  crianca: "/v1/questionario/crianca"
};

// O resultado da bancada vale uma vez por aula: já respondido, vai direto para as perguntas individuais.
export function primeiraParte(estado) {
  return estado && estado.bancada_respondida ? "crianca" : "bancada";
}

export function iniciarRodada(parte, submissionId) {
  if (!PARTES[parte]) throw new Error(`parte desconhecida: ${parte}`);
  return { parte, indice: 0, respostas: [], submissionId };
}

export function perguntaAtual(rodada) {
  return PARTES[rodada.parte][rodada.indice];
}

// Registra a resposta (ou a recusa) e devolve a próxima pergunta ou, na última, o envio para o bridge.
export function responder(rodada, valor) {
  const itens = PARTES[rodada.parte];
  const item = itens[rodada.indice];
  const validos = item.options.map(([codigo]) => codigo);
  if (valor !== RECUSA && !validos.includes(valor)) throw new Error(`resposta fora do instrumento: ${valor}`);
  const respostas = [...rodada.respostas, { item_id: item.item_id, value: valor }];
  if (rodada.indice + 1 < itens.length) {
    return { rodada: { ...rodada, indice: rodada.indice + 1, respostas }, envio: null };
  }
  return {
    rodada: null,
    envio: { parte: rodada.parte, rota: ROTAS[rodada.parte], corpo: { submission_id: rodada.submissionId, answers: respostas } }
  };
}
