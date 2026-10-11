"""Integração do Bridge com um Supabase falso: cadastro pelo token do polo, renovação de
token após 401 e envio do snapshot só com a turma encerrada.

Roda o bridge real em pwsh (PowerShell 7). Sem pwsh no PATH, o teste é pulado.
"""

from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import unittest
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PWSH = shutil.which("pwsh")
SITE_TOKEN = "t" * 43
INSTALLATION_ID = "11111111-2222-4333-8444-555555555555"


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class FakeSupabase(BaseHTTPRequestHandler):
    calls: list[dict] = []
    session_event_attempts = 0
    lock = threading.Lock()

    def log_message(self, *args):
        pass

    def reply(self, status: int, body: dict | None = None):
        payload = json.dumps(body or {}).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        body = json.loads(raw) if raw else {}
        auth = self.headers.get("Authorization", "")
        with FakeSupabase.lock:
            FakeSupabase.calls.append({"path": self.path, "auth": auth, "body": body})

        if self.path.startswith("/functions/v1/enroll-device"):
            if body.get("enrollment_token") != SITE_TOKEN or body.get("site_id") != "PET":
                return self.reply(401, {"error": "bad token"})
            return self.reply(200, {
                "access_token": "tok-1",
                "refresh_token": "ref-1",
                "expires_at": int(time.time()) + 3600,
                "user_id": "device-user",
                "installation_id": body.get("installation_id"),
                "site_id": "PET",
            })
        if self.path.startswith("/auth/v1/token"):
            if body.get("refresh_token") != "ref-1":
                return self.reply(400, {"error": "invalid refresh"})
            return self.reply(200, {"access_token": "tok-2", "refresh_token": "ref-2", "expires_in": 3600})
        if self.path.startswith("/rest/v1/research_session_events"):
            with FakeSupabase.lock:
                FakeSupabase.session_event_attempts += 1
                first = FakeSupabase.session_event_attempts == 1
            if first:
                return self.reply(401, {"message": "JWT expired"})
            return self.reply(201 if auth == "Bearer tok-2" else 401)
        if self.path.startswith("/rest/v1/research_bancada_sessions"):
            return self.reply(201 if auth == "Bearer tok-2" else 401)
        return self.reply(404)


class PowerShellInterpolationTest(unittest.TestCase):
    def test_no_variable_followed_by_question_mark(self):
        """Em PowerShell, "$tabela?x=1" lê a variável "tabela?x"; use "$($tabela)?x=1"."""
        import re

        offenders = []
        for path in list(ROOT.glob("*.ps1")) + list((ROOT / "bridge").glob("*.ps1")) + list((ROOT / "scripts").glob("*.ps1")):
            for number, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
                if line.lstrip().startswith("#"):
                    continue
                if re.search(r'"[^"]*\$[A-Za-z_][A-Za-z0-9_]*\?', line):
                    offenders.append(f"{path.name}:{number}")
        self.assertEqual(offenders, [])


