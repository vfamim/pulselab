#!/usr/bin/env python3
"""
PulseLab — Relatório automático das aulas de bancada.
=====================================================
Junta as aulas registradas na nuvem (view research_aula_bancada no Supabase) e as importadas por
pendrive (SQLite consolidado do importador) numa tabela com uma linha por aula de bancada, sem
duplicar a mesma sessão, e gera na pasta de saída:

  aulas.csv               uma linha por aula
  resumo-polos.csv        por polo e por semana
  maquinas-sem-envio.csv  máquinas e há quantos dias não chegam dados delas
  testes-carrinho.csv     questionário do fim da aula: resultado das bancadas, por polo e mês
  criancas.csv            questionário do fim da aula: respostas das crianças por pergunta, polo e mês
  criancas-resumo.csv     crianças que responderam e mudança de autoconfiança (perguntas 6 e 7)
  questionario-sinalizacoes.csv  aulas com respostas a conferir
  relatorio.md            resumo em português, com a seção "Atenção"

Credenciais da nuvem: as mesmas do importador (PULSELAB_SUPABASE_URL, PULSELAB_SERVICE_ROLE_KEY ou
PULSELAB_OPERATIONAL_JWT). Sem credencial, ou com --sem-nuvem, usa só o SQLite e não acessa a rede.

Só campos de bancada e de máquina e respostas anônimas do questionário (códigos fixos, sem nome,
idade ou texto livre); aulas não autorizadas ou retiradas ficam fora de tudo.
Zero dependências externas.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import importlib.util
import json
from pathlib import Path
import re
import sqlite3
import statistics
import sys
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[2]

_spec = importlib.util.spec_from_file_location(
    "importar_para_supabase", Path(__file__).resolve().parent / "importar-para-supabase.py"
)
imp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(imp)

# Todos os polos ficam em UTC-3 sem horário de verão (America/Recife). Offset fixo porque o
# Python do Windows não traz a base de fusos horários.
FUSO_LOCAL = dt.timezone(dt.timedelta(hours=-3))
DIAS_SEM_DADOS = 7
LIMITE_AULAS_MD = 200
SPIKE_COM_PROBLEMA = {"pasta_nao_encontrada", "leitor_indisponivel", "arquivo_invalido"}

COLUNAS_AULAS = [
    "session_id", "polo", "escola", "maquina", "installation_id",
    "data_local", "hora_inicio", "hora_fim", "duracao_min",
    "encerrada_por", "interrompida", "fase", "modo_inicio",
    "versoes_programa", "blocos_executaveis", "usa_motor", "usa_sensor", "usa_laco", "usa_condicao",
    "ct_score", "spike_status",
    "sinais_de_vida", "maior_lacuna_min", "reinicios", "linhas_corrompidas",
    "client_version", "instrument_version", "origem", "qualidade", "motivo_qualidade",
]
COLUNAS_RESUMO = [
    "polo", "semana_inicio", "aulas", "maquinas", "duracao_mediana_min",
    "pct_encerradas_instrutor", "pct_interrompidas", "pct_sem_spike",
]
COLUNAS_MAQUINAS = [
    "polo", "maquina", "installation_id", "ultimo_envio_nuvem", "aulas_30d_nuvem",
    "ultima_aula_pendrive", "ultimo_dado", "dias_sem_dados", "situacao",
]
# Campos que a view já entrega com o mesmo nome; o resto da linha é calculado aqui.
CAMPOS_FONTE = COLUNAS_AULAS[:-3]

ENCERRAMENTO_LEIGO = {
    "instrutor": "instrutor",
    "tempo": "limite de 3 h",
    "sem_encerramento": "computador desligado ou suspenso",
    # Turma esquecida aberta: não é problema por si só; 0 versões salvas continua sendo "sem SPIKE".
    "inatividade": "sem uso do SPIKE por 40 min",
}

# Questionário do fim da aula (instrumento bancada-3.2.0, apps/student-pwa/lib/contracts.js).
TIPOS_QUESTIONARIO = {"bancada_result_recorded": "bancada", "student_feedback_recorded": "crianca"}
RECUSA = "recusou"
ITEM_LINHA, ITEM_CORRIDA, ITEM_QUIZ = "bancada_linha_v1", "bancada_corrida_v1", "bancada_quiz_v1"
ITENS_BANCADA = {
    ITEM_LINHA: ("sim", "em_parte", "nao"),
    ITEM_CORRIDA: ("ganhamos", "terminamos_sem_ganhar", "nao_terminamos", "nao_participamos"),
    ITEM_QUIZ: ("quase_todas", "metade", "poucas", "sem_quiz"),
}
ITENS_CRIANCA = {
    "crianca_gostou_v1": (4, "Eu gostei da aula de robótica."),
    "crianca_outra_aula_v1": (5, "Eu queria ter outra aula de robótica."),
    "crianca_confianca_antes_v1": (6, "Antes da aula, eu achava que conseguia programar um robô."),
    "crianca_confianca_agora_v1": (7, "Agora, eu acho que consigo programar um robô."),
    "crianca_ajudou_v1": (8, "Na minha bancada, eu consegui ajudar a montar ou programar."),
}
ITEM_CONFIANCA_ANTES, ITEM_CONFIANCA_AGORA = "crianca_confianca_antes_v1", "crianca_confianca_agora_v1"
ESCALA_CRIANCA = {"nao": 0, "mais_ou_menos": 1, "sim": 2}
LIMITE_RESPOSTAS_CRIANCA = 8      # mais que isso numa aula: bancada com mais respostas que crianças
LIMITE_MINUTOS_DEPOIS_INICIO = 180  # resposta gravada mais de 3 h depois do início da aula

COLUNAS_CARRINHO = [
    "polo", "mes", "bancadas_responderam",
    "linha_respostas", "pct_linha_ate_o_fim", "pct_linha_em_parte", "pct_linha_nao", "linha_recusas",
    "corrida_participaram", "pct_corrida_ganharam", "pct_corrida_terminaram_sem_ganhar", "pct_corrida_nao_terminaram",
    "corrida_nao_participaram", "corrida_recusas",
    "quiz_tiveram", "pct_quiz_quase_todas", "pct_quiz_metade", "pct_quiz_poucas", "quiz_sem_jogo", "quiz_recusas",
]
COLUNAS_CRIANCAS = ["polo", "mes", "numero", "item_id", "pergunta", "respostas", "pct_sim", "pct_mais_ou_menos", "pct_nao", "recusas"]
COLUNAS_CRIANCAS_RESUMO = [
    "polo", "mes", "criancas_responderam", "pares_autoconfianca",
    "pct_sim_antes", "pct_sim_agora", "pct_melhorou", "pct_igual", "pct_piorou",
]
COLUNAS_SINALIZACOES = ["polo", "maquina", "session_id", "data_local", "motivo"]


# ---------------------------------------------------------------------------
# Conversões
# ---------------------------------------------------------------------------

def parse_iso(text) -> dt.datetime | None:
    """ISO 8601 do bridge (com Z e milissegundos) ou do PostgREST; sem fuso, assume UTC."""
    if not text or not isinstance(text, str):
        return None
    raw = text.strip().replace(" ", "T", 1)
    if raw.endswith("Z"):
        raw = raw[:-1] + "+00:00"
    raw = re.sub(r"(\.\d{6})\d+", r"\1", raw)
    raw = re.sub(r"\.(\d{1,5})(?=[+-]|$)", lambda m: "." + m.group(1).ljust(6, "0"), raw)
    try:
        value = dt.datetime.fromisoformat(raw)
    except ValueError:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=dt.timezone.utc)
    return value


def local(value: dt.datetime | None) -> dt.datetime | None:
    return value.astimezone(FUSO_LOCAL) if value else None


def numero(val) -> float | None:
    if isinstance(val, bool) or val is None:
        return None
    if isinstance(val, (int, float)):
        return float(val)
    try:
        return float(str(val))
    except ValueError:
        return None


def inteiro(val) -> int | None:
    n = numero(val)
    return None if n is None else int(round(n))


def booleano(val) -> bool | None:
    if isinstance(val, bool):
        return val
    if isinstance(val, int) and val in (0, 1):
        return bool(val)
    return None


def texto(val) -> str | None:
    if val is None or isinstance(val, (dict, list)):
        return None
    t = str(val).strip()
    return t or None


def carregar_json(raw) -> dict:
    if not raw:
        return {}
    try:
        data = json.loads(raw)
    except (TypeError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


# ---------------------------------------------------------------------------
# Nuvem (Supabase REST)
# ---------------------------------------------------------------------------

def credenciais_nuvem() -> tuple[str, str] | None:
    """Mesmas variáveis e configs do importador. Nunca imprime a chave."""
    url, key = imp.load_operational_credentials(ROOT)
    if not url or not key or imp.is_anon_key(key):
        return None
    return url, key


def buscar_nuvem(url: str, key: str, recurso: str, filtros: list[tuple[str, str]], ordem: str) -> list[dict]:
    api_key = key if imp.is_service_role_key(key) else imp.DEFAULT_SUPABASE_ANON_KEY
    linhas: list[dict] = []
    pagina = 1000
    inicio = 0
    while True:
        params = [("select", "*"), *filtros, ("order", ordem), ("limit", str(pagina)), ("offset", str(inicio))]
        endpoint = f"{url.rstrip('/')}/rest/v1/{recurso}?{urllib.parse.urlencode(params)}"
        req = urllib.request.Request(endpoint, headers={
            "apikey": api_key,
            "Authorization": f"Bearer {key}",
            "Accept": "application/json",
        })
        with urllib.request.urlopen(req, timeout=30) as resp:
            lote = json.loads(resp.read().decode("utf-8"))
        if not isinstance(lote, list):
            break
        linhas.extend(r for r in lote if isinstance(r, dict))
        if len(lote) < pagina:
            break
        inicio += pagina
    return linhas


def descrever_erro(exc: Exception) -> str:
    """Erro de rede sem cabeçalhos nem URL com credencial."""
    if isinstance(exc, urllib.error.HTTPError):
        detalhe = ""
        try:
            corpo = json.loads(exc.read().decode("utf-8", errors="replace"))
            detalhe = str(corpo.get("message") or "")[:160]
        except Exception:
            pass
        return f"HTTP {exc.code}" + (f": {detalhe}" if detalhe else "")
    if isinstance(exc, urllib.error.URLError):
        return f"sem conexão ({exc.reason})"
    return type(exc).__name__


def aula_da_nuvem(row: dict) -> dict:
    aula = {c: row.get(c) for c in CAMPOS_FONTE}
    aula["session_id"] = imp.session_key(row.get("session_id"))
    for c in ("polo", "escola", "maquina", "installation_id", "encerrada_por", "fase", "modo_inicio",
              "spike_status", "client_version", "instrument_version", "hora_inicio", "hora_fim"):
        aula[c] = texto(aula.get(c))
    aula["data_local"] = texto(row.get("data_local"))
    for c in ("duracao_min", "ct_score", "maior_lacuna_min"):
        aula[c] = numero(aula.get(c))
    for c in ("versoes_programa", "blocos_executaveis", "sinais_de_vida", "reinicios", "linhas_corrompidas"):
        aula[c] = inteiro(aula.get(c))
    for c in ("interrompida", "usa_motor", "usa_sensor", "usa_laco", "usa_condicao"):
        aula[c] = booleano(aula.get(c))
    aula["_inicio"] = parse_iso(row.get("inicio_em"))
    aula["origem"] = "nuvem"
    return aula


def maquina_da_nuvem(row: dict) -> dict:
    return {
        "installation_id": texto(row.get("installation_id")),
        "polo": texto(row.get("site_id")),
        "ultimo_envio": parse_iso(row.get("last_received_at")),
        "ultima_ocorrencia": parse_iso(row.get("last_occurred_at")),
        "aulas_30d": inteiro(row.get("sessions_last_30d")),
    }


# ---------------------------------------------------------------------------
# SQLite consolidado (importador --no-cloud)
# ---------------------------------------------------------------------------

def ler_sqlite(path: Path) -> tuple[list[dict], set[str]]:
    """Aulas do SQLite do importador e o conjunto de sessões retiradas."""
    conn = sqlite3.connect(str(path))
    conn.row_factory = sqlite3.Row
    try:
        tabelas = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
        retiradas: set[str] = set()
        if "withdrawn_sessions" in tabelas:
            retiradas = {imp.session_key(r[0]) for r in conn.execute("SELECT session_id FROM withdrawn_sessions") if r[0]}
        if "sessions" not in tabelas:
            return [], retiradas
        # Aulas marcadas como não autorizadas nunca entram no relatório (revisão do pesquisador decide).
        nao_autorizadas: set[str] = set()
        if "unauthorized_sessions" in tabelas:
            nao_autorizadas = {
                imp.session_key(r[0])
                for r in conn.execute("SELECT session_id FROM unauthorized_sessions WHERE status = 'nao_autorizada'")
                if r[0]
            }

        eventos: dict[str, list[tuple[str, dict]]] = {}
        if "session_events" in tabelas:
            for r in conn.execute(
                "SELECT session_id, event_type, details_json FROM session_events "
                "WHERE event_type IN ('spike_telemetry', 'session_started') "
                "ORDER BY session_id, coalesce(occurred_at, timestamp), rowid"
            ):
                eventos.setdefault(imp.session_key(r["session_id"]), []).append((r["event_type"], carregar_json(r["details_json"])))
            com_eventos = {imp.session_key(r[0]) for r in conn.execute("SELECT DISTINCT session_id FROM session_events")}
        else:
            com_eventos = set()

        aulas = []
        for r in conn.execute("SELECT * FROM sessions"):
            row = dict(r)
            sid = imp.session_key(row.get("session_id"))
            if not sid or sid in nao_autorizadas:
                continue
            aulas.append(aula_do_sqlite(row, sid, eventos.get(sid, []), sid in com_eventos))
        return aulas, retiradas
    finally:
        conn.close()


def aula_do_sqlite(row: dict, sid: str, eventos: list[tuple[str, dict]], tem_eventos: bool) -> dict:
    dq = carregar_json(row.get("data_quality_json"))
    telemetria = [d for tipo, d in eventos if tipo == "spike_telemetry"]
    inicio_ev = next((d for tipo, d in eventos if tipo == "session_started"), {})
    ultima = telemetria[-1] if telemetria else {}

    fase = "completed" if row.get("status") == "completed" else "in_progress"
    inicio = parse_iso(row.get("started_at"))
    fim = parse_iso(row.get("completed_at")) if fase == "completed" else None
    duracao = None
    if fase == "completed":
        segundos = numero(row.get("duration_seconds"))
        if segundos:
            duracao = round(segundos / 60, 1)
        elif inicio and fim:
            duracao = round((fim - inicio).total_seconds() / 60, 1)

    versoes = inteiro(dq.get("telemetry_events"))
    if versoes is None and tem_eventos:
        versoes = len(telemetria)
    ct = ultima.get("ct_score")
    inicio_local, fim_local = local(inicio), local(fim)

    return {
        "session_id": sid,
        "polo": texto(row.get("site_id")),
        "escola": texto(row.get("school_code")),
        "maquina": texto(row.get("machine_label")),
        "installation_id": imp.session_key(row.get("installation_id")) if texto(row.get("installation_id")) else None,
        "data_local": inicio_local.date().isoformat() if inicio_local else None,
        "hora_inicio": inicio_local.strftime("%H:%M") if inicio_local else None,
        "hora_fim": fim_local.strftime("%H:%M") if fim_local else None,
        "duracao_min": duracao,
        "encerrada_por": texto(row.get("ended_by")),
        "interrompida": booleano(row.get("interrupted")),
        "fase": fase,
        "modo_inicio": texto(row.get("start_mode")) or texto(inicio_ev.get("start_mode")),
        "versoes_programa": versoes,
        "blocos_executaveis": inteiro(ultima.get("executable_blocks")),
        "usa_motor": booleano(ultima.get("uses_motor")),
        "usa_sensor": booleano(ultima.get("uses_sensor")),
        "usa_laco": booleano(ultima.get("uses_loop")),
        "usa_condicao": booleano(ultima.get("uses_condition")),
        "ct_score": numero(ct.get("total")) if isinstance(ct, dict) else None,
        "spike_status": texto(dq.get("spike_status")) or texto(ultima.get("spike_status")),
        "sinais_de_vida": inteiro(dq.get("heartbeat_count")),
        "maior_lacuna_min": numero(dq.get("max_heartbeat_gap_min")),
        "reinicios": inteiro(dq.get("bridge_restarts")),
        "linhas_corrompidas": inteiro(dq.get("corrupted_lines")),
        "client_version": texto(row.get("client_version")),
        "instrument_version": texto(row.get("instrument_version")) or texto(inicio_ev.get("instrument_version")),
        "origem": "pendrive",
        "_inicio": inicio,
    }


# ---------------------------------------------------------------------------
# Questionário do fim da aula: leitura (nuvem e SQLite)
# ---------------------------------------------------------------------------

def resposta(event_id, session_id, parte, item_id, valor, envio_id, respondido_em, polo, maquina,
             installation_id, minutos, origem) -> dict | None:
    """Uma resposta normalizada; None se não for do instrumento (códigos fora da lista)."""
    item_id, valor = texto(item_id), texto(valor)
    validos = ITENS_BANCADA.get(item_id) if parte == "bancada" else (tuple(ESCALA_CRIANCA) if item_id in ITENS_CRIANCA else None)
    if not validos or (valor not in validos and valor != RECUSA):
        return None
    sid = imp.session_key(session_id)
    quando = respondido_em if isinstance(respondido_em, dt.datetime) else parse_iso(respondido_em)
    if not sid or not quando:
        return None
    data_local = local(quando).date()
    return {
        "event_id": (texto(event_id) or "").lower() or None,
        "session_id": sid,
        "parte": parte,
        "item_id": item_id,
        "valor": valor,
        "envio_id": (texto(envio_id) or "").lower() or None,
        "respondido_em": quando,
        "data_local": data_local.isoformat(),
        "mes": data_local.strftime("%Y-%m"),
        "polo": texto(polo),
        "maquina": texto(maquina),
        "installation_id": texto(installation_id),
        "minutos_desde_inicio": numero(minutos),
        "origem": origem,
    }


def resposta_da_nuvem(row: dict) -> dict | None:
    parte = texto(row.get("parte"))
    if parte not in ("bancada", "crianca") or row.get("ambiente") == "test":
        return None
    return resposta(row.get("event_id"), row.get("session_id"), parte, row.get("item_id"), row.get("valor"),
                    row.get("envio_id"), row.get("respondido_em"), row.get("polo"), row.get("maquina"),
                    row.get("installation_id"), row.get("minutos_desde_inicio"), "nuvem")


def sem_envios_invalidos(pares: list[tuple[dict | None, tuple]]) -> list[dict]:
    """Descarta o envio inteiro quando uma das respostas dele está fora do instrumento.

    pares: (resposta normalizada ou None, (session_id, envio_id) da linha de origem)."""
    invalidos = {chave for item, chave in pares if item is None and chave[0] and chave[1]}
    return [item for item, chave in pares if item is not None and chave not in invalidos]


def respostas_da_nuvem(rows: list[dict]) -> list[dict]:
    pares = []
    for row in rows:
        if row.get("ambiente") == "test" or texto(row.get("parte")) not in ("bancada", "crianca"):
            continue
        chave = (imp.session_key(row.get("session_id")), (texto(row.get("envio_id")) or "").lower())
        pares.append((resposta_da_nuvem(row), chave))
    return sem_envios_invalidos(pares)


def ler_questionario_sqlite(path: Path) -> list[dict]:
    """Respostas do questionário no SQLite do importador, sem aulas não autorizadas ou retiradas."""
    conn = sqlite3.connect(str(path))
    conn.row_factory = sqlite3.Row
    try:
        tabelas = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
        if "session_events" not in tabelas:
            return []
        fora: set[str] = set()
        if "withdrawn_sessions" in tabelas:
            fora |= {imp.session_key(r[0]) for r in conn.execute("SELECT session_id FROM withdrawn_sessions") if r[0]}
        if "unauthorized_sessions" in tabelas:
            fora |= {imp.session_key(r[0]) for r in conn.execute(
                "SELECT session_id FROM unauthorized_sessions WHERE status = 'nao_autorizada'") if r[0]}
        sessoes: dict[str, dict] = {}
        if "sessions" in tabelas:
            colunas = {r[1] for r in conn.execute("PRAGMA table_info(sessions)")}
            for r in conn.execute("SELECT * FROM sessions"):
                row = dict(r)
                sessoes[imp.session_key(row.get("session_id"))] = {
                    "polo": row.get("site_id"),
                    "maquina": row.get("machine_label") if "machine_label" in colunas else None,
                    "installation_id": row.get("installation_id") if "installation_id" in colunas else None,
                    "inicio": parse_iso(row.get("started_at")),
                }
        pares = []
        marcadores = ",".join("?" for _ in TIPOS_QUESTIONARIO)
        for r in conn.execute(
            f"SELECT event_id, session_id, event_type, occurred_at, timestamp, details_json FROM session_events "
            f"WHERE event_type IN ({marcadores}) ORDER BY coalesce(occurred_at, timestamp), rowid",
            tuple(TIPOS_QUESTIONARIO),
        ):
            sid = imp.session_key(r["session_id"])
            if not sid or sid in fora:
                continue
            det = carregar_json(r["details_json"])
            sessao = sessoes.get(sid, {})
            quando = parse_iso(r["occurred_at"] or r["timestamp"])
            minutos = det.get("minutes_since_session_start")
            if numero(minutos) is None and quando and sessao.get("inicio"):
                minutos = round((quando - sessao["inicio"]).total_seconds() / 60, 1)
            item = resposta(r["event_id"], sid, TIPOS_QUESTIONARIO[r["event_type"]], det.get("item_id"), det.get("value"),
                            det.get("submission_id"), quando, sessao.get("polo"), sessao.get("maquina"),
                            sessao.get("installation_id"), minutos, "pendrive")
            pares.append((item, (sid, (texto(det.get("submission_id")) or "").lower())))
        return sem_envios_invalidos(pares)
    finally:
        conn.close()


def juntar_respostas(*fontes: list[dict], retiradas: set[str] = frozenset()) -> list[dict]:
    """Uma linha por evento (a mesma resposta pode chegar pela nuvem e pelo pendrive)."""
    vistas: dict[str, dict] = {}
    for fonte in fontes:
        for r in fonte:
            if not r or r["session_id"] in retiradas:
                continue
            chave = r.get("event_id") or f"{r['session_id']}|{r.get('envio_id')}|{r['item_id']}"
            atual = vistas.get(chave)
            if atual is None:
                vistas[chave] = dict(r)
                continue
            for campo, valor in r.items():
                if vazio(atual.get(campo)) and not vazio(valor):
                    atual[campo] = valor
            atual["origem"] = "+".join(o for o in ("nuvem", "pendrive") if o in f"{atual['origem']}+{r['origem']}")
    return sorted(vistas.values(), key=lambda r: (r["respondido_em"], r["session_id"], r["item_id"]))


def filtrar_respostas(respostas: list[dict], de: str | None, ate: str | None, polo: str | None) -> list[dict]:
    return [r for r in respostas
            if (not de or r["data_local"] >= de) and (not ate or r["data_local"] <= ate)
            and (not polo or (r.get("polo") or "").casefold() == polo.casefold())]


# ---------------------------------------------------------------------------
# Junção, filtros e indicadores
# ---------------------------------------------------------------------------

def vazio(val) -> bool:
    return val is None or val == ""


def juntar_aulas(*fontes: list[dict], retiradas: set[str] = frozenset()) -> list[dict]:
    """Uma linha por session_id. A aula encerrada prevalece; empate fica com a primeira fonte (nuvem).
    Campos ausentes na linha escolhida são completados pela outra fonte."""
    por_id: dict[str, dict] = {}
    for fonte in fontes:
        for aula in fonte:
            sid = aula.get("session_id")
            if not sid or sid in retiradas:
                continue
            atual = por_id.get(sid)
            if atual is None:
                por_id[sid] = dict(aula)
                continue
            if atual.get("fase") != "completed" and aula.get("fase") == "completed":
                base, outra = aula, atual
            else:
                base, outra = atual, aula
            junta = dict(base)
            for campo, valor in outra.items():
                if vazio(junta.get(campo)) and not vazio(valor):
                    junta[campo] = valor
            origens = set(base["origem"].split("+")) | set(outra["origem"].split("+"))
            junta["origem"] = "+".join(o for o in ("nuvem", "pendrive") if o in origens)
            por_id[sid] = junta
    aulas = list(por_id.values())
    for aula in aulas:
        motivos = motivos_qualidade(aula)
        aula["qualidade"] = "ruim" if motivos else "boa"
        aula["motivo_qualidade"] = "; ".join(motivos)
    aulas.sort(key=lambda a: (a.get("data_local") or "", a.get("hora_inicio") or "", a.get("polo") or "", a.get("maquina") or ""))
    return aulas


def motivos_qualidade(aula: dict) -> list[str]:
    motivos = []
    if aula.get("fase") != "completed":
        motivos.append("aula não encerrada")
    if aula.get("interrompida") is True:
        motivos.append("interrompida")
    if aula.get("versoes_programa") == 0:
        motivos.append("nenhum programa salvo")
    if aula.get("spike_status") in SPIKE_COM_PROBLEMA:
        motivos.append(f"problema no SPIKE ({aula['spike_status']})")
    return motivos


def filtrar(aulas: list[dict], de: str | None, ate: str | None, polo: str | None) -> list[dict]:
    out = []
    for a in aulas:
        data = a.get("data_local") or ""
        if de and (not data or data < de):
            continue
        if ate and (not data or data > ate):
            continue
        if polo and (a.get("polo") or "").casefold() != polo.casefold():
            continue
        out.append(a)
    return out


def sessao_vazia(aula: dict) -> bool:
    """PC ligado sem aula: fechou por inatividade sem nenhum programa salvo. Não conta como aula."""
    return aula.get("encerrada_por") == "inatividade" and not aula.get("versoes_programa")


def chave_maquina(aula: dict) -> str | None:
    return aula.get("installation_id") or aula.get("maquina")


def pct(parte: int, total: int) -> float | None:
    return round(100.0 * parte / total, 1) if total else None


def indicadores(aulas: list[dict]) -> dict:
    duracoes = [a["duracao_min"] for a in aulas if a.get("duracao_min") is not None]
    total = len(aulas)
    return {
        "aulas": total,
        "maquinas": len({k for k in (chave_maquina(a) for a in aulas) if k}),
        "duracao_mediana_min": round(statistics.median(duracoes), 1) if duracoes else None,
        "pct_encerradas_instrutor": pct(sum(1 for a in aulas if a.get("encerrada_por") == "instrutor"), total),
        "pct_interrompidas": pct(sum(1 for a in aulas if a.get("interrompida") is True), total),
        "pct_sem_spike": pct(sum(1 for a in aulas if a.get("versoes_programa") == 0), total),
    }


def resumo_polos(aulas: list[dict]) -> list[dict]:
    grupos: dict[tuple[str, str], list[dict]] = {}
    for a in aulas:
        if not a.get("data_local"):
            continue
        dia = dt.date.fromisoformat(a["data_local"])
        semana = (dia - dt.timedelta(days=dia.weekday())).isoformat()
        grupos.setdefault((a.get("polo") or "", semana), []).append(a)
    linhas = []
    for (polo, semana), grupo in sorted(grupos.items()):
        linhas.append({"polo": polo, "semana_inicio": semana, **indicadores(grupo)})
    return linhas


def maquinas_sem_envio(
    maquinas_nuvem: list[dict], todas_aulas: list[dict], hoje: dt.date, polo: str | None
) -> list[dict]:
    """Uma linha por máquina conhecida (nuvem ou SQLite), da que está há mais tempo sem dados."""
    maquinas: dict[str, dict] = {}

    def item(chave: str) -> dict:
        return maquinas.setdefault(chave, {
            "installation_id": None, "polo": None, "maquina": None, "ultimo_envio": None,
            "ultima_ocorrencia": None, "aulas_30d": None, "ultima_aula_pendrive": None, "_rotulo_em": None,
        })

    for m in maquinas_nuvem:
        if not m.get("installation_id"):
            continue
        reg = item(m["installation_id"])
        reg.update({k: v for k, v in m.items() if v is not None})

    for a in todas_aulas:
        chave = chave_maquina(a)
        if not chave:
            continue
        reg = item(chave)
        reg["installation_id"] = reg["installation_id"] or a.get("installation_id")
        reg["polo"] = reg["polo"] or a.get("polo")
        inicio = a.get("_inicio")
        if a.get("maquina") and (reg["_rotulo_em"] is None or (inicio and inicio > reg["_rotulo_em"])):
            reg["maquina"] = a["maquina"]
            reg["_rotulo_em"] = inicio or reg["_rotulo_em"]
        if "pendrive" in a.get("origem", "") and inicio and (reg["ultima_aula_pendrive"] is None or inicio > reg["ultima_aula_pendrive"]):
            reg["ultima_aula_pendrive"] = inicio

    linhas = []
    for reg in maquinas.values():
        if polo and (reg.get("polo") or "").casefold() != polo.casefold():
            continue
        datas = [d for d in (reg["ultimo_envio"], reg["ultima_ocorrencia"], reg["ultima_aula_pendrive"]) if d]
        ultimo = max(datas) if datas else None
        dias = (hoje - local(ultimo).date()).days if ultimo else None
        if ultimo is None:
            situacao = "nunca enviou dados"
        elif dias > DIAS_SEM_DADOS:
            situacao = f"sem dados há mais de {DIAS_SEM_DADOS} dias"
        else:
            situacao = "ok"
        linhas.append({
            "polo": reg["polo"],
            "maquina": reg["maquina"],
            "installation_id": reg["installation_id"],
            "ultimo_envio_nuvem": formatar_data_hora(reg["ultimo_envio"]),
            "aulas_30d_nuvem": reg["aulas_30d"],
            "ultima_aula_pendrive": local(reg["ultima_aula_pendrive"]).date().isoformat() if reg["ultima_aula_pendrive"] else None,
            "ultimo_dado": local(ultimo).date().isoformat() if ultimo else None,
            "dias_sem_dados": dias,
            "situacao": situacao,
        })
    linhas.sort(key=lambda m: (-(m["dias_sem_dados"] if m["dias_sem_dados"] is not None else 10**6), m["polo"] or "", m["maquina"] or ""))
    return linhas


def formatar_data_hora(value: dt.datetime | None) -> str | None:
    return local(value).strftime("%Y-%m-%d %H:%M") if value else None


# ---------------------------------------------------------------------------
# Questionário do fim da aula: indicadores
# ---------------------------------------------------------------------------

def por_polo_mes(itens: list[dict]) -> dict[tuple[str, str], list[dict]]:
    grupos: dict[tuple[str, str], list[dict]] = {}
    for item in itens:
        grupos.setdefault((item.get("polo") or "", item["mes"]), []).append(item)
    return dict(sorted(grupos.items()))


def resultados_bancada(respostas: list[dict]) -> list[dict]:
    """Uma linha por aula (bancada) com as três respostas; vale o primeiro envio da aula."""
    por_sessao: dict[str, dict] = {}
    for r in respostas:
        if r["parte"] != "bancada":
            continue
        aula = por_sessao.setdefault(r["session_id"], {
            "session_id": r["session_id"], "polo": r.get("polo"), "mes": r["mes"], "envio_id": r.get("envio_id"), "itens": {},
        })
        if aula["envio_id"] and r.get("envio_id") and r["envio_id"] != aula["envio_id"]:
            continue
        aula["itens"].setdefault(r["item_id"], r["valor"])
    return list(por_sessao.values())


def testes_carrinho(respostas: list[dict]) -> list[dict]:
    linhas = []
    for (polo, mes), aulas in por_polo_mes(resultados_bancada(respostas)).items():
        def contar(item: str) -> dict[str, int]:
            cont: dict[str, int] = {}
            for a in aulas:
                valor = a["itens"].get(item)
                if valor:
                    cont[valor] = cont.get(valor, 0) + 1
            return cont

        linha, corrida, quiz = contar(ITEM_LINHA), contar(ITEM_CORRIDA), contar(ITEM_QUIZ)
        n_linha = sum(v for k, v in linha.items() if k != RECUSA)
        n_corrida = sum(corrida.get(k, 0) for k in ("ganhamos", "terminamos_sem_ganhar", "nao_terminamos"))
        n_quiz = sum(quiz.get(k, 0) for k in ("quase_todas", "metade", "poucas"))
        linhas.append({
            "polo": polo, "mes": mes, "bancadas_responderam": len(aulas),
            "linha_respostas": n_linha,
            "pct_linha_ate_o_fim": pct(linha.get("sim", 0), n_linha),
            "pct_linha_em_parte": pct(linha.get("em_parte", 0), n_linha),
            "pct_linha_nao": pct(linha.get("nao", 0), n_linha),
            "linha_recusas": linha.get(RECUSA, 0),
            "corrida_participaram": n_corrida,
            "pct_corrida_ganharam": pct(corrida.get("ganhamos", 0), n_corrida),
            "pct_corrida_terminaram_sem_ganhar": pct(corrida.get("terminamos_sem_ganhar", 0), n_corrida),
            "pct_corrida_nao_terminaram": pct(corrida.get("nao_terminamos", 0), n_corrida),
            "corrida_nao_participaram": corrida.get("nao_participamos", 0),
            "corrida_recusas": corrida.get(RECUSA, 0),
            "quiz_tiveram": n_quiz,
            "pct_quiz_quase_todas": pct(quiz.get("quase_todas", 0), n_quiz),
            "pct_quiz_metade": pct(quiz.get("metade", 0), n_quiz),
            "pct_quiz_poucas": pct(quiz.get("poucas", 0), n_quiz),
            "quiz_sem_jogo": quiz.get("sem_quiz", 0),
            "quiz_recusas": quiz.get(RECUSA, 0),
        })
    return linhas


def envios_criancas(respostas: list[dict]) -> list[dict]:
    """Uma rodada por criança: as respostas do mesmo envio (submission_id) na mesma aula."""
    envios: dict[tuple[str, str], dict] = {}
    for r in respostas:
        if r["parte"] != "crianca":
            continue
        chave = (r["session_id"], r.get("envio_id") or r.get("event_id") or "")
        envio = envios.setdefault(chave, {"session_id": r["session_id"], "polo": r.get("polo"), "mes": r["mes"], "itens": {}})
        envio["itens"].setdefault(r["item_id"], r["valor"])
    return list(envios.values())


def criancas_por_pergunta(respostas: list[dict]) -> list[dict]:
    linhas = []
    for (polo, mes), envios in por_polo_mes(envios_criancas(respostas)).items():
        for item_id, (numero_item, pergunta) in ITENS_CRIANCA.items():
            valores = [e["itens"][item_id] for e in envios if item_id in e["itens"]]
            validas = [v for v in valores if v != RECUSA]
            linhas.append({
                "polo": polo, "mes": mes, "numero": numero_item, "item_id": item_id, "pergunta": pergunta,
                "respostas": len(validas),
                "pct_sim": pct(validas.count("sim"), len(validas)),
                "pct_mais_ou_menos": pct(validas.count("mais_ou_menos"), len(validas)),
                "pct_nao": pct(validas.count("nao"), len(validas)),
                "recusas": valores.count(RECUSA),
            })
    return linhas


def criancas_resumo(respostas: list[dict]) -> list[dict]:
    """Autoconfiança: pergunta 6 (antes) contra 7 (agora), só com as duas respondidas no mesmo envio."""
    linhas = []
    for (polo, mes), envios in por_polo_mes(envios_criancas(respostas)).items():
        pares = [(ESCALA_CRIANCA[e["itens"][ITEM_CONFIANCA_ANTES]], ESCALA_CRIANCA[e["itens"][ITEM_CONFIANCA_AGORA]])
                 for e in envios
                 if e["itens"].get(ITEM_CONFIANCA_ANTES) in ESCALA_CRIANCA and e["itens"].get(ITEM_CONFIANCA_AGORA) in ESCALA_CRIANCA]
        n = len(pares)
        linhas.append({
            "polo": polo, "mes": mes, "criancas_responderam": len(envios), "pares_autoconfianca": n,
            "pct_sim_antes": pct(sum(1 for a, _ in pares if a == ESCALA_CRIANCA["sim"]), n),
            "pct_sim_agora": pct(sum(1 for _, b in pares if b == ESCALA_CRIANCA["sim"]), n),
            "pct_melhorou": pct(sum(1 for a, b in pares if b > a), n),
            "pct_igual": pct(sum(1 for a, b in pares if b == a), n),
            "pct_piorou": pct(sum(1 for a, b in pares if b < a), n),
        })
    return linhas


def sinalizacoes_questionario(respostas: list[dict]) -> list[dict]:
    """Aulas a conferir: mais de 8 crianças responderam, ou respostas gravadas mais de 3 h depois do início."""
    por_sessao: dict[str, list[dict]] = {}
    for r in respostas:
        por_sessao.setdefault(r["session_id"], []).append(r)
    linhas = []
    for sid, itens in por_sessao.items():
        base = {"polo": itens[0].get("polo"), "maquina": next((r["maquina"] for r in itens if r.get("maquina")), None),
                "session_id": sid, "data_local": min(r["data_local"] for r in itens)}
        envios = {r.get("envio_id") or r.get("event_id") for r in itens if r["parte"] == "crianca"}
        if len(envios) > LIMITE_RESPOSTAS_CRIANCA:
            linhas.append({**base, "motivo": f"{len(envios)} respostas individuais na aula (mais de {LIMITE_RESPOSTAS_CRIANCA})"})
        tarde = [r for r in itens if (r.get("minutos_desde_inicio") or 0) > LIMITE_MINUTOS_DEPOIS_INICIO]
        if tarde:
            horas = max(r["minutos_desde_inicio"] for r in tarde) / 60
            linhas.append({**base, "motivo": f"{len(tarde)} resposta(s) gravada(s) mais de 3 h depois do início da aula (até {br_num(round(horas, 1))} h)"})
    linhas.sort(key=lambda s: (s["data_local"], s["polo"] or "", s["maquina"] or "", s["motivo"]))
    return linhas


def mes_leigo(mes: str) -> str:
    ano, m = mes.split("-")
    return f"{m}/{ano}"


# ---------------------------------------------------------------------------
# Saída
# ---------------------------------------------------------------------------

def celula_csv(val) -> str:
    """CSV para Excel em português: ponto e vírgula, vírgula decimal, sim/não."""
    if val is None:
        return ""
    if isinstance(val, bool):
        return "sim" if val else "não"
    if isinstance(val, float):
        return f"{val:.1f}".replace(".", ",")
    return str(val)


def escrever_csv(path: Path, colunas: list[str], linhas: list[dict]) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f, delimiter=";", lineterminator="\r\n")
        w.writerow(colunas)
        for linha in linhas:
            w.writerow([celula_csv(linha.get(c)) for c in colunas])


def br_num(val, sufixo: str = "") -> str:
    if val is None:
        return "–"
    if isinstance(val, float):
        txt = f"{val:.1f}".replace(".", ",")
        if txt.endswith(",0"):
            txt = txt[:-2]
        return txt + sufixo
    return f"{val}{sufixo}"


def br_data(iso: str | None) -> str:
    if not iso:
        return "–"
    d = dt.date.fromisoformat(iso[:10])
    return d.strftime("%d/%m/%Y")


def md_celula(val) -> str:
    return str(val).replace("|", "/") if val not in (None, "") else "–"


def md_tabela(cabecalho: list[str], linhas: list[list]) -> str:
    out = ["| " + " | ".join(cabecalho) + " |", "|" + "|".join("---" for _ in cabecalho) + "|"]
    for linha in linhas:
        out.append("| " + " | ".join(md_celula(c) for c in linha) + " |")
    return "\n".join(out)


def gerar_markdown(
    aulas: list[dict], resumo: list[dict], maquinas: list[dict], hoje: dt.date,
    de: str | None, ate: str | None, polo: str | None, fontes: list[str], avisos: list[str],
    questionario: dict | None = None,
) -> str:
    q = questionario or {"carrinho": [], "criancas": [], "resumo": [], "sinalizacoes": []}
    ind = indicadores(aulas)
    if de or ate:
        periodo = f"{br_data(de) if de else 'início'} a {br_data(ate) if ate else 'hoje'}"
    else:
        periodo = "todas as aulas registradas"
    polos = sorted({a.get("polo") for a in aulas if a.get("polo")})

    partes = [
        f"# Relatório PulseLab — {hoje.strftime('%d/%m/%Y')}",
        "",
        f"- **Período:** {periodo}",
        f"- **Polo:** {polo or 'todos'}",
        f"- **Dados de:** {', '.join(fontes) if fontes else 'nenhuma fonte'}",
    ]
    for aviso in avisos:
        partes.append(f"- **Aviso:** {aviso}")
    partes += [
        "",
        "Cada linha de dados é uma **aula de bancada**: o que um computador registrou durante uma turma.",
        "Não há nomes nem dados de crianças.",
        "",
        "## Resumo",
        "",
        f"- **{ind['aulas']}** aulas de bancada em **{len(polos)}** polo(s) e **{ind['maquinas']}** máquina(s).",
        f"- Duração mediana de uma aula: **{br_num(ind['duracao_mediana_min'], ' min')}**.",
        f"- Encerradas pelo instrutor no ícone da bandeja: **{br_num(ind['pct_encerradas_instrutor'], '%')}**.",
        f"- Interrompidas (computador desligado ou PulseLab reiniciado no meio): **{br_num(ind['pct_interrompidas'], '%')}**.",
        f"- Sem nenhum programa salvo no SPIKE: **{br_num(ind['pct_sem_spike'], '%')}**.",
        f"- Questionário do fim da aula: **{sum(r['bancadas_responderam'] for r in q['carrinho'])}** bancada(s) e"
        f" **{sum(r['criancas_responderam'] for r in q['resumo'])}** criança(s) responderam.",
        "",
        "## Atenção",
        "",
        f"### Máquinas sem dados há mais de {DIAS_SEM_DADOS} dias",
        "",
    ]
    paradas = [m for m in maquinas if m["situacao"] != "ok"]
    if paradas:
        partes.append(md_tabela(
            ["Polo", "Máquina", "Último dado", "Dias sem dados", "Situação"],
            [[m["polo"], m["maquina"] or (m["installation_id"] or "")[:8], br_data(m["ultimo_dado"]) if m["ultimo_dado"] else None,
              m["dias_sem_dados"], m["situacao"]] for m in paradas],
        ))
        partes += ["", "Verifique se o computador foi ligado, se tem internet ou se os dados precisam vir por pendrive."]
    elif maquinas:
        partes.append("Nenhuma. Todas as máquinas mandaram dados nos últimos dias.")
    else:
        partes.append("Sem lista de máquinas: nenhuma fonte trouxe máquinas identificadas.")

    ruins = [a for a in aulas if a.get("qualidade") == "ruim"]
    partes += ["", "### Aulas com qualidade ruim", ""]
    if ruins:
        partes.append(md_tabela(
            ["Data", "Início", "Polo", "Máquina", "Motivo"],
            [[br_data(a.get("data_local")), a.get("hora_inicio"), a.get("polo"), a.get("maquina"), a.get("motivo_qualidade")] for a in ruins],
        ))
    else:
        partes.append("Nenhuma.")

    partes += ["", "### Questionário do fim da aula a conferir", ""]
    if q["sinalizacoes"]:
        partes.append(md_tabela(
            ["Data", "Polo", "Máquina", "Motivo"],
            [[br_data(s["data_local"]), s["polo"], s["maquina"], s["motivo"]] for s in q["sinalizacoes"]],
        ))
        partes += ["", "As respostas sinalizadas continuam nas contagens: confira com o polo antes de usá-las."]
    else:
        partes.append("Nenhum.")

    partes += ["", "## Resumo semanal por polo", ""]
    if resumo:
        partes.append(md_tabela(
            ["Polo", "Semana (segunda)", "Aulas", "Máquinas", "Duração mediana", "Encerradas pelo instrutor", "Interrompidas", "Sem SPIKE"],
            [[r["polo"], br_data(r["semana_inicio"]), r["aulas"], r["maquinas"], br_num(r["duracao_mediana_min"], " min"),
              br_num(r["pct_encerradas_instrutor"], "%"), br_num(r["pct_interrompidas"], "%"), br_num(r["pct_sem_spike"], "%")] for r in resumo],
        ))
    else:
        partes.append("Nenhuma aula no período.")

    partes += [
        "", "## Testes com os carrinhos", "",
        "Perguntas 1 a 3 do questionário do fim da aula, respondidas pela bancada junto (uma vez por aula).",
        "Corrida e jogo de perguntas contam só as bancadas que participaram ou tiveram o jogo.", "",
    ]
    if q["carrinho"]:
        partes.append(md_tabela(
            ["Polo", "Mês", "Bancadas que responderam", "Seguiram a linha até o fim", "Corrida: ganharam / terminaram sem ganhar / não terminaram",
             "Jogo de perguntas: quase todas / metade / poucas"],
            [[r["polo"], mes_leigo(r["mes"]), r["bancadas_responderam"],
              f"{br_num(r['pct_linha_ate_o_fim'], '%')} de {r['linha_respostas']}",
              f"{br_num(r['pct_corrida_ganharam'], '%')} / {br_num(r['pct_corrida_terminaram_sem_ganhar'], '%')} / "
              f"{br_num(r['pct_corrida_nao_terminaram'], '%')} de {r['corrida_participaram']}",
              f"{br_num(r['pct_quiz_quase_todas'], '%')} / {br_num(r['pct_quiz_metade'], '%')} / "
              f"{br_num(r['pct_quiz_poucas'], '%')} de {r['quiz_tiveram']}"] for r in q["carrinho"]],
        ))
        partes += ["", "Recusas, bancadas que não correram e turmas sem jogo de perguntas estão em `testes-carrinho.csv`."]
    else:
        partes.append("Nenhuma bancada respondeu no período.")

    partes += [
        "", "## O que as crianças disseram", "",
        "Perguntas 4 a 8, respondidas por cada criança sozinha, sem nome. As porcentagens não contam quem tocou"
        " em \"Não quero responder\".", "",
    ]
    if q["resumo"]:
        partes.append(md_tabela(
            ["Polo", "Mês", "Pergunta", "Respostas", "Sim", "Mais ou menos", "Não", "Não quiseram responder"],
            [[r["polo"], mes_leigo(r["mes"]), f"{r['numero']}. {r['pergunta']}", r["respostas"], br_num(r["pct_sim"], "%"),
              br_num(r["pct_mais_ou_menos"], "%"), br_num(r["pct_nao"], "%"), r["recusas"]] for r in q["criancas"]],
        ))
        partes += [
            "", "### Mudança de autoconfiança (pergunta 6 contra pergunta 7)", "",
            "Só as crianças que responderam as duas perguntas no mesmo envio. \"Melhorou\" é subir de Não para Mais ou"
            " menos ou Sim, ou de Mais ou menos para Sim.", "",
            md_tabela(
                ["Polo", "Mês", "Crianças que responderam", "Com as duas respostas", "\"Sim\" antes", "\"Sim\" agora", "Melhorou"],
                [[r["polo"], mes_leigo(r["mes"]), r["criancas_responderam"], r["pares_autoconfianca"], br_num(r["pct_sim_antes"], "%"),
                  br_num(r["pct_sim_agora"], "%"), br_num(r["pct_melhorou"], "%")] for r in q["resumo"]],
            ),
        ]
    else:
        partes.append("Nenhuma criança respondeu no período.")

    partes += ["", "## Aulas", ""]
    if aulas:
        mostradas = aulas[-LIMITE_AULAS_MD:]
        if len(aulas) > LIMITE_AULAS_MD:
            partes += [f"As {LIMITE_AULAS_MD} aulas mais recentes; a lista completa está em `aulas.csv`.", ""]
        partes.append(md_tabela(
            ["Data", "Início", "Fim", "Polo", "Escola", "Máquina", "Duração", "Encerrada por", "Versões salvas", "Blocos", "Escore PC", "Origem"],
            [[br_data(a.get("data_local")), a.get("hora_inicio"), a.get("hora_fim"), a.get("polo"), a.get("escola"), a.get("maquina"),
              br_num(a.get("duracao_min"), " min") if a.get("duracao_min") is not None else None,
              ENCERRAMENTO_LEIGO.get(a.get("encerrada_por"), a.get("encerrada_por")),
              a.get("versoes_programa"), a.get("blocos_executaveis"), br_num(a.get("ct_score")) if a.get("ct_score") is not None else None,
              a.get("origem")] for a in mostradas],
        ))
    else:
        partes.append("Nenhuma aula no período.")

    partes += [
        "",
        "## Como ler",
        "",
        "- **Versões salvas:** quantas vezes a bancada salvou o programa no SPIKE com mudança.",
        "- **Encerrada por** `sem uso do SPIKE por 40 min`: o instrutor não encerrou e a aula fechou sozinha;"
        " o fim é 40 minutos depois do último programa salvo (ou do início, sem nenhum).",
        "- **Blocos** e **Escore PC:** do último programa salvo. O escore de pensamento computacional é"
        " adaptado de Dr. Scratch e ainda não foi validado.",
        "- **Origem:** `nuvem` (enviado pela internet), `pendrive` (importado do SQLite) ou os dois.",
        "- **Questionário do fim da aula:** respostas por mês da resposta; aulas não autorizadas ficam fora."
        " Uma criança é um envio (as respostas dela na mesma rodada), sem nome nem forma de seguir alguém entre aulas.",
        "- Significado de cada coluna dos arquivos CSV: `docs/pesquisa/relatorio.md`.",
        "",
    ]
    return "\n".join(partes)


# ---------------------------------------------------------------------------
# Programa
# ---------------------------------------------------------------------------

def data_arg(texto_data: str) -> str:
    try:
        return dt.date.fromisoformat(texto_data).isoformat()
    except ValueError:
        raise argparse.ArgumentTypeError(f"data inválida: {texto_data} (use AAAA-MM-DD)")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="PulseLab — relatório das aulas de bancada (nuvem e/ou pendrive).")
    parser.add_argument("--sqlite", help="SQLite consolidado do importador (padrão: dados_locais/pulselab_consolidado.sqlite, se existir).")
    parser.add_argument("--sem-nuvem", action="store_true", help="Não consulta o Supabase, mesmo com credencial configurada.")
    parser.add_argument("--saida", help="Pasta de saída (padrão: relatorios/AAAA-MM-DD/).")
    parser.add_argument("--de", type=data_arg, help="Primeira data das aulas (AAAA-MM-DD).")
    parser.add_argument("--ate", type=data_arg, help="Última data das aulas (AAAA-MM-DD).")
    parser.add_argument("--polo", help="Só este polo (código, ex.: PET).")
    parser.add_argument("--hoje", type=data_arg, help="Data de referência para 'dias sem dados' (padrão: hoje).")
    args = parser.parse_args(argv)

    hoje = dt.date.fromisoformat(args.hoje) if args.hoje else dt.datetime.now(FUSO_LOCAL).date()
    saida = Path(args.saida) if args.saida else ROOT / "relatorios" / hoje.isoformat()

    fontes: list[str] = []
    avisos: list[str] = []
    aulas_nuvem: list[dict] = []
    maquinas_nuvem: list[dict] = []
    aulas_pendrive: list[dict] = []
    respostas_nuvem: list[dict] = []
    respostas_pendrive: list[dict] = []
    retiradas: set[str] = set()

    sqlite_path = Path(args.sqlite) if args.sqlite else ROOT / "dados_locais" / "pulselab_consolidado.sqlite"
    if args.sqlite and not sqlite_path.is_file():
        print(f"[ERRO] Arquivo SQLite não encontrado: {sqlite_path}")
        return 1
    if sqlite_path.is_file():
        aulas_pendrive, retiradas = ler_sqlite(sqlite_path)
        respostas_pendrive = ler_questionario_sqlite(sqlite_path)
        fontes.append(f"pendrive (SQLite `{sqlite_path.name}`)")
        print(f"[OK] SQLite: {len(aulas_pendrive)} aulas em {sqlite_path}")
        if aulas_pendrive and not any(a.get("installation_id") for a in aulas_pendrive):
            avisos.append("o SQLite não tem a identificação das máquinas; importe os pendrives de novo com o importador atual.")

    if not args.sem_nuvem:
        cred = credenciais_nuvem()
        if cred is None:
            print("[i] Sem credencial da nuvem (PULSELAB_SERVICE_ROLE_KEY ou PULSELAB_OPERATIONAL_JWT): só o SQLite será usado.")
        else:
            url, key = cred
            filtros: list[tuple[str, str]] = []
            if args.de:
                filtros.append(("data_local", f"gte.{args.de}"))
            if args.ate:
                filtros.append(("data_local", f"lte.{args.ate}"))
            if args.polo:
                filtros.append(("polo", f"eq.{args.polo}"))
            try:
                aulas_nuvem = [aula_da_nuvem(r) for r in buscar_nuvem(url, key, "research_aula_bancada", filtros, "inicio_em.asc")
                               if r.get("ambiente") != "test"]
                fontes.append("nuvem (Supabase)")
                print(f"[OK] Nuvem: {len(aulas_nuvem)} aulas.")
            except Exception as exc:
                avisos.append(f"a nuvem não respondeu ({descrever_erro(exc)}); o relatório usa só o pendrive.")
                print(f"[!] Nuvem indisponível: {descrever_erro(exc)}")
            else:
                try:
                    maquinas_nuvem = [maquina_da_nuvem(r) for r in buscar_nuvem(url, key, "research_installation_last_seen", [], "installation_id.asc")]
                except Exception as exc:
                    avisos.append(f"a lista de máquinas da nuvem não respondeu ({descrever_erro(exc)}).")
                try:
                    # A view do questionário tem as mesmas colunas de filtro (data_local e polo).
                    respostas_nuvem = respostas_da_nuvem(buscar_nuvem(
                        url, key, "research_questionario_respostas", filtros, "respondido_em.asc"))
                except Exception as exc:
                    avisos.append(f"as respostas do questionário na nuvem não responderam ({descrever_erro(exc)}).")

    if not fontes:
        print("[ERRO] Nenhuma fonte de dados: informe --sqlite ou configure a credencial da nuvem.")
        return 1

    todas = juntar_aulas(aulas_nuvem, aulas_pendrive, retiradas=retiradas)
    filtradas = filtrar(todas, args.de, args.ate, args.polo)
    aulas = [a for a in filtradas if not sessao_vazia(a)]
    vazias = len(filtradas) - len(aulas)
    if vazias:
        avisos.append(f"{vazias} sessão(ões) sem nenhum programa salvo, fechadas por inatividade "
                      "(computador ligado sem aula), ficaram fora das contagens.")
    resumo = resumo_polos(aulas)
    maquinas = maquinas_sem_envio(maquinas_nuvem, todas, hoje, args.polo)
    respostas = filtrar_respostas(juntar_respostas(respostas_nuvem, respostas_pendrive, retiradas=retiradas),
                                  args.de, args.ate, args.polo)
    questionario = {
        "carrinho": testes_carrinho(respostas),
        "criancas": criancas_por_pergunta(respostas),
        "resumo": criancas_resumo(respostas),
        "sinalizacoes": sinalizacoes_questionario(respostas),
    }

    saida.mkdir(parents=True, exist_ok=True)
    escrever_csv(saida / "aulas.csv", COLUNAS_AULAS, aulas)
    escrever_csv(saida / "resumo-polos.csv", COLUNAS_RESUMO, resumo)
    escrever_csv(saida / "maquinas-sem-envio.csv", COLUNAS_MAQUINAS, maquinas)
    escrever_csv(saida / "testes-carrinho.csv", COLUNAS_CARRINHO, questionario["carrinho"])
    escrever_csv(saida / "criancas.csv", COLUNAS_CRIANCAS, questionario["criancas"])
    escrever_csv(saida / "criancas-resumo.csv", COLUNAS_CRIANCAS_RESUMO, questionario["resumo"])
    escrever_csv(saida / "questionario-sinalizacoes.csv", COLUNAS_SINALIZACOES, questionario["sinalizacoes"])
    (saida / "relatorio.md").write_text(
        gerar_markdown(aulas, resumo, maquinas, hoje, args.de, args.ate, args.polo, fontes, avisos, questionario=questionario),
        encoding="utf-8",
    )
    print(f"[OK] {len(aulas)} aulas, {len(resumo)} linhas de resumo, {len(maquinas)} máquinas.")
    print(f"[OK] Questionário: {len(respostas)} respostas, {len(questionario['sinalizacoes'])} sinalização(ões).")
    print(f"[OK] Relatório em: {saida}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
