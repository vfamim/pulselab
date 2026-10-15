"""Integração do Bridge real (pwsh) com um Supabase falso.

Cobre o cadastro pelo token do polo, a renovação de token após 401 e a sessão da turma,
que desde a 2.4.0 é do Bridge: abre sozinha, registra o programa SPIKE e o sinal de vida,
fecha pelo formulário final, por tempo ou por computador desligado, e "Não registrar esta
turma" apaga e pausa. Sem pwsh no PATH, os testes de integração são pulados.
"""

from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

from test_spike_parser import SECRET, known_blocks, project_json, wait_until_blocks, write_llsp3  # noqa: E402
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


def write_json(path: Path, data) -> None:
    path.write_text(json.dumps(data), encoding="utf-8")


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def read_events(data_dir: Path) -> list[dict]:
    events_file = data_dir / "events.jsonl"
    if not events_file.exists():
        return []
    return [json.loads(line) for line in events_file.read_text(encoding="utf-8-sig").splitlines() if line.strip()]


class BridgeProcess:
    """Bridge real numa pasta temporária, com prazos encurtados por variáveis de ambiente."""

    def __init__(self, root: Path, supabase_url: str, env_extra: dict | None = None):
        self.root = root
        (root / "bridge").mkdir(parents=True, exist_ok=True)
        for name in ("pulselab-bridge.ps1", "spike-parser.ps1"):
            shutil.copy2(ROOT / "bridge" / name, root / "bridge" / name)
        (root / "config").mkdir(exist_ok=True)
        write_json(root / "config" / "config.json", {
            "version": "test", "group_size": 2, "supabase_url": supabase_url, "sync_interval_seconds": 1,
        })
        self.data = root / "dados_locais"
        self.data.mkdir(exist_ok=True)
        self.spike = root / "LEGO SPIKE"
        self.spike.mkdir(exist_ok=True)
        self.env = {
            **os.environ,
            "USERPROFILE": str(root / "perfil"),
            "PULSELAB_SPIKE_DIR": str(self.spike),
            "PULSELAB_HEARTBEAT_SECONDS": "2",
            "PULSELAB_SPIKE_POLL_SECONDS": "1",
            **(env_extra or {}),
        }
        self.proc = None
        self.port = None

    def start(self):
        self.port = free_port()
        self.base = f"http://127.0.0.1:{self.port}"
        self.proc = subprocess.Popen(
            [PWSH, "-NoProfile", "-File", str(self.root / "bridge" / "pulselab-bridge.ps1"),
             "-Port", str(self.port), "-AppRoot", str(ROOT / "alunos"), "-DataDir", str(self.data)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=self.env,
        )
        deadline = time.time() + 40
        while time.time() < deadline:
            try:
                with urllib.request.urlopen(f"{self.base}/health", timeout=1):
                    return
            except Exception:
                time.sleep(0.3)
        raise RuntimeError("Bridge não respondeu")

    def stop(self):
        if self.proc:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.proc.kill()
            self.proc = None

    def get(self, path: str):
        with urllib.request.urlopen(f"{self.base}{path}", timeout=5) as resp:
            return json.loads(resp.read())

    def post(self, path: str, payload: dict):
        req = urllib.request.Request(
            f"{self.base}{path}",
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json", "Origin": self.base},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                return resp.status, json.loads(resp.read() or b"{}")
        except urllib.error.HTTPError as err:
            return err.code, json.loads(err.read() or b"{}")


def wait_for(predicate, timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.5)
    return False


def authorized_installation(**extra) -> dict:
    return {
        "installation_id": INSTALLATION_ID,
        "machine_label": "PET-LAB1-PC03",
        "site_id": "PET",
        "research_collection_enabled": True,
        "research_authorization_version": "12345678.9.0000.1234",
        "research_authorized_purposes": ["academic_research"],
        **extra,
    }


@unittest.skipUnless(PWSH, "pwsh não encontrado")
class BridgeCloudSyncTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        FakeSupabase.calls = []
        FakeSupabase.session_event_attempts = 0
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), FakeSupabase)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.tmp = Path(tempfile.mkdtemp(prefix="pulselab-bridge-cloud-"))
        cls.bridge = BridgeProcess(cls.tmp, f"http://127.0.0.1:{cls.server.server_port}")
        write_json(cls.bridge.data / "installation.json", authorized_installation(enrollment_token=SITE_TOKEN))
        # Linha cortada por desligamento brusco no fim da aula anterior
        (cls.bridge.data / "events.jsonl").write_bytes(b'{"event_id":"77777777-7777-4777-8777-77777')
        cls.bridge.start()

    @classmethod
    def tearDownClass(cls):
        cls.bridge.stop()
        cls.server.shutdown()
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def debug_state(self) -> str:
        log = self.bridge.data / "bridge.log"
        tail = log.read_text(encoding="utf-8-sig", errors="replace").splitlines()[-12:] if log.exists() else []
        with FakeSupabase.lock:
            calls = [(c["path"], c["auth"]) for c in FakeSupabase.calls]
        return json.dumps({"calls": calls, "log": tail}, ensure_ascii=False, indent=1)

    def calls_to(self, prefix: str):
        with FakeSupabase.lock:
            return [c for c in FakeSupabase.calls if c["path"].startswith(prefix)]

    def test_full_class_flow(self):
        data = self.bridge.data
        # 1. Linha cortada separada; a fila segue
        self.assertTrue((data / "events_corrupted.jsonl").exists(), "linha cortada deveria ir para events_corrupted.jsonl")

        # 2. Cadastro automático com o token do polo
        self.assertTrue(wait_for(lambda: self.calls_to("/functions/v1/enroll-device")), "bridge não tentou se cadastrar")
        enroll = self.calls_to("/functions/v1/enroll-device")[0]["body"]
        self.assertEqual(enroll["installation_id"], INSTALLATION_ID)
        self.assertEqual(enroll["machine_label"], "PET-LAB1-PC03")
        self.assertTrue(wait_for(lambda: "enrolled_at" in read_json(data / "installation.json")))
        self.assertNotIn("enrollment_token", read_json(data / "installation.json"), "token do polo deve sair do disco")

        # 3. A turma abre sozinha, sem página aberta
        current = self.bridge.get("/v1/session/current")
        self.assertTrue(current["research_active"])
        self.assertTrue(current["active"], self.debug_state())
        session_id = current["session_id"]
        started = [e for e in read_events(data) if e["event_type"] == "session_started"]
        self.assertEqual(len(started), 1)
        self.assertEqual(started[0]["session_id"], session_id)
        self.assertEqual(started[0]["details"]["start_mode"], "abertura_app")
        self.assertEqual(started[0]["participant_role"], None)

        # 4. Evento: primeiro envio recebe 401, bridge renova o token e reenvia sem quarentena
        self.assertTrue(wait_for(lambda: any(c["auth"] == "Bearer tok-2" for c in self.calls_to("/rest/v1/research_session_events"))), "evento não reenviado com token renovado: " + self.debug_state())
        self.assertTrue(self.calls_to("/auth/v1/token"), "token não foi renovado")
        self.assertFalse((data / "events_quarantine.jsonl").exists(), "401 não pode mandar evento para quarentena")
        self.assertEqual(read_json(data / "device_session.json")["access_token"], "tok-2")

        # 5. Programa salvo no SPIKE vira telemetria, sem textos das crianças nem caminhos
        write_llsp3(self.bridge.spike / "Projeto1.llsp3", json.dumps(project_json(known_blocks())))
        self.assertTrue(wait_for(lambda: any(e["event_type"] == "spike_telemetry" for e in read_events(data))), self.debug_state())
        telemetry = [e for e in read_events(data) if e["event_type"] == "spike_telemetry"][0]
        details = telemetry["details"]
        self.assertGreater(details["executable_blocks"], 0)
        self.assertTrue(details["first_coding_detected"])
        self.assertEqual(telemetry["activity_stage"], "primeira_programacao_detectada")
        self.assertEqual(details["file_seq"], 1)
        self.assertFalse(details["continued_previous_file"])
        self.assertRegex(details["structure_hash"], r"^[0-9a-f]{64}$")
        self.assertIn("total", details["ct_score"])
        raw_events = (data / "events.jsonl").read_text(encoding="utf-8")
        self.assertNotIn(SECRET, raw_events)
        self.assertNotIn("JOAO", raw_events)
        self.assertNotIn(str(self.bridge.spike), raw_events)

        # 6. Sinal de vida
        self.assertTrue(wait_for(lambda: any(e["event_type"] == "heartbeat" for e in read_events(data))))

        # 7. Em andamento não sobe; formulário com turma errada é recusado; turma certa fecha e sobe
        self.assertEqual(self.calls_to("/rest/v1/research_bancada_sessions"), [], "snapshot em andamento não deve subir")
        status, _ = self.bridge.post("/v1/session/close", {"session_id": "00000000-0000-4000-8000-000000000000", "experience": {"refused": True}, "rubric": {"skipped": True}})
        self.assertEqual(status, 409)
        status, _ = self.bridge.post("/v1/session/close", {"session_id": session_id, "experience": {"value": 9}, "rubric": {"skipped": True}})
        self.assertEqual(status, 400, "valor fora da escala")
        status, body = self.bridge.post("/v1/session/close", {
            "session_id": session_id,
            "experience": {"value": 3, "label": "Gostamos", "refused": False},
            "rubric": {"skipped": False, "result_level": 2, "support_level": "algum"},
        })
        self.assertEqual((status, body["session_id"]), (200, session_id))
        self.assertFalse(self.bridge.get("/v1/session/current")["active"], "próxima turma só abre no primeiro programa salvo")
        types = [e["event_type"] for e in read_events(data) if e["session_id"] == session_id]
        self.assertEqual(types[-3:], ["experience_recorded", "rubric_completed", "session_completed"])
        self.assertTrue(wait_for(lambda: self.calls_to("/rest/v1/research_bancada_sessions")), "snapshot encerrado não subiu: " + self.debug_state())
        uploaded = self.calls_to("/rest/v1/research_bancada_sessions")[0]["body"]
        self.assertEqual(uploaded["phase"], "completed")
        self.assertEqual(uploaded["ended_by"], "instrutor")
        self.assertFalse(uploaded["interrupted"])
        self.assertGreaterEqual(uploaded["data_quality"]["heartbeat_count"], 1)
        self.assertEqual(uploaded["data_quality"]["telemetry_events"], 1)
        self.assertEqual(uploaded["school_code"], "nao_informado")
        self.assertEqual(uploaded["protocol_version"], "protocolo-oficinas-rotativas-v2")

        # 8. Próxima turma abre no primeiro programa salvo, continuando o arquivo da anterior
        time.sleep(1.1)
        write_llsp3(self.bridge.spike / "Projeto1.llsp3", json.dumps(project_json(wait_until_blocks())))
        self.assertTrue(wait_for(lambda: self.bridge.get("/v1/session/current")["active"]), self.debug_state())
        second = self.bridge.get("/v1/session/current")["session_id"]
        self.assertNotEqual(second, session_id)
        self.assertTrue(wait_for(lambda: any(e["event_type"] == "spike_telemetry" and e["session_id"] == second for e in read_events(data))))
        second_start = [e for e in read_events(data) if e["session_id"] == second and e["event_type"] == "session_started"][0]
        self.assertEqual(second_start["details"]["start_mode"], "atividade_spike")
        second_tel = [e for e in read_events(data) if e["session_id"] == second and e["event_type"] == "spike_telemetry"][0]["details"]
        self.assertTrue(second_tel["continued_previous_file"], "arquivo deixado pela turma anterior deve ser reconhecido")
        self.assertEqual(second_tel["baseline_executable_blocks"], details["executable_blocks"])
        self.assertEqual(second_tel["blocks_delta_from_baseline"], second_tel["executable_blocks"] - details["executable_blocks"])

        # 9. "Não registrar esta turma": apaga a turma atual, grava tombstone e pausa
        status, body = self.bridge.post("/v1/session/pause", {})
        self.assertEqual((status, body["purged_session"]), (200, True))
        self.assertFalse(any(e["session_id"] == second for e in read_events(data)), "eventos da turma não registrada devem ser apagados")
        self.assertIn(second, (data / "sessions_withdrawn.txt").read_text(encoding="utf-8-sig"))
        self.assertTrue(self.bridge.get("/v1/status")["paused"])
        status, _ = self.bridge.post("/v1/session/close", {"session_id": None})
        self.assertEqual(status, 409, "turma pausada não tem o que encerrar")