@unittest.skipUnless(PWSH, "pwsh não encontrado")
class BridgeCloudSyncTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        FakeSupabase.calls = []
        FakeSupabase.session_event_attempts = 0
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), FakeSupabase)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        supabase_url = f"http://127.0.0.1:{cls.server.server_port}"

        cls.tmp = Path(tempfile.mkdtemp(prefix="pulselab-bridge-cloud-"))
        (cls.tmp / "bridge").mkdir()
        for name in ("pulselab-bridge.ps1", "spike-parser.ps1"):
            shutil.copy2(ROOT / "bridge" / name, cls.tmp / "bridge" / name)
        (cls.tmp / "config").mkdir()
        (cls.tmp / "config" / "config.json").write_text(json.dumps({
            "version": "test",
            "group_size": 2,
            "supabase_url": supabase_url,
            "sync_interval_seconds": 1,
        }), encoding="utf-8")
        cls.data = cls.tmp / "dados_locais"
        cls.data.mkdir()
        (cls.data / "installation.json").write_text(json.dumps({
            "installation_id": INSTALLATION_ID,
            "machine_label": "PET-LAB1-PC03",
            "site_id": "PET",
            "research_collection_enabled": True,
            "research_authorization_version": "12345678.9.0000.1234",
            "research_authorized_purposes": ["academic_research"],
            "enrollment_token": SITE_TOKEN,
        }), encoding="utf-8")

        cls.port = free_port()
        # O leitor do SPIKE usa USERPROFILE (Windows); fora dele, aponta para uma pasta vazia.
        env = {**os.environ, "USERPROFILE": str(cls.tmp / "perfil")}
        (cls.tmp / "perfil").mkdir()
        cls.proc = subprocess.Popen(
            [PWSH, "-NoProfile", "-File", str(cls.tmp / "bridge" / "pulselab-bridge.ps1"),
             "-Port", str(cls.port), "-AppRoot", str(ROOT / "alunos"), "-DataDir", str(cls.data), "-NoAlert"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env,
        )
        cls.base = f"http://127.0.0.1:{cls.port}"
        deadline = time.time() + 40
        while time.time() < deadline:
            try:
                with urllib.request.urlopen(f"{cls.base}/health", timeout=1):
                    break
            except Exception:
                time.sleep(0.3)
        else:
            raise RuntimeError("Bridge não respondeu")

    @classmethod
    def tearDownClass(cls):
        cls.proc.terminate()
        try:
            cls.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            cls.proc.kill()
        cls.server.shutdown()
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def post(self, path: str, payload: dict):
        req = urllib.request.Request(
            f"{self.base}{path}",
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json", "Origin": self.base},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status

    def wait_for(self, predicate, timeout=30):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if predicate():
                return True
            time.sleep(0.5)
        return False

    def debug_state(self) -> str:
        log = self.data / "bridge.log"
        tail = log.read_text(encoding="utf-8-sig", errors="replace").splitlines()[-12:] if log.exists() else []
        with FakeSupabase.lock:
            calls = [(c["path"], c["auth"]) for c in FakeSupabase.calls]
        return json.dumps({"calls": calls, "log": tail}, ensure_ascii=False, indent=1)

    def calls_to(self, prefix: str):
        with FakeSupabase.lock:
            return [c for c in FakeSupabase.calls if c["path"].startswith(prefix)]

    def test_full_cloud_flow(self):
        # 1. Cadastro automático com o token do polo
        self.assertTrue(self.wait_for(lambda: self.calls_to("/functions/v1/enroll-device")), "bridge não tentou se cadastrar")
        enroll = self.calls_to("/functions/v1/enroll-device")[0]["body"]
        self.assertEqual(enroll["installation_id"], INSTALLATION_ID)
        self.assertEqual(enroll["machine_label"], "PET-LAB1-PC03")
        self.assertTrue(self.wait_for(lambda: "enrolled_at" in json.loads((self.data / "installation.json").read_text(encoding="utf-8-sig"))))
        installation = json.loads((self.data / "installation.json").read_text(encoding="utf-8-sig"))
        self.assertNotIn("enrollment_token", installation, "token do polo deve sair do disco após o cadastro")

        # 2. Evento: primeiro envio recebe 401, bridge renova o token e reenvia sem quarentena
        session_id = "33333333-3333-4333-8333-333333333333"
        event = {
            "event_id": "44444444-4444-4444-8444-444444444444",
            "session_id": session_id,
            "group_id": "55555555-5555-4555-8555-555555555555",
            "installation_id": INSTALLATION_ID,
            "site_id": "PET",
            "event_type": "session_started",
            "occurred_at": "2026-10-11T12:00:00Z",
            "config_hash": "a" * 64,
            "_target_table": "research_session_events",
        }
        self.assertIn(self.post("/v1/events", event), (200, 201))
        self.assertTrue(self.wait_for(lambda: any(c["auth"] == "Bearer tok-2" for c in self.calls_to("/rest/v1/research_session_events"))), "evento não reenviado com token renovado: " + self.debug_state())
        self.assertTrue(self.calls_to("/auth/v1/token"), "token não foi renovado")
        self.assertFalse((self.data / "events_quarantine.jsonl").exists(), "401 não pode mandar evento para quarentena")
        stored = json.loads((self.data / "device_session.json").read_text(encoding="utf-8-sig"))
        self.assertEqual(stored["access_token"], "tok-2")
        self.assertEqual(stored["refresh_token"], "ref-2")

        # 3. Snapshot em andamento não sobe; encerrado sobe uma vez
        snapshot = {"session_id": session_id, "group_id": event["group_id"], "installation_id": INSTALLATION_ID,
                    "site_id": "PET", "status": "in_progress", "timeline": [event]}
        self.post("/v1/sessions/save", snapshot)
        time.sleep(4)
        self.assertEqual(self.calls_to("/rest/v1/research_bancada_sessions"), [], "snapshot em andamento não deve subir")
        self.post("/v1/sessions/save", {**snapshot, "status": "completed", "phase": "completed"})
        self.assertTrue(self.wait_for(lambda: self.calls_to("/rest/v1/research_bancada_sessions")), "snapshot encerrado não subiu")
        uploaded = self.calls_to("/rest/v1/research_bancada_sessions")[0]["body"]
        self.assertEqual(uploaded["phase"], "completed")
        self.assertEqual(uploaded["school_code"], "nao_informado")
        self.assertIsNone(uploaded.get("protocol_version"))


if __name__ == "__main__":
    unittest.main()
