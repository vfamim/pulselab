"""Integração do Bridge real (pwsh) com um Supabase falso.

Cobre o cadastro pelo token do polo, a renovação de token após 401 e a sessão da turma,
que desde a 2.4.0 é do Bridge: abre sozinha, registra o programa SPIKE e o sinal de vida,
fecha pelo formulário final, por tempo, por computador desligado ou sem programa salvo no SPIKE
(inatividade), e "Não registrar esta
turma" marca a aula como não autorizada (sem apagar), reenvia com a marca e pausa. Sem pwsh no
PATH, os testes de integração são pulados.
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
import uuid
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
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
        for path in list((ROOT / "runtime" / "windows").rglob("*.ps1")) + list((ROOT / "tooling").rglob("*.ps1")):
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
            shutil.copy2(ROOT / "runtime" / "windows" / "bridge" / name, root / "bridge" / name)
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

        # 9. Encerrar e depois "Não registrar esta turma": a aula encerrada é marcada, não apagada
        target = self.bridge.get("/v1/status")["mark_target"]
        self.assertEqual((target["session_id"], target["active"]), (second, True))
        status, body = self.bridge.post("/v1/session/close", {})
        self.assertEqual((status, body["session_id"]), (200, second))
        bancada = lambda: [c["body"] for c in self.calls_to("/rest/v1/research_bancada_sessions") if c["body"].get("session_id") == second]
        self.assertTrue(wait_for(lambda: bancada()), "snapshot da segunda turma não subiu: " + self.debug_state())
        self.assertNotIn("authorization_status", bancada()[0]["session_payload"])
        target = self.bridge.get("/v1/status")["mark_target"]
        self.assertEqual((target["session_id"], target["active"]), (second, False), "sem turma nova, o alvo é a última encerrada")
        self.assertRegex(target["started_local"], r"^\d\d:\d\d$")
        self.assertGreaterEqual(target["duration_min"], 0)
        status, _ = self.bridge.post("/v1/session/pause", {"session_id": session_id})
        self.assertEqual(status, 409, "aula diferente da mostrada ao instrutor")
        status, body = self.bridge.post("/v1/session/pause", {"session_id": second})
        self.assertEqual((status, body["marked"], body["target"]["session_id"]), (200, True, second))
        self.assertTrue(any(e["session_id"] == second for e in read_events(data)), "eventos da aula marcada ficam no computador")
        snap = read_json(data / "sessoes" / f"sessao_{second}.json")
        self.assertEqual(snap["authorization_status"], "nao_autorizada")
        self.assertTrue(snap["marked_at"])
        self.assertIn(second, (data / "sessions_unauthorized.txt").read_text(encoding="utf-8-sig"))
        self.assertFalse((data / "sessions_withdrawn.txt").exists(), "marcar não grava tombstone de exclusão")
        marked = lambda: [b for b in bancada() if b["session_payload"].get("authorization_status") == "nao_autorizada"]
        self.assertTrue(wait_for(lambda: marked()), "aula marcada não foi reenviada com a marca: " + self.debug_state())
        self.assertTrue(marked()[0]["session_payload"]["marked_at"])
        current = self.bridge.get("/v1/status")
        self.assertTrue(current["paused"])
        self.assertIsNone(current["mark_target"], "aula já marcada não é alvo de novo")
        status, _ = self.bridge.post("/v1/session/close", {"session_id": None})
        self.assertEqual(status, 409, "turma pausada não tem o que encerrar")
        status, body = self.bridge.post("/v1/session/pause", {"session_id": ""})
        self.assertEqual((status, body["marked"]), (200, False), "sem aula, só pausa")

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

    def shift_state(self, started_min_ago: float, alive_min_ago: float, program_min_ago: float | None = None):
        state_file = self.bridge.data / "active_session.json"
        state = read_json(state_file)
        now_ms = int(time.time() * 1000)
        state["started_at_ms"] = now_ms - int(started_min_ago * 60000)
        state["last_alive_ms"] = now_ms - int(alive_min_ago * 60000)
        if program_min_ago is not None:
            state["last_program_ms"] = now_ms - int(program_min_ago * 60000)
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

    def test_mark_active_class_closes_it_and_keeps_data(self):
        first = self.start_and_get_session()
        target = self.bridge.get("/v1/status")["mark_target"]
        self.assertEqual((target["session_id"], target["active"], target["started_today"]), (first, True, True))
        status, body = self.bridge.post("/v1/session/pause", {"session_id": first})
        self.assertEqual((status, body["marked"]), (200, True))
        snap = self.snapshot(first)
        self.assertEqual((snap["status"], snap["ended_by"], snap["authorization_status"]), ("completed", "instrutor", "nao_autorizada"))
        self.assertTrue(any(e["session_id"] == first for e in read_events(self.bridge.data)))
        current = self.bridge.get("/v1/session/current")
        self.assertEqual((current["active"], current["paused"]), (False, True))
        # Reinício com o PC ligado mantém a pausa e não volta a oferecer a aula marcada
        self.bridge.stop()
        self.bridge.start()
        status = self.bridge.get("/v1/status")
        self.assertTrue(status["paused"])
        self.assertIsNone(status["mark_target"])

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
        # Programa salvo há 1 minuto: a turma está em uso e só o limite de 3 horas a fecha.
        self.shift_state(started_min_ago=200, alive_min_ago=1, program_min_ago=1)
        second = self.start_and_get_session()
        self.assertNotEqual(second, first)
        snap = self.snapshot(first)
        self.assertEqual(snap["ended_by"], "tempo")
        self.assertEqual(snap["duration_seconds"], 180 * 60)

    def test_recent_program_keeps_class_open_after_restart(self):
        first = self.start_and_get_session()
        self.bridge.stop()
        # 100 min de aula, mas o último programa foi salvo há 30 min: o relógio conta dele.
        self.shift_state(started_min_ago=100, alive_min_ago=1, program_min_ago=30)
        self.assertEqual(self.start_and_get_session(), first)

    def test_idle_class_closes_on_restart_and_can_be_marked(self):
        first = self.start_and_get_session()
        self.bridge.stop()
        # Nenhum programa salvo em 50 min: fecha por inatividade; o fim é o último sinal de atividade (o início).
        self.shift_state(started_min_ago=50, alive_min_ago=1)
        self.bridge.start()
        status = self.bridge.get("/v1/status")
        self.assertIsNone(status["session"])
        self.assertTrue(status["awaiting_activity"], "a próxima turma abre no primeiro programa salvo")
        snap = self.snapshot(first)
        self.assertEqual((snap["status"], snap["ended_by"]), ("completed", "inatividade"))
        self.assertEqual(snap["duration_seconds"], 0)
        self.assertEqual(snap["data_quality"]["telemetry_events"], 0)
        completed = [e for e in read_events(self.bridge.data) if e["session_id"] == first and e["event_type"] == "session_completed"]
        self.assertEqual(completed[-1]["details"]["ended_by"], "inatividade")
        # "Não registrar esta turma" depois disso marca a aula encerrada por inatividade
        target = status["mark_target"]
        self.assertEqual((target["session_id"], target["active"], target["duration_min"]), (first, False, 0))
        status_code, body = self.bridge.post("/v1/session/pause", {"session_id": first})
        self.assertEqual((status_code, body["marked"], body["target"]["session_id"]), (200, True, first))
        snap = self.snapshot(first)
        self.assertEqual((snap["ended_by"], snap["authorization_status"]), ("inatividade", "nao_autorizada"))
        self.assertTrue(self.bridge.get("/v1/status")["paused"])

    def test_without_site_package_nothing_is_recorded(self):
        write_json(self.bridge.data / "installation.json", {"installation_id": INSTALLATION_ID, "site_id": "PET", "research_collection_enabled": False})
        self.bridge.start()
        current = self.bridge.get("/v1/session/current")
        self.assertFalse(current["research_active"])
        self.assertFalse(current["active"])
        self.assertEqual(read_events(self.bridge.data), [])

@unittest.skipUnless(PWSH, "pwsh não encontrado")
class BridgeIdleTest(unittest.TestCase):
    """Turma esquecida aberta fecha sozinha sem programa salvo no SPIKE (limite de 1 min no teste)."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="pulselab-bridge-idle-"))
        self.bridge = BridgeProcess(self.tmp, "http://127.0.0.1:9", {"PULSELAB_SESSION_IDLE_MINUTES": "1"})
        write_json(self.bridge.data / "installation.json", authorized_installation())

    def tearDown(self):
        self.bridge.stop()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_class_without_new_program_closes_and_next_program_opens_new_class(self):
        data = self.bridge.data
        self.bridge.start()
        self.assertTrue(wait_for(lambda: self.bridge.get("/v1/session/current")["active"]))
        first = self.bridge.get("/v1/session/current")["session_id"]
        started = [e for e in read_events(data) if e["event_type"] == "session_started"][0]
        self.assertEqual(started["details"]["session_idle_minutes"], 1)

        # Programa salvo: o relógio de inatividade passa a contar dele
        write_llsp3(self.bridge.spike / "Projeto1.llsp3", json.dumps(project_json(known_blocks())))
        self.assertTrue(wait_for(lambda: any(e["event_type"] == "spike_telemetry" for e in read_events(data))))
        saved_at = [e for e in read_events(data) if e["event_type"] == "spike_telemetry"][-1]["details"]["saved_at"]

        self.assertTrue(wait_for(lambda: not self.bridge.get("/v1/session/current")["active"], timeout=100), "turma sem uso não fechou")
        snap = read_json(data / "sessoes" / f"sessao_{first}.json")
        self.assertEqual((snap["status"], snap["ended_by"]), ("completed", "inatividade"))
        self.assertEqual(snap["data_quality"]["telemetry_events"], 1)
        to_dt = lambda iso: datetime.fromisoformat(iso.replace("Z", "+00:00"))
        self.assertAlmostEqual((to_dt(snap["completed_at"]) - to_dt(saved_at)).total_seconds(), 0, delta=1)
        status = self.bridge.get("/v1/status")
        self.assertTrue(status["awaiting_activity"])
        self.assertFalse(status["paused"])
        self.assertEqual((status["mark_target"]["session_id"], status["mark_target"]["active"]), (first, False))

        # O próximo programa salvo abre outra turma
        time.sleep(1.1)
        write_llsp3(self.bridge.spike / "Projeto1.llsp3", json.dumps(project_json(known_blocks())))
        self.assertTrue(wait_for(lambda: self.bridge.get("/v1/session/current")["active"]))
        second = self.bridge.get("/v1/session/current")["session_id"]
        self.assertNotEqual(second, first)
        second_start = [e for e in read_events(data) if e["session_id"] == second and e["event_type"] == "session_started"][0]
        self.assertEqual(second_start["details"]["start_mode"], "atividade_spike")


