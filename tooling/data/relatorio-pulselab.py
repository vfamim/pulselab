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
  relatorio.md            resumo em português, com a seção "Atenção"

Credenciais da nuvem: as mesmas do importador (PULSELAB_SUPABASE_URL, PULSELAB_SERVICE_ROLE_KEY ou
PULSELAB_OPERATIONAL_JWT). Sem credencial, ou com --sem-nuvem, usa só o SQLite e não acessa a rede.

Só campos de bancada e de máquina; nenhum dado de criança nem texto livre.
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
}


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
            if not sid:
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
) -> str:
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

    partes += ["", "## Resumo semanal por polo", ""]
    if resumo:
        partes.append(md_tabela(
            ["Polo", "Semana (segunda)", "Aulas", "Máquinas", "Duração mediana", "Encerradas pelo instrutor", "Interrompidas", "Sem SPIKE"],
            [[r["polo"], br_data(r["semana_inicio"]), r["aulas"], r["maquinas"], br_num(r["duracao_mediana_min"], " min"),
              br_num(r["pct_encerradas_instrutor"], "%"), br_num(r["pct_interrompidas"], "%"), br_num(r["pct_sem_spike"], "%")] for r in resumo],
        ))
    else:
        partes.append("Nenhuma aula no período.")

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
        "- **Blocos** e **Escore PC:** do último programa salvo. O escore de pensamento computacional é"
        " adaptado de Dr. Scratch e ainda não foi validado.",
        "- **Origem:** `nuvem` (enviado pela internet), `pendrive` (importado do SQLite) ou os dois.",
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
    retiradas: set[str] = set()

    sqlite_path = Path(args.sqlite) if args.sqlite else ROOT / "dados_locais" / "pulselab_consolidado.sqlite"
    if args.sqlite and not sqlite_path.is_file():
        print(f"[ERRO] Arquivo SQLite não encontrado: {sqlite_path}")
        return 1
    if sqlite_path.is_file():
        aulas_pendrive, retiradas = ler_sqlite(sqlite_path)
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

    if not fontes:
        print("[ERRO] Nenhuma fonte de dados: informe --sqlite ou configure a credencial da nuvem.")
        return 1

    todas = juntar_aulas(aulas_nuvem, aulas_pendrive, retiradas=retiradas)
    aulas = filtrar(todas, args.de, args.ate, args.polo)
    resumo = resumo_polos(aulas)
    maquinas = maquinas_sem_envio(maquinas_nuvem, todas, hoje, args.polo)

    saida.mkdir(parents=True, exist_ok=True)
    escrever_csv(saida / "aulas.csv", COLUNAS_AULAS, aulas)
    escrever_csv(saida / "resumo-polos.csv", COLUNAS_RESUMO, resumo)
    escrever_csv(saida / "maquinas-sem-envio.csv", COLUNAS_MAQUINAS, maquinas)
    (saida / "relatorio.md").write_text(
        gerar_markdown(aulas, resumo, maquinas, hoje, args.de, args.ate, args.polo, fontes, avisos), encoding="utf-8"
    )
    print(f"[OK] {len(aulas)} aulas, {len(resumo)} linhas de resumo, {len(maquinas)} máquinas.")
    print(f"[OK] Relatório em: {saida}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
