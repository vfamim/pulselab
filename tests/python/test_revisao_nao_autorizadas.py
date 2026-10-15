"""Aula marcada como não autorizada: importador preserva a marca e a revisão lista, apaga e restaura.

Nuvem mockada (urllib.request.urlopen), SQLite sintético em pasta temporária.
"""

from __future__ import annotations

import base64
import contextlib
import hashlib
import importlib.util
import io
import json
import os
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

ROOT = Path(__file__).resolve().parents[2]


def load(name: str, rel: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


imp = load("importar_para_supabase_marks", "tooling/data/importar-para-supabase.py")
rev = load("revisar_nao_autorizadas", "tooling/data/revisar-nao-autorizadas.py")

MARKED = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
LISTED_ONLY = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
KEPT = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"


def fake_key(role: str) -> str:
    payload = base64.urlsafe_b64encode(json.dumps({"role": role}).encode()).decode().rstrip("=")
    return f"eyJhbGciOiJIUzI1NiJ9.{payload}.assinatura-secreta"


def snapshot(session_id: str, **extra) -> dict:
    data = {
        "session_id": session_id, "group_id": "g-1", "site_id": "PET", "status": "completed",
        "computer_id": "PET-LAB1-PC03", "started_at": "2026-10-15T17:05:00.000Z", "duration_seconds": 3000,
    }
    data.update(extra)
    return data


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.sqlite = self.root / "consolidado.sqlite"

    def tearDown(self):
        self.tmp.cleanup()

    def write_export(self, name: str, files: dict[str, bytes]) -> Path:
        folder = self.root / "coletas" / name
        lines = []
        for rel, content in files.items():
            path = folder / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
            lines.append(f"{hashlib.sha256(content).hexdigest().upper()}  {rel}")
        (folder / "manifesto_coleta.txt").write_text(
            "INTEGRIDADE DOS ARQUIVOS (SHA-256):\n\n" + "\n".join(lines) + "\n", encoding="utf-8"
        )
        return folder

    def import_no_cloud(self):
        argv = ["importar", "--no-cloud", "--source", str(self.root / "coletas"), "--sqlite-path", str(self.sqlite)]
        out = io.StringIO()
        with patch.object(imp, "__file__", str(self.root / "tooling" / "data" / "importar-para-supabase.py")), \
                patch.object(sys, "argv", argv), patch.dict(os.environ, {"PULSELAB_MANIFEST_HMAC_KEY": ""}), \
                contextlib.redirect_stdout(out):
            code = imp.main()
        return code, out.getvalue()

    def standard_export(self):
        events = "\n".join(json.dumps(e) for e in [
            {"event_id": "e1", "session_id": MARKED, "event_type": "session_started", "occurred_at": "2026-10-15T17:05:00Z"},
            {"event_id": "e2", "session_id": LISTED_ONLY, "event_type": "session_started", "occurred_at": "2026-10-15T19:00:00Z"},
            {"event_id": "e3", "session_id": KEPT, "event_type": "session_started", "occurred_at": "2026-10-15T13:00:00Z"},
        ]).encode("utf-8")
        listed = ("﻿" + f"{MARKED}\t2026-10-15T17:55:00.000Z\r\n{LISTED_ONLY}\t2026-10-15T19:40:00.000Z\r\n").encode("utf-8")
        return self.write_export("Coleta_PET-LAB1-PC03_20261015_200000", {
            "events.jsonl": events,
            f"sessoes/sessao_{MARKED}.json": json.dumps(snapshot(
                MARKED, authorization_status="nao_autorizada", marked_at="2026-10-15T17:55:00.000Z")).encode("utf-8"),
            f"sessoes/sessao_{LISTED_ONLY}.json": json.dumps(snapshot(LISTED_ONLY, started_at="2026-10-15T19:00:00.000Z")).encode("utf-8"),
            f"sessoes/sessao_{KEPT}.json": json.dumps(snapshot(KEPT, started_at="2026-10-15T13:00:00.000Z")).encode("utf-8"),
            "sessions_unauthorized.txt": listed,
        })


class ImportadorPreservaMarcacao(Base):
    def test_lista_da_coleta_precisa_estar_no_manifesto(self):
        folder = self.write_export("Coleta_A", {"events.jsonl": b"{}\n"})
        (folder / "sessions_unauthorized.txt").write_text(MARKED, encoding="utf-8")
        valid, msg = imp.validate_manifest(folder)
        self.assertFalse(valid)
        self.assertIn("sessions_unauthorized.txt", msg)

    def test_le_lista_com_bom_e_data_da_marcacao(self):
        (self.root / "sessions_unauthorized.txt").write_bytes(
            ("﻿" + MARKED.upper() + "\t2026-10-15T17:55:00.000Z\r\n\r\n" + KEPT + "\r\n").encode("utf-8"))
        self.assertEqual(imp.read_unauthorized_sessions(self.root),
                         {MARKED: "2026-10-15T17:55:00.000Z", KEPT: None})

    def test_importacao_guarda_dados_e_marca_fora_das_views_de_analise(self):
        self.standard_export()
        code, out = self.import_no_cloud()
        self.assertEqual(code, 0, out)
        self.assertIn("Aulas não autorizadas: 2", out)
        db = sqlite3.connect(str(self.sqlite))
        try:
            # Dados guardados, nada apagado
            self.assertEqual(db.execute("SELECT count(*) FROM sessions").fetchone()[0], 3)
            self.assertEqual(db.execute("SELECT count(*) FROM session_events").fetchone()[0], 3)
            marks = dict(db.execute("SELECT session_id, marked_at FROM unauthorized_sessions WHERE status='nao_autorizada'"))
            self.assertEqual(marks, {MARKED: "2026-10-15T17:55:00.000Z", LISTED_ONLY: "2026-10-15T19:40:00.000Z"})
            # Análise só vê a aula autorizada
            self.assertEqual(db.execute("SELECT session_id FROM sessions_autorizadas").fetchall(), [(KEPT,)])
            self.assertEqual(db.execute("SELECT session_id FROM session_events_autorizados").fetchall(), [(KEPT,)])
            self.assertEqual(db.execute("SELECT computer_id FROM sessions WHERE session_id=?", (KEPT,)).fetchone()[0], "PET-LAB1-PC03")
        finally:
            db.close()

        # Reimportar não desfaz uma restauração feita na revisão
        conn = imp.init_sqlite_database(self.sqlite)
        try:
            self.assertTrue(rev.sqlite_restore(conn, MARKED, "teste", "agora"))
        finally:
            conn.close()
        code, out = self.import_no_cloud()
        self.assertEqual(code, 0, out)
        db = sqlite3.connect(str(self.sqlite))
        try:
            self.assertEqual(db.execute("SELECT status FROM unauthorized_sessions WHERE session_id=?", (MARKED,)).fetchone()[0], "autorizada")
        finally:
            db.close()

    def test_snapshot_enviado_a_nuvem_leva_a_marca(self):
        marks = {LISTED_ONLY: "2026-10-15T19:40:00.000Z"}
        data = imp.apply_mark_to_snapshot(snapshot(LISTED_ONLY), marks)
        record = imp.build_bancada_record(data, "agora")
        self.assertEqual(record["session_payload"]["authorization_status"], "nao_autorizada")
        self.assertEqual(record["session_payload"]["marked_at"], "2026-10-15T19:40:00.000Z")
        untouched = imp.build_bancada_record(imp.apply_mark_to_snapshot(snapshot(KEPT), marks), "agora")
        self.assertNotIn("authorization_status", untouched["session_payload"])

    @patch("urllib.request.urlopen")
    def test_marcas_vao_para_a_nuvem_com_service_role(self, mock_urlopen):
        resp = MagicMock()
        resp.__enter__.return_value.read.return_value = b""
        mock_urlopen.return_value = resp
        sent, err = imp.send_unauthorized_marks_remote({MARKED: None}, "https://exemplo.supabase.co", fake_key("service_role"), "agora")
        self.assertEqual((sent, err), (1, None))
        req = mock_urlopen.call_args.args[0]
        self.assertIn("/research_unauthorized_sessions?on_conflict=session_id", req.full_url)
        self.assertIn("ignore-duplicates", req.headers["Prefer"])
        self.assertEqual(json.loads(req.data), [{"session_id": MARKED, "marked_at": "agora"}])

        mock_urlopen.reset_mock()
        sent, err = imp.send_unauthorized_marks_remote({MARKED: None}, "https://exemplo.supabase.co", fake_key("authenticated"), "agora")
        self.assertEqual(sent, 0)
        self.assertIn("service_role", err)
        mock_urlopen.assert_not_called()


class FakeCloud:
    """PostgREST falso: tabela de marcas, snapshots e as duas funções de revisão."""

    def __init__(self):
        self.marks = {MARKED: {"session_id": MARKED, "marked_at": "2026-10-15T17:55:00+00:00", "site_id": "PET",
                               "installation_id": "11111111-2222-4333-8444-555555555555", "status": "nao_autorizada"}}
        self.calls: list[tuple[str, str, object]] = []

    def __call__(self, req, timeout=None):
        url = req.full_url
        body = json.loads(req.data) if req.data else None
        self.calls.append((req.get_method(), url, body))
        if "/research_unauthorized_sessions?" in url and req.get_method() == "GET":
            data = [m for m in self.marks.values() if m["status"] == "nao_autorizada"]
        elif "/research_bancada_sessions?" in url:
            data = [{"session_id": MARKED, "site_id": "PET", "installation_id": "x", "computer_id": "PET-LAB1-PC03",
                     "started_at": "2026-10-15T17:05:00.000Z", "duration_seconds": "3000"}]
        elif url.endswith("/rpc/review_purge_research_session"):
            self.marks.pop(body["p_session_id"], None)
            data = {"purged": True}
        elif url.endswith("/rpc/review_restore_research_session"):
            self.marks[body["p_session_id"]]["status"] = "autorizada"
            data = {"restored": True}
        else:
            data = None
        resp = MagicMock()
        resp.__enter__.return_value.read.return_value = json.dumps(data).encode() if data is not None else b""
        return resp


class RevisaoDoPesquisador(Base):
    def setUp(self):
        super().setUp()
        self.standard_export()
        code, out = self.import_no_cloud()
        self.assertEqual(code, 0, out)
        self.key = fake_key("service_role")

    def run_tool(self, *args, cloud: FakeCloud | None = None):
        argv = list(args) + ["--sqlite-path", str(self.sqlite)]
        if cloud is None:
            argv.append("--no-cloud")
        env = {"PULSELAB_SERVICE_ROLE_KEY": self.key, "PULSELAB_SUPABASE_URL": "https://exemplo.supabase.co"}
        out = io.StringIO()
        with patch.dict(os.environ, env), patch("urllib.request.urlopen", side_effect=cloud), contextlib.redirect_stdout(out):
            code = rev.main(argv)
        return code, out.getvalue()

    def test_lista_nuvem_e_sqlite_sem_imprimir_segredo(self):
        cloud = FakeCloud()
        code, out = self.run_tool(cloud=cloud)
        self.assertEqual(code, 0, out)
        self.assertIn(MARKED, out)
        self.assertIn(LISTED_ONLY, out)
        self.assertNotIn(KEPT, out)
        self.assertIn("PET-LAB1-PC03", out)
        self.assertIn("nuvem+sqlite", out)
        self.assertIn(" 50 ", out)  # duração em minutos
        self.assertNotIn("assinatura-secreta", out)
        self.assertNotIn(self.key, out)

    def test_exige_service_role_para_a_nuvem(self):
        self.key = fake_key("authenticated")
        code, out = self.run_tool(cloud=FakeCloud())
        self.assertEqual(code, 1)
        self.assertIn("service_role", out)

    def test_apagar_grava_tombstone_e_remove_da_nuvem_e_do_sqlite(self):
        cloud = FakeCloud()
        code, out = self.run_tool("--apagar", MARKED, "--sim", cloud=cloud)
        self.assertEqual(code, 0, out)
        rpc = [c for c in cloud.calls if c[1].endswith("/rpc/review_purge_research_session")]
        self.assertEqual([c[2] for c in rpc], [{"p_session_id": MARKED}])
        db = sqlite3.connect(str(self.sqlite))
        try:
            for tbl in ("sessions", "events", "session_events", "unauthorized_sessions"):
                self.assertEqual(db.execute(f"SELECT count(*) FROM {tbl} WHERE session_id=?", (MARKED,)).fetchone()[0], 0, tbl)
            self.assertEqual(db.execute("SELECT session_id FROM withdrawn_sessions").fetchall(), [(MARKED,)])
            self.assertEqual(db.execute("SELECT count(*) FROM sessions WHERE session_id=?", (KEPT,)).fetchone()[0], 1)
        finally:
            db.close()

        # Reimportar a mesma coleta não traz a aula apagada de volta
        code, out = self.import_no_cloud()
        self.assertEqual(code, 0, out)
        db = sqlite3.connect(str(self.sqlite))
        try:
            self.assertEqual(db.execute("SELECT count(*) FROM sessions WHERE session_id=?", (MARKED,)).fetchone()[0], 0)
            self.assertEqual(db.execute("SELECT count(*) FROM unauthorized_sessions WHERE session_id=?", (MARKED,)).fetchone()[0], 0)
        finally:
            db.close()

    def test_apagar_todas_grava_tombstone_na_nuvem_para_aula_so_do_sqlite(self):
        cloud = FakeCloud()
        code, out = self.run_tool("--apagar-todas", "--sim", cloud=cloud)
        self.assertEqual(code, 0, out)
        tombstones = [c for c in cloud.calls if "/research_withdrawals?" in c[1]]
        self.assertEqual(tombstones[0][2], [{"session_id": LISTED_ONLY, "source": "importer"}])
        db = sqlite3.connect(str(self.sqlite))
        try:
            self.assertEqual(db.execute("SELECT count(*) FROM unauthorized_sessions").fetchone()[0], 0)
            self.assertEqual(db.execute("SELECT session_id FROM sessions").fetchall(), [(KEPT,)])
        finally:
            db.close()

    def test_apagar_recusa_aula_nao_marcada_e_pede_confirmacao(self):
        code, out = self.run_tool("--apagar", KEPT, "--sim")
        self.assertEqual(code, 1)
        self.assertIn("Não estão marcadas", out)
        with patch("builtins.input", return_value="nao"):
            code, out = self.run_tool("--apagar", MARKED)
        self.assertEqual(code, 1)
        self.assertIn("Nada foi apagado", out)
        db = sqlite3.connect(str(self.sqlite))
        try:
            self.assertEqual(db.execute("SELECT count(*) FROM sessions WHERE session_id=?", (MARKED,)).fetchone()[0], 1)
        finally:
            db.close()

    def test_restaurar_exige_motivo_e_grava(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            self.run_tool("--restaurar", MARKED)
        cloud = FakeCloud()
        code, out = self.run_tool("--restaurar", MARKED, "--motivo", "marcada no computador errado", cloud=cloud)
        self.assertEqual(code, 0, out)
        rpc = [c[2] for c in cloud.calls if c[1].endswith("/rpc/review_restore_research_session")]
        self.assertEqual(rpc, [{"p_session_id": MARKED, "p_reason": "marcada no computador errado"}])
        db = sqlite3.connect(str(self.sqlite))
        try:
            row = db.execute("SELECT status, restore_reason FROM unauthorized_sessions WHERE session_id=?", (MARKED,)).fetchone()
            self.assertEqual(row, ("autorizada", "marcada no computador errado"))
            self.assertIn((MARKED,), db.execute("SELECT session_id FROM sessions_autorizadas").fetchall())
        finally:
            db.close()


if __name__ == "__main__":
    unittest.main()
