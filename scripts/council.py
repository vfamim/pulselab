#!/usr/bin/env python3
"""
LLM Council para PulseLab
Baseado na metodologia 'llm-council' de Andrej Karpathy (https://github.com/karpathy/llm-council).

Executa um conselho deliberativo em 3 estágios:
  1. Stage 1: Primeiras Opiniões (coleta independente de múltiplos modelos/personas)
  2. Stage 2: Revisão Cega por Pares (respostas anonimizadas, crítica cruzada e ranking estrito)
  3. Stage 3: Síntese do Presidente (Chairman compila o veredito final com base nas opiniões e rankings)

Suporta OpenRouter, Google Gemini API ou Modo Persona Local (offline).
Zero dependências externas: usa apenas a biblioteca padrão do Python.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
import concurrent.futures
from datetime import datetime
import json
import os
from pathlib import Path
import re
import sys
import time
import urllib.error
import urllib.request
from typing import Any

# Modelos padrão para o Conselho (OpenRouter)
DEFAULT_OPENROUTER_MODELS = [
    "google/gemini-2.5-pro",
    "anthropic/claude-3-7-sonnet",
    "openai/gpt-4o",
]
DEFAULT_OPENROUTER_CHAIRMAN = "google/gemini-2.5-pro"

# Modelos padrão para o Conselho (Google Gemini API)
DEFAULT_GEMINI_MODELS = [
    "gemini-2.5-pro",
    "gemini-2.5-flash",
    "gemini-2.0-flash",
]
DEFAULT_GEMINI_CHAIRMAN = "gemini-2.5-pro"


def load_env_safe(root_dir: Path | None = None) -> dict[str, str]:
    """
    Carrega variáveis do arquivo .env sem expor nem imprimir conteúdo sensível.
    """
    env_vars: dict[str, str] = {}
    if root_dir is None:
        root_dir = Path(__file__).resolve().parent.parent

    env_path = root_dir / ".env"
    if env_path.is_file():
        try:
            content = env_path.read_text(encoding="utf-8")
            for line in content.splitlines():
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                k = k.strip()
                v = v.strip().strip("'\"")
                if k and v:
                    env_vars[k] = v
        except Exception:
            pass
    return env_vars


def get_api_key(name: str, env_vars: dict[str, str]) -> str | None:
    """Busca a chave no os.environ ou nas variáveis do .env."""
    return os.environ.get(name) or env_vars.get(name)


def query_openrouter(
    model: str,
    messages: list[dict[str, str]],
    api_key: str,
    timeout: float = 120.0,
) -> dict[str, Any] | None:
    """Consulta um modelo via API do OpenRouter."""
    url = "https://openrouter.ai/api/v1/chat/completions"
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://github.com/karpathy/llm-council",
        "X-Title": "PulseLab LLM Council",
        "User-Agent": "PulseLabCouncil/1.0",
    }
    payload = {
        "model": model,
        "messages": messages,
        "temperature": 0.7,
    }

    try:
        data_bytes = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(url, data=data_bytes, headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            choice = data.get("choices", [{}])[0]
            msg = choice.get("message", {})
            return {
                "content": msg.get("content", ""),
                "model": model,
            }
    except Exception as exc:
        sys.stderr.write(f"[WARN] Falha ao consultar {model} no OpenRouter: {exc}\n")
        return None


def query_gemini(
    model: str,
    messages: list[dict[str, str]],
    api_key: str,
    timeout: float = 120.0,
) -> dict[str, Any] | None:
    """Consulta um modelo via Google Gemini API."""
    clean_model = model.replace("google/", "").replace("models/", "")
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{clean_model}:generateContent?key={api_key}"

    # Converter messages (role: user/assistant) para o formato do Gemini
    contents = []
    for m in messages:
        role = "user" if m.get("role") in ("user", "system") else "model"
        contents.append({
            "role": role,
            "parts": [{"text": m.get("content", "")}]
        })

    payload = {
        "contents": contents,
        "generationConfig": {
            "temperature": 0.7,
        }
    }

    headers = {"Content-Type": "application/json"}
    try:
        data_bytes = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(url, data=data_bytes, headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            candidates = data.get("candidates", [])
            if candidates:
                parts = candidates[0].get("content", {}).get("parts", [])
                text = "".join(p.get("text", "") for p in parts)
                return {"content": text, "model": model}
    except Exception as exc:
        sys.stderr.write(f"[WARN] Falha ao consultar {model} no Gemini: {exc}\n")
        return None
    return None


def query_models_parallel(
    models: list[str],
    messages: list[dict[str, str]],
    mode: str,
    api_key: str,
    timeout: float = 120.0,
) -> dict[str, dict[str, Any] | None]:
    """Executa consultas aos modelos em paralelo usando ThreadPoolExecutor."""
    results: dict[str, dict[str, Any] | None] = {}
    query_fn = query_openrouter if mode == "openrouter" else query_gemini

    with concurrent.futures.ThreadPoolExecutor(max_workers=len(models)) as executor:
        future_to_model = {
            executor.submit(query_fn, model, messages, api_key, timeout): model
            for model in models
        }
        for future in concurrent.futures.as_completed(future_to_model):
            model = future_to_model[future]
            try:
                results[model] = future.result()
            except Exception as exc:
                sys.stderr.write(f"[WARN] Erro no worker para {model}: {exc}\n")
                results[model] = None
    return results


# ----------------------------------------------------------------------
# Estágio 1: Coleta das Primeiras Opiniões
# ----------------------------------------------------------------------

def stage1_collect_responses(
    user_query: str,
    models: list[str],
    mode: str,
    api_key: str,
) -> list[dict[str, Any]]:
    """
    Estágio 1: Envia a consulta original para todos os modelos individualmente.
    """
    messages = [{"role": "user", "content": user_query}]
    responses = query_models_parallel(models, messages, mode, api_key)

    stage1_results = []
    for model in models:
        resp = responses.get(model)
        if resp and resp.get("content"):
            stage1_results.append({
                "model": model,
                "response": resp["content"].strip(),
            })
    return stage1_results


# ----------------------------------------------------------------------
# Estágio 2: Revisão Cega por Pares e Ranking
# ----------------------------------------------------------------------

def parse_ranking_from_text(ranking_text: str) -> list[str]:
    """
    Extrai as posições ordenadas da seção 'FINAL RANKING:' do texto da resposta.
    Suporta inglês ('Response A') e português ('Resposta A').
    """
    text_clean = ranking_text.replace("**", "").replace("__", "")

    headers = ["FINAL RANKING:", "RANKING FINAL:", "FINAL RANKING", "RANKING:"]
    section = ""
    for header in headers:
        if header in text_clean.upper():
            parts = re.split(re.escape(header), text_clean, flags=re.IGNORECASE)
            if len(parts) >= 2:
                section = parts[1]
                break

    target_text = section if section else text_clean

    # Tenta padrão de lista numerada: '1. Response A' ou '1. Resposta A'
    numbered = re.findall(
        r"\d+\.\s*(?:Response|Resposta)\s+([A-Z])",
        target_text,
        flags=re.IGNORECASE,
    )
    if numbered:
        return [f"Response {letter.upper()}" for letter in numbered]

    # Fallback: extrai qualquer ocorrência de 'Response X' / 'Resposta X' na ordem
    matches = re.findall(
        r"(?:Response|Resposta)\s+([A-Z])",
        target_text,
        flags=re.IGNORECASE,
    )
    seen = set()
    ordered = []
    for m in matches:
        label = f"Response {m.upper()}"
        if label not in seen:
            seen.add(label)
            ordered.append(label)
    return ordered


def calculate_aggregate_rankings(
    stage2_results: list[dict[str, Any]],
    label_to_model: dict[str, str],
) -> list[dict[str, Any]]:
    """
    Calcula a média aritmética dos postos (Borda/Rank ordinal) para cada modelo.
    Quanto menor a média, melhor a classificação geral.
    """
    model_positions = defaultdict(list)

    for ranking_entry in stage2_results:
        parsed = ranking_entry.get("parsed_ranking", [])
        for position, label in enumerate(parsed, start=1):
            if label in label_to_model:
                model_name = label_to_model[label]
                model_positions[model_name].append(position)

    aggregate = []
    for model, positions in model_positions.items():
        if positions:
            avg_rank = sum(positions) / len(positions)
            aggregate.append({
                "model": model,
                "average_rank": round(avg_rank, 2),
                "rankings_count": len(positions),
                "positions": positions,
            })

    # Ordena pelo menor rank médio (1º lugar = menor média)
    aggregate.sort(key=lambda x: x["average_rank"])
    return aggregate


def stage2_collect_rankings(
    user_query: str,
    stage1_results: list[dict[str, Any]],
    models: list[str],
    mode: str,
    api_key: str,
) -> tuple[list[dict[str, Any]], dict[str, str]]:
    """
    Estágio 2: Anonimiza as respostas e pede que cada conselheiro avalie e classifique.
    """
    labels = [chr(65 + i) for i in range(len(stage1_results))]
    label_to_model = {
        f"Response {label}": res["model"]
        for label, res in zip(labels, stage1_results)
    }

    responses_text = "\n\n".join([
        f"--- Response {label} ---\n{res['response']}"
        for label, res in zip(labels, stage1_results)
    ])

    ranking_prompt = f"""Você é um membro especialista do Conselho Deliberativo Técnico e Metodológico.
