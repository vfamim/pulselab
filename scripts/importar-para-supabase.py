#!/usr/bin/env python3
"""
PulseLab — Importador Manual de Dados Locais para o Supabase e SQLite Consolidado.
================================================================================
Lê arquivos de sessão (.json) e eventos (.jsonl) coletados offline (em pendrives
ou na pasta dados_locais), valida o manifesto SHA-256 de integridade da coleta,
consolida em uma base SQLite local com rastreamento de inserção, quarentena e
duplicação, e envia para o banco central Supabase exigindo credencial operacional
autenticada (service_role ou JWT operacional) e garantindo idempotência e divide-and-conquer.

Zero dependências externas: biblioteca padrão do Python (sqlite3, urllib, json, hashlib).
"""

from __future__ import annotations

import argparse
import base64
import datetime
import hashlib
import hmac
import json
import os
from pathlib import Path
import sqlite3
import sys
import urllib.error
import urllib.request
import uuid


DEFAULT_SUPABASE_URL = "https://cylsqbmtglvdfubbarqe.supabase.co"
DEFAULT_SUPABASE_ANON_KEY = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN5bHNxYm10Z2x2ZGZ1YmJhcnFlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5NjE1MzIsImV4cCI6MjA5MzUzNzUzMn0."
    "tscU354WLjnYz6E6NOrDQK16ViWBc-Af5FYhvZikFbU"
)


def is_anon_key(key: str) -> bool:
    """Verifica se a chave fornecida é a chave pública anônima padrão ou possui role anon."""
    if not key or key == DEFAULT_SUPABASE_ANON_KEY:
        return True
    try:
        parts = key.split(".")
        if len(parts) == 3:
            padding = "=" * ((4 - len(parts[1]) % 4) % 4)
            payload_bytes = base64.urlsafe_b64decode(parts[1] + padding)
            payload = json.loads(payload_bytes.decode("utf-8"))
            if payload.get("role") == "anon":
                return True
    except Exception:
        pass
    return False


def load_operational_credentials(
    repo_root: Path, explicit_key: str = "", explicit_url: str = ""
) -> tuple[str, str]:
    """
    Carrega credenciais operacionais adequadas (service_role ou JWT operacional explícito).
    Não aceita a chave anônima pública (anon key), que foi revogada pelo RLS.
    """
    url = explicit_url or os.environ.get("PULSELAB_SUPABASE_URL", "")
    key = (
        explicit_key
        or os.environ.get("PULSELAB_SERVICE_ROLE_KEY", "")
        or os.environ.get("PULSELAB_OPERATIONAL_JWT", "")
    )

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
            except Exception:
                pass

    return url or DEFAULT_SUPABASE_URL, key


def verify_manifest_signature(
    target_dir: Path,
    hmac_key: str = "",
    require_signature: bool = False,
) -> tuple[bool, str]:
    """
    Verifica a autenticidade do manifesto através de assinatura HMAC-SHA256 institucional.
    - Usa compare_digest para prevenir timing attacks.
    - Se require_signature=True: falha se chave ou assinatura estiverem ausentes ou inválidas.
    - Se require_signature=False e assinatura ausente: retorna (True, "unsigned").
    """
    manifest_candidates = list(target_dir.glob("manifesto_*.txt"))
    if not manifest_candidates:
        if require_signature:
            return False, "Manifesto ausente para verificação de autenticidade."
        return True, "no_manifest"

    manifest_file = manifest_candidates[0]
    sig_candidates = [
        manifest_file.with_suffix(".sig"),
        target_dir / f"{manifest_file.name}.sig",
        target_dir / "manifesto_coleta.sig",
    ]
    sig_candidates.extend(list(target_dir.glob("manifesto_*.sig")))

    sig_file: Path | None = None
    for cand in sig_candidates:
        if cand.is_file():
            sig_file = cand
            break

    if not sig_file:
        if require_signature:
            return False, "Assinatura institucional ausente: envio privilegiado em nuvem exige manifesto assinado (manifesto_coleta.sig)."
        return True, "unsigned"

    if not hmac_key:
        if require_signature:
            return False, "Chave institucional ausente: envio privilegiado em nuvem exige PULSELAB_MANIFEST_HMAC_KEY configurada no ambiente."
        return False, "Assinatura presente mas chave PULSELAB_MANIFEST_HMAC_KEY ausente."

    try:
        expected_sig = sig_file.read_text(encoding="utf-8").strip().lower()
        if len(expected_sig) != 64 or not all(c in "0123456789abcdef" for c in expected_sig):
            return False, f"Formato de assinatura inválido em {sig_file.name} (esperado digest hexadecimal de 64 caracteres)."

        manifest_bytes = manifest_file.read_bytes()
        actual_hmac = hmac.new(
            hmac_key.encode("utf-8"),
            manifest_bytes,
            hashlib.sha256
        ).hexdigest().lower()

        if hmac.compare_digest(actual_hmac, expected_sig):
            return True, f"Assinatura HMAC-SHA256 institucional válida ({sig_file.name})"
        else:
            return False, f"Assinatura HMAC-SHA256 institucional inválida ou divergente em {sig_file.name} (digest divergente)."
    except Exception as exc:
        return False, f"Erro ao processar assinatura HMAC-SHA256: {exc}"


