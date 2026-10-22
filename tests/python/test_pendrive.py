"""Pendrive dos polos sem internet: chave por polo, assinatura do exportador e importação.

Fluxo: gerar-pacote-polo.py cria a chave do polo (provisionamento.json + dist-polos/chaves-manifesto.json),
o exportador assina o manifesto com ela e o importador escolhe a chave pelo site_id do manifesto.
Todas as chaves aqui são sintéticas.
"""

from __future__ import annotations

import base64
import contextlib
import hashlib
import hmac
import importlib.util
import io
import json
import os
import shutil
import sqlite3
import stat
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def load(name: str, rel: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


polo = load("gerar_pacote_polo_pendrive", "tooling/polo/gerar-pacote-polo.py")
imp = load("importar_para_supabase_pendrive", "tooling/data/importar-para-supabase.py")

KEY_PET = "a1" * 32
KEY_JUA = "b2" * 32
WITHDRAWN = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
KEPT = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
KEEP_NEW = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"


class FakeBuilder:
    VERSION = "9.9.9"

    def __init__(self):
        self.provisionings: list[dict] = []

    def build_package(self, root, output, provisioning=None):
        self.provisionings.append(json.loads(Path(provisioning).read_text(encoding="utf-8")))
        Path(output).write_bytes(b"zip")
        return output


class PoloManifestKeyTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.out = Path(self.tmp.name) / "dist-polos"

    def tearDown(self):
        self.tmp.cleanup()

    def run_generator(self, polo_code: str) -> dict:
        builder = FakeBuilder()
        with patch.object(polo, "load_builder", return_value=builder), contextlib.redirect_stdout(io.StringIO()):
            code = polo.main(["--polo", polo_code, "--regional", "Petrolina", "--caae", "87654321.0.0000.5678",
                              "--out-dir", str(self.out)])
        self.assertEqual(code, 0)
        return builder.provisionings[0]

    def keys(self) -> dict:
        return json.loads((self.out / "chaves-manifesto.json").read_text(encoding="utf-8"))

    def test_pacote_cria_chave_e_reutiliza_na_segunda_vez(self):
        first = self.run_generator("PET")
        key = first["manifest_hmac_key"]
        self.assertRegex(key, r"^[0-9a-f]{64}$")
        self.assertEqual(self.keys(), {"PET": key})

        second = self.run_generator("PET")
        self.assertEqual(second["manifest_hmac_key"], key)
        self.assertNotEqual(second["provisioning_id"], "")

        other = self.run_generator("JUA")
        self.assertNotEqual(other["manifest_hmac_key"], key)
        self.assertEqual(self.keys(), {"JUA": other["manifest_hmac_key"], "PET": key})

    @unittest.skipIf(sys.platform.startswith("win"), "permissões POSIX")
    def test_arquivo_de_chaves_so_para_o_dono(self):
        self.run_generator("PET")
        mode = stat.S_IMODE((self.out / "chaves-manifesto.json").stat().st_mode)
        self.assertEqual(mode, 0o600)

    def test_chave_invalida_no_arquivo_nao_e_substituida_em_silencio(self):
        self.out.mkdir(parents=True)
        (self.out / "chaves-manifesto.json").write_text(json.dumps({"PET": "curta"}), encoding="utf-8")
        with self.assertRaises(ValueError):
            polo.ensure_manifest_key(self.out / "chaves-manifesto.json", "PET")

    def test_instalacao_copia_a_chave_do_provisionamento(self):
        script = (ROOT / "runtime" / "windows" / "pulselab-installation.ps1").read_text(encoding="utf-8")
        self.assertIn('"manifest_hmac_key"', script)


def write_export(folder: Path, files: dict[str, bytes], site_id: str | None, key: str | None) -> Path:
    """Pasta de coleta no formato do exportar-pendrive.ps1 (manifesto UTF-8 com BOM e CRLF)."""
    lines = []
    for rel, content in files.items():
        path = folder / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        lines.append(f"{hashlib.sha256(content).hexdigest().upper()}  {rel}")
    header = ["PULSELAB - MANIFESTO DE COLETA DE DADOS EM CAMPO (OFFLINE)", "Maquina (rotulo)      : PET-PC01"]
    if site_id is not None:
        header.append(f"Polo (site_id)        : {site_id}")
    text = "\r\n".join(header + ["INTEGRIDADE DOS ARQUIVOS (SHA-256):", ""] + lines) + "\r\n"
    manifest = folder / "manifesto_coleta.txt"
    manifest.write_bytes(b"\xef\xbb\xbf" + text.encode("utf-8"))
    if key:
        sig = hmac.new(key.encode("utf-8"), manifest.read_bytes(), hashlib.sha256).hexdigest()
        (folder / "manifesto_coleta.sig").write_text(sig, encoding="utf-8")
    return folder


def snapshot(session_id: str) -> bytes:
    return json.dumps({"session_id": session_id, "group_id": "g-1", "site_id": "PET", "status": "completed"}).encode("utf-8")


class ImportadorChavePorPoloTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.keys_file = self.root / "chaves-manifesto.json"
        self.keys_file.write_text(json.dumps({"PET": KEY_PET, "JUA": KEY_JUA}), encoding="utf-8")
        self.coletas = self.root / "coletas"

    def tearDown(self):
        self.tmp.cleanup()

    def validate(self, folder: Path):
        site = imp.read_manifest_site_id(folder)
        keys = imp.load_manifest_keys(self.keys_file)
        return imp.validate_manifest(folder, hmac_keys=[keys[site]] if site in keys else None, require_signature=True)

    def test_assinatura_com_a_chave_do_polo_certo_e_aceita(self):
        folder = write_export(self.coletas / "Coleta_PET", {"events.jsonl": b"{}\n"}, "PET", KEY_PET)
        self.assertEqual(imp.read_manifest_site_id(folder), "PET")
        valid, msg = self.validate(folder)
        self.assertTrue(valid, msg)
        self.assertIn("autenticado", msg)

    def test_assinatura_com_chave_de_outro_polo_e_rejeitada(self):
        folder = write_export(self.coletas / "Coleta_PET", {"events.jsonl": b"{}\n"}, "PET", KEY_JUA)
        valid, msg = self.validate(folder)
        self.assertFalse(valid)
        self.assertIn("inválida ou divergente", msg)

    def test_assinatura_gravada_com_bom_pelo_exportador_antigo_e_aceita(self):
        folder = write_export(self.coletas / "Coleta_PET", {"events.jsonl": b"{}\n"}, "PET", KEY_PET)
        sig = folder / "manifesto_coleta.sig"
        sig.write_bytes(b"\xef\xbb\xbf" + sig.read_bytes())
        valid, msg = self.validate(folder)
        self.assertTrue(valid, msg)

    def test_variavel_de_ambiente_continua_valendo(self):
        folder = write_export(self.coletas / "Coleta_X", {"events.jsonl": b"{}\n"}, "PET", "chave-institucional-antiga")
        valid, msg = imp.validate_manifest(folder, hmac_key="chave-institucional-antiga",
                                           hmac_keys=[KEY_PET], require_signature=True)
        self.assertTrue(valid, msg)

    def test_mensagem_diz_o_que_fazer_quando_falta_a_chave(self):
        hint = imp.missing_key_hint("SBF", self.keys_file, {"PET": KEY_PET})
        self.assertIn("Falta a chave do polo SBF", hint)
        self.assertIn("chaves-manifesto.json", hint)
        self.assertIn("--chaves", hint)
        self.assertIn("pacote antigo ou genérico", imp.missing_key_hint("", self.keys_file, {}))
        self.assertIn("não confere", imp.missing_key_hint("PET", self.keys_file, {"PET": KEY_PET}))

    def run_main(self, *extra: str):
        argv = ["importar", "--source", str(self.coletas), "--sqlite-path", str(self.root / "consolidado.sqlite"),
                "--chaves", str(self.keys_file), *extra]
        out = io.StringIO()
        with patch.object(imp, "__file__", str(self.root / "a" / "b" / "importar-para-supabase.py")), \
                patch.object(sys, "argv", argv), patch.dict(os.environ, {"PULSELAB_MANIFEST_HMAC_KEY": ""}), \
                contextlib.redirect_stdout(out):
            code = imp.main()
        return code, out.getvalue()

    @staticmethod
    def fake_service_key():
        payload = base64.urlsafe_b64encode(json.dumps({"role": "service_role"}).encode()).decode().rstrip("=")
        return f"eyJhbGciOiJIUzI1NiJ9.{payload}.assinatura"

    def test_polo_sem_chave_explica_o_que_fazer(self):
        write_export(self.coletas / "Coleta_SBF", {"events.jsonl": b"{}\n"}, "SBF", "c3" * 32)
        code, out = self.run_main("--supabase-key", self.fake_service_key(), "--supabase-url", "https://exemplo.supabase.co")
        self.assertEqual(code, 1, out)
        self.assertIn("Falta a chave do polo SBF", out)

    def test_retiradas_de_pasta_rejeitada_sao_processadas(self):
        write_export(self.coletas / "Coleta_PET_1", {
            f"sessoes/sessao_{WITHDRAWN}.json": snapshot(WITHDRAWN),
            f"sessoes/sessao_{KEPT}.json": snapshot(KEPT),
        }, "PET", KEY_PET)
        code, out = self.run_main("--no-cloud")
        self.assertEqual(code, 0, out)

        # Pendrive seguinte com assinatura que não confere (chave de outro polo): dados recusados,
        # mas a retirada de "Não registrar esta turma" vale.
        write_export(self.coletas / "Coleta_PET_2", {
            f"sessoes/sessao_{KEEP_NEW}.json": snapshot(KEEP_NEW),
            "sessions_withdrawn.txt": ("﻿" + WITHDRAWN + "\r\n").encode("utf-8"),
        }, "PET", KEY_JUA)
        code, out = self.run_main("--no-cloud")
        self.assertEqual(code, 0, out)
        self.assertIn("Pasta rejeitada", out)
        self.assertIn("Retiradas desta pasta honradas", out)

        db = sqlite3.connect(str(self.root / "consolidado.sqlite"))
        try:
            ids = {row[0] for row in db.execute("SELECT session_id FROM sessions")}
            self.assertEqual(ids, {KEPT})
            self.assertEqual(db.execute("SELECT session_id FROM withdrawn_sessions").fetchall(), [(WITHDRAWN,)])
        finally:
            db.close()

    def test_retirada_de_pasta_rejeitada_vai_para_a_nuvem(self):
        write_export(self.coletas / "Coleta_PET_ok", {f"sessoes/sessao_{KEPT}.json": snapshot(KEPT)}, "PET", KEY_PET)
        write_export(self.coletas / "Coleta_PET_sem_assinatura", {
            f"sessoes/sessao_{KEEP_NEW}.json": snapshot(KEEP_NEW),
            "sessions_withdrawn.txt": (WITHDRAWN + "\n").encode("utf-8"),
        }, None, None)
        sent_tables: dict[str, list] = {}

        def fake_send(table, records, *args, **kwargs):
            sent_tables[table] = list(records)
            return len(records), 0, 0, None

        with patch.object(imp, "withdraw_sessions_remote", return_value=(1, None)) as withdraw, \
                patch.object(imp, "send_to_supabase", side_effect=fake_send):
            code, out = self.run_main("--supabase-key", self.fake_service_key(), "--supabase-url", "https://exemplo.supabase.co")
        self.assertEqual(code, 0, out)
        withdraw.assert_called_once()
        self.assertEqual(withdraw.call_args[0][0], {WITHDRAWN})
        self.assertIn("pacote antigo ou genérico", out)
        self.assertEqual({r["session_id"] for r in sent_tables["research_bancada_sessions"]}, {KEPT})



@unittest.skipUnless(shutil.which("pwsh"), "pwsh não instalado")
class ExportadorPowerShellTest(unittest.TestCase):
    """Roda o exportar-pendrive.ps1 de verdade numa instalação falsa e confere com o importador."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.install = base / "PulseLab"
        scripts = self.install / "scripts"
        scripts.mkdir(parents=True)
        shutil.copy2(ROOT / "runtime" / "windows" / "scripts" / "exportar-pendrive.ps1", scripts / "exportar-pendrive.ps1")
        data = self.install / "dados_locais"
        (data / "sessoes").mkdir(parents=True)
        (data / "installation.json").write_text(json.dumps({
            "installation_id": "11111111-2222-4333-8444-555555555555",
            "machine_label": "PET-LAB1-PC03",
            "site_id": "PET",
            "manifest_hmac_key": KEY_PET,
        }), encoding="utf-8")
        (data / "sessoes" / f"sessao_{KEPT}.json").write_bytes(snapshot(KEPT))
        (data / "events.jsonl").write_text(json.dumps({"event_id": "e1", "session_id": KEPT}) + "\n", encoding="utf-8")
        (data / "sessions_withdrawn.txt").write_text(WITHDRAWN + "\n", encoding="utf-8")
        self.usb = base / "usb"
        self.usb.mkdir()
        self.localappdata = base / "localappdata"
        self.localappdata.mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def export(self, env_key: str | None = None) -> Path:
        env = {k: v for k, v in os.environ.items() if k != "PULSELAB_MANIFEST_HMAC_KEY"}
        env["LOCALAPPDATA"] = str(self.localappdata)
        if env_key:
            env["PULSELAB_MANIFEST_HMAC_KEY"] = env_key
        result = subprocess.run(
            ["pwsh", "-NoProfile", "-NonInteractive", "-File", str(self.install / "scripts" / "exportar-pendrive.ps1"),
             "-TargetDrive", str(self.usb)],
            env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=120,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        folders = [p.parent for p in Path(self.tmp.name).rglob("manifesto_coleta.txt")]
        self.assertEqual(len(folders), 1, result.stdout)
        return folders[0]

    def test_assina_com_a_chave_do_polo_e_nao_leva_a_chave(self):
        folder = self.export()
        self.assertTrue((folder / "manifesto_coleta.sig").is_file())
        self.assertEqual(imp.read_manifest_site_id(folder), "PET")
        valid, msg = imp.validate_manifest(folder, hmac_keys=[KEY_PET], require_signature=True)
        self.assertTrue(valid, msg)
        self.assertIn("autenticado", msg)
        valid, _ = imp.validate_manifest(folder, hmac_keys=[KEY_JUA], require_signature=True)
        self.assertFalse(valid)

        names = {p.name for p in folder.rglob("*")}
        self.assertNotIn("installation.json", names)
        for path in folder.rglob("*"):
            if path.is_file():
                self.assertNotIn(KEY_PET.encode("ascii"), path.read_bytes(), path.name)

    def test_registra_a_exportacao_para_a_retencao(self):
        antes = datetime.now(timezone.utc).replace(microsecond=0)
        folder = self.export()
        marca = json.loads((self.install / "dados_locais" / "ultima_exportacao_pendrive.json").read_text(encoding="utf-8"))
        exportado = datetime.strptime(marca["exported_at"], "%Y-%m-%dT%H:%M:%S.%fZ").replace(tzinfo=timezone.utc)
        self.assertGreaterEqual(exportado, antes)
        self.assertLessEqual(exportado, datetime.now(timezone.utc))
        self.assertNotIn("ultima_exportacao_pendrive.json", {p.name for p in folder.rglob("*")})

    def test_variavel_de_ambiente_tem_prioridade(self):
        folder = self.export(env_key="chave-institucional-de-teste")
        valid, msg = imp.validate_manifest(folder, hmac_key="chave-institucional-de-teste", require_signature=True)
        self.assertTrue(valid, msg)
        valid, _ = imp.validate_manifest(folder, hmac_keys=[KEY_PET], require_signature=True)
        self.assertFalse(valid)


if __name__ == "__main__":
    unittest.main()