BANCADA_OK = [
    {"item_id": "bancada_linha_v1", "value": "em_parte"},
    {"item_id": "bancada_corrida_v1", "value": "recusou"},
    {"item_id": "bancada_quiz_v1", "value": "sem_quiz"},
]
CRIANCA_ITENS = ["crianca_gostou_v1", "crianca_outra_aula_v1", "crianca_confianca_antes_v1",
                 "crianca_confianca_agora_v1", "crianca_ajudou_v1"]


def crianca(*valores: str) -> list[dict]:
    return [{"item_id": i, "value": v} for i, v in zip(CRIANCA_ITENS, valores)]


@unittest.skipUnless(PWSH, "pwsh não encontrado")
class BridgeQuestionarioTest(unittest.TestCase):
    """Questionário do fim da aula: respostas viram eventos da sessão certa, sem nada que identifique a criança."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="pulselab-bridge-questionario-"))
        self.bridge = BridgeProcess(self.tmp, "http://127.0.0.1:9")
        write_json(self.bridge.data / "installation.json", authorized_installation())

    def tearDown(self):
        self.bridge.stop()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def start_and_get_session(self) -> str:
        self.bridge.start()
        self.assertTrue(wait_for(lambda: self.bridge.get("/v1/session/current")["active"]))
        return self.bridge.get("/v1/session/current")["session_id"]

    def respostas(self, tipo: str) -> list[dict]:
        return [e for e in read_events(self.bridge.data) if e["event_type"] == tipo]

    def post(self, parte: str, answers: list[dict], submission_id: str | None = None):
        return self.bridge.post(f"/v1/questionario/{parte}", {"submission_id": submission_id or str(uuid.uuid4()), "answers": answers})

    def test_grava_na_sessao_ativa_e_bancada_uma_vez_por_aula(self):
        sid = self.start_and_get_session()
        estado = self.bridge.get("/v1/questionario/estado")
        self.assertEqual((estado["coleta_ativa"], estado["motivo"], estado["bancada_respondida"]), (True, None, False))
        self.assertNotIn("session_id", estado, "a aba das crianças não vê o id da aula")

        # Validação antes de gravar: fora do instrumento, item faltando ou repetido, envio sem id
        invalidos = [
            ("bancada", [dict(BANCADA_OK[0], value="talvez"), *BANCADA_OK[1:]], None),
            ("bancada", BANCADA_OK[:2], None),
            ("bancada", [BANCADA_OK[0], BANCADA_OK[0], BANCADA_OK[2]], None),
            ("bancada", [dict(BANCADA_OK[0], value="SIM"), *BANCADA_OK[1:]], None),
            ("crianca", crianca("sim", "sim", "sim", "sim", "em_parte"), None),
            ("crianca", BANCADA_OK, None),
        ]
        for parte, answers, _ in invalidos:
            status, _ = self.post(parte, answers)
            self.assertEqual(status, 400, (parte, answers))
        status, _ = self.bridge.post("/v1/questionario/crianca", {"submission_id": "joao", "answers": crianca("sim", "sim", "sim", "sim", "sim")})
        self.assertEqual(status, 400, "submission_id precisa ser um código aleatório")
        self.assertEqual(self.respostas("bancada_result_recorded") + self.respostas("student_feedback_recorded"), [])

        envio_bancada = str(uuid.uuid4())
        status, body = self.post("bancada", BANCADA_OK, envio_bancada)
        self.assertEqual((status, body["status"], body["respostas"]), (200, "gravado", 3))
        bancada = self.respostas("bancada_result_recorded")
        self.assertEqual([(e["details"]["item_id"], e["details"]["value"]) for e in bancada],
                         [(a["item_id"], a["value"]) for a in BANCADA_OK])
        for e in bancada:
            self.assertEqual(e["session_id"], sid)
            self.assertEqual((e["participant_id"], e["participant_role"], e["activity_stage"]), ("BANCADA", "group", "questionario_fim_aula"))
            self.assertEqual(e["details"]["instrument_version"], "bancada-3.2.0")
            self.assertEqual(e["config_version"], "bancada-3.2.0")
            self.assertEqual(e["details"]["submission_id"], envio_bancada)
            self.assertTrue(e["details"]["session_active"])
        self.assertEqual([e["details"]["refused"] for e in bancada], [False, True, False])
        self.assertTrue(self.bridge.get("/v1/questionario/estado")["bancada_respondida"])

        # Uma vez por aula: o segundo envio não grava
        status, body = self.post("bancada", BANCADA_OK)
        self.assertEqual((status, body["status"]), (200, "ja_respondido"))
        self.assertEqual(len(self.respostas("bancada_result_recorded")), 3)

        # Duas crianças, cada uma com o próprio envio
        self.assertEqual(self.post("crianca", crianca("sim", "mais_ou_menos", "nao", "sim", "recusou"))[1]["status"], "gravado")
        self.assertEqual(self.post("crianca", crianca("nao", "sim", "mais_ou_menos", "mais_ou_menos", "sim"))[1]["status"], "gravado")
        individuais = self.respostas("student_feedback_recorded")
        self.assertEqual(len(individuais), 10)
        self.assertEqual(len({e["details"]["submission_id"] for e in individuais}), 2)
        for e in individuais:
            self.assertEqual((e["session_id"], e["participant_id"], e["participant_role"]), (sid, None, "individual"))
        self.assertEqual([e["details"]["item_order"] for e in individuais[:5]], [1, 2, 3, 4, 5])
        # A aula ativa continua aberta e o snapshot leva as respostas
        self.assertTrue(self.bridge.get("/v1/session/current")["active"])
        snap = read_json(self.bridge.data / "sessoes" / f"sessao_{sid}.json")
        tipos = [e["event_type"] for e in snap["timeline"]]
        self.assertEqual(tipos.count("bancada_result_recorded"), 3)
        self.assertEqual(tipos.count("student_feedback_recorded"), 10)

    def test_sem_aula_ativa_grava_na_ultima_aula_encerrada(self):
        sid = self.start_and_get_session()
        status, body = self.bridge.post("/v1/session/close", {})
        self.assertEqual((status, body["session_id"]), (200, sid))
        self.assertFalse(self.bridge.get("/v1/session/current")["active"])
        estado = self.bridge.get("/v1/questionario/estado")
        self.assertEqual((estado["coleta_ativa"], estado["bancada_respondida"]), (True, False))

        self.assertEqual(self.post("bancada", BANCADA_OK)[1]["status"], "gravado")
        self.assertEqual(self.post("bancada", BANCADA_OK)[1]["status"], "ja_respondido")
        self.assertEqual(self.post("crianca", crianca("sim", "sim", "nao", "sim", "sim"))[1]["status"], "gravado")
        for e in self.respostas("bancada_result_recorded") + self.respostas("student_feedback_recorded"):
            self.assertEqual(e["session_id"], sid)
            self.assertFalse(e["details"]["session_active"])
            self.assertGreaterEqual(e["details"]["minutes_since_session_start"], 0)
            self.assertGreaterEqual(e["elapsed_ms"], 0)
            self.assertEqual(e["installation_id"], INSTALLATION_ID)
            self.assertEqual(e["site_id"], "PET")
            self.assertRegex(e["config_hash"], r"^[0-9a-f]{64}$")
        snap = read_json(self.bridge.data / "sessoes" / f"sessao_{sid}.json")
        self.assertEqual((snap["status"], snap["ended_by"]), ("completed", "instrutor"), "a aula continua encerrada")
        self.assertEqual([e["event_type"] for e in snap["timeline"]][-8:], ["bancada_result_recorded"] * 3 + ["student_feedback_recorded"] * 5)
        sequencias = [e["_sequence"] for e in snap["timeline"]]
        self.assertEqual(sequencias, sorted(set(sequencias)), "sequência continua depois do encerramento")
        self.assertFalse(self.bridge.get("/v1/session/current")["active"], "responder não abre outra aula")

    def test_aula_pausada_nao_grava(self):
        sid = self.start_and_get_session()
        status, body = self.bridge.post("/v1/session/pause", {"session_id": sid})
        self.assertEqual((status, body["marked"]), (200, True))
        estado = self.bridge.get("/v1/questionario/estado")
        self.assertEqual((estado["coleta_ativa"], estado["motivo"]), (False, "pausado"))
        status, body = self.post("crianca", crianca("sim", "sim", "sim", "sim", "sim"))
        self.assertEqual((status, body["status"], body["motivo"]), (200, "nao_gravado", "pausado"))
        status, body = self.post("bancada", BANCADA_OK)
        self.assertEqual((status, body["status"]), (200, "nao_gravado"))
        self.assertEqual(self.respostas("bancada_result_recorded") + self.respostas("student_feedback_recorded"), [])

    def test_aula_nao_autorizada_sem_pausa_nao_grava(self):
        # Limite da aula (e da pausa) de 1 min: a pausa vence e a última aula encerrada continua marcada.
        self.bridge = BridgeProcess(self.tmp / "curta", "http://127.0.0.1:9", {"PULSELAB_SESSION_MAX_MINUTES": "1"})
        write_json(self.bridge.data / "installation.json", authorized_installation())
        sid = self.start_and_get_session()
        self.assertEqual(self.bridge.post("/v1/session/pause", {"session_id": sid})[0], 200)
        self.assertTrue(wait_for(lambda: self.bridge.get("/v1/questionario/estado")["motivo"] == "nao_autorizada", timeout=100),
                        "pausa vencida: a última aula continua não autorizada")
        self.assertFalse(self.bridge.get("/v1/status")["paused"])
        status, body = self.post("crianca", crianca("sim", "sim", "sim", "sim", "sim"))
        self.assertEqual((status, body["status"], body["motivo"]), (200, "nao_gravado", "nao_autorizada"))
        self.assertEqual(self.respostas("student_feedback_recorded"), [])

    def test_modo_livre_nao_grava(self):
        write_json(self.bridge.data / "installation.json", {"installation_id": INSTALLATION_ID, "site_id": "PET", "research_collection_enabled": False})
        self.bridge.start()
        estado = self.bridge.get("/v1/questionario/estado")
        self.assertEqual((estado["coleta_ativa"], estado["motivo"], estado["bancada_respondida"]), (False, "modo_livre", False))
        status, body = self.post("crianca", crianca("sim", "sim", "sim", "sim", "sim"))
        self.assertEqual((status, body["status"], body["motivo"]), (200, "nao_gravado", "modo_livre"))
        self.assertEqual(read_events(self.bridge.data), [])

    def test_rotas_exigem_origem_local_e_json(self):
        self.start_and_get_session()
        req = urllib.request.Request(
            f"{self.bridge.base}/v1/questionario/crianca",
            data=json.dumps({"submission_id": str(uuid.uuid4()), "answers": crianca("sim", "sim", "sim", "sim", "sim")}).encode(),
            headers={"Content-Type": "application/json", "Origin": "http://exemplo.com"}, method="POST",
        )
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(req, timeout=10)
        self.assertEqual(ctx.exception.code, 403)
        req = urllib.request.Request(
            f"{self.bridge.base}/v1/questionario/crianca", data=b"x=1",
            headers={"Content-Type": "text/plain", "Origin": self.bridge.base}, method="POST",
        )
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(req, timeout=10)
        self.assertEqual(ctx.exception.code, 415)
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(f"{self.bridge.base}/v1/questionario/crianca", timeout=10)
        self.assertEqual(ctx.exception.code, 405)
        self.assertEqual(self.respostas("student_feedback_recorded"), [])



class ConfigurableSupabase(BaseHTTPRequestHandler):
    """Supabase falso cuja resposta ao envio de eventos muda durante o teste (mode)."""

    mode = "ok"
    event_statuses: list[int] = []
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
        body = json.loads(self.rfile.read(length) or b"{}") if length else {}
        if self.path.startswith("/functions/v1/enroll-device"):
            return self.reply(200, {"access_token": "tok-1", "refresh_token": "ref-1", "expires_at": int(time.time()) + 3600,
                                    "user_id": "device-user", "installation_id": body.get("installation_id"), "site_id": "PET"})
        if self.path.startswith("/rest/v1/research_session_events"):
            status = {"ok": 201, "forbidden": 403, "bad": 400}[ConfigurableSupabase.mode]
            with ConfigurableSupabase.lock:
                ConfigurableSupabase.event_statuses.append(status)
            return self.reply(status, {} if status < 400 else {"message": "rejected"})
        if self.path.startswith("/rest/v1/research_bancada_sessions"):
            return self.reply(201)
        return self.reply(404)


@unittest.skipUnless(PWSH, "pwsh não encontrado")
class BridgeQuarantineTest(unittest.TestCase):
    """Erro da nuvem deixa o evento pendente; quarentena é visível e volta para a fila."""

    def setUp(self):
        ConfigurableSupabase.mode = "ok"
        ConfigurableSupabase.event_statuses = []
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), ConfigurableSupabase)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.tmp = Path(tempfile.mkdtemp(prefix="pulselab-bridge-quarantine-"))
        self.bridge = BridgeProcess(self.tmp, f"http://127.0.0.1:{self.server.server_port}", {
            "PULSELAB_SYNC_BACKOFF_MAX_SECONDS": "1",
            "PULSELAB_QUARANTINE_RETRY_SECONDS": "3",
        })
        write_json(self.bridge.data / "installation.json", authorized_installation(enrollment_token=SITE_TOKEN))

    def tearDown(self):
        self.bridge.stop()
        self.server.shutdown()
        self.server.server_close()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def statuses(self) -> list[int]:
        with ConfigurableSupabase.lock:
            return list(ConfigurableSupabase.event_statuses)

    def synced_ids(self) -> set[str]:
        tracker = self.bridge.data / "events_synced.txt"
        if not tracker.exists():
            return set()
        return {line.strip() for line in tracker.read_text(encoding="utf-8-sig").splitlines() if line.strip()}

    def test_403_deixa_pendente_e_recupera(self):
        ConfigurableSupabase.mode = "forbidden"
        self.bridge.start()
        self.assertTrue(wait_for(lambda: self.statuses().count(403) >= 2), "bridge não tentou de novo depois do 403")
        status = self.bridge.get("/v1/status")
        self.assertFalse((self.bridge.data / "events_quarantine.jsonl").exists(), "403 não pode mandar evento para quarentena")
        self.assertEqual(status["quarantined_events"], 0)
        self.assertEqual(status["last_sync_error"]["status_code"], 403)
        self.assertGreater(status["pending_sync"], 0)

        ConfigurableSupabase.mode = "ok"
        started = [e["event_id"] for e in read_events(self.bridge.data) if e["event_type"] == "session_started"]
        self.assertTrue(wait_for(lambda: set(started) <= self.synced_ids()), "evento não subiu depois que a nuvem voltou")

    def test_400_vai_para_quarentena_visivel_e_volta_para_a_fila(self):
        ConfigurableSupabase.mode = "bad"
        self.bridge.start()
        quarantine = self.bridge.data / "events_quarantine.jsonl"
        self.assertTrue(wait_for(quarantine.exists), "evento recusado com 400 deveria ir para a quarentena")
        self.assertTrue(wait_for(lambda: self.bridge.get("/v1/status")["quarantined_events"] > 0))
        self.assertEqual(self.bridge.get("/v1/status")["last_sync_error"]["status_code"], 400)
        self.assertTrue(wait_for(lambda: any(
            e["event_type"] == "heartbeat" and e["details"].get("quarantined_events", 0) > 0 for e in read_events(self.bridge.data))),
            "o sinal de vida deveria levar a contagem da quarentena para a nuvem")

        ConfigurableSupabase.mode = "ok"
        started = [e["event_id"] for e in read_events(self.bridge.data) if e["event_type"] == "session_started"]
        self.assertTrue(wait_for(lambda: set(started) <= self.synced_ids()), "quarentena não voltou para a fila")
        self.assertTrue(wait_for(lambda: self.bridge.get("/v1/status")["quarantined_events"] == 0))

    def test_nova_versao_devolve_quarentena_antiga(self):
        event_id = "99999999-9999-4999-8999-999999999999"
        line = json.dumps({"event_id": event_id, "session_id": "88888888-8888-4888-8888-888888888888", "event_type": "heartbeat"})
        (self.bridge.data / "events.jsonl").write_text(line + "\r\n", encoding="utf-8")
        (self.bridge.data / "events_quarantine.txt").write_text(event_id + "\r\n", encoding="utf-8")
        write_json(self.bridge.data / "quarantine_retry.json", {"retried_at": "2099-01-01T00:00:00.000Z", "bridge_version": "0.0.1"})
        self.bridge.env["PULSELAB_QUARANTINE_RETRY_SECONDS"] = "2592000"
        self.bridge.start()
        self.assertTrue(wait_for(lambda: event_id in self.synced_ids()), "evento da quarentena antiga não voltou para a fila")
        self.assertNotEqual(read_json(self.bridge.data / "quarantine_retry.json")["bridge_version"], "0.0.1")



@unittest.skipUnless(PWSH, "pwsh não encontrado")
class BridgeRetentionTest(unittest.TestCase):
    """Depois de retention_days, só sai do computador a aula que já foi para a nuvem ou para o pendrive."""

    NAO_SAIU = "a0000000-0000-4000-8000-00000000000a"
    NA_NUVEM = "b0000000-0000-4000-8000-00000000000b"
    NO_PENDRIVE = "c0000000-0000-4000-8000-00000000000c"

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="pulselab-bridge-retention-"))
        self.bridge = BridgeProcess(self.tmp, "http://127.0.0.1:9")
        data = self.bridge.data
        write_json(data / "installation.json", authorized_installation(retention_days=1))
        antiga = (datetime.now(timezone.utc) - timedelta(days=400)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
        (data / "sessoes").mkdir()
        linhas = []
        for sid in (self.NAO_SAIU, self.NA_NUVEM, self.NO_PENDRIVE):
            write_json(data / "sessoes" / f"sessao_{sid}.json", {"session_id": sid, "created_at": antiga, "status": "completed"})
            linhas.append(json.dumps({"event_id": "e" + sid[1:], "session_id": sid, "event_type": "session_started"}))
        (data / "events.jsonl").write_text("\r\n".join(linhas) + "\r\n", encoding="utf-8")
        (data / "sessions_synced.txt").write_text(self.NA_NUVEM + "\r\n", encoding="utf-8")
        (data / "events_synced.txt").write_text("e" + self.NA_NUVEM[1:] + "\r\n", encoding="utf-8")
        exportado = (datetime.now(timezone.utc) + timedelta(seconds=5)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
        write_json(data / "ultima_exportacao_pendrive.json", {"exported_at": exportado})
        # Regravadas depois da exportação (questionário respondido mais tarde, por exemplo): o pendrive não as leva.
        future = time.time() + 60
        for sid in (self.NAO_SAIU, self.NA_NUVEM):
            os.utime(data / "sessoes" / f"sessao_{sid}.json", (future, future))

    def tearDown(self):
        self.bridge.stop()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_poupa_o_que_nao_saiu_do_computador(self):
        self.bridge.start()
        sessoes = self.bridge.data / "sessoes"
        self.assertTrue(wait_for(lambda: not (sessoes / f"sessao_{self.NA_NUVEM}.json").exists()), "aula enviada à nuvem deveria sair")
        self.assertTrue(wait_for(lambda: not (sessoes / f"sessao_{self.NO_PENDRIVE}.json").exists()), "aula exportada deveria sair")
        self.assertTrue((sessoes / f"sessao_{self.NAO_SAIU}.json").exists(), "aula que não saiu do computador não pode ser apagada")
        restantes = {e["session_id"] for e in read_events(self.bridge.data)}
        self.assertIn(self.NAO_SAIU, restantes)
        self.assertNotIn(self.NA_NUVEM, restantes)
        self.assertNotIn(self.NO_PENDRIVE, restantes)
        self.assertEqual(self.bridge.get("/v1/status")["retention_kept_sessions"], 1)


if __name__ == "__main__":
    unittest.main()