Você está avaliando anonimamente diferentes respostas para o seguinte problema/pergunta:

Pergunta Original:
{user_query}

Abaixo estão as propostas fornecidas pelos outros membros do conselho (identidades anonimizadas):

{responses_text}

Sua tarefa obrigatória:
1. Primeiro, faça uma avaliação crítica individual de cada resposta. Para cada uma (Response A, Response B, etc.), destaque:
   - Pontos fortes e precisão técnica.
   - Limitações, omissões, riscos arquiteturais, éticos ou de conformidade.
2. Ao final estrito da sua resposta, forneça a classificação final ordenada da melhor para a pior.

IMPORTANTE: A seção de ranking deve seguir EXATAMENTE a formatação abaixo:
FINAL RANKING:
1. Response X
2. Response Y
...

Não adicione comentários ou texto explicativo dentro da seção FINAL RANKING.

Agora, apresente sua avaliação crítica e o ranking:"""

    messages = [{"role": "user", "content": ranking_prompt}]
    responses = query_models_parallel(models, messages, mode, api_key)

    stage2_results = []
    for model in models:
        resp = responses.get(model)
        if resp and resp.get("content"):
            full_text = resp["content"].strip()
            parsed = parse_ranking_from_text(full_text)
            stage2_results.append({
                "model": model,
                "ranking": full_text,
                "parsed_ranking": parsed,
            })

    return stage2_results, label_to_model


# ----------------------------------------------------------------------
# Estágio 3: Síntese do Presidente (Chairman Synthesis)
# ----------------------------------------------------------------------

def stage3_synthesize_final(
    user_query: str,
    stage1_results: list[dict[str, Any]],
    stage2_results: list[dict[str, Any]],
    aggregate_rankings: list[dict[str, Any]],
    chairman_model: str,
    mode: str,
    api_key: str,
) -> dict[str, Any]:
    """
    Estágio 3: O Presidente do Conselho sintetiza o parecer definitivo.
    """
    stage1_text = "\n\n".join([
        f"### Modelo: {r['model']}\n{r['response']}"
        for r in stage1_results
    ])

    stage2_text = "\n\n".join([
        f"### Avaliador: {r['model']}\n{r['ranking']}"
        for r in stage2_results
    ])

    agg_summary = "\n".join([
        f"- {entry['model']}: Média de Posição {entry['average_rank']} (Votos: {entry['rankings_count']})"
        for entry in aggregate_rankings
    ])

    chairman_prompt = f"""Você é o Presidente do Conselho Deliberativo Técnico (Chairman).
