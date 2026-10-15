#!/usr/bin/env python3
"""
Testes unitários automatizados para o importador e consolidador (tooling/data/importar-para-supabase.py).
Valida:
1. Validação estrita do manifesto SHA-256 (arquivos válidos, ausentes, adulterados, manifesto ausente, vazio e arquivos extras).
2. Preservação estrita de occurred_at original (sem substituição silenciosa).
3. Preservação de tipos desconhecidos em quarentena (sem conversão para phase_completed).
4. Idempotência estrita em HTTP 409 (código 23505 comprovado na PK esperada é duplicado, conflitos em outras constraints são rejeitados).
5. Estratégia divide-and-conquer em lotes no envio ao Supabase.
6. Rejeição de credencial pública anônima (anon) para sincronização remota.
"""

from __future__ import annotations

import base64
import contextlib
import hashlib
import hmac
import io
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch
import urllib.error

import importlib.util

spec = importlib.util.spec_from_file_location(
    "importar_para_supabase",
    Path(__file__).resolve().parents[2] / "tooling" / "data" / "importar-para-supabase.py",
)
imp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(imp)


class TestImportadorIntegridade(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.dir_path = Path(self.temp_dir.name)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_manifest_validation_valid(self):
        """Manifesto com arquivos válidos deve retornar (True, ...)"""
        f1 = self.dir_path / "sessao_123.json"
        content = b'{"session_id": "test-123"}'
        f1.write_bytes(content)
        h1 = hashlib.sha256(content).hexdigest()

        manifest = self.dir_path / "manifesto_coleta.txt"
        manifest.write_text(
            f"INTEGRIDADE DOS ARQUIVOS (SHA-256):\n\n{h1}  sessao_123.json\n",
            encoding="utf-8",
        )

        valid, msg = imp.validate_manifest(self.dir_path)
        self.assertTrue(valid)
        self.assertIn("1 arquivos verificados", msg)

    def test_manifest_validation_tampered(self):
        """Arquivo adulterado em relação ao manifesto deve ser detectado e rejeitado."""
        f1 = self.dir_path / "sessao_123.json"
        f1.write_bytes(b'{"session_id": "original"}')
        h1 = hashlib.sha256(b'{"session_id": "original"}').hexdigest()

        manifest = self.dir_path / "manifesto_coleta.txt"
        manifest.write_text(
            f"INTEGRIDADE DOS ARQUIVOS (SHA-256):\n\n{h1}  sessao_123.json\n",
            encoding="utf-8",
        )

        # Adultera o arquivo
        f1.write_bytes(b'{"session_id": "adulterado"}')

        valid, msg = imp.validate_manifest(self.dir_path)
        self.assertFalse(valid)
        self.assertIn("Adulteração detectada", msg)

    def test_manifest_validation_missing_file(self):
        """Arquivo listado no manifesto mas ausente na pasta deve falhar de forma segura."""
        manifest = self.dir_path / "manifesto_coleta.txt"
        manifest.write_text(
            "INTEGRIDADE DOS ARQUIVOS (SHA-256):\n\ne3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  arquivo_fantasma.json\n",
            encoding="utf-8",
        )

        valid, msg = imp.validate_manifest(self.dir_path)
        self.assertFalse(valid)
        self.assertIn("ausente", msg)

    def test_manifest_missing_fails_safely(self):
        """Pasta sem nenhum arquivo manifesto_*.txt deve falhar de forma segura."""
        f1 = self.dir_path / "sessao_123.json"
        f1.write_bytes(b'{"session_id": "test-123"}')

        valid, msg = imp.validate_manifest(self.dir_path, require_manifest=True)
        self.assertFalse(valid)
        self.assertIn("Manifesto ausente", msg)

    def test_manifest_empty_fails_safely(self):
        """Manifesto vazio ou sem arquivos deve falhar de forma segura."""
        manifest = self.dir_path / "manifesto_coleta.txt"
        manifest.write_text("INTEGRIDADE DOS ARQUIVOS (SHA-256):\n\n", encoding="utf-8")

        valid, msg = imp.validate_manifest(self.dir_path)
        self.assertFalse(valid)
        self.assertIn("vazio ou inválido", msg)

    def test_manifest_extra_file_fails_safely(self):
        """Arquivo extra (.json/.jsonl) não listado no manifesto deve falhar de forma segura."""
        f1 = self.dir_path / "sessao_123.json"
        content = b'{"session_id": "test-123"}'
        f1.write_bytes(content)
        h1 = hashlib.sha256(content).hexdigest()

        # Arquivo intruso não declarado
        extra = self.dir_path / "arquivo_intruso.json"
        extra.write_bytes(b'{"malicious": true}')

        manifest = self.dir_path / "manifesto_coleta.txt"
        manifest.write_text(
            f"INTEGRIDADE DOS ARQUIVOS (SHA-256):\n\n{h1}  sessao_123.json\n",
            encoding="utf-8",
        )

        valid, msg = imp.validate_manifest(self.dir_path)
        self.assertFalse(valid)
        self.assertIn("Arquivo extra não declarado", msg)

    def test_occurred_at_preservation(self):
        """occurred_at original deve ser preservado e não substituído por timestamp atual."""
        original_time = "2026-10-03T10:15:30.123Z"
        event = {
            "event_id": "550e8400-e29b-41d4-a716-446655440000",
            "session_id": "550e8400-e29b-41d4-a716-446655440001",
            "event_type": "spike_telemetry",
            "occurred_at": original_time,
        }

        sanitized = imp.sanitize_event_for_supabase(event, "research_session_events")
        self.assertEqual(sanitized.get("occurred_at"), original_time)

    def test_unknown_event_type_quarantined_not_converted(self):
        """Tipo desconhecido nunca deve ser convertido para phase_completed; deve ir para quarentena."""
        event = {
            "event_id": "550e8400-e29b-41d4-a716-446655440002",
            "session_id": "550e8400-e29b-41d4-a716-446655440001",
            "event_type": "evento_customizado_desconhecido",
            "occurred_at": "2026-10-03T10:20:00Z",
        }

        sanitized = imp.sanitize_event_for_supabase(event, "research_session_events")
        self.assertEqual(sanitized.get("event_type"), "evento_customizado_desconhecido")
        self.assertNotEqual(sanitized.get("event_type"), "phase_completed")
        self.assertTrue(sanitized.get("_is_quarantine"))

    def test_anon_key_detection(self):
        """Verifica detecção de chave anônima (pública) para rejeição de sincronização remota não autorizada."""
        self.assertTrue(imp.is_anon_key(imp.DEFAULT_SUPABASE_ANON_KEY))
        self.assertTrue(imp.is_anon_key(""))
        # Chave service_role sintética com role diferente de anon
        self.assertFalse(imp.is_anon_key("eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.sig"))

    @patch("urllib.request.urlopen")
    def test_supabase_pk_23505_accepted_as_duplicate(self, mock_urlopen):
        """HTTP 409 com código 23505 comprovado na chave primária esperada (event_id) é duplicata."""
        mock_resp_409_pk = urllib.error.HTTPError(
            url="http://mock",
            code=409,
            msg="Conflict",
            hdrs={},
            fp=MagicMock(
                read=lambda: b'{"code": "23505", "message": "duplicate key value violates unique constraint \\"research_session_events_pkey\\"", "details": "Key (event_id)=(550e8400-e29b-41d4-a716-446655440003) already exists."}'
            ),
        )
        mock_urlopen.side_effect = mock_resp_409_pk

        records = [{"event_id": "550e8400-e29b-41d4-a716-446655440003"}]
        inserted, duplicates, errors, last_err = imp.send_to_supabase(
            "research_session_events", records, "https://mock.supabase.co", "service_key"
        )
        self.assertEqual(inserted, 0)
        self.assertEqual(duplicates, 1)
        self.assertEqual(errors, 0)
        self.assertIsNone(last_err)

    @patch("urllib.request.urlopen")
    def test_supabase_non_pk_23505_rejected(self, mock_urlopen):
        """HTTP 409 com código 23505 em constraint que NÃO é PK deve ser rejeitado como erro."""
        mock_resp_409_other = urllib.error.HTTPError(
            url="http://mock",
            code=409,
            msg="Conflict",
            hdrs={},
            fp=MagicMock(
                read=lambda: b'{"code": "23505", "message": "duplicate key value violates unique constraint \\"idx_bancada_unique_logic\\"", "details": "Key (bancada_code)=(A1) already exists."}'
            ),
        )
        mock_urlopen.side_effect = mock_resp_409_other

        records = [{"event_id": "550e8400-e29b-41d4-a716-446655440004"}]
        inserted, duplicates, errors, last_err = imp.send_to_supabase(
            "research_session_events", records, "https://mock.supabase.co", "service_key"
        )
        self.assertEqual(inserted, 0)
        self.assertEqual(duplicates, 0)
        self.assertEqual(errors, 1)
        self.assertIn("HTTP 409", last_err)

    @patch("urllib.request.urlopen")
    def test_divide_and_conquer_batch(self, mock_urlopen):
        """Em caso de falha em lote de 2 itens, o lote é dividido e cada item tratado individualmente."""
        def mock_dispatch(req, timeout=15):
            payload = json.loads(req.data.decode("utf-8"))
            if len(payload) > 1:
                # Lote inteiro falha com erro 409
                raise urllib.error.HTTPError(
                    url="http://mock",
                    code=409,
                    msg="Conflict",
                    hdrs={},
                    fp=MagicMock(
                        read=lambda: b'{"code": "23505", "message": "duplicate key value violates unique constraint \\"research_session_events_pkey\\"", "details": "Key (event_id)=(ev-1) already exists."}'
                    ),
                )
            # Item único ev-1: é duplicata da PK
            if payload[0]["event_id"] == "ev-1":
                raise urllib.error.HTTPError(
                    url="http://mock",
                    code=409,
                    msg="Conflict",
                    hdrs={},
                    fp=MagicMock(
                        read=lambda: b'{"code": "23505", "message": "duplicate key value violates unique constraint \\"research_session_events_pkey\\"", "details": "Key (event_id)=(ev-1) already exists."}'
                    ),
                )
            # Item único ev-2: é inserido com sucesso e retornado pela API
            resp = MagicMock()
            resp.__enter__.return_value = resp
            resp.status = 201
            resp.read.return_value = json.dumps([payload[0]]).encode("utf-8")
            return resp

        mock_urlopen.side_effect = mock_dispatch

        records = [{"event_id": "ev-1"}, {"event_id": "ev-2"}]
        inserted, duplicates, errors, last_err = imp.send_to_supabase(
            "research_session_events", records, "https://mock.supabase.co", "service_key", batch_size=2
        )
        # ev-1 duplicado, ev-2 inserido: nenhum erro global nem perda de registros
        self.assertEqual(inserted, 1)
        self.assertEqual(duplicates, 1)
        self.assertEqual(errors, 0)


    def test_manifest_relative_paths_with_homonymous_files_one_tampered(self):
        """Dois arquivos homônimos em pastas diferentes: resolução com caminhos relativos detecta o adulterado."""
        sub1 = self.dir_path / "sessoes"
        sub2 = self.dir_path / "backup"
        sub1.mkdir(parents=True, exist_ok=True)
        sub2.mkdir(parents=True, exist_ok=True)

        f1 = sub1 / "sessao_123.json"
        f2 = sub2 / "sessao_123.json"

        f1.write_bytes(b'{"session_id": "sessao_original_1"}')
        f2.write_bytes(b'{"session_id": "sessao_original_2"}')

        h1 = hashlib.sha256(b'{"session_id": "sessao_original_1"}').hexdigest()
        h2 = hashlib.sha256(b'{"session_id": "sessao_original_2"}').hexdigest()

        # Adultera o segundo arquivo
        f2.write_bytes(b'{"session_id": "sessao_tampered_2"}')

        manifest = self.dir_path / "manifesto_coleta.txt"
        manifest.write_text(
            f"INTEGRIDADE DOS ARQUIVOS (SHA-256):\n\n"
            f"{h1}  sessoes/sessao_123.json\n"
            f"{h2}  backup/sessao_123.json\n",
            encoding="utf-8",
        )

        valid, msg = imp.validate_manifest(self.dir_path)
        self.assertFalse(valid)
        self.assertIn("Adulteração detectada em backup/sessao_123.json", msg)

    def test_manifest_legacy_basename_homonymous_ambiguity_fails(self):
        """Dois arquivos homônimos com manifesto no formato legado (apenas basename) devem falhar por ambiguidade."""
        sub1 = self.dir_path / "sessoes"
        sub2 = self.dir_path / "outra"
        sub1.mkdir(parents=True, exist_ok=True)
        sub2.mkdir(parents=True, exist_ok=True)

        f1 = sub1 / "sessao_123.json"
        f2 = sub2 / "sessao_123.json"

        f1.write_bytes(b'{"session_id": "sessao_1"}')
        f2.write_bytes(b'{"session_id": "sessao_2"}')

        h1 = hashlib.sha256(b'{"session_id": "sessao_1"}').hexdigest()

        manifest = self.dir_path / "manifesto_coleta.txt"
        manifest.write_text(
            f"INTEGRIDADE DOS ARQUIVOS (SHA-256):\n\n{h1}  sessao_123.json\n",
            encoding="utf-8",
        )

        valid, msg = imp.validate_manifest(self.dir_path)
        self.assertFalse(valid)
        self.assertIn("Ambiguidade no manifesto legado", msg)

    def test_manifest_path_traversal_rejected(self):
        """Tentativa de path traversal no manifesto deve falhar de forma segura."""
        manifest = self.dir_path / "manifesto_coleta.txt"
        manifest.write_text(
            "INTEGRIDADE DOS ARQUIVOS (SHA-256):\n\n"
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  ../secret.txt\n",
            encoding="utf-8",
        )
        valid, msg = imp.validate_manifest(self.dir_path)
        self.assertFalse(valid)
        self.assertIn("Path traversal detectado", msg)

    def test_manifest_duplicate_entries_rejected(self):
        """Entradas duplicadas no manifesto devem falhar de forma segura."""
        f1 = self.dir_path / "sessao_123.json"
        content = b'{"session_id": "test-123"}'
        f1.write_bytes(content)
        h1 = hashlib.sha256(content).hexdigest()

        manifest = self.dir_path / "manifesto_coleta.txt"
        manifest.write_text(
            f"INTEGRIDADE DOS ARQUIVOS (SHA-256):\n\n"
            f"{h1}  sessao_123.json\n"
            f"{h1}  sessao_123.json\n",
            encoding="utf-8",
        )
        valid, msg = imp.validate_manifest(self.dir_path)
        self.assertFalse(valid)
        self.assertIn("Entrada duplicada", msg)

    def test_is_pk_conflict_rejects_unrelated_constraints_and_pks(self):
        """is_pk_conflict rejeita PKs não relacionadas e constraints de outras colunas."""
        # PK não relacionada (outra tabela)
        err_other_table = '{"code": "23505", "message": "duplicate key value violates unique constraint \\"users_pkey\\"", "details": "Key (id)=(user-1) already exists."}'
        self.assertFalse(imp.is_pk_conflict(err_other_table, "event_id", "research_session_events"))

        # Constraint de unicidade em outra coluna da mesma tabela
        err_other_col = '{"code": "23505", "message": "duplicate key value violates unique constraint \\"idx_unique_code\\"", "details": "Key (code)=(c-1) already exists."}'
        self.assertFalse(imp.is_pk_conflict(err_other_col, "event_id", "research_session_events"))

        # Menção casual a session_id em FK ou check constraint
        err_fk_mention = '{"code": "23503", "message": "violates foreign key constraint on session_id", "details": "Key (session_id)=(sess-1) is not present in table."}'
        self.assertFalse(imp.is_pk_conflict(err_fk_mention, "session_id", "research_bancada_sessions"))

        # PK legítima esperada
        err_legit = '{"code": "23505", "message": "duplicate key value violates unique constraint \\"research_session_events_pkey\\"", "details": "Key (event_id)=(ev-1) already exists."}'
        self.assertTrue(imp.is_pk_conflict(err_legit, "event_id", "research_session_events"))

    @patch("urllib.request.urlopen")
    def test_remote_rejections_captured_in_sink(self, mock_urlopen):
        """Rejeições remotas devem ser capturadas no rejected_sink com payload, status e erro detalhado."""
        mock_resp_400 = urllib.error.HTTPError(
            url="http://mock",
            code=400,
            msg="Bad Request",
            hdrs={},
            fp=MagicMock(read=lambda: b'{"code": "PGRST100", "message": "invalid input syntax for type uuid"}'),
        )
        mock_urlopen.side_effect = mock_resp_400

        rejected_sink = []
        record = {"event_id": "invalid-uuid-event", "event_type": "experience_recorded"}
        ins, dup, rej, last_err = imp.send_to_supabase(
            "research_session_events", [record], "https://mock.supabase.co", "service_key", rejected_sink=rejected_sink
        )

        self.assertEqual(ins, 0)
        self.assertEqual(dup, 0)
        self.assertEqual(rej, 1)
        self.assertEqual(len(rejected_sink), 1)
        self.assertEqual(rejected_sink[0]["status"], 400)
        self.assertEqual(rejected_sink[0]["record"]["event_id"], "invalid-uuid-event")
        self.assertIn("PGRST100", rejected_sink[0]["error"])

    def test_load_operational_credentials_ignores_config_secrets(self):
        """load_operational_credentials nunca deve extrair segredos operacionais de config.json ou defaults.json."""
        with tempfile.TemporaryDirectory() as fake_root_dir:
            fake_root = Path(fake_root_dir)
            cfg_dir = fake_root / "config"
            cfg_dir.mkdir(parents=True, exist_ok=True)
            (cfg_dir / "config.json").write_text(json.dumps({
                "supabase_url": "https://test.supabase.co",
                "supabase_operational_jwt": "leaked_jwt_in_config",
                "supabase_service_role_key": "leaked_service_key_in_config"
            }), encoding="utf-8")

            with patch.dict("os.environ", {}, clear=True):
                url, key = imp.load_operational_credentials(fake_root)
                self.assertEqual(url, "https://test.supabase.co")
                self.assertEqual(key, "")  # Não deve ler chave do arquivo de config


class TestBridgeSecurityStatic(unittest.TestCase):
    """Testes estáticos de segurança para runtime/windows/bridge/pulselab-bridge.ps1 sem necessidade de Windows."""

    @classmethod
    def setUpClass(cls):
        bridge_path = Path(__file__).resolve().parents[2] / "runtime" / "windows" / "bridge" / "pulselab-bridge.ps1"
        cls.bridge_code = bridge_path.read_text(encoding="utf-8", errors="replace")

    def test_auto_update_completely_disabled(self):
        """Auto-update remoto deve estar completamente desabilitado no Bridge sem download/update acionável."""
        self.assertIn("$script:AutoUpdateEnabled = $false", self.bridge_code)
        self.assertIn('$path -eq "/update"', self.bridge_code)
        self.assertIn('$response.StatusCode = 403', self.bridge_code)
        self.assertIn('status = "disabled"', self.bridge_code)
        # Nenhuma URL remota de download
        self.assertNotIn("raw.githubusercontent.com", self.bridge_code)
        self.assertNotIn("pulselab-robotica-edu.web.app", self.bridge_code)
        self.assertNotIn("releases/download", self.bridge_code)
        # Nenhuma chamada a DownloadFile ou DownloadString para update
        self.assertNotIn(".DownloadFile(", self.bridge_code)
        self.assertNotIn(".DownloadString(", self.bridge_code)

    def test_retention_cleanup_routine_present(self):
        """Bridge deve possuir rotina Invoke-BridgeRetentionCleanup com prazo configurável (padrão 180 dias)."""
        self.assertIn("function Invoke-BridgeRetentionCleanup", self.bridge_code)
        self.assertIn("$cutoffUtc = [DateTime]::UtcNow.AddDays(-$MaxAgeDays)", self.bridge_code)
        self.assertIn("Invoke-BridgeRetentionCleanup -MaxAgeDays (Get-BridgeRetentionDays)", self.bridge_code)
        self.assertIn("param([int]$MaxAgeDays = 180)", self.bridge_code)

    def test_operational_jwt_not_read_from_config(self):
        """Bridge deve ler JWT operacional exclusivamente de PULSELAB_OPERATIONAL_JWT."""
        self.assertIn("$env:PULSELAB_OPERATIONAL_JWT", self.bridge_code)
        self.assertNotIn('$config.supabase_operational_jwt', self.bridge_code)
        self.assertNotIn('$config["supabase_operational_jwt"]', self.bridge_code)

    def test_config_endpoint_returns_allowlist_only(self):
        """Endpoints /config e /v1/config devem retornar allowlist pública, nunca chaves/tokens."""
        self.assertIn("$publicConfig = [ordered]@{", self.bridge_code)
        self.assertIn('$path -eq "/config"', self.bridge_code)
        self.assertNotIn('$config | ConvertTo-Json', self.bridge_code)

    def test_origin_header_enforced_on_mutating_endpoints(self):
        """Métodos POST/PUT/DELETE devem exigir Origin estrito da aplicação local servida."""
        self.assertIn("function Test-PulseLabAllowedOrigin", self.bridge_code)
        self.assertIn('$isMutating = $request.HttpMethod -in @("POST", "PUT", "DELETE", "PATCH")', self.bridge_code)
        self.assertIn("if (-not $isAllowedOrigin)", self.bridge_code)
        self.assertIn("$response.StatusCode = 403", self.bridge_code)

    def test_cors_wildcard_prohibited(self):
        """Header Access-Control-Allow-Origin não pode ser '*'."""
        self.assertNotIn("'Access-Control-Allow-Origin', '*'", self.bridge_code)
        self.assertNotIn('"Access-Control-Allow-Origin", "*"', self.bridge_code)
        self.assertNotIn('"Access-Control-Allow-Origin" = "*"', self.bridge_code)

    def test_content_length_limit_and_content_type_enforced(self):
        """Content-Length máximo e Content-Type application/json devem ser validados."""
        self.assertIn("$request.ContentLength64 -gt 5242880", self.bridge_code)
        self.assertIn("$response.StatusCode = 413", self.bridge_code)
        self.assertIn('$ct.ToLower().StartsWith("application/json")', self.bridge_code)
        self.assertIn("$response.StatusCode = 415", self.bridge_code)


builder_spec = importlib.util.spec_from_file_location(
    "build_installer",
    Path(__file__).resolve().parents[2] / "tooling" / "release" / "build-installer.py",
)
builder = importlib.util.module_from_spec(builder_spec)
builder_spec.loader.exec_module(builder)


class TestBuilderSecurity(unittest.TestCase):
    def test_nested_sensitive_key_detection(self):
        """Varredura recursiva deve identificar chaves sensíveis em estruturas aninhadas."""
        payload = {
            "app": {
                "name": "PulseLab",
                "settings": {
                    "database": {
                        "host": "localhost",
                        "service_role_secret": "super-secret-key-123",
                    }
                }
            }
        }
        violations = builder.scan_sensitive_configs(payload)
        self.assertIn("app.settings.database.service_role_secret", violations)

    def test_case_insensitive_sensitive_patterns(self):
        """Padrões como secret, token, password, operational_jwt devem ser case-insensitive."""
        payload = {
            "SECRET_KEY": "val1",
            "Api_Token": "val2",
            "USER_PASSWORD": "val3",
            "operational_JWT": "val4",
            "Private_Key": "val5",
            "nested_list": [
                {"supabase_key": "val6"}
            ]
        }
        violations = builder.scan_sensitive_configs(payload)
        self.assertIn("SECRET_KEY", violations)
        self.assertIn("Api_Token", violations)
        self.assertIn("USER_PASSWORD", violations)
        self.assertIn("operational_JWT", violations)
        self.assertIn("Private_Key", violations)
        self.assertIn("nested_list[0].supabase_key", violations)

    def test_empty_values_do_not_trigger_violation(self):
        """Chaves com valores vazios, nulos ou ausentes são permitidas."""
        payload = {
            "api_token": "",
            "secret_key": None,
            "password": [],
            "operational_jwt": {}
        }
        violations = builder.scan_sensitive_configs(payload)
        self.assertEqual(violations, [])

    def test_no_secret_leaked_in_error_message(self):
        """A mensagem de erro não pode vazar os valores dos segredos encontrados."""
        secret_val = "SECRET_THAT_MUST_NEVER_BE_EXPOSED_998877"
        payload = {"deep": {"config": {"api_secret": secret_val}}}
        violations = builder.scan_sensitive_configs(payload)
        err_msg = f"Chave sensível com valor não vazio encontrada: {', '.join(violations)}"
        self.assertIn("deep.config.api_secret", err_msg)
        self.assertNotIn(secret_val, err_msg)

    def test_repo_config_files_contain_zero_sensitive_keys(self):
        """Arquivos públicos config.json e defaults.json não podem conter nenhuma chave sensível com valor."""
        repo_root = Path(__file__).resolve().parents[2]
        for cfg_name in ("defaults.json", "config.json"):
            cfg_path = repo_root / "config" / cfg_name
            if cfg_path.is_file():
                data = json.loads(cfg_path.read_text(encoding="utf-8"))
                violations = builder.scan_sensitive_configs(data)
                self.assertEqual(violations, [], f"Chaves sensíveis encontradas em {cfg_name}: {violations}")


class TestManifestHmacAuthenticity(unittest.TestCase):
    """Testes de autenticação institucional do manifesto com HMAC-SHA256."""

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.dir_path = Path(self.temp_dir.name)
        f1 = self.dir_path / "sessao_123.json"
        content = b'{"session_id": "test-123"}'
        f1.write_bytes(content)
        h1 = hashlib.sha256(content).hexdigest()

        self.manifest = self.dir_path / "manifesto_coleta.txt"
        self.manifest_text = f"INTEGRIDADE DOS ARQUIVOS (SHA-256):\n\n{h1}  sessao_123.json\n"
        self.manifest.write_text(self.manifest_text, encoding="utf-8")
        self.hmac_key = "segredo-institucional-de-teste-super-seguro"

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_manifest_hmac_valid_signature_authenticates_origin(self):
        """Assinatura HMAC-SHA256 válida autentica a origem da coleta."""
        expected_hmac = hmac.new(
            self.hmac_key.encode("utf-8"),
            self.manifest.read_bytes(),
            hashlib.sha256
        ).hexdigest().lower()
        (self.dir_path / "manifesto_coleta.sig").write_text(expected_hmac, encoding="utf-8")

        valid, msg = imp.validate_manifest(
            self.dir_path,
            require_manifest=True,
            hmac_key=self.hmac_key,
            require_signature=True
        )
        self.assertTrue(valid)
        self.assertIn("autenticado", msg)

    def test_manifest_hmac_missing_signature_rejected_in_cloud(self):
        """Envio com credencial privilegiada para nuvem deve rejeitar coleta sem assinatura."""
        valid, msg = imp.validate_manifest(
            self.dir_path,
            require_manifest=True,
            hmac_key=self.hmac_key,
            require_signature=True
        )
        self.assertFalse(valid)
        self.assertIn("Assinatura institucional ausente", msg)

    def test_manifest_hmac_missing_signature_accepted_unauthenticated_in_no_cloud(self):
        """--no-cloud pode aceitar coleta sem assinatura para consolidação local sem alegar autenticidade."""
        valid, msg = imp.validate_manifest(
            self.dir_path,
            require_manifest=True,
            hmac_key=self.hmac_key,
            require_signature=False
        )
        self.assertTrue(valid)
        self.assertIn("origem não autenticada", msg)

    def test_manifest_hmac_invalid_signature_rejected(self):
        """Assinatura divergente ou adulterada deve falhar fail-closed em ambos os modos."""
        (self.dir_path / "manifesto_coleta.sig").write_text("a" * 64, encoding="utf-8")

        # Em modo nuvem
        valid, msg = imp.validate_manifest(
            self.dir_path,
            require_manifest=True,
            hmac_key=self.hmac_key,
            require_signature=True
        )
        self.assertFalse(valid)
        self.assertIn("inválida ou divergente", msg)

        # Em modo no-cloud
        valid2, msg2 = imp.validate_manifest(
            self.dir_path,
            require_manifest=True,
            hmac_key=self.hmac_key,
            require_signature=False
        )
        self.assertFalse(valid2)
        self.assertIn("inválida ou divergente", msg2)

    def test_manifest_hmac_missing_key_rejected_in_cloud(self):
        """Envio à nuvem sem a chave institucional no ambiente deve falhar de forma segura."""
        expected_hmac = hmac.new(
            self.hmac_key.encode("utf-8"),
            self.manifest.read_bytes(),
            hashlib.sha256
        ).hexdigest().lower()
        (self.dir_path / "manifesto_coleta.sig").write_text(expected_hmac, encoding="utf-8")

        valid, msg = imp.validate_manifest(
            self.dir_path,
            require_manifest=True,
            hmac_key="",
            require_signature=True
        )
        self.assertFalse(valid)
        self.assertIn("Chave institucional ausente", msg)


if __name__ == "__main__":
    unittest.main()


class TestProvenienciaNaoImputada(unittest.TestCase):
    """O importador não inventa contexto nem versão do instrumento."""

    def base_event(self, **overrides):
        event = {
            "event_id": "11111111-1111-4111-8111-111111111111",
            "session_id": "22222222-2222-4222-8222-222222222222",
            "group_id": "33333333-3333-4333-8333-333333333333",
            "installation_id": "44444444-4444-4444-8444-444444444444",
            "event_type": "session_started",
            "occurred_at": "2026-10-11T12:00:00Z",
            "config_hash": "a" * 64,
            "protocol_version": "protocolo-oficinas-rotativas-v2",
        }
        event.update(overrides)
        return event

    def test_contexto_ausente_vira_nao_informado(self):
        payload = imp.sanitize_event_for_supabase(self.base_event(), "research_session_events")
        self.assertEqual(payload["school_code"], "nao_informado")
        self.assertEqual(payload["workshop_code"], "nao_informado")
        self.assertEqual(payload["class_code"], "nao_informado")
        self.assertNotIn("_is_quarantine", payload)

    def test_config_hash_ausente_vai_para_quarentena(self):
        event = self.base_event()
        del event["config_hash"]
        payload = imp.sanitize_event_for_supabase(event, "research_session_events")
        self.assertTrue(payload.get("_is_quarantine"))
        self.assertIn("config_hash", payload["_quarantine_reason"])
        self.assertNotEqual(payload.get("config_hash"), "3c3662c7306d64236b0f7f26da183cc59a36c00061a2077d93fb0272876b2468")

    def test_protocolo_nao_e_inventado(self):
        event = self.base_event()
        del event["protocol_version"]
        payload = imp.sanitize_event_for_supabase(event, "research_session_events")
        self.assertIsNone(payload.get("protocol_version"))

    def test_eventos_do_encerramento_sao_aceitos(self):
        for event_type in ("experience_recorded", "rubric_completed", "session_completed"):
            payload = imp.sanitize_event_for_supabase(self.base_event(event_type=event_type), "research_session_events")
            self.assertNotIn("_is_quarantine", payload, event_type)


class TestRetiradaEQualidadeDaBancada(unittest.TestCase):
    """Sessões retiradas nunca entram (SQLite e nuvem); snapshot encerrado não regride."""

    WITHDRAWN = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    KEPT = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.conn = imp.init_sqlite_database(self.root / "teste.sqlite")

    def tearDown(self):
        self.conn.close()
        self.temp_dir.cleanup()

    def snapshot(self, session_id, **overrides):
        data = {"session_id": session_id, "group_id": "g-1", "site_id": "SITE_A", "status": "completed"}
        data.update(overrides)
        return data

    def write_export(self, name, files: dict[str, bytes]):
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

    def run_main(self):
        argv = ["importar", "--no-cloud", "--source", str(self.root / "coletas"),
                "--sqlite-path", str(self.root / "consolidado.sqlite")]
        out = io.StringIO()
        with patch.object(imp, "__file__", str(self.root / "scripts" / "importar-para-supabase.py")), \
                patch.object(sys, "argv", argv), patch.dict(os.environ, {"PULSELAB_MANIFEST_HMAC_KEY": ""}), \
                contextlib.redirect_stdout(out):
            code = imp.main()
        return code, out.getvalue()

    def test_lista_de_retiradas_aceita_bom_e_linhas_vazias(self):
        (self.root / "sessions_withdrawn.txt").write_bytes(
            ("﻿" + self.WITHDRAWN.upper() + "\r\n\r\n  sessao-legada  \r\n").encode("utf-8")
        )
        ids = imp.read_withdrawn_sessions(self.root)
        self.assertEqual(ids, {self.WITHDRAWN, imp.ensure_uuid("sessao-legada")})
        self.assertTrue(imp.is_withdrawn("sessao-legada", ids))
        self.assertFalse(imp.is_withdrawn(None, ids))
        self.assertEqual(imp.read_withdrawn_sessions(self.root / "inexistente"), set())

    def test_lista_de_retiradas_precisa_estar_no_manifesto(self):
        folder = self.write_export("Coleta_A", {"events.jsonl": b"{}\n"})
        (folder / "sessions_withdrawn.txt").write_text(self.WITHDRAWN, encoding="utf-8")
        valid, msg = imp.validate_manifest(folder)
        self.assertFalse(valid)
        self.assertIn("sessions_withdrawn.txt", msg)

        declared = self.write_export("Coleta_B", {"sessions_withdrawn.txt": self.WITHDRAWN.encode("utf-8")})
        valid, msg = imp.validate_manifest(declared)
        self.assertTrue(valid, msg)

    def test_importacao_descarta_sessao_retirada_e_lembra_em_coletas_antigas(self):
        events = "\n".join(json.dumps(e) for e in [
            {"event_id": "e1", "session_id": self.WITHDRAWN, "event_type": "session_started", "occurred_at": "2026-10-14T10:00:00Z"},
            {"event_id": "e2", "session_id": self.WITHDRAWN, "event_type": "pre", "occurred_at": "2026-10-14T10:01:00Z"},
            {"session_id": self.WITHDRAWN, "event_type": "heartbeat"},
            {"event_id": "e3", "session_id": self.KEPT, "event_type": "session_started", "occurred_at": "2026-10-14T10:00:00Z"},
        ]).encode("utf-8")
        self.write_export("Coleta_PC1_20261014_120000", {
            "events.jsonl": events,
            f"sessoes/sessao_{self.WITHDRAWN}.json": json.dumps(self.snapshot(self.WITHDRAWN)).encode("utf-8"),
            f"sessoes/sessao_{self.KEPT}.json": json.dumps(self.snapshot(self.KEPT)).encode("utf-8"),
            "sessions_withdrawn.txt": ("﻿" + self.WITHDRAWN + "\r\n").encode("utf-8"),
        })
        code, out = self.run_main()
        self.assertEqual(code, 0, out)
        self.assertIn("descartados 1 snapshots e 3 eventos", out)

        db = sqlite3.connect(str(self.root / "consolidado.sqlite"))
        try:
            for tbl in ("sessions", "events", "session_events", "quarantined_events"):
                count = db.execute(f"SELECT count(*) FROM {tbl} WHERE session_id = ?", (self.WITHDRAWN,)).fetchone()[0]
                self.assertEqual(count, 0, tbl)
            self.assertEqual(db.execute("SELECT count(*) FROM sessions WHERE session_id = ?", (self.KEPT,)).fetchone()[0], 1)
            self.assertEqual(db.execute("SELECT session_id FROM withdrawn_sessions").fetchall(), [(self.WITHDRAWN,)])
        finally:
            db.close()

        # Coleta antiga, exportada antes da retirada e sem a lista: o tombstone local ainda vale.
        self.write_export("Coleta_PC1_20261001_120000", {
            "events.jsonl": json.dumps({"event_id": "e9", "session_id": self.WITHDRAWN, "event_type": "heartbeat"}).encode("utf-8"),
            f"sessoes/sessao_{self.WITHDRAWN}.json": json.dumps(self.snapshot(self.WITHDRAWN)).encode("utf-8"),
        })
        code, out = self.run_main()
        self.assertEqual(code, 0, out)
        db = sqlite3.connect(str(self.root / "consolidado.sqlite"))
        try:
            self.assertEqual(db.execute("SELECT count(*) FROM sessions WHERE session_id = ?", (self.WITHDRAWN,)).fetchone()[0], 0)
            self.assertEqual(db.execute("SELECT count(*) FROM session_events WHERE session_id = ?", (self.WITHDRAWN,)).fetchone()[0], 0)
        finally:
            db.close()

    def test_retirada_apaga_o_que_ja_estava_no_sqlite(self):
        imp.upsert_session_sqlite(self.conn, self.snapshot(self.WITHDRAWN), "a.json", "agora")
        imp.upsert_session_sqlite(self.conn, self.snapshot(self.KEPT), "b.json", "agora")
        with self.conn:
            self.conn.execute("INSERT INTO events (event_id, session_id) VALUES ('x1', ?)", (self.WITHDRAWN.upper(),))
        removed = imp.purge_withdrawn_sqlite(self.conn, {self.WITHDRAWN})
        self.assertEqual(removed, 2)
        self.assertEqual(self.conn.execute("SELECT session_id FROM sessions").fetchall(), [(self.KEPT,)])

    def test_sqlite_nao_regride_sessao_encerrada(self):
        sid = self.KEPT
        self.assertEqual(imp.upsert_session_sqlite(self.conn, self.snapshot(sid, ended_by="instrutor"), "a.json", "t1"), "inserted")
        self.assertEqual(
            imp.upsert_session_sqlite(self.conn, self.snapshot(sid, status="in_progress", ended_by=None), "b.json", "t2"),
            "kept_completed",
        )
        self.assertEqual(
            self.conn.execute("SELECT status, ended_by, source_file FROM sessions WHERE session_id = ?", (sid,)).fetchone(),
            ("completed", "instrutor", "a.json"),
        )
        self.assertEqual(
            imp.upsert_session_sqlite(self.conn, self.snapshot(sid, phase="completed", status=None), "c.json", "t3"),
            "updated",
        )

    def test_sqlite_completa_sessao_em_andamento_e_grava_qualidade(self):
        sid = self.KEPT
        imp.upsert_session_sqlite(self.conn, self.snapshot(sid, status="in_progress"), "a.json", "t1")
        quality = {"heartbeat_count": 12, "max_heartbeat_gap_min": 3.5, "bridge_restarts": 1, "corrupted_lines": 0,
                   "spike_status": "ok", "telemetry_events": 40, "last_activity_at": None}
        outcome = imp.upsert_session_sqlite(
            self.conn, self.snapshot(sid, ended_by="tempo", interrupted=True, data_quality=quality), "b.json", "t2"
        )
        self.assertEqual(outcome, "updated")
        status, ended_by, interrupted, dq = self.conn.execute(
            "SELECT status, ended_by, interrupted, data_quality_json FROM sessions WHERE session_id = ?", (sid,)
        ).fetchone()
        self.assertEqual((status, ended_by, interrupted), ("completed", "tempo", 1))
        self.assertEqual(json.loads(dq), quality)

    def test_sqlite_existente_recebe_colunas_novas(self):
        legacy = sqlite3.connect(str(self.root / "legado.sqlite"))
        legacy.execute("CREATE TABLE sessions (session_id TEXT PRIMARY KEY, status TEXT)")
        legacy.commit()
        legacy.close()
        conn = imp.init_sqlite_database(self.root / "legado.sqlite")
        try:
            cols = {row[1]: row[2] for row in conn.execute("PRAGMA table_info(sessions)")}
            self.assertEqual(cols["ended_by"], "TEXT")
            self.assertEqual(cols["interrupted"], "INTEGER")
            self.assertEqual(cols["data_quality_json"], "TEXT")
        finally:
            conn.close()

    def test_registro_da_nuvem_mapeia_qualidade(self):
        quality = {"heartbeat_count": 3, "spike_status": "pasta_nao_encontrada"}
        rec = imp.build_bancada_record(
            self.snapshot(self.KEPT, ended_by="sem_encerramento", interrupted=False, data_quality=quality), "agora"
        )
        self.assertEqual(rec["ended_by"], "sem_encerramento")
        self.assertIs(rec["interrupted"], False)
        self.assertEqual(rec["data_quality"], quality)
        self.assertEqual(rec["phase"], "completed")

        legacy = imp.build_bancada_record(self.snapshot(self.KEPT, status="in_progress", ended_by="aluno", data_quality=[1]), "agora")
        self.assertEqual(legacy["phase"], "in_progress")
        self.assertIsNone(legacy["ended_by"])
        self.assertIsNone(legacy["interrupted"])
        self.assertIsNone(legacy["data_quality"])
        # PostgREST exige as mesmas chaves em todos os registros do lote
        self.assertEqual(set(rec), set(legacy))

    def test_dedup_mantem_snapshot_encerrado(self):
        done = imp.build_bancada_record(self.snapshot(self.KEPT), "t")
        open_ = imp.build_bancada_record(self.snapshot(self.KEPT, status="in_progress"), "t")
        self.assertEqual(imp.dedup_bancada_records([done, open_])[0]["phase"], "completed")
        self.assertEqual(imp.dedup_bancada_records([open_, done])[0]["phase"], "completed")

    @staticmethod
    def fake_key(role):
        payload = base64.urlsafe_b64encode(json.dumps({"role": role}).encode()).decode().rstrip("=")
        return f"eyJhbGciOiJIUzI1NiJ9.{payload}.assinatura"

    @patch("urllib.request.urlopen")
    def test_retirada_remota_grava_tombstone_antes_de_apagar(self, mock_urlopen):
        resp = MagicMock()
        resp.__enter__.return_value.read.return_value = b""
        mock_urlopen.return_value = resp
        sent, err = imp.withdraw_sessions_remote({self.WITHDRAWN}, "https://exemplo.supabase.co", self.fake_key("service_role"))
        self.assertEqual((sent, err), (1, None))
        calls = [c.args[0] for c in mock_urlopen.call_args_list]
        self.assertEqual(calls[0].get_method(), "POST")
        self.assertIn("/research_withdrawals?on_conflict=session_id", calls[0].full_url)
        self.assertIn("ignore-duplicates", calls[0].headers["Prefer"])
        self.assertEqual(json.loads(calls[0].data), [{"session_id": self.WITHDRAWN, "source": "importer"}])
        deleted = [c.full_url.split("/rest/v1/")[1] for c in calls[1:]]
        self.assertTrue(all(c.get_method() == "DELETE" for c in calls[1:]))
        self.assertEqual(
            [d.split("?")[0] for d in deleted],
            ["instructor_evaluations", "research_events", "research_session_events", "research_bancada_sessions"],
        )
        self.assertTrue(all(d.endswith(f"session_id=in.({self.WITHDRAWN})") for d in deleted))

    @patch("urllib.request.urlopen")
    def test_retirada_remota_exige_service_role(self, mock_urlopen):
        sent, err = imp.withdraw_sessions_remote({self.WITHDRAWN}, "https://exemplo.supabase.co", self.fake_key("authenticated"))
        self.assertEqual(sent, 0)
        self.assertIn("service_role", err)
        mock_urlopen.assert_not_called()