def validate_manifest(
    target_dir: Path,
    require_manifest: bool = True,
    hmac_key: str = "",
    require_signature: bool = False,
) -> tuple[bool, str]:
    """
    Valida a integridade dos arquivos em uma pasta de coleta através do manifesto_*.txt
    e a autenticidade de origem via HMAC-SHA256 institucional.
    - Se require_manifest=True e não houver manifesto: falha de forma segura.
    - Se o manifesto estiver vazio ou não contiver hashes válidos: falha de forma segura.
    - Se houver path traversal, duplicatas de declaração ou ambiguidade em formato legado: falha de forma segura.
    - Se houver arquivo ausente ou adulterado (SHA-256 divergente): falha de forma segura.
    - Se houver arquivo .json ou .jsonl extra na pasta que não esteja declarado no manifesto: falha de forma segura.
    - Se require_signature=True: exige assinatura HMAC válida com PULSELAB_MANIFEST_HMAC_KEY.
    """
    manifest_candidates = list(target_dir.glob("manifesto_*.txt"))
    if not manifest_candidates:
        if require_manifest:
            return False, f"Manifesto ausente: nenhum manifesto_*.txt encontrado em '{target_dir.name}'."
        return True, "no_manifest"

    target_dir_resolved = target_dir.resolve()

    for manifest_file in manifest_candidates:
        try:
            content = manifest_file.read_text(encoding="utf-8", errors="replace")
        except Exception as exc:
            return False, f"Falha ao ler manifesto {manifest_file.name}: {exc}"

        lines = content.splitlines()
        in_hash_section = False
        checked_files = 0
        declared_entries: set[str] = set()
        verified_file_paths: set[Path] = set()

        for line in lines:
            line_str = line.strip()
            if not line_str:
                continue
            if "INTEGRIDADE DOS ARQUIVOS (SHA-256):" in line_str:
                in_hash_section = True
                continue
            if not in_hash_section or line_str.startswith("="):
                continue

            parts = line_str.split(maxsplit=1)
            if len(parts) == 2 and len(parts[0]) == 64:
                expected_hash = parts[0].lower()
                raw_path_str = parts[1].strip()

                norm_key = raw_path_str.replace("\\", "/").lower()
                if norm_key in declared_entries:
                    return False, f"Entrada duplicada no manifesto: {raw_path_str}"
                declared_entries.add(norm_key)

                # Bloquear path traversal
                parts_path = [p for p in raw_path_str.replace("\\", "/").split("/") if p]
                if ".." in parts_path or raw_path_str.startswith("/") or raw_path_str.startswith("\\") or ":" in raw_path_str:
                    return False, f"Path traversal detectado no manifesto: {raw_path_str}"

                # Resolver arquivo: formato com caminho relativo canônico vs formato legado com basename
                has_subpath = "/" in raw_path_str or "\\" in raw_path_str
                if has_subpath:
                    normalized_rel = Path(raw_path_str.replace("\\", "/"))
                    candidate_path = (target_dir / normalized_rel).resolve()
                    try:
                        if not candidate_path.is_relative_to(target_dir_resolved):
                            return False, f"Caminho escapa da pasta de coleta: {raw_path_str}"
                    except AttributeError:
                        if not str(candidate_path).startswith(str(target_dir_resolved)):
                            return False, f"Caminho escapa da pasta de coleta: {raw_path_str}"

                    if not candidate_path.is_file():
                        return False, f"Arquivo listado no manifesto está ausente: {raw_path_str}"
                    fpath = candidate_path
                else:
                    matches = [
                        p.resolve() for p in target_dir.rglob(raw_path_str)
                        if p.is_file() and p.name == raw_path_str
                    ]
                    if not matches:
                        return False, f"Arquivo listado no manifesto está ausente: {raw_path_str}"
                    if len(matches) > 1:
                        matches_rel = [p.relative_to(target_dir_resolved).as_posix() for p in matches]
                        return False, f"Ambiguidade no manifesto legado: múltiplos arquivos correspondem a '{raw_path_str}': {matches_rel}"
                    fpath = matches[0]

                if fpath in verified_file_paths:
                    return False, f"Conflito no manifesto: múltiplos registros apontam para o mesmo arquivo em disco: {fpath.name}"

                try:
                    actual_hash = hashlib.sha256(fpath.read_bytes()).hexdigest().lower()
                except Exception as exc:
                    return False, f"Falha ao ler {raw_path_str} para validação SHA-256: {exc}"

                if actual_hash != expected_hash:
                    return False, f"Adulteração detectada em {raw_path_str}: esperado {expected_hash}, obtido {actual_hash}"

                verified_file_paths.add(fpath)
                checked_files += 1

        if checked_files == 0:
            return False, f"Manifesto vazio ou inválido: nenhum arquivo verificado em {manifest_file.name}."

        # Verificação de arquivos extras (.json ou .jsonl) não declarados
        for cand_path in target_dir.rglob("*"):
            if cand_path.is_file() and cand_path.suffix.lower() in (".json", ".jsonl"):
                if cand_path.name.startswith("relatorio_") or cand_path.name.startswith("rejeicoes_"):
                    continue
                if cand_path.resolve() not in verified_file_paths:
                    return False, f"Arquivo extra não declarado no manifesto: {cand_path.name}"

    # Verificação de autenticidade HMAC-SHA256 institucional
    if require_signature or hmac_key:
        sig_valid, sig_msg = verify_manifest_signature(
            target_dir, hmac_key=hmac_key, require_signature=require_signature
        )
        if not sig_valid:
            return False, sig_msg
        if sig_msg.startswith("Assinatura HMAC-SHA256 institucional válida"):
            return True, f"Manifesto válido e autenticado ({checked_files} arquivos verificados)"
        return True, f"Manifesto válido ({checked_files} arquivos verificados, origem não autenticada)"

    return True, f"Manifesto válido ({checked_files} arquivos verificados)"


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
                occurred_at TEXT,
                timestamp TEXT,
                group_id TEXT,
                team_role TEXT,
                activity_stage TEXT,
                response_status TEXT,
                knowledge_answers_json TEXT,
                prior_robotics TEXT,
                mission_performance TEXT,
                primary_issue TEXT,
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
                occurred_at TEXT,
                timestamp TEXT,
                details_json TEXT,
                source_file TEXT,
                imported_at TEXT
            )
        """)

        conn.execute("""
            CREATE TABLE IF NOT EXISTS quarantined_events (
                event_id TEXT PRIMARY KEY,
                session_id TEXT,
                event_type TEXT,
                occurred_at TEXT,
                reason TEXT,
                raw_payload TEXT,
                source_file TEXT,
                quarantined_at TEXT
            )
        """)

        conn.execute("CREATE INDEX IF NOT EXISTS idx_events_session ON events(session_id);")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_session_events_session ON session_events(session_id);")

    # Migração retrocompatível de colunas se o banco já existia
    cur = conn.cursor()
    for tbl, cols in [
        ("events", ["occurred_at", "response_status", "knowledge_answers_json", "prior_robotics", "mission_performance", "primary_issue"]),
        ("session_events", ["occurred_at"]),
    ]:
        existing = {row[1] for row in cur.execute(f"PRAGMA table_info({tbl})").fetchall()}
        for col in cols:
            if col not in existing:
                try:
                    conn.execute(f"ALTER TABLE {tbl} ADD COLUMN {col} TEXT;")
                except Exception:
                    pass

    return conn


TABLE_PK_CONSTRAINTS = {
    "research_events": {"research_events_pkey"},
    "research_session_events": {"research_session_events_pkey"},
    "research_bancada_sessions": {"research_bancada_sessions_pkey"},
}


def is_pk_conflict(err_body: str, id_col: str, table: str) -> bool:
    """
    Verifica se o erro HTTP 409 corresponde comprovadamente à chave primária esperada (id_col)
    da tabela alvo (table). Violações em outras constraints de unicidade, FKs ou PKs
    não relacionadas retornam False.
    """
    err_lower = str(err_body).lower()
    has_marker = (
        "23505" in err_lower
        or "duplicate key" in err_lower
        or "unique constraint" in err_lower
        or "already exists" in err_lower
    )
    if not has_marker:
        return False

    norm_col = id_col.lower()
    expected_constraints = TABLE_PK_CONSTRAINTS.get(table, set())

    # Verifica se alguma constraint esperada da tabela está nomeada no corpo do erro
    has_expected_constraint = any(c.lower() in err_lower for c in expected_constraints)

    # Verifica se os detalhes do PostgreSQL indicam explicitamente a coluna da PK
    has_expected_column = f"({norm_col})=" in err_lower or f"key ({norm_col})" in err_lower

    if has_expected_constraint or has_expected_column:
        return True

    return False


def send_to_supabase(
    table: str,
    records: list[dict],
    supabase_url: str,
    supabase_key: str,
    batch_size: int = 40,
    id_col: str = "event_id",
    is_snapshot: bool = False,
    rejected_sink: list[dict] | None = None,
) -> tuple[int, int, int, str | None]:
    """
    Envia registros para o Supabase com divide-and-conquer em caso de erro em lote,
    resolução estrita de 23505 apenas na PK esperada, contagem honesta e coleta de
    rejeições remotas para quarentena.
    Snapshots utilizam resolution=merge-duplicates para atualizar todos os campos.
    Retorna: (inseridos_ou_atualizados, duplicados_confirmados, rejeitados, ultimo_erro)
    """
    if not records or not supabase_url or not supabase_key:
        return 0, 0, 0, None

    endpoint = f"{supabase_url.rstrip('/')}/rest/v1/{table}?on_conflict={id_col}"
    is_service_role = False
    try:
        parts = supabase_key.split(".")
        if len(parts) == 3:
            padding = "=" * ((4 - len(parts[1]) % 4) % 4)
            payload_bytes = base64.urlsafe_b64decode(parts[1] + padding)
            payload_data = json.loads(payload_bytes.decode("utf-8"))
            if payload_data.get("role") == "service_role":
                is_service_role = True
    except Exception:
        pass

    resolution = "merge-duplicates" if (is_snapshot and is_service_role) else "ignore-duplicates"
    prefer_header = f"resolution={resolution},return=representation" if is_service_role else f"resolution={resolution},return=minimal"
    api_key_header = supabase_key if is_service_role else DEFAULT_SUPABASE_ANON_KEY

    inserted = 0
    duplicates = 0
    rejected = 0
    last_error = None

    def send_chunk(chunk: list[dict]) -> tuple[int, int, int, str | None]:
        nonlocal last_error
        if not chunk:
            return 0, 0, 0, None

        payload = json.dumps(chunk).encode("utf-8")
        req = urllib.request.Request(
            endpoint,
            data=payload,
            headers={
                "Content-Type": "application/json",
                "apikey": api_key_header,
                "Authorization": f"Bearer {supabase_key}",
                "Prefer": prefer_header,
            },
            method="POST",
        )

        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                resp_body = resp.read().decode("utf-8")
                returned = json.loads(resp_body) if resp_body.strip() else []
                num_returned = len(returned) if isinstance(returned, list) else len(chunk)
                num_dup = len(chunk) - num_returned
                return num_returned, num_dup, 0, None
        except urllib.error.HTTPError as exc:
            err_body = ""
            try:
                err_body = exc.read().decode("utf-8")
            except Exception:
                pass

            # Divide-and-conquer para lotes maiores que 1
            if len(chunk) > 1:
                mid = len(chunk) // 2
                ins1, dup1, rej1, err1 = send_chunk(chunk[:mid])
                ins2, dup2, rej2, err2 = send_chunk(chunk[mid:])
                return ins1 + ins2, dup1 + dup2, rej1 + rej2, err2 or err1

            # Item individual (len == 1)
            if exc.code == 409 and is_pk_conflict(err_body, id_col, table):
                return 0, 1, 0, None
            else:
                err_msg = f"HTTP {exc.code} ({table}): {err_body or exc.reason}"
                last_error = err_msg
                if rejected_sink is not None:
                    rejected_sink.append({
                        "table": table,
                        "record": chunk[0],
                        "error": err_msg,
                        "status": exc.code,
                        "id_col": id_col,
                    })
                return 0, 0, 1, err_msg
        except Exception as exc:
            if len(chunk) > 1:
                mid = len(chunk) // 2
                ins1, dup1, rej1, err1 = send_chunk(chunk[:mid])
                ins2, dup2, rej2, err2 = send_chunk(chunk[mid:])
                return ins1 + ins2, dup1 + dup2, rej1 + rej2, err2 or err1
            last_error = str(exc)
            if rejected_sink is not None:
                rejected_sink.append({
                    "table": table,
                    "record": chunk[0],
                    "error": str(exc),
                    "status": None,
                    "id_col": id_col,
                })
            return 0, 0, 1, str(exc)

    for i in range(0, len(records), batch_size):
        chunk = records[i : i + batch_size]
        ins, dup, rej, err = send_chunk(chunk)
        inserted += ins
        duplicates += dup
        rejected += rej
        if err:
            last_error = err

    return inserted, duplicates, rejected, last_error


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
    "free_feedback", "rubric_assembly", "rubric_circuit", "rubric_support",
    "occurred_at"
}

ALLOWED_SESSION_EVENTS = {
    "session_started", "phase_completed", "phase_transition", "activity_started",
    "heartbeat", "checkpoint_started", "checkpoint_completed", "help_requested",
    "role_swapped", "spike_telemetry", "experience_recorded", "race_recorded",
    "quiz_recorded", "ending_requested", "rubric_completed",
    "session_completed", "session_aborted", "quality_issue"
}

ALLOWED_RESEARCH_EVENTS = {"pre", "checkpoint", "post", "rubric"}


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

    # Preservação estrita do occurred_at original
    original_occurred_at = event.get("occurred_at") or event.get("timestamp") or event.get("_client_occurred_at")
    if original_occurred_at:
        payload["occurred_at"] = original_occurred_at

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

    original_type = event.get("event_type", "")
    payload["event_type"] = original_type

    if target_table == "research_events":
        if "participant_id" not in payload:
            payload["participant_id"] = event.get("participant_id") or "bancada"
        if "participant_role" not in payload:
            payload["participant_role"] = event.get("participant_role") or "group"
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
            payload["config_version"] = event.get("config_version") or "2.2.7"
        if "client_version" not in payload:
            payload["client_version"] = event.get("client_version") or "2.2.7"
        if "response_status" not in payload:
            payload["response_status"] = event.get("response_status") or "completed"

        if original_type not in ALLOWED_RESEARCH_EVENTS:
            payload["_is_quarantine"] = True
            payload["_quarantine_reason"] = f"Tipo de resposta não reconhecido: {original_type}"

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
            payload["protocol_version"] = event.get("protocol_version") or "v2.2"
        if "config_version" not in payload:
            payload["config_version"] = event.get("config_version") or "2.2.7"
        if "config_hash" not in payload or not payload["config_hash"]:
            payload["config_hash"] = "3c3662c7306d64236b0f7f26da183cc59a36c00061a2077d93fb0272876b2468"
        if "client_version" not in payload:
            payload["client_version"] = event.get("client_version") or "2.2.7"


        # Invariante metodológica: NUNCA converter silenciosamente tipo desconhecido em phase_completed
        if original_type not in ALLOWED_SESSION_EVENTS:
            payload["_is_quarantine"] = True
            payload["_quarantine_reason"] = f"Tipo de evento não canônico: {original_type}"

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

    desktop = Path.home() / "Desktop" / "Coleta-PulseLab"
    if desktop.is_dir():
        sources.append(desktop)

    if sys.platform.startswith("win"):
        for letter in "DEFGHIJKLMNOPQRSTUVWXYZ":
            candidate = Path(f"{letter}:\\Coleta-PulseLab")
            if candidate.is_dir():
                sources.append(candidate)

    local_data = repo_root / "dados_locais"
    if local_data.is_dir():
        sources.append(local_data)

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
        help="URL da instância Supabase (ou usa PULSELAB_SUPABASE_URL).",
        default="",
    )
    parser.add_argument(
        "--supabase-key",
        help="Chave de API operacional do Supabase (service_role ou JWT operacional).",
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
    parser.add_argument(
        "--allow-unverified",
        action="store_true",
        help="Permite importar pastas sem manifesto (desaconselhado em produção de pesquisa).",
    )
    parser.add_argument(
        "--manifest-hmac-key",
        help="Chave HMAC-SHA256 institucional para autenticação do manifesto (ou usa PULSELAB_MANIFEST_HMAC_KEY).",
        default="",
    )

    args = parser.parse_args()
    repo_root = Path(__file__).resolve().parent.parent

    print("====================================================================")
    print("   PULSELAB — IMPORTADOR E CONSOLIDADOR DE DADOS OFFLINE")
    print("====================================================================")
    print(f"Data/Hora: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")

    # Falha 1: Autenticação operacional exigida para envio remoto
    sb_url = ""
    sb_key = ""
    if not args.no_cloud:
        sb_url, sb_key = load_operational_credentials(
            repo_root, explicit_key=args.supabase_key, explicit_url=args.supabase_url
        )
        if not sb_key or is_anon_key(sb_key):
            print("=" * 68)
            print("[ERRO DE AUTENTICAÇÃO] Credencial operacional autorizada obrigatória!")
            print("=" * 68)
            print("O envio de dados para o Supabase requer uma credencial operacional autorizada")
            print("(service_role ou JWT de pesquisador/operacional). A chave anônima (anon key)")
            print("foi revogada no banco de dados pela migration de segurança.")
            print()
            print("Como proceder:")
            print("  1. Para sincronizar com a nuvem, forneça a credencial operacional:")
            print("     export PULSELAB_SERVICE_ROLE_KEY='<sua-chave-operacional>'")
            print("     ou passe via argumento: --supabase-key '<chave>'")
            print()
            print("  2. Para importar e consolidar localmente no SQLite sem envio à nuvem:")
            print("     python scripts/importar-para-supabase.py --no-cloud")
            print("=" * 68 + "\n")
            return 1

    sources = find_data_sources(args.source, repo_root)
    if not sources:
        print("[ERRO] Nenhuma fonte de dados encontrada.")
        print("Certifique-se de conectar o pendrive ou indicar o caminho com --source.")
        return 1

    print(f"Fontes de dados detectadas ({len(sources)}):")
    for s in sources:
        print(f"  📁 {s}")
    print()

    sqlite_file = (
        Path(args.sqlite_path).resolve()
        if args.sqlite_path
        else (repo_root / "dados_locais" / "pulselab_consolidado.sqlite")
    )
    conn = init_sqlite_database(sqlite_file)
    print(f"[OK] Banco SQLite consolidado pronto em:\n     {sqlite_file}\n")

    session_files: list[Path] = []
    events_files: list[Path] = []
    raw_sessions_data: list[dict] = []

    hmac_key = (
        args.manifest_hmac_key
        or os.environ.get("PULSELAB_MANIFEST_HMAC_KEY", "")
    )

    for src in sources:
        sub_collects = [p for p in src.glob("Coleta_*") if p.is_dir()]
        target_dirs = sub_collects if sub_collects else [src]

        for tdir in target_dirs:
            # Validação estrita de integridade SHA-256 e autenticidade HMAC-SHA256 institucional
            require_m = not args.allow_unverified
            require_sig = not args.no_cloud
            valid, manifest_msg = validate_manifest(
                tdir,
                require_manifest=require_m,
                hmac_key=hmac_key,
                require_signature=require_sig,
            )
            if not valid:
                print(f"[!] SEGURANÇA: Pasta rejeitada por falha no manifesto ({tdir.name}): {manifest_msg}")
                continue
            elif "autenticado" in manifest_msg or "Assinatura HMAC-SHA256" in manifest_msg:
                print(f"[✓] Origem autenticada e integridade comprovada via HMAC-SHA256 em: {tdir.name} ({manifest_msg})")
            elif manifest_msg != "no_manifest":
                print(f"[!] Integridade verificada, origem não autenticada em: {tdir.name} ({manifest_msg})")

            s_dir = tdir / "sessoes"
            if s_dir.is_dir():
                session_files.extend(s_dir.glob("*.json"))
            else:
                session_files.extend(tdir.glob("sessao_*.json"))

            ev_f = tdir / "events.jsonl"
            if ev_f.is_file():
                events_files.append(ev_f)
            ev_arch = tdir / "events_archive.jsonl"
            if ev_arch.is_file():
                events_files.append(ev_arch)

    session_files = list({p.resolve(): p for p in session_files}.values())
    events_files = list({p.resolve(): p for p in events_files}.values())

    if not args.no_cloud and not session_files and not events_files:
        print("[ERRO] Nenhuma pasta de coleta atendeu aos requisitos de integridade e autenticidade institucional para envio à nuvem.")
        return 1

    print(f"\nArquivos íntegros validados para importação:")
    print(f"  - Sessões completas (.json): {len(session_files)}")
    print(f"  - Arquivos de eventos (.jsonl): {len(events_files)}\n")

    now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()

    # 1. Processar Sessões (Falha 9: atualização completa coerente sem registro híbrido)
    sessions_inserted = 0
    sessions_updated = 0
    all_events_from_sessions: list[dict] = []

    for sf in session_files:
        try:
            content = sf.read_text(encoding="utf-8-sig")
            data = json.loads(content)
            sess_id = data.get("session_id")
            if not sess_id:
                continue

            raw_sessions_data.append(data)
            events_list = data.get("events") or []
            if isinstance(events_list, list):
                all_events_from_sessions.extend(events_list)

            cur = conn.cursor()
            cur.execute("SELECT session_id FROM sessions WHERE session_id = ?", (sess_id,))
            exists = cur.fetchone() is not None

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
                        group_id = excluded.group_id,
                        site_id = excluded.site_id,
                        regional_hub = excluded.regional_hub,
                        school_code = excluded.school_code,
                        workshop_code = excluded.workshop_code,
                        class_code = excluded.class_code,
                        activity_id = excluded.activity_id,
                        started_at = excluded.started_at,
                        completed_at = excluded.completed_at,
                        duration_seconds = excluded.duration_seconds,
                        team_role = excluded.team_role,
                        status = excluded.status,
                        pre_answers_json = excluded.pre_answers_json,
                        post_answers_json = excluded.post_answers_json,
                        spike_telemetry_json = excluded.spike_telemetry_json,
                        events_count = excluded.events_count,
                        source_file = excluded.source_file,
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

            if exists:
                sessions_updated += 1
            else:
                sessions_inserted += 1
        except Exception as exc:
            print(f"[!] Erro ao processar sessão {sf.name}: {exc}")

    print(f"[✓] Sessões SQLite: {sessions_inserted} inseridas, {sessions_updated} atualizadas.")

    # 2. Processar Eventos (Falha 9: contabilizar JSON inválido, evento sem event_id e erros de sanitização)
    events_to_upload_research: list[dict] = []
    events_to_upload_session: list[dict] = []
    quarantined_events: list[dict] = []

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

    for ev in all_events_from_sessions:
        all_raw_event_lines.append((json.dumps(ev), "session_json"))

    events_inserted_sqlite = 0
    events_duplicate_sqlite = 0
    events_rejected_sqlite = 0

    rejections_file = repo_root / "dados_locais" / "rejeicoes_importacao.jsonl"
    rejections_file.parent.mkdir(parents=True, exist_ok=True)

    with conn:
        for raw_line, src_name in all_raw_event_lines:
            try:
                ev = json.loads(raw_line)
            except Exception as exc:
                events_rejected_sqlite += 1
                rej_id = f"corrupt-json-{hashlib.sha256(raw_line.encode('utf-8', errors='replace')).hexdigest()[:12]}"
                rej_reason = f"JSON malformado/inválido: {exc}"
                conn.execute("""
                    INSERT OR IGNORE INTO quarantined_events (
                        event_id, session_id, event_type, occurred_at, reason, raw_payload, source_file, quarantined_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, (rej_id, "", "corrupt_json", None, rej_reason, raw_line, src_name, now_iso))
                with rejections_file.open("a", encoding="utf-8") as rf:
                    rf.write(json.dumps({"rejection_id": rej_id, "reason": rej_reason, "source": src_name, "raw": raw_line}) + "\n")
                continue

            event_id = ev.get("event_id")
            if not event_id:
                events_rejected_sqlite += 1
                rej_id = f"missing-id-{hashlib.sha256(raw_line.encode('utf-8', errors='replace')).hexdigest()[:12]}"
                rej_reason = "Evento sem event_id obrigatório"
                conn.execute("""
                    INSERT OR IGNORE INTO quarantined_events (
                        event_id, session_id, event_type, occurred_at, reason, raw_payload, source_file, quarantined_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, (rej_id, ev.get("session_id", ""), ev.get("event_type", ""), ev.get("occurred_at"), rej_reason, raw_line, src_name, now_iso))
                with rejections_file.open("a", encoding="utf-8") as rf:
                    rf.write(json.dumps({"rejection_id": rej_id, "reason": rej_reason, "source": src_name, "raw": raw_line}) + "\n")
                continue

            event_type = ev.get("event_type", "")
            session_id = ev.get("session_id", "")
            occurred_at = ev.get("occurred_at") or ev.get("timestamp") or ev.get("_client_occurred_at") or None
            timestamp = occurred_at or now_iso
            group_id = ev.get("group_id", "")
            team_role = ev.get("team_role", "")
            stage = ev.get("activity_stage", "")
            details = ev.get("details") or {}
            resp_status = ev.get("response_status", "completed")

            if event_type in ALLOWED_RESEARCH_EVENTS:
                clean_ev = sanitize_event_for_supabase(ev, "research_events")
                if clean_ev.get("_is_quarantine"):
                    quarantined_events.append(clean_ev)
                    conn.execute("""
                        INSERT OR IGNORE INTO quarantined_events (
                            event_id, session_id, event_type, occurred_at, reason, raw_payload, source_file, quarantined_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, (event_id, session_id, event_type, occurred_at, clean_ev.get("_quarantine_reason"), raw_line, src_name, now_iso))
                else:
                    events_to_upload_research.append(clean_ev)

                cur = conn.cursor()
                cur.execute("""
                    INSERT OR IGNORE INTO events (
                        event_id, session_id, event_type, occurred_at, timestamp, group_id,
                        team_role, activity_stage, response_status, details_json, source_file, imported_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    event_id, session_id, event_type, occurred_at, timestamp, group_id,
                    team_role, stage, resp_status, json.dumps(details), src_name, now_iso
                ))
                if cur.rowcount > 0:
                    events_inserted_sqlite += 1
                else:
                    events_duplicate_sqlite += 1

            elif event_type in ALLOWED_SESSION_EVENTS:
                clean_ev = sanitize_event_for_supabase(ev, "research_session_events")
                if clean_ev.get("_is_quarantine"):
                    quarantined_events.append(clean_ev)
                    conn.execute("""
                        INSERT OR IGNORE INTO quarantined_events (
                            event_id, session_id, event_type, occurred_at, reason, raw_payload, source_file, quarantined_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, (event_id, session_id, event_type, occurred_at, clean_ev.get("_quarantine_reason"), raw_line, src_name, now_iso))
                else:
                    events_to_upload_session.append(clean_ev)

                cur = conn.cursor()
                cur.execute("""
                    INSERT OR IGNORE INTO session_events (
                        event_id, session_id, event_type, occurred_at, timestamp,
                        details_json, source_file, imported_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    event_id, session_id, event_type, occurred_at, timestamp,
                    json.dumps(details), src_name, now_iso
                ))
                if cur.rowcount > 0:
                    events_inserted_sqlite += 1
                else:
                    events_duplicate_sqlite += 1
            else:
                # Tipo não canônico/desconhecido: preserva intacto em quarantined_events, nunca converte
                quarantined_events.append(ev)
                conn.execute("""
                    INSERT OR IGNORE INTO quarantined_events (
                        event_id, session_id, event_type, occurred_at, reason, raw_payload, source_file, quarantined_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, (event_id, session_id, event_type, occurred_at, f"Tipo desconhecido preservado: {event_type}", raw_line, src_name, now_iso))

    print(f"[✓] Eventos SQLite: {events_inserted_sqlite} novos inseridos, {events_duplicate_sqlite} duplicados ignorados.")
    if events_rejected_sqlite > 0:
        print(f"[!] Rejeições SQLite: {events_rejected_sqlite} linhas com JSON inválido ou sem event_id preservadas em quarantined_events.")
    if quarantined_events:
        print(f"[!] Quarentena local: {len(quarantined_events)} eventos com tipos não canônicos preservados em quarantined_events.")

    # 3. Enviar ao Supabase (se habilitado) (Falhas 1, 3 e 9)
    remote_rejections: list[dict] = []
    ins_res = dup_res = rej_res = 0
    ins_sess = dup_sess = rej_sess = 0
    ins_bs = dup_bs = rej_bs = 0
    last_err1 = last_err2 = last_err3 = None
    res_unique: list[dict] = []
    sess_unique: list[dict] = []
    sess_list: list[dict] = []

    if args.no_cloud:
        print("\n[!] Modo offline ativado (--no-cloud): envio para Supabase ignorado.")
    elif not sb_url or not sb_key:
        print("\n[!] Supabase URL/Key operacional não configurada. Envio remoto ignorado.")
    else:
        print(f"\nSincronizando com o Supabase ({sb_url})...")

        # 3.1 research_events
        res_dict = {e["event_id"]: e for e in events_to_upload_research}
        res_unique = list(res_dict.values())
        print(f"  - Tabela 'research_events': {len(res_unique)} registros a verificar")
        ins_res, dup_res, rej_res, last_err1 = send_to_supabase(
            "research_events", res_unique, sb_url, sb_key, rejected_sink=remote_rejections
        )
        print(f"    ✓ Inseridos: {ins_res} | Duplicados confirmados (PK 23505): {dup_res} | Rejeitados: {rej_res}")
        if last_err1:
            print(f"    [!] Detalhes do erro: {last_err1}")

        # 3.2 research_session_events
        sess_dict = {e["event_id"]: e for e in events_to_upload_session}
        sess_unique = list(sess_dict.values())
        print(f"  - Tabela 'research_session_events': {len(sess_unique)} registros a verificar")
        ins_sess, dup_sess, rej_sess, last_err2 = send_to_supabase(
            "research_session_events", sess_unique, sb_url, sb_key, rejected_sink=remote_rejections
        )
        print(f"    ✓ Inseridos: {ins_sess} | Duplicados confirmados (PK 23505): {dup_sess} | Rejeitados: {rej_sess}")
        if last_err2:
            print(f"    [!] Detalhes do erro: {last_err2}")

        # 3.3 research_bancada_sessions (Snapshots consolidados com merge-duplicates)
        if raw_sessions_data:
            bancada_sessions_records = []
            for sdata in raw_sessions_data:
                sid = sdata.get("session_id")
                if not sid:
                    continue
                bancada_sessions_records.append({
                    "session_id": ensure_uuid(sid),
                    "group_id": ensure_uuid(sdata.get("group_id")),
                    "installation_id": ensure_uuid(sdata.get("installation_id") or sdata.get("computer_id") or "10000000-0000-4000-8000-000000000001"),
                    "site_id": sdata.get("site_id") or "Polo-Nordeste",
                    "school_code": sdata.get("school_code") or "geral",
                    "workshop_code": sdata.get("workshop_code") or "oficina-spike",
                    "class_code": sdata.get("class_code") or "turma-geral",
                    "environment": "test" if sdata.get("is_synthetic") else "production",
                    "protocol_version": sdata.get("protocol_version") or "v2.2",

                    "instrument_version": sdata.get("instrument_version") or "bancada-2.0.0",
                    "group_size": sdata.get("group_size") or 2,
                    "phase": sdata.get("phase") or "completed",
                    "session_payload": sdata,
                    "created_at": sdata.get("started_at") or now_iso,
                    "updated_at": sdata.get("completed_at") or now_iso,
                })
            sess_dedup = {r["session_id"]: r for r in bancada_sessions_records}
            sess_list = list(sess_dedup.values())
            print(f"  - Tabela 'research_bancada_sessions': {len(sess_list)} snapshots consolidados a sincronizar")
            ins_bs, dup_bs, rej_bs, last_err3 = send_to_supabase(
                "research_bancada_sessions", sess_list, sb_url, sb_key, id_col="session_id", is_snapshot=True, rejected_sink=remote_rejections
            )
            print(f"    ✓ Sincronizados/Atualizados: {ins_bs} | Duplicados: {dup_bs} | Rejeitados: {rej_bs}")
            if last_err3:
                print(f"    [!] Detalhes do erro: {last_err3}")

        # Persistir cada payload rejeitado remotamente em quarantined_events e no arquivo de rejeições
        if remote_rejections:
            with conn:
                for rej in remote_rejections:
                    tbl = rej["table"]
                    rec = rej["record"]
                    status_code = rej.get("status")
                    err_msg = rej["error"]
                    rec_id = str(rec.get("event_id") or rec.get("session_id") or uuid.uuid4())
                    sess_id = str(rec.get("session_id", ""))
                    ev_type = str(rec.get("event_type") or ("session_snapshot" if tbl == "research_bancada_sessions" else "unknown"))
                    occ_at = rec.get("occurred_at") or rec.get("updated_at") or now_iso
                    rej_reason = f"Rejeição remota Supabase [{tbl}] (status={status_code}): {err_msg}"
                    raw_str = json.dumps(rec)

                    conn.execute("""
                        INSERT INTO quarantined_events (
                            event_id, session_id, event_type, occurred_at, reason, raw_payload, source_file, quarantined_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(event_id) DO UPDATE SET
                            reason = excluded.reason,
                            raw_payload = excluded.raw_payload,
                            quarantined_at = excluded.quarantined_at
                    """, (rec_id, sess_id, ev_type, occ_at, rej_reason, raw_str, f"remote_supabase:{tbl}", now_iso))

                    with rejections_file.open("a", encoding="utf-8") as rf:
                        rf.write(json.dumps({
                            "rejection_id": rec_id,
                            "source": f"remote_supabase:{tbl}",
                            "status": status_code,
                            "reason": rej_reason,
                            "payload": rec,
                            "quarantined_at": now_iso
                        }) + "\n")

    # 4. Totalizadores e Resumo
    total_remote_inserted = ins_res + ins_sess + ins_bs
    total_remote_duplicates = dup_res + dup_sess + dup_bs
    total_remote_rejected = len(remote_rejections)

    if args.no_cloud or not sb_url or not sb_key:
        total_remote_pending = len(events_to_upload_research) + len(events_to_upload_session) + len(raw_sessions_data)
    else:
        total_target = len(res_unique) + len(sess_unique) + (len(sess_list) if raw_sessions_data else 0)
        total_remote_pending = max(0, total_target - (total_remote_inserted + total_remote_duplicates + total_remote_rejected))

    total_unresolved_rejections = total_remote_rejected + events_rejected_sqlite

    # 5. Gerar Relatório de Importação
    report_file = (
        repo_root / "dados_locais" / f"relatorio_importacao_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
    )
    report_text = f"""====================================================================
PULSELAB — RELATÓRIO DE IMPORTAÇÃO E CONSOLIDAÇÃO DE DADOS
====================================================================
Data/Hora da Execução : {now_iso}
Base SQLite Local     : {sqlite_file}
Sessões Inseridas     : {sessions_inserted}
Sessões Atualizadas   : {sessions_updated}
Eventos Inseridos     : {events_inserted_sqlite}
Eventos Duplicados    : {events_duplicate_sqlite}
Eventos Rejeitados    : {events_rejected_sqlite}
Eventos Quarentenados : {len(quarantined_events) + total_remote_rejected}
--------------------------------------------------------------------
Sincronização Remota Supabase:
Status de Envio       : {'Desabilitado (--no-cloud)' if args.no_cloud else (sb_url if sb_url else 'Não configurado')}
Registros Inseridos   : {total_remote_inserted}
Duplicados Comprovados: {total_remote_duplicates} (PK 23505)
Registros Rejeitados  : {total_remote_rejected} (quarentenados)
Registros Pendentes   : {total_remote_pending}
====================================================================
Fontes de dados analisadas:
{chr(10).join(' - ' + str(s) for s in sources)}
====================================================================
"""
    try:
        report_file.parent.mkdir(parents=True, exist_ok=True)
        report_file.write_text(report_text, encoding="utf-8")
        print(f"\n[OK] Relatório gravado em:\n     {report_file}")
    except Exception:
        pass

    print("\n====================================================================")
    print("RESUMO CONSOLIDADO DA IMPORTAÇÃO:")
    print("====================================================================")
    print("Base SQLite Local:")
    print(f"  - Inseridos: {events_inserted_sqlite} eventos, {sessions_inserted} sessões")
    print(f"  - Duplicados ignorados/atualizados: {events_duplicate_sqlite} eventos, {sessions_updated} sessões")
    print(f"  - Rejeitados/quarentenados: {events_rejected_sqlite + len(quarantined_events)} registros")
    print("Sincronização Remota Supabase:")
    print(f"  - Inseridos/atualizados: {total_remote_inserted}")
    print(f"  - Duplicados comprovados (PK 23505): {total_remote_duplicates}")
    print(f"  - Rejeitados/quarentenados: {total_remote_rejected}")
    print(f"  - Pendentes: {total_remote_pending}")
    print("====================================================================")

    if total_unresolved_rejections > 0:
        print("\n====================================================================")
        print("  [ATENÇÃO] IMPORTAÇÃO FINALIZADA COM REJEIÇÕES / ITENS EM QUARENTENA")
        print(f"  Total de rejeições não resolvidas: {total_unresolved_rejections}")
        print(f"  Consulte o arquivo de rejeições em:\n  {rejections_file}")
        print("====================================================================")
        return 2

    print("\n====================================================================")
    print("  PROCESSO DE IMPORTAÇÃO CONCLUÍDO COM SUCESSO!")
    print("====================================================================")
    return 0


if __name__ == "__main__":
    sys.exit(main())