Diversos especialistas do conselho responderam a uma questão e, em seguida, realizaram uma revisão cega por pares das propostas de cada um.

Pergunta Original:
{user_query}

ESTÁGIO 1 - Respostas e Propostas Individuais:
{stage1_text}

ESTÁGIO 2 - Revisões Críticas dos Pares:
{stage2_text}

RANKING AGREGADO DOS PARES (menor média = mais bem avaliado):
{agg_summary}

Sua missão como Presidente:
1. Sintetizar a deliberação coletiva em uma única resposta definitiva, rigorosa, abrangente e diretamente acionável.
2. Identificar consensos fundamentais e resolver divergências apontadas pelos pares.
3. Se aplicável ao contexto de código ou engenharia do PulseLab, assegurar que as diretrizes normativas (Portabilidade Windows, loopback 43128, CRLF, salvaguardas da LGPD Art. 14, bancada como unidade analítica, retenção de 7 dias, ausência de telemetria invasiva) sejam atendidas integralmente.
4. Concluir com uma lista de recomendações claras de implementação ou decisão final.

Produza agora o parecer definitivo do Conselho:"""

    messages = [{"role": "user", "content": chairman_prompt}]
    query_fn = query_openrouter if mode == "openrouter" else query_gemini
    resp = query_fn(chairman_model, messages, api_key)

    if not resp or not resp.get("content"):
        return {
            "model": chairman_model,
            "response": "Erro: Não foi possível obter a síntese do Presidente.",
        }
    return {
        "model": chairman_model,
        "response": resp["content"].strip(),
    }


# ----------------------------------------------------------------------
# Modo Offline / Personas Especializadas do PulseLab
# ----------------------------------------------------------------------

PULSELAB_PERSONAS = [
    {
        "id": "arquiteto",
        "name": "Arquiteto de Software & Engenharia Windows",
        "role": (
            "Foco rigoroso em robustez operacional, compatibilidade com Windows PowerShell 5.1, "
            "terminações CRLF, servidor loopback isolado na porta 43128, integridade de processos e "
            "ausência de dependências invasivas no sistema operacional."
        ),
    },
    {
        "id": "governanca_lgpd",
        "name": "Auditor de Governança, Ética & LGPD (Art. 14)",
        "role": (
            "Foco absoluto na proteção de dados de crianças e adolescentes (Art. 14 da LGPD), "
            "tratamento da bancada coletiva (group_id) como única unidade analítica, assentimento "
            "livre e não-punitivo, política estrita de descarte em 7 dias e abolição de qualquer "
            "telemetria invasiva (sem prints/sem keylogger)."
        ),
    },
    {
        "id": "metodologia_mmla",
        "name": "Cientista da Aprendizagem & Metodologia MMLA",
        "role": (
            "Foco na validade científica dos instrumentos pedagógicos, triangulação entre observação "
            "humana e telemetria estrutural do LEGO SPIKE, monitoramento de carga cognitiva sem "
            "inferências automatizadas simplistas de aprendizagem."
        ),
    },
]


def run_offline_persona_council(user_query: str) -> dict[str, Any]:
    """
    Gera uma deliberação estruturada com base nas 3 personas especializadas do PulseLab.
    Usado quando nenhuma chave de API externa estiver disponível ou quando solicitado offline.
    """
    stage1 = []
    for p in PULSELAB_PERSONAS:
        perspective_notes = (
            f"**Perspectiva: {p['name']}**\n\n"
            f"- *Missão*: {p['role']}\n"
            f"- *Avaliação da Questão*: Diante de '{user_query}', esta ótica demanda atenção prioritária "
            f"aos limites do protocolo PulseLab, garantindo que qualquer evolução técnica mantenha "
            f"o isolamento de bancada, estabilidade e conformidade normativa.\n"
        )
        stage1.append({"model": p["name"], "response": perspective_notes})

    labels = ["A", "B", "C"]
    label_to_model = {f"Response {labels[i]}": p["name"] for i, p in enumerate(PULSELAB_PERSONAS)}

    stage2 = []
    for i, p in enumerate(PULSELAB_PERSONAS):
        # Cada persona avalia as outras
        eval_text = (
            f"Análise crítica por {p['name']}:\n"
            f"Todas as propostas trazem aspectos complementares indispensáveis. "
            f"A governança e a segurança técnica devem ancorar as decisões arquiteturais.\n\n"
            f"FINAL RANKING:\n"
            f"1. Response A\n"
            f"2. Response B\n"
            f"3. Response C\n"
        )
        stage2.append({
            "model": p["name"],
            "ranking": eval_text,
            "parsed_ranking": ["Response A", "Response B", "Response C"],
        })

    agg = calculate_aggregate_rankings(stage2, label_to_model)

    chairman_text = (
        f"# Parecer Sintetizado do Conselho Técnico PulseLab\n\n"
        f"**Questão sob Deliberação:** {user_query}\n\n"
        f"### 1. Síntese Deliberativa e Consenso Interdisciplinar\n"
        f"O conselho técnico reuniu as óticas de Arquitetura de Sistemas, Governança LGPD e Metodologia MMLA. "
        f"Houve consenso absoluto de que qualquer modificação precisa obedecer rigorosamente às salvaguardas "
        f"normativas do repositório PulseLab:\n\n"
        f"- **Preservação de Isolamento**: Operação restrita ao loopback 127.0.0.1:43128, sem chamadas externas não autorizadas.\n"
        f"- **Proteção a Menores**: Bancada coletiva como unidade de análise; nenhum dado pessoal identificável.\n"
        f"- **Compatibilidade de Plataforma**: Manter terminação de linha CRLF em scripts PowerShell e conformidade com PS 5.1.\n"
        f"- **Integridade e Versionamento**: Toda alteração operacional deve passar pelo verificador de versão e suíte de testes.\n\n"
        f"### 2. Veredito e Recomendações Acionáveis\n"
        f"1. Conduzir a implementação com cobertura de testes unitários (`npm run test:unit`).\n"
        f"2. Validar a consistência do repositório através de `python3 scripts/check-version-consistency.py`.\n"
        f"3. Para ativar a deliberação com modelos de ponta em tempo real (ex.: Gemini 2.5 Pro, Claude Sonnet 3.7, GPT-4o), "
        f"configure a variável `OPENROUTER_API_KEY` ou `GEMINI_API_KEY` no seu ambiente ou no arquivo `.env`."
    )

    stage3 = {
        "model": "Presidente do Conselho Técnico (PulseLab Chairman)",
        "response": chairman_text,
    }

    return {
        "stage1": stage1,
        "stage2": stage2,
        "stage3": stage3,
        "aggregate_rankings": agg,
        "label_to_model": label_to_model,
        "mode": "persona_offline",
    }


# ----------------------------------------------------------------------
# Exportação de Relatórios e Formatação Visual
# ----------------------------------------------------------------------

def save_council_log(
    user_query: str,
    stage1_results: list[dict[str, Any]],
    stage2_results: list[dict[str, Any]],
    stage3_result: dict[str, Any],
    aggregate_rankings: list[dict[str, Any]],
    label_to_model: dict[str, str],
    output_path: Path | None = None,
) -> Path:
    """Salva a deliberação completa em um documento Markdown."""
    if output_path is None:
        logs_dir = Path(__file__).resolve().parent.parent / ".agents" / "council_logs"
        logs_dir.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        output_path = logs_dir / f"council-{timestamp}.md"
    else:
        output_path.parent.mkdir(parents=True, exist_ok=True)

    lines = [
        "# Relatório de Deliberação do LLM Council (PulseLab)",
        f"**Data/Hora:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}  ",
        f"**Presidente (Chairman):** {stage3_result.get('model', 'N/A')}  ",
        f"**Questão:** {user_query}\n",
        "---",
        "## 1. Veredito Final do Presidente (Stage 3)",
        stage3_result.get("response", ""),
        "\n---",
        "## 2. Ranking Agregado dos Pares (Stage 2 Summary)",
        "| Posição Média | Modelo / Conselheiro | Avaliações Recebidas |",
        "| :--- | :--- | :--- |",
    ]

    for agg in aggregate_rankings:
        lines.append(f"| {agg['average_rank']:.2f} | {agg['model']} | {agg['rankings_count']} |")

    lines.extend([
        "\n---",
        "## 3. Revisões Críticas dos Pares (Stage 2 Details)",
    ])

    for s2 in stage2_results:
        lines.append(f"### Avaliador: {s2['model']}")
        lines.append(s2.get("ranking", ""))
        parsed_str = ", ".join(s2.get("parsed_ranking", []))
        lines.append(f"\n*Ranking extraído:* {parsed_str}\n")

    lines.extend([
        "\n---",
        "## 4. Primeiras Opiniões Individuais (Stage 1)",
    ])

    for s1 in stage1_results:
        # Encontra label anonimizada correspondente
        anon_label = next(
            (label for label, model in label_to_model.items() if model == s1["model"]),
            "N/A"
        )
        lines.append(f"### {s1['model']} ({anon_label})")
        lines.append(s1.get("response", ""))
        lines.append("")

    output_path.write_text("\n".join(lines), encoding="utf-8")
    return output_path


def print_banner() -> None:
    banner = """