@unittest.skipUnless(PWSH, "pwsh não encontrado")
class BridgeRestartTest(unittest.TestCase):
    """Reinício rápido retoma a turma; computador desligado ou turma longa fecha sozinha."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="pulselab-bridge-restart-"))
        self.bridge = BridgeProcess(self.tmp, "http://127.0.0.1:9")
        write_json(self.bridge.data / "installation.json", authorized_installation())

    def tearDown(self):
        self.bridge.stop()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def start_and_get_session(self) -> str:
        self.bridge.start()
        self.assertTrue(wait_for(lambda: self.bridge.get("/v1/session/current")["active"]))
        return self.bridge.get("/v1/session/current")["session_id"]

    def shift_state(self, started_min_ago: float, alive_min_ago: float):
        state_file = self.bridge.data / "active_session.json"
        state = read_json(state_file)
        now_ms = int(time.time() * 1000)
        state["started_at_ms"] = now_ms - int(started_min_ago * 60000)
        state["last_alive_ms"] = now_ms - int(alive_min_ago * 60000)
        write_json(state_file, state)

    def snapshot(self, session_id: str) -> dict:
        return read_json(self.bridge.data / "sessoes" / f"sessao_{session_id}.json")

    def test_quick_restart_resumes_same_class(self):
        first = self.start_and_get_session()
        self.bridge.stop()
        self.shift_state(started_min_ago=30, alive_min_ago=2)
        self.assertEqual(self.start_and_get_session(), first)
        issues = [e for e in read_events(self.bridge.data) if e["event_type"] == "quality_issue"]
        self.assertEqual(issues[-1]["details"]["issue"], "pulselab_reiniciado")
        self.assertEqual(read_json(self.bridge.data / "active_session.json")["bridge_restarts"], 1)

    def test_computer_off_closes_previous_class_without_closing_form(self):
        first = self.start_and_get_session()
        self.bridge.stop()
        self.shift_state(started_min_ago=90, alive_min_ago=45)
        second = self.start_and_get_session()
        self.assertNotEqual(second, first)
        snap = self.snapshot(first)
        self.assertEqual((snap["status"], snap["ended_by"]), ("completed", "sem_encerramento"))
        self.assertAlmostEqual(snap["duration_seconds"], 45 * 60, delta=120)

    def test_class_longer_than_limit_closes_by_time(self):
        first = self.start_and_get_session()
        self.bridge.stop()
        self.shift_state(started_min_ago=200, alive_min_ago=1)
        second = self.start_and_get_session()
        self.assertNotEqual(second, first)
        snap = self.snapshot(first)
        self.assertEqual(snap["ended_by"], "tempo")
        self.assertEqual(snap["duration_seconds"], 180 * 60)

    def test_without_site_package_nothing_is_recorded(self):
        write_json(self.bridge.data / "installation.json", {"installation_id": INSTALLATION_ID, "site_id": "PET", "research_collection_enabled": False})
        self.bridge.start()
        current = self.bridge.get("/v1/session/current")
        self.assertFalse(current["research_active"])
        self.assertFalse(current["active"])
        self.assertEqual(read_events(self.bridge.data), [])

if __name__ == "__main__":
    unittest.main()
