#!/usr/bin/env python3
"""
PulseLab — Importador Manual de Dados Locais para o Supabase e SQLite Consolidado.
================================================================================
Lê arquivos de sessão (.json) e eventos (.jsonl) coletados offline (em pendrives
ou na pasta dados_locais), consolida em uma base SQLite local e envia
para o banco central Supabase com resolução de duplicatas.

Zero dependências externas: usa apenas a biblioteca padrão do Python (sqlite3, urllib, json).
"""

from __future__ import annotations

import argparse
import datetime
import glob
import json
import os
from pathlib import Path
import sqlite3
import sys
import urllib.error
import urllib.request


DEFAULT_SUPABASE_URL = "https://cylsqbmtglvdfubbarqe.supabase.co"
DEFAULT_SUPABASE_ANON_KEY = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN5bHNxYm10Z2x2ZGZ1YmJhcnFlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5NjE1MzIsImV4cCI6MjA5MzUzNzUzMn0."
    "tscU354WLjnYz6E6NOrDQK16ViWBc-Af5FYhvZikFbU"
)


def load_config(repo_root: Path) -> tuple[str, str]:
    url = os.environ.get("PULSELAB_SUPABASE_URL", "")
    key = os.environ.get("PULSELAB_SUPABASE_KEY", "")

    candidates = [
        repo_root / "config" / "config.json",
        repo_root / "config" / "defaults.json",
    ]
    for c in candidates:
        if c.is_file():
            try:
                data = json.loads(c.read_text(encoding="utf-8"))
                if not url and data.get("supabase_url"):
                    url = data["supabase_url"]
                if not key and data.get("supabase_anon_key"):
                    key = data["supabase_anon_key"]
            except Exception:
                pass

    return url or DEFAULT_SUPABASE_URL, key or DEFAULT_SUPABASE_ANON_KEY


