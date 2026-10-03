#!/usr/bin/env python3
"""
Testes unitários automatizados para o importador e consolidador (scripts/importar-para-supabase.py).
Valida:
1. Validação estrita do manifesto SHA-256 (arquivos válidos, ausentes, adulterados, manifesto ausente, vazio e arquivos extras).
2. Preservação estrita de occurred_at original (sem substituição silenciosa).
3. Preservação de tipos desconhecidos em quarentena (sem conversão para phase_completed).
4. Idempotência estrita em HTTP 409 (código 23505 comprovado na PK esperada é duplicado, conflitos em outras constraints são rejeitados).
5. Estratégia divide-and-conquer em lotes no envio ao Supabase.
6. Rejeição de credencial pública anônima (anon) para sincronização remota.
"""

from __future__ import annotations

import hashlib
import hmac
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import MagicMock, patch
import urllib.error

import importlib.util

spec = importlib.util.spec_from_file_location(
    "importar_para_supabase",
    Path(__file__).resolve().parent / "importar-para-supabase.py",
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
    """Testes estáticos de segurança para bridge/pulselab-bridge.ps1 sem necessidade de Windows."""

    @classmethod
    def setUpClass(cls):
        bridge_path = Path(__file__).resolve().parent.parent / "bridge" / "pulselab-bridge.ps1"
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
        """Bridge deve possuir rotina Invoke-BridgeRetentionCleanup com expurgo seguro de 7 dias."""
        self.assertIn("function Invoke-BridgeRetentionCleanup", self.bridge_code)
        self.assertIn("$cutoffUtc = [DateTime]::UtcNow.AddDays(-$MaxAgeDays)", self.bridge_code)
        self.assertIn("Invoke-BridgeRetentionCleanup -MaxAgeDays 7", self.bridge_code)

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
    Path(__file__).resolve().parent.parent / "installer" / "build-installer.py",
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
        repo_root = Path(__file__).resolve().parent.parent
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
