#!/usr/bin/env python3
"""
PulseLab — Revisão das aulas marcadas como não autorizadas.
==========================================================
"Não registrar esta turma" marca a aula no computador da bancada; os dados chegam à nuvem
(ou ao SQLite consolidado, por pendrive) com authorization_status = "nao_autorizada" e nunca
entram em análise. Esta ferramenta é a revisão do pesquisador:

  python3 tooling/data/revisar-nao-autorizadas.py                    # lista
  python3 tooling/data/revisar-nao-autorizadas.py --apagar <id>      # apaga uma (padrão da revisão)
  python3 tooling/data/revisar-nao-autorizadas.py --apagar-todas     # apaga todas as listadas
  python3 tooling/data/revisar-nao-autorizadas.py --restaurar <id> --motivo "texto"

Apagar grava o tombstone (research_withdrawals na nuvem, withdrawn_sessions no SQLite) antes de
remover, o que barra reenvio do bridge e reimportação por pendrive. Restaurar volta a aula para
autorizada e grava o motivo. Credenciais e variáveis são as do importador
(PULSELAB_SUPABASE_URL, PULSELAB_SERVICE_ROLE_KEY); a chave nunca é impressa.
"""

from __future__ import annotations

import argparse
import datetime
import importlib.util
import json
import sqlite3
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def _load_importer():
    spec = importlib.util.spec_from_file_location(
        "pulselab_importer", Path(__file__).resolve().with_name("importar-para-supabase.py")
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


imp = _load_importer()


# ---------------------------------------------------------------------------
# Nuvem (PostgREST, service_role)
# ---------------------------------------------------------------------------

class Cloud:
    def __init__(self, url: str, key: str):
        self.url, self.key = url, key
        self.base = url.rstrip("/") + "/rest/v1"
        self.headers = {"Content-Type": "application/json", "apikey": key, "Authorization": f"Bearer {key}"}

    def _request(self, path: str, method: str = "GET", body=None):
        data = json.dumps(body).encode("utf-8") if body is not None else None
        req = urllib.request.Request(f"{self.base}/{path}", data=data, headers=self.headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                raw = resp.read().decode("utf-8")
        except urllib.error.HTTPError as exc:
            detail = ""
            try:
                detail = exc.read().decode("utf-8")
            except Exception:
                pass
            raise RuntimeError(f"HTTP {exc.code} em {path.split('?')[0]}: {detail or exc.reason}") from None
        return json.loads(raw) if raw.strip() else None

    def list_marked(self) -> list[dict]:
        marks = self._request(
            "research_unauthorized_sessions?select=session_id,marked_at,site_id,installation_id"
            "&status=eq.nao_autorizada&order=marked_at.asc"
        ) or []
        if not marks:
            return []
        ids = ",".join(m["session_id"] for m in marks)
        select = urllib.parse.quote(
            "session_id,site_id,installation_id,"
            "computer_id:session_payload->>computer_id,"
            "started_at:session_payload->>started_at,"
            "duration_seconds:session_payload->>duration_seconds",
            safe=",:>-_",
        )
        snaps = self._request(f"research_bancada_sessions?select={select}&session_id=in.({ids})") or []
        by_id = {s["session_id"]: s for s in snaps}
        rows = []
        for m in marks:
            snap = by_id.get(m["session_id"], {})
            rows.append({
                "session_id": m["session_id"],
                "site_id": snap.get("site_id") or m.get("site_id"),
                "machine": snap.get("computer_id") or snap.get("installation_id") or m.get("installation_id"),
                "started_at": snap.get("started_at"),
                "duration_seconds": snap.get("duration_seconds"),
                "marked_at": m.get("marked_at"),
            })
        return rows

    def purge(self, session_id: str) -> dict:
        return self._request("rpc/review_purge_research_session", "POST", {"p_session_id": session_id}) or {}

    def restore(self, session_id: str, reason: str) -> dict:
        return self._request(
            "rpc/review_restore_research_session", "POST", {"p_session_id": session_id, "p_reason": reason}
        ) or {}


# ---------------------------------------------------------------------------
# SQLite consolidado (mesmo esquema e mesmas rotinas de retirada do importador)
# ---------------------------------------------------------------------------

def sqlite_list_marked(conn: sqlite3.Connection) -> list[dict]:
    cur = conn.execute("""
        SELECT u.session_id, s.site_id, s.machine_label, s.started_at, s.duration_seconds, u.marked_at
          FROM unauthorized_sessions u
          LEFT JOIN sessions s ON lower(s.session_id) = lower(u.session_id)
         WHERE u.status = 'nao_autorizada'
         ORDER BY u.marked_at
    """)
    return [
        {"session_id": r[0], "site_id": r[1], "machine": r[2], "started_at": r[3],
         "duration_seconds": r[4], "marked_at": r[5]}
        for r in cur.fetchall()
    ]


def sqlite_purge(conn: sqlite3.Connection, session_id: str, now_iso: str) -> int:
    """Tombstone em withdrawn_sessions antes de apagar, como o importador faz com as retiradas."""
    key = imp.session_key(session_id)
    imp.record_withdrawn_sqlite(conn, {key}, now_iso)
    removed = imp.purge_withdrawn_sqlite(conn, {key})
    with conn:
        conn.execute("DELETE FROM unauthorized_sessions WHERE lower(session_id) = lower(?)", (key,))
    return removed


def sqlite_restore(conn: sqlite3.Connection, session_id: str, reason: str, now_iso: str) -> bool:
    with conn:
        cur = conn.execute(
            "UPDATE unauthorized_sessions SET status = 'autorizada', restored_at = ?, restore_reason = ? "
            "WHERE lower(session_id) = lower(?) AND status = 'nao_autorizada'",
            (now_iso, reason, imp.session_key(session_id)),
        )
    return cur.rowcount > 0


# ---------------------------------------------------------------------------
# Listagem
# ---------------------------------------------------------------------------

def _local(value) -> tuple[str, str]:
    if not value:
        return "-", "-"
    try:
        dt = datetime.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=datetime.timezone.utc)
        dt = dt.astimezone()
        return dt.strftime("%d/%m/%Y"), dt.strftime("%H:%M")
    except ValueError:
        return str(value), "-"


def _minutes(value) -> str:
    try:
        return str(round(float(value) / 60))
    except (TypeError, ValueError):
        return "-"


def merge_listings(cloud_rows: list[dict], sqlite_rows: list[dict]) -> list[dict]:
    merged: dict[str, dict] = {}
    for origin, rows in (("nuvem", cloud_rows), ("sqlite", sqlite_rows)):
        for row in rows:
            key = imp.session_key(row["session_id"])
            item = merged.setdefault(key, {"session_id": key, "origins": []})
            item["origins"].append(origin)
            for field in ("site_id", "machine", "started_at", "duration_seconds", "marked_at"):
                if not item.get(field) and row.get(field) not in (None, ""):
                    item[field] = row[field]
    return list(merged.values())


def print_listing(rows: list[dict]) -> None:
    if not rows:
        print("Nenhuma aula marcada como não autorizada aguardando revisão.")
        return
    print(f"{'session_id':36}  {'polo':10} {'máquina':16} {'data':10} {'hora':5} {'min':>4}  {'marcada em':16}  onde")
    for r in rows:
        day, hour = _local(r.get("started_at"))
        mday, mhour = _local(r.get("marked_at"))
        print(
            f"{r['session_id']:36}  {str(r.get('site_id') or '-'):10.10} {str(r.get('machine') or '-'):16.16} "
            f"{day:10} {hour:5} {_minutes(r.get('duration_seconds')):>4}  {mday + ' ' + mhour:16}  "
            f"{'+'.join(r['origins'])}"
        )
    print(f"\n{len(rows)} aula(s) marcada(s). Padrão da revisão: --apagar <id> ou --apagar-todas.")


# ---------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Revisão das aulas marcadas como não autorizadas.")
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--apagar", metavar="SESSION_ID", action="append", help="Apaga a aula marcada (pode repetir).")
    action.add_argument("--apagar-todas", action="store_true", help="Apaga todas as aulas marcadas listadas.")
    action.add_argument("--restaurar", metavar="SESSION_ID", help="Volta a aula para autorizada (exige --motivo).")
    parser.add_argument("--motivo", default="", help="Motivo da restauração (fica gravado).")
    parser.add_argument("--sim", action="store_true", help="Não pede confirmação antes de apagar.")
    parser.add_argument("--no-cloud", action="store_true", help="Só o SQLite consolidado.")
    parser.add_argument("--sqlite-path", default="", help="SQLite consolidado (padrão: dados_locais/pulselab_consolidado.sqlite).")
    parser.add_argument("--supabase-url", default="", help="URL do Supabase (ou PULSELAB_SUPABASE_URL).")
    parser.add_argument("--supabase-key", default="", help="Chave service_role (ou PULSELAB_SERVICE_ROLE_KEY).")
    args = parser.parse_args(argv)

    if args.restaurar and not args.motivo.strip():
        parser.error("--restaurar exige --motivo \"texto\"")

    now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()

    cloud = None
    if not args.no_cloud:
        url, key = imp.load_operational_credentials(REPO_ROOT, explicit_key=args.supabase_key, explicit_url=args.supabase_url)
        if not key or imp.is_anon_key(key) or not imp.is_service_role_key(key):
            print("[ERRO] A revisão na nuvem exige a chave service_role do pesquisador "
                  "(PULSELAB_SERVICE_ROLE_KEY ou --supabase-key). Use --no-cloud para revisar só o SQLite.")
            return 1
        cloud = Cloud(url, key)

    sqlite_file = Path(args.sqlite_path).resolve() if args.sqlite_path else REPO_ROOT / "dados_locais" / "pulselab_consolidado.sqlite"
    conn = imp.init_sqlite_database(sqlite_file) if sqlite_file.exists() or args.sqlite_path else None
    try:
        return review(args, cloud, conn, now_iso)
    finally:
        if conn:
            conn.close()


def review(args, cloud: Cloud | None, conn: sqlite3.Connection | None, now_iso: str) -> int:
    try:
        cloud_rows = cloud.list_marked() if cloud else []
        sqlite_rows = sqlite_list_marked(conn) if conn else []
    except RuntimeError as exc:
        print(f"[ERRO] {exc}")
        return 1
    rows = merge_listings(cloud_rows, sqlite_rows)
    marked = {r["session_id"]: r for r in rows}

    if args.restaurar:
        sid = imp.session_key(args.restaurar)
        if sid not in marked:
            print(f"[ERRO] {sid} não está marcada como não autorizada.")
            return 1
        reason = args.motivo.strip()
        if cloud and "nuvem" in marked[sid]["origins"]:
            cloud.restore(sid, reason)
        if conn and "sqlite" in marked[sid]["origins"]:
            sqlite_restore(conn, sid, reason, now_iso)
        print(f"[OK] {sid} restaurada como autorizada. Motivo gravado: {reason}")
        return 0

    targets: list[str] = []
    if args.apagar_todas:
        targets = list(marked)
    elif args.apagar:
        targets = [imp.session_key(s) for s in args.apagar]
        unknown = [s for s in targets if s not in marked]
        if unknown:
            print(f"[ERRO] Não estão marcadas como não autorizadas: {', '.join(unknown)}")
            return 1

    if not targets:
        print_listing(rows)
        return 0

    print_listing([marked[s] for s in targets])
    if not args.sim:
        answer = input(f"\nApagar de vez {len(targets)} aula(s)? Digite APAGAR para confirmar: ")
        if answer.strip() != "APAGAR":
            print("Nada foi apagado.")
            return 1

    failures = 0
    for sid in targets:
        origins = marked[sid]["origins"]
        try:
            if cloud and "nuvem" in origins:
                cloud.purge(sid)
            elif cloud:
                # Marcada só no SQLite (pendrive): o tombstone na nuvem barra o envio atrasado pelo bridge.
                _, err = imp.withdraw_sessions_remote({sid}, cloud.url, cloud.key)
                if err:
                    raise RuntimeError(err)
            removed = sqlite_purge(conn, sid, now_iso) if conn else 0
            print(f"[OK] {sid} apagada ({'+'.join(origins)}; {removed} registro(s) no SQLite). Tombstone gravado.")
        except RuntimeError as exc:
            failures += 1
            print(f"[ERRO] {sid}: {exc}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