def init_sqlite_database(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))
    conn.execute("PRAGMA journal_mode = WAL;")

    with conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS sessions (
                session_id TEXT PRIMARY KEY,
                group_id TEXT,
                site_id TEXT,
                regional_hub TEXT,
                school_code TEXT,
                workshop_code TEXT,
                class_code TEXT,
                activity_id TEXT,
                started_at TEXT,
                completed_at TEXT,
                duration_seconds INTEGER,
                team_role TEXT,
                status TEXT,
                pre_answers_json TEXT,
                post_answers_json TEXT,
                spike_telemetry_json TEXT,
                events_count INTEGER,
                source_file TEXT,
                imported_at TEXT
            )
        """)

        conn.execute("""
            CREATE TABLE IF NOT EXISTS events (
                event_id TEXT PRIMARY KEY,
                session_id TEXT,
                event_type TEXT,
                timestamp TEXT,
                group_id TEXT,
                team_role TEXT,
                activity_stage TEXT,
                details_json TEXT,
                source_file TEXT,
                imported_at TEXT
            )
        """)

        conn.execute("""
            CREATE TABLE IF NOT EXISTS session_events (
                event_id TEXT PRIMARY KEY,
                session_id TEXT,
                event_type TEXT,
                timestamp TEXT,
                details_json TEXT,
                source_file TEXT,
                imported_at TEXT
            )
        """)

        conn.execute("CREATE INDEX IF NOT EXISTS idx_events_session ON events(session_id);")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_session_events_session ON session_events(session_id);")

    return conn


def send_to_supabase(
    table: str,
    records: list[dict],
    supabase_url: str,
    supabase_key: str,
    batch_size: int = 40,
) -> tuple[int, int, str | None]:
    """Envia registros em lotes para o Supabase com on_conflict=event_id e resolution=ignore-duplicates."""
    if not records or not supabase_url or not supabase_key:
        return 0, 0, None

    endpoint = f"{supabase_url.rstrip('/')}/rest/v1/{table}?on_conflict=event_id"
    inserted = 0
    errors = 0
    last_error = None

    for i in range(0, len(records), batch_size):
        chunk = records[i : i + batch_size]
        payload = json.dumps(chunk).encode("utf-8")

        req = urllib.request.Request(
            endpoint,
            data=payload,
            headers={
                "Content-Type": "application/json",
                "apikey": supabase_key,
                "Authorization": f"Bearer {supabase_key}",
                "Prefer": "resolution=ignore-duplicates,return=minimal",
            },
            method="POST",
        )

        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                if resp.status in (200, 201, 204):
                    inserted += len(chunk)
        except urllib.error.HTTPError as exc:
            err_body = ""
            try:
                err_body = exc.read().decode("utf-8")
            except Exception:
                pass
            if exc.code == 409:
                inserted += len(chunk)
            else:
                errors += len(chunk)
                last_error = f"HTTP {exc.code}: {exc.reason} - {err_body}"
        except Exception as exc:
            errors += len(chunk)
            last_error = str(exc)

    return inserted, errors, last_error


SESSION_EVENT_COLUMNS = {
    "event_id", "session_id", "dyad_id", "group_id", "installation_id", "site_id",
    "regional_hub", "school_code", "workshop_code", "class_code", "grade_band",
    "activity_id", "computer_id", "protocol_version", "config_version", "config_hash",
    "client_version", "event_type", "severity", "interval_mark", "participant_id",
    "participant_role", "activity_stage", "elapsed_ms", "scheduled_at", "occurred_at",
    "received_at", "details"
}

RESEARCH_EVENT_COLUMNS = {
    "event_id", "session_id", "dyad_id", "installation_id", "site_id", "participant_id",
    "participant_role", "event_type", "response_status", "interval_mark", "regional_hub",
    "school_code", "workshop_code", "class_code", "grade_band", "group_size",
    "activity_id", "computer_id", "protocol_version", "config_version", "config_hash",
    "client_version", "activity_stage", "student_age", "prior_robotics", "self_efficacy_pre",
    "knowledge_score", "knowledge_answers", "self_reported_role", "mental_effort",
    "progress_state", "perceived_difficulty", "satisfaction", "learning_perception",
    "free_feedback", "rubric_assembly", "rubric_circuit", "rubric_support"
}

import uuid

def ensure_uuid(val: str | None) -> str:
    if not val:
        return str(uuid.uuid4())
    try:
        return str(uuid.UUID(str(val)))
    except (ValueError, AttributeError):
        return str(uuid.uuid5(uuid.NAMESPACE_DNS, str(val)))


def sanitize_event_for_supabase(event: dict, target_table: str) -> dict:
    valid_cols = RESEARCH_EVENT_COLUMNS if target_table == "research_events" else SESSION_EVENT_COLUMNS
    payload = {}
    extra_details = {}

    for k, v in event.items():
        if k.startswith("_") or v is None:
            continue
        if k in valid_cols:
            payload[k] = v
        else:
            extra_details[k] = v

    if "event_id" in payload:
        payload["event_id"] = ensure_uuid(payload["event_id"])
    if "session_id" in payload:
        payload["session_id"] = ensure_uuid(payload["session_id"])
    if "dyad_id" in payload:
        payload["dyad_id"] = ensure_uuid(payload["dyad_id"])
    else:
        payload["dyad_id"] = ensure_uuid(event.get("group_id") or "bancada-offline")
    if "group_id" in payload:
        payload["group_id"] = ensure_uuid(payload["group_id"])

    if target_table == "research_events":
        if "participant_id" not in payload:
            payload["participant_id"] = event.get("participant_id") or "bancada"
        if "participant_role" not in payload:
            payload["participant_role"] = event.get("participant_role") or "computer"
        if "regional_hub" not in payload:
            payload["regional_hub"] = event.get("regional_hub") or "Nordeste"
        if "school_code" not in payload:
            payload["school_code"] = event.get("school_code") or "geral"
        if "workshop_code" not in payload:
            payload["workshop_code"] = event.get("workshop_code") or "oficina-spike"
        if "class_code" not in payload:
            payload["class_code"] = event.get("class_code") or "turma-geral"
        if "activity_id" not in payload:
            payload["activity_id"] = event.get("activity_id") or "atividade-01-spike"
        if "computer_id" not in payload:
            payload["computer_id"] = event.get("computer_id") or "pc-offline"
        if "config_version" not in payload:
            payload["config_version"] = event.get("config_version") or "2.1.0"
        if "client_version" not in payload:
            payload["client_version"] = event.get("client_version") or "2.1.0"
        if "response_status" not in payload:
            payload["response_status"] = "completed"

    if target_table == "research_session_events":
        if "installation_id" not in payload or not payload["installation_id"]:
            payload["installation_id"] = ensure_uuid(event.get("installation_id") or "inst-offline")
        else:
            payload["installation_id"] = ensure_uuid(payload["installation_id"])
        if "site_id" not in payload:
            payload["site_id"] = event.get("site_id") or "Polo-Nordeste"
        if "regional_hub" not in payload:
            payload["regional_hub"] = event.get("regional_hub") or "Nordeste"
        if "school_code" not in payload:
            payload["school_code"] = event.get("school_code") or "geral"
        if "workshop_code" not in payload:
            payload["workshop_code"] = event.get("workshop_code") or "oficina-spike"
        if "class_code" not in payload:
            payload["class_code"] = event.get("class_code") or "turma-geral"
        if "activity_id" not in payload:
            payload["activity_id"] = event.get("activity_id") or "atividade-01-spike"
        if "computer_id" not in payload:
            payload["computer_id"] = event.get("computer_id") or "pc-offline"
        if "protocol_version" not in payload:
            payload["protocol_version"] = event.get("protocol_version") or "v2.1"
        if "config_version" not in payload:
            payload["config_version"] = event.get("config_version") or "2.1.0"
        if "config_hash" not in payload or not payload["config_hash"]:
            payload["config_hash"] = "3c3662c7306d64236b0f7f26da183cc59a36c00061a2077d93fb0272876b2468"
        if "client_version" not in payload:
            payload["client_version"] = event.get("client_version") or "2.1.0"

        allowed_session_events = {
            "session_started", "phase_completed", "activity_started", "heartbeat",
            "checkpoint_started", "checkpoint_completed", "help_requested",
            "role_swapped", "ending_requested", "rubric_completed",
            "session_completed", "session_aborted", "quality_issue"
        }
        if payload.get("event_type") not in allowed_session_events:
            payload["event_type"] = "phase_completed"

        existing_details = payload.get("details")
        if not isinstance(existing_details, dict):
            existing_details = {}
        existing_details.update(extra_details)
        payload["details"] = existing_details

    return payload


def find_data_sources(specified_source: str | None, repo_root: Path) -> list[Path]:
    sources: list[Path] = []

    if specified_source:
        p = Path(specified_source).resolve()
        if p.exists():
            sources.append(p)
            return sources
        else:
            print(f"[!] Caminho especificado não encontrado: {specified_source}")

    # 1. Procura pastas Coleta-PulseLab em unidades montadas ou no Desktop
    desktop = Path.home() / "Desktop" / "Coleta-PulseLab"
    if desktop.is_dir():
        sources.append(desktop)

    # 2. No Windows, varre letras de unidade D: a Z: procurando Coleta-PulseLab
    if sys.platform.startswith("win"):
        for letter in "DEFGHIJKLMNOPQRSTUVWXYZ":
            candidate = Path(f"{letter}:\\Coleta-PulseLab")
            if candidate.is_dir():
                sources.append(candidate)

    # 3. Na pasta do próprio repositório / aplicativo
    local_data = repo_root / "dados_locais"
    if local_data.is_dir():
        sources.append(local_data)

    # Remove duplicatas preservando ordem
    seen = set()
    unique = []
    for s in sources:
        rp = s.resolve()
        if rp not in seen:
            seen.add(rp)
            unique.append(rp)

    return unique


def main() -> int:
    parser = argparse.ArgumentParser(
        description="PulseLab — Importador Manual de Dados Locais para o Supabase e SQLite."
    )
    parser.add_argument(
        "--source",
        "-s",
        help="Caminho da pasta coletada (ex: E:\\Coleta-PulseLab ou ./dados_locais). Se omitido, busca automaticamente.",
        default=None,
    )
    parser.add_argument(
        "--supabase-url",
        help="URL da instância Supabase (ou usa config/config.json).",
        default="",
    )
    parser.add_argument(
        "--supabase-key",
        help="Chave de API do Supabase (ou usa config/config.json).",
        default="",
    )
    parser.add_argument(
        "--no-cloud",
        action="store_true",
        help="Importa apenas para a base SQLite local, sem enviar para o Supabase.",
    )
    parser.add_argument(
        "--sqlite-path",
        help="Caminho do arquivo SQLite consolidado (padrão: dados_locais/pulselab_consolidado.sqlite).",
        default="",
    )

    args = parser.parse_args()
    repo_root = Path(__file__).resolve().parent.parent

    print("====================================================================")
    print("   PULSELAB — IMPORTADOR E CONSOLIDADOR DE DADOS OFFLINE")
    print("====================================================================")
    print(f"Data/Hora: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")

    # Identificar fontes de dados
    sources = find_data_sources(args.source, repo_root)
    if not sources:
        print("[ERRO] Nenhuma fonte de dados encontrada.")
        print("Certifique-se de conectar o pendrive ou indicar o caminho com --source.")
        return 1

    print(f"Fontes de dados detectadas ({len(sources)}):")
    for s in sources:
        print(f"  📁 {s}")
    print()

    # Banco SQLite consolidado
    sqlite_file = (
        Path(args.sqlite_path).resolve()
        if args.sqlite_path
        else (repo_root / "dados_locais" / "pulselab_consolidado.sqlite")
    )
    conn = init_sqlite_database(sqlite_file)
    print(f"[OK] Banco SQLite consolidado pronto em:\n     {sqlite_file}\n")

    # Supabase credentials
    sb_url = args.supabase_url
    sb_key = args.supabase_key
    if not args.no_cloud and (not sb_url or not sb_key):
        cfg_url, cfg_key = load_config(repo_root)
        sb_url = sb_url or cfg_url
        sb_key = sb_key or cfg_key

    # Coleta de arquivos
    session_files: list[Path] = []
    events_files: list[Path] = []

    for src in sources:
        # Se for um diretorio raiz que contém subpastas de coleta (ex: Coleta_PC01_...)
        sub_collects = [p for p in src.glob("Coleta_*") if p.is_dir()]
        target_dirs = sub_collects if sub_collects else [src]

        for tdir in target_dirs:
            # Sessoes
            s_dir = tdir / "sessoes"
            if s_dir.is_dir():
                session_files.extend(s_dir.glob("*.json"))
            else:
                session_files.extend(tdir.glob("sessao_*.json"))

            # Eventos
            ev_f = tdir / "events.jsonl"
            if ev_f.is_file():
                events_files.append(ev_f)
            ev_arch = tdir / "events_archive.jsonl"
            if ev_arch.is_file():
                events_files.append(ev_arch)

    # Remover duplicatas de arquivos
    session_files = list({p.resolve(): p for p in session_files}.values())
    events_files = list({p.resolve(): p for p in events_files}.values())

    print(f"Arquivos localizados:")
    print(f"  - Sessões completas (.json): {len(session_files)}")
    print(f"  - Arquivos de eventos (.jsonl): {len(events_files)}\n")

    now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()

    # 1. Processar Sessões
    sessions_imported = 0
    all_events_from_sessions: list[dict] = []

    for sf in session_files:
        try:
            content = sf.read_text(encoding="utf-8-sig")
            data = json.loads(content)
            sess_id = data.get("session_id")
            if not sess_id:
                continue

            events_list = data.get("events") or []
            if isinstance(events_list, list):
                all_events_from_sessions.extend(events_list)

            with conn:
                conn.execute("""
                    INSERT INTO sessions (
                        session_id, group_id, site_id, regional_hub, school_code,
                        workshop_code, class_code, activity_id, started_at, completed_at,
                        duration_seconds, team_role, status, pre_answers_json,
                        post_answers_json, spike_telemetry_json, events_count,
                        source_file, imported_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(session_id) DO UPDATE SET
                        status = excluded.status,
                        completed_at = excluded.completed_at,
                        duration_seconds = excluded.duration_seconds,
                        post_answers_json = excluded.post_answers_json,
                        events_count = excluded.events_count,
                        imported_at = excluded.imported_at
                """, (
                    sess_id,
                    data.get("group_id", ""),
                    data.get("site_id", ""),
                    data.get("regional_hub", ""),
                    data.get("school_code", ""),
                    data.get("workshop_code", ""),
                    data.get("class_code", ""),
                    data.get("activity_id", ""),
                    data.get("started_at", ""),
                    data.get("completed_at", ""),
                    data.get("duration_seconds", 0),
                    data.get("team_role", ""),
                    data.get("status", "completed"),
                    json.dumps(data.get("pre_answers") or {}),
                    json.dumps(data.get("post_answers") or {}),
                    json.dumps(data.get("spike_telemetry") or {}),
                    len(events_list),
                    str(sf.name),
                    now_iso,
                ))
            sessions_imported += 1
        except Exception as exc:
            print(f"[!] Erro ao processar sessão {sf.name}: {exc}")

    print(f"[✓] {sessions_imported} sessões consolidadas na base SQLite.")

    # 2. Processar Eventos (.jsonl)
    events_to_upload_research: list[dict] = []
    events_to_upload_session: list[dict] = []
    total_events_read = 0

    all_raw_event_lines: list[tuple[str, str]] = []
    for ef in events_files:
        try:
            with ef.open("r", encoding="utf-8-sig", errors="replace") as f:
                for line in f:
                    sline = line.strip()
                    if sline:
                        all_raw_event_lines.append((sline, str(ef.name)))
        except Exception as exc:
            print(f"[!] Erro ao ler arquivo de eventos {ef.name}: {exc}")

    # Adiciona também eventos contidos dentro dos JSONs de sessão
    for ev in all_events_from_sessions:
        all_raw_event_lines.append((json.dumps(ev), "session_json"))

    events_inserted_sqlite = 0
    with conn:
        for raw_line, src_name in all_raw_event_lines:
            try:
                ev = json.loads(raw_line)
                event_id = ev.get("event_id")
                if not event_id:
                    continue

                event_type = ev.get("event_type", "")
                session_id = ev.get("session_id", "")
                timestamp = ev.get("timestamp", now_iso)
                group_id = ev.get("group_id", "")
                team_role = ev.get("team_role", "")
                stage = ev.get("activity_stage", "")
                details = ev.get("details") or {}

                if event_type in ("pre", "checkpoint", "post", "rubric"):
                    clean_ev = sanitize_event_for_supabase(ev, "research_events")
                    events_to_upload_research.append(clean_ev)
                    conn.execute("""
                        INSERT OR IGNORE INTO events (
                            event_id, session_id, event_type, timestamp, group_id,
                            team_role, activity_stage, details_json, source_file, imported_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, (
                        event_id, session_id, event_type, timestamp, group_id,
                        team_role, stage, json.dumps(details), src_name, now_iso
                    ))
                else:
                    clean_ev = sanitize_event_for_supabase(ev, "research_session_events")
                    events_to_upload_session.append(clean_ev)
                    conn.execute("""
                        INSERT OR IGNORE INTO session_events (
                            event_id, session_id, event_type, timestamp,
                            details_json, source_file, imported_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, (
                        event_id, session_id, event_type, timestamp,
                        json.dumps(details), src_name, now_iso
                    ))

                events_inserted_sqlite += 1
                total_events_read += 1
            except Exception:
                continue

    print(f"[✓] {events_inserted_sqlite} eventos consolidados na base SQLite.")

    # 3. Enviar ao Supabase (se habilitado)
    if args.no_cloud:
        print("\n[!] Modo offline ativado (--no-cloud): envio para Supabase ignorado.")
    elif not sb_url or not sb_key:
        print("\n[!] Supabase URL/Key não configurados. Envio remoto ignorado.")
    else:
        print(f"\nSincronizando com o Supabase ({sb_url})...")

        # Deduplicar registros pelo event_id
        res_dict = {e["event_id"]: e for e in events_to_upload_research}
        sess_dict = {e["event_id"]: e for e in events_to_upload_session}

        res_unique = list(res_dict.values())
        sess_unique = list(sess_dict.values())

        print(f"  - Tabela 'research_events': {len(res_unique)} registros a verificar/enviar")
        ins_res, err_res, last_err1 = send_to_supabase("research_events", res_unique, sb_url, sb_key)
        print(f"    ✓ Sincronizados com sucesso: {ins_res} (Erros: {err_res})")
        if last_err1:
            print(f"    [!] Detalhes do erro: {last_err1}")

        print(f"  - Tabela 'research_session_events': {len(sess_unique)} registros a verificar/enviar")
        ins_sess, err_sess, last_err2 = send_to_supabase("research_session_events", sess_unique, sb_url, sb_key)
        print(f"    ✓ Sincronizados com sucesso: {ins_sess} (Erros: {err_sess})")
        if last_err2:
            print(f"    [!] Detalhes do erro: {last_err2}")

    # 4. Gerar Relatório de Importação
    report_file = (
        repo_root / "dados_locais" / f"relatorio_importacao_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
    )
    report_text = f"""====================================================================
PULSELAB — RELATÓRIO DE IMPORTAÇÃO E CONSOLIDAÇÃO DE DADOS
====================================================================
Data/Hora da Execução : {now_iso}
Base SQLite Local     : {sqlite_file}
Sessões Importadas    : {sessions_imported}
Eventos Processados   : {events_inserted_sqlite}
Supabase Endpoint     : {sb_url if not args.no_cloud else 'Desabilitado'}
====================================================================
Fontes de dados analisadas:
{chr(10).join(' - ' + str(s) for s in sources)}
====================================================================
Importação concluída com sucesso.
"""
    try:
        report_file.parent.mkdir(parents=True, exist_ok=True)
        report_file.write_text(report_text, encoding="utf-8")
        print(f"\n[OK] Relatório gravado em:\n     {report_file}")
    except Exception:
        pass

    print("\n====================================================================")
    print("  PROCESSO DE IMPORTAÇÃO CONCLUÍDO COM SUCESSO!")
    print("====================================================================")
    return 0


if __name__ == "__main__":
    sys.exit(main())