========================================================================
             ⚖️  PULSELAB LLM COUNCIL (Deliberação Multi-Modelo)
             Metodologia: Karpathy 3-Stage Peer-Review Deliberation
========================================================================
"""
    print(banner)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Executa o LLM Council para o repositório PulseLab (Baseado em karpathy/llm-council)."
    )
    parser.add_argument(
        "query",
        nargs="?",
        default=None,
        help="Pergunta, dilema arquitetural ou proposta de alteração a ser deliberada.",
    )
    parser.add_argument(
        "--models",
        type=str,
        default=None,
        help="Lista de modelos separados por vírgula para compor o conselho.",
    )
    parser.add_argument(
        "--chairman",
        type=str,
        default=None,
        help="Modelo designado como Presidente do Conselho.",
    )
    parser.add_argument(
        "--mode",
        choices=["auto", "openrouter", "gemini", "persona"],
        default="auto",
        help="Modo de consulta (auto detecta chaves de API disponíveis).",
    )
    parser.add_argument(
        "--output",
        type=str,
        default=None,
        help="Caminho do arquivo Markdown para gravar o log da deliberação.",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Exibe apenas o veredito final do Presidente.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Executa em modo sintético local sem consumir cotas de API.",
    )

    args = parser.parse_args()

    # Se a query não foi passada na linha de comando, solicita via stdin interativo
    query = args.query
    if not query:
        if sys.stdin.isatty():
            print_banner()
            try:
                query = input("Digite a questão técnica ou arquitetural para o Conselho: ").strip()
            except (KeyboardInterrupt, EOFError):
                print("\nOperação cancelada.")
                return 1
        else:
            query = sys.stdin.read().strip()

    if not query:
        sys.stderr.write("Erro: Nenhuma questão informada para deliberação.\n")
        return 1

    repo_root = Path(__file__).resolve().parent.parent
    env_vars = load_env_safe(repo_root)

    openrouter_key = get_api_key("OPENROUTER_API_KEY", env_vars)
    gemini_key = get_api_key("GEMINI_API_KEY", env_vars) or get_api_key("GOOGLE_API_KEY", env_vars)

    # Resolução de modo
    mode = args.mode
    if args.dry_run or mode == "persona":
        mode = "persona"
    elif mode == "auto":
        if openrouter_key:
            mode = "openrouter"
        elif gemini_key:
            mode = "gemini"
        else:
            mode = "persona"

    if not args.quiet:
        print_banner()
        print(f"📋 Questão: {query}")
        print(f"⚙️ Modo Selecionado: {mode.upper()}")

    # Execução no modo Persona Local (offline/fallback)
    if mode == "persona":
        if not args.quiet and not args.dry_run and not (openrouter_key or gemini_key):
            print("\n💡 [NOTA] Nenhuma chave OPENROUTER_API_KEY ou GEMINI_API_KEY detectada.")
            print("   Executando Conselho no modo Persona Local do ecossistema PulseLab.")
            print("   (Para acionar modelos externos como Claude/GPT/Gemini, defina a chave no seu .env)\n")

        res = run_offline_persona_council(query)
        stage1_res = res["stage1"]
        stage2_res = res["stage2"]
        stage3_res = res["stage3"]
        agg_rankings = res["aggregate_rankings"]
        label_to_model = res["label_to_model"]

    elif mode == "openrouter":
        if not openrouter_key:
            sys.stderr.write("Erro: OPENROUTER_API_KEY não encontrada no ambiente ou .env.\n")
            return 1

        models = [m.strip() for m in args.models.split(",")] if args.models else DEFAULT_OPENROUTER_MODELS
        chairman = args.chairman or DEFAULT_OPENROUTER_CHAIRMAN

        if not args.quiet:
            print(f"👥 Membros do Conselho ({len(models)}): {', '.join(models)}")
            print(f"👑 Presidente (Chairman): {chairman}\n")
            print("⏳ [Estágio 1/3] Coletando primeiras opiniões em paralelo...")

        stage1_res = stage1_collect_responses(query, models, "openrouter", openrouter_key)
        if not stage1_res:
            sys.stderr.write("Erro: Nenhum modelo respondeu no Estágio 1.\n")
            return 1

        if not args.quiet:
            print(f"✅ [Estágio 1/3] {len(stage1_res)} opiniões coletadas com sucesso.")
            print("⏳ [Estágio 2/3] Conduzindo revisão cega cruzada e rankeamento...")

        stage2_res, label_to_model = stage2_collect_rankings(query, stage1_res, models, "openrouter", openrouter_key)
        agg_rankings = calculate_aggregate_rankings(stage2_res, label_to_model)

        if not args.quiet:
            print(f"✅ [Estágio 2/3] Revisões e rankings concluídos.")
            print("⏳ [Estágio 3/3] Presidente sintetizando o parecer final...")

        stage3_res = stage3_synthesize_final(
            query, stage1_res, stage2_res, agg_rankings, chairman, "openrouter", openrouter_key
        )

    elif mode == "gemini":
        if not gemini_key:
            sys.stderr.write("Erro: GEMINI_API_KEY não encontrada no ambiente ou .env.\n")
            return 1

        models = [m.strip() for m in args.models.split(",")] if args.models else DEFAULT_GEMINI_MODELS
        chairman = args.chairman or DEFAULT_GEMINI_CHAIRMAN

        if not args.quiet:
            print(f"👥 Membros do Conselho ({len(models)}): {', '.join(models)}")
            print(f"👑 Presidente (Chairman): {chairman}\n")
            print("⏳ [Estágio 1/3] Coletando primeiras opiniões no Gemini...")

        stage1_res = stage1_collect_responses(query, models, "gemini", gemini_key)
        if not stage1_res:
            sys.stderr.write("Erro: Nenhum modelo respondeu no Estágio 1.\n")
            return 1

        if not args.quiet:
            print(f"✅ [Estágio 1/3] {len(stage1_res)} opiniões coletadas com sucesso.")
            print("⏳ [Estágio 2/3] Conduzindo revisão cega cruzada...")

        stage2_res, label_to_model = stage2_collect_rankings(query, stage1_res, models, "gemini", gemini_key)
        agg_rankings = calculate_aggregate_rankings(stage2_res, label_to_model)

        if not args.quiet:
            print(f"✅ [Estágio 2/3] Revisões e rankings concluídos.")
            print("⏳ [Estágio 3/3] Presidente sintetizando o parecer final...")

        stage3_res = stage3_synthesize_final(
            query, stage1_res, stage2_res, agg_rankings, chairman, "gemini", gemini_key
        )

    # Exibição dos resultados no terminal
    if not args.quiet:
        print("\n" + "=" * 72)
        print("📊 TABELA AGREGADA DE AVALIAÇÃO DOS PARES (Stage 2)")
        print("=" * 72)
        print(f"{'Posição Média':<15} | {'Conselheiro/Modelo':<35} | {'Votos':<8}")
        print("-" * 72)
        for agg in agg_rankings:
            print(f"{agg['average_rank']:<15.2f} | {agg['model']:<35} | {agg['rankings_count']:<8}")

    print("\n" + "=" * 72)
    print("👑 VEREDITO FINAL DO PRESIDENTE (Stage 3)")
    print("=" * 72)
    print(stage3_res.get("response", "Sem resposta"))
    print("=" * 72 + "\n")

    # Salva log se solicitado ou por padrão
    out_file = Path(args.output) if args.output else None
    log_saved = save_council_log(
        query, stage1_res, stage2_res, stage3_res, agg_rankings, label_to_model, out_file
    )
    if not args.quiet:
        print(f"💾 Relatório completo registrado em: {log_saved.relative_to(repo_root)}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
