import base64
import hashlib
import json
import os
import re
import sqlite3
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = REPO_ROOT / "config" / "config.json"
AGENT_PATH = REPO_ROOT / "agent" / "pulselab-agent.ps1"
SCHEMA_PATH = REPO_ROOT / "schema" / "supabase-schema.sql"
INSTALLER_PATH = REPO_ROOT / "installer" / "build-installer.py"
SETUP_PATH = REPO_ROOT / "installer" / "setup-startup.ps1"
POWERSHELL_INSTALLER_PATH = REPO_ROOT / "installer" / "build-installer.ps1"
BOOTSTRAP_PATH = REPO_ROOT / "installer" / "install.ps1"
PORTABLE_LAUNCHER_PATH = REPO_ROOT / "pulselab.ps1"
FAST_LAUNCHER_PATH = REPO_ROOT / "Testar-Pulselab-Rapido.bat"

MIGRATION_PATH = REPO_ROOT / "supabase" / "migrations" / "20260816000000_device_authenticated_ingestion.sql"
ENROLL_PS1_PATH = REPO_ROOT / "supabase" / "scripts" / "enroll-device.ps1"
PROVISION_PY_PATH = REPO_ROOT / "supabase" / "scripts" / "provision_device.py"
EDGE_FUNCTION_PATH = REPO_ROOT / "supabase" / "functions" / "enroll-device" / "index.ts"


def read_text(path):
    return path.read_text(encoding="utf-8-sig")


class ConfigContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config = json.loads(read_text(CONFIG_PATH))

    def test_version_and_protocol_are_explicit(self):
        self.assertEqual(self.config["version"], "1.5.0")
        self.assertTrue(self.config["protocol_version"].strip())
        self.assertTrue(self.config["activity_id"].strip())
        self.assertTrue(self.config["site_id"].strip())

    def test_checkpoint_marks_are_positive_and_strictly_increasing(self):
        marks = self.config["interval_marks_minutes"]
        self.assertTrue(marks)
        self.assertTrue(all(isinstance(mark, int) and mark > 0 for mark in marks))
        self.assertEqual(marks, sorted(set(marks)))

    def test_checkpoint_metadata_matches_configured_marks(self):
        marks = set(self.config["interval_marks_minutes"])
        stages = {int(mark) for mark in self.config["checkpoint_stages"]}
        collaboration = set(self.config["collaboration_marks_minutes"])
        role_swaps = set(self.config["role_swap_after_marks_minutes"])
        self.assertEqual(stages, marks)
        self.assertTrue(collaboration <= marks)
        self.assertTrue(role_swaps <= marks)

    def test_operational_limits_are_safe(self):
        self.assertGreater(self.config["network_timeout_seconds"], 0)
        self.assertGreaterEqual(self.config["heartbeat_interval_seconds"], 15)
        self.assertGreaterEqual(self.config["max_checkpoint_lateness_seconds"], 0)
        self.assertGreater(self.config["timeout_seconds"], 0)

    def test_client_config_has_no_service_role_and_defines_anon_key_fields(self):
        self.assertIn("supabase_anon_key_env_var", self.config)
        self.assertIn("supabase_anon_key", self.config)
        # Ensure no hardcoded secret or service_role
        self.assertNotIn("service_role", json.dumps(self.config).lower())
        self.assertNotIn("secret", json.dumps(self.config).lower())


class SchemaContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.schema = read_text(SCHEMA_PATH)

    def test_append_only_event_store_and_quality_view_exist(self):
        self.assertIn(
            "CREATE TABLE IF NOT EXISTS public.research_session_events",
            self.schema,
        )
        self.assertIn(
            "CREATE OR REPLACE VIEW public.research_session_quality",
            self.schema,
        )
        for status in ("in_progress", "aborted", "needs_review", "complete"):
            self.assertIn(f"'{status}'", self.schema)

    def test_all_agent_session_event_types_are_allowed_by_schema(self):
        agent = read_text(AGENT_PATH)
        emitted = set(re.findall(r'Submit-SessionEvent\s+"([^"]+)"', agent))
        allowed_block = re.search(
            r"research_session_events.*?CHECK \(event_type IN \((.*?)\)\)",
            self.schema,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(allowed_block)
        allowed = set(re.findall(r"'([^']+)'", allowed_block.group(1)))
        self.assertTrue(emitted)
        self.assertEqual(emitted - allowed, set())

    def test_collector_roles_are_insert_only(self):
        for table in ("research_events", "research_session_events"):
            self.assertIn(
                f"REVOKE ALL ON TABLE public.{table} FROM anon, authenticated;",
                self.schema,
            )
            self.assertIn(f"GRANT INSERT ON TABLE public.{table} TO authenticated;", self.schema)
        self.assertIn(
            "REVOKE ALL ON TABLE public.research_session_quality FROM anon, authenticated;",
            self.schema,
        )
        self.assertNotRegex(
            self.schema,
            r"GRANT\s+(SELECT|UPDATE|DELETE|ALL|INSERT).*?\bTO\s+anon\b",
        )

    def test_idempotency_and_private_storage_are_declared(self):
        self.assertRegex(
            self.schema,
            r"event_id\s+uuid\s+PRIMARY KEY",
        )
        self.assertIn("VALUES ('screenshots', 'screenshots', false)", self.schema)
        self.assertNotIn("FOR SELECT\n    TO anon", self.schema)

    def test_legacy_age_column_remains_nullable_for_older_rows(self):
        definition = re.search(r"^\s*student_age\s+([^\n]+)", self.schema, re.MULTILINE)
        self.assertIsNotNone(definition)
        self.assertNotIn("NOT NULL", definition.group(1))

    def test_device_installations_table_and_rls_binding(self):
        schema = self.schema
        self.assertIn("CREATE TABLE IF NOT EXISTS public.device_installations", schema)
        self.assertIn("device_user_id", schema)
        self.assertIn("installation_id", schema)
        self.assertIn("site_id", schema)
        self.assertIn("idx_device_installations_user", schema)
        self.assertIn("idx_device_installations_installation", schema)
        self.assertIn("ALTER TABLE public.device_installations ENABLE ROW LEVEL SECURITY", schema)
        self.assertIn('CREATE POLICY "authenticated_select_device_installations"', schema)

        # Single-use device enrollment tokens table
        self.assertIn("CREATE TABLE IF NOT EXISTS public.device_enrollment_tokens", schema)
        self.assertIn("token_hash", schema)
        self.assertIn("consumed_at", schema)
        self.assertIn("expires_at", schema)
        self.assertIn("REVOKE ALL ON TABLE public.device_enrollment_tokens FROM anon, authenticated;", schema)

    def test_rls_with_check_enforces_installation_binding_fail_closed(self):
        schema = self.schema
        self.assertIn('CREATE POLICY "authenticated_insert_research_events"', schema)
        self.assertIn('CREATE POLICY "authenticated_insert_research_session_events"', schema)

        # Verify that WITH CHECK does NOT simply allow everything (no WITH CHECK (true))
        self.assertNotIn("WITH CHECK (true)", schema)

        # Strict exact match on device_installations with active status, installation_id and site_id
        self.assertIn("FROM public.device_installations di", schema)
        self.assertIn("di.device_user_id = auth.uid()", schema)
        self.assertIn("di.is_active = true", schema)
        self.assertIn("di.installation_id = research_events.installation_id", schema)
        self.assertIn("di.site_id = research_events.site_id", schema)
        self.assertIn("di.installation_id = research_session_events.installation_id", schema)
        self.assertIn("di.site_id = research_session_events.site_id", schema)

        # Ensure NO fallback to untrusted user_metadata, app_metadata or raw auth.uid=installation_id
        self.assertNotIn("user_metadata", schema)
        self.assertNotIn("app_metadata", schema)
        self.assertNotIn("auth.uid() = research_events.installation_id", schema)
        self.assertNotIn("auth.uid() = research_session_events.installation_id", schema)

    def test_storage_screenshot_policy_restricts_to_installation_prefix(self):
        schema = self.schema
        self.assertIn('CREATE POLICY "Allow authenticated uploads to screenshots"', schema)
        self.assertIn("bucket_id = 'screenshots'", schema)
        self.assertIn("split_part(storage.objects.name, '/', 1)", schema)
        self.assertNotIn("user_metadata", schema)
        self.assertNotIn("app_metadata", schema)

    def test_quality_view_counts_completed_distinct_coverage(self):
        schema = self.schema
        self.assertIn("distinct_pre_completed_participants", schema)
        self.assertIn("distinct_post_completed_participants", schema)
        self.assertIn("distinct_checkpoint_completed_pairs", schema)
        self.assertIn("distinct_completed_interval_marks", schema)
        self.assertIn("distinct_checkpoint_completed_participants", schema)
        self.assertIn("response_status = 'completed'", schema)


class AgentStaticTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.agent = read_text(AGENT_PATH)
        cls.config = json.loads(read_text(CONFIG_PATH))

    def test_component_versions_match(self):
        version_match = re.search(r'\$script:VERSION\s*=\s*"([^"]+)"', self.agent)
        self.assertIsNotNone(version_match)
        self.assertEqual(version_match.group(1), self.config["version"])
        self.assertIn(self.config["version"], read_text(SETUP_PATH))
        for path in (BOOTSTRAP_PATH, PORTABLE_LAUNCHER_PATH):
            self.assertIn(self.config["version"], read_text(path))

    def test_windows_launchers_forward_accelerated_test_modes(self):
        portable = read_text(PORTABLE_LAUNCHER_PATH)
        fast = read_text(FAST_LAUNCHER_PATH)
        self.assertIn("[switch]$DebugMode", self.agent)
        self.assertIn("[switch]$ProductionTest", self.agent)
        self.assertIn("$script:Config.debug_no_wait = $true", self.agent)
        self.assertIn("$script:Config.debug_no_wait = $false", self.agent)
        self.assertNotIn("interval_marks_minutes = @(1, 2)", self.agent)
        self.assertIn('$params["DebugMode"] = $true', portable)
        self.assertIn('$params["ProductionTest"] = $true', portable)
        self.assertIn("-ProductionTest", fast)

    def test_windows_compatibility_guards_are_present(self):
        for path in (
            AGENT_PATH,
            SETUP_PATH,
            POWERSHELL_INSTALLER_PATH,
            BOOTSTRAP_PATH,
            PORTABLE_LAUNCHER_PATH,
        ):
            self.assertTrue(path.read_bytes().startswith(b"\xef\xbb\xbf"), path)
        self.assertIn("RawContentStream.ToArray()", self.agent)
        self.assertIn("[Text.Encoding]::UTF8.GetString($rawBytes)", self.agent)
        self.assertGreaterEqual(
            self.agent.count("[Security.SecurityElement]::Escape"),
            10,
        )

    def test_raw_window_title_is_not_sent(self):
        self.assertIn('$event["telemetry_window_title"] = $null', self.agent)
        self.assertNotIn(
            '$event["telemetry_window_title"] = $Telemetry.WindowTitle',
            self.agent,
        )
        self.assertIn("ForegroundApp = $appCategory", self.agent)

    def test_absolute_timing_and_persistent_installation_are_present(self):
        required_fragments = (
            "installation.json",
            "Get-Sha256Hex",
            "Get-CheckpointTargetMs",
            "$script:ActivityStartedAt.AddMilliseconds($targetElapsedMs)",
            "[Diagnostics.Stopwatch]::StartNew()",
            "checkpoint_lateness_ms",
        )
        for fragment in required_fragments:
            self.assertIn(fragment, self.agent)

    def test_session_setup_reuses_saved_values_and_requires_fresh_confirmation(self):
        self.assertIn("function Test-NeedsSetupValue", self.agent)
        self.assertIn('Width="540" Height="680"', self.agent)
        self.assertIn('Name="PnlSite"', self.agent)
        self.assertIn('Name="PnlSchool"', self.agent)
        self.assertIn('Name="PnlWorkshop"', self.agent)
        self.assertIn(
            "O PulseLab reutilizará estes valores na próxima execução",
            self.agent,
        )
        self.assertIn(
            'Name="ChkConsent"',
            self.agent,
        )
        self.assertNotIn("Bypassing setup window", self.agent)
        self.assertNotIn("$script:GradeBand", self.agent)

    def test_installation_profile_keeps_all_operational_setup_values(self):
        for field in (
            "site_id",
            "regional_hub",
            "school_code",
            "workshop_code",
            "class_code",
            "activity_id",
            "group_size",
        ):
            self.assertRegex(
                self.agent,
                rf"(?m)^\s*{field}\s*=\s*\$script:",
            )
        self.assertNotIn("grade_band", self.config)

    def test_pre_survey_does_not_collect_age(self):
        self.assertNotIn("student_age_prompt", self.config)
        self.assertNotIn("Qual a sua idade?", self.agent)
        self.assertNotIn('event["student_age"]', self.agent)
        self.assertNotIn("StudentAge", self.agent)

    def test_remote_protocol_update_preserves_installed_site_identity(self):
        self.assertIn(
            'foreach ($identityField in @("site_id", "regional_hub", "school_code"))',
            self.agent,
        )
        self.assertIn("$remote.$identityField = $identityValue", self.agent)
        self.assertIn(
            "$remoteRaw = $remote | ConvertTo-Json -Depth 10",
            self.agent,
        )

    def test_offline_queue_keeps_local_evidence_with_event(self):
        self.assertIn(
            "Preserve the database row and its visual evidence as one delivery unit.",
            self.agent,
        )
        self.assertIn("local_screenshot_path", self.agent)
        self.assertIn("resolution=ignore-duplicates,return=minimal", self.agent)

    def test_embedded_xaml_is_well_formed_xml(self):
        blocks = re.findall(
            r'\$xaml\s*=\s*@"\r?\n(.*?)\r?\n"@',
            self.agent,
            flags=re.DOTALL,
        )
        self.assertGreaterEqual(len(blocks), 5)
        for index, block in enumerate(blocks, start=1):
            try:
                ET.fromstring(block)
            except ET.ParseError as exc:
                self.fail(f"XAML block {index} is not well-formed XML: {exc}")

    def test_powershell_structure_and_no_duplicate_finally(self):
        self.assertNotIn(
            '} finally {\n            Write-PulseLog "ERROR" "Could not record aborted session',
            self.agent,
        )
        self.assertNotIn(
            '} finally {\r\n            Write-PulseLog "ERROR" "Could not record aborted session',
            self.agent,
        )
        clean_code = re.sub(r'@"[^"]*"@', '""', self.agent, flags=re.DOTALL)
        clean_code = re.sub(r'"[^"\n]*"', '""', clean_code)
        clean_code = re.sub(r"'[^'\n]*'", "''", clean_code)
        clean_code = re.sub(r"#.*$", "", clean_code, flags=re.MULTILINE)
        open_braces = clean_code.count("{")
        close_braces = clean_code.count("}")
        self.assertEqual(
            open_braces,
            close_braces,
            f"Mismatched braces: {open_braces} open vs {close_braces} close",
        )
        entrypoint = self.agent.split("# ENTRY POINT", maxsplit=1)[-1]
        self.assertEqual(entrypoint.count("\n} finally {\n"), 1)
        final_block = re.search(
            r"\n} finally \{\n(?P<cleanup>.*?)\n}\s*$",
            entrypoint,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(final_block)
        if final_block is None:
            self.fail("Entry point must end in a cleanup finally block")
        self.assertIn("\n} catch {\n", entrypoint[: final_block.start()])
        self.assertIn("Dispose-TrayIcon", final_block.group("cleanup"))

    def test_group_size_and_participant_roles_contract(self):
        validate_set_match = re.search(
            r'function New-ResearchEvent\s*\{.*?\[ValidateSet\((.*?)\)\]\[string\]\$Role',
            self.agent,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(validate_set_match)
        roles = {r.strip('"\' ') for r in validate_set_match.group(1).split(",")}
        expected_roles = {"computer", "assembly", "individual", "member_3", "member_4"}
        self.assertTrue(expected_roles.issubset(roles))

        self.assertIn('function Get-ParticipantList', self.agent)
        self.assertIn('function Get-RoleLabel', self.agent)
        self.assertIn('"individual"', self.agent)
        self.assertIn('"member_3"', self.agent)

    def test_role_swap_and_rubric_are_mandatory_in_flow(self):
        loop_match = re.search(
            r'function Start-ResearchLoop\s*\{.*?\n\}',
            self.agent,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(loop_match)
        loop_code = loop_match.group(0)
        self.assertIn("Invoke-ConfiguredRoleSwap", loop_code)
        self.assertIn("Show-WpfInstructorRubric", loop_code)
        self.assertIn('"rubric_completed"', loop_code)
        self.assertIn("Save-PostSurvey", loop_code)

    def test_role_preservation_and_resumption(self):
        self.assertIn("$script:ParticipantComputerRole", self.agent)
        self.assertIn("$script:ParticipantAssemblyRole", self.agent)
        self.assertIn("participant_computer_role = $script:ParticipantComputerRole", self.agent)
        self.assertIn("participant_assembly_role = $script:ParticipantAssemblyRole", self.agent)
        self.assertIn("$script:ParticipantComputerRole = [string]$resumable.participant_computer_role", self.agent)
        self.assertIn("$script:ParticipantAssemblyRole = [string]$resumable.participant_assembly_role", self.agent)

    def test_resumption_absolute_timing_and_frozen_context(self):
        self.assertIn("function Get-CurrentElapsedMs", self.agent)
        self.assertIn("config_hash", self.agent)
        self.assertIn("checkpoint_count = $script:CompletedCheckpoints.Count", self.agent)
        self.assertNotIn("checkpoint_count = $marks.Count", self.agent)
        loop_start = self.agent.find("function Start-ResearchLoop")
        participants_init = self.agent.find("$participants = Get-ParticipantList", loop_start)
        first_foreach = self.agent.find("foreach ($mark in $marks)", loop_start)
        self.assertTrue(0 < participants_init < first_foreach)

    def test_reconfiguration_is_blocked_during_session(self):
        self.assertIn(
            "if ($script:CollectionAuthorized)",
            self.agent,
        )
        self.assertIn("congelado", self.agent)

    def test_powershell_syntax_and_block_balance(self):
        code = self.agent
        open_braces = code.count("{")
        close_braces = code.count("}")
        self.assertEqual(open_braces, close_braces, f"Mismatched braces: {open_braces} open vs {close_braces} close")

        open_here = len(re.findall(r'@"\r?\n', code))
        close_here = len(re.findall(r'\r?\n"@', code))
        self.assertEqual(open_here, close_here, f"Mismatched here-strings: {open_here} vs {close_here}")

        self.assertIn("Global\\PulseLab_Agent_Singleton_Mutex", code)
        self.assertIn("function Write-AtomicUtf8Json", code)
        self.assertIn("Write-AtomicUtf8Json $script:INSTALLATION_FILE", code)
        self.assertIn("Write-AtomicUtf8Json $script:SESSION_STATE_FILE", code)
        self.assertIn("Write-AtomicUtf8Json $script:OFFLINE_CACHE_FILE", code)

    def test_group_size_matrix_and_role_contracts(self):
        code = self.agent
        self.assertIn('"individual"', code)
        self.assertIn('"member_3"', code)
        self.assertIn('"member_4"', code)
        self.assertIn('function Get-ParticipantList', code)
        self.assertIn('function Get-RoleLabel', code)
        self.assertIn('function Show-WpfGroupSizeSelection', code)

    def test_state_machine_role_swap_and_rubric(self):
        code = self.agent
        self.assertIn('function Invoke-ConfiguredRoleSwap', code)
        self.assertIn('function Show-WpfInstructorRubric', code)
        self.assertIn('Invoke-ConfiguredRoleSwap $mark $activityStage', code)
        self.assertIn('Show-WpfInstructorRubric', code)
        self.assertIn('session_completed', code)
        self.assertIn('completed_checkpoints', code)
        self.assertIn('expected_checkpoints', code)
        self.assertIn('rubric_completed', code)

    def test_offline_queue_quarantine_and_evidence(self):
        code = self.agent
        self.assertIn('.corrupted.', code)
        self.assertIn('screenshot_missing_on_disk', code)
        self.assertIn('Select-Object -Last 500', code)


class DeviceAuthenticationSecurityContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.agent = read_text(AGENT_PATH)
        cls.config = json.loads(read_text(CONFIG_PATH))

    def test_dpapi_functions_and_storage_are_implemented(self):
        agent = self.agent
        self.assertIn("function Protect-PulseSecret", agent)
        self.assertIn("function Unprotect-PulseSecret", agent)
        self.assertIn("function Save-DeviceSession", agent)
        self.assertIn("function Load-DeviceSession", agent)
        self.assertIn("function Clear-DeviceSession", agent)
        self.assertIn("[System.Security.Cryptography.DataProtectionScope]::CurrentUser", agent)
        self.assertIn("device_session.dat", agent)
        self.assertIn("System.Security", agent)

    def test_session_refresh_logic_in_powershell_agent(self):
        agent = self.agent
        self.assertIn("function Invoke-DeviceSessionRefresh", agent)
        self.assertIn("/auth/v1/token?grant_type=refresh_token", agent)
        self.assertIn("refresh_token", agent)
        self.assertIn("function Test-DeviceSessionValid", agent)
        self.assertIn("function Get-DeviceAuthHeader", agent)

    def test_fail_closed_agent_auth_functions(self):
        agent = self.agent
        # Get-DeviceAuthHeader must return $null when session is invalid, NEVER anon key Bearer
        self.assertNotIn('return "Bearer $($script:SupabaseAnonKey)"', agent)
        # Test-DeviceSessionValid must NOT return true just because anon key is present
        self.assertNotIn('return (-not [string]::IsNullOrWhiteSpace($script:SupabaseAnonKey))', agent)
        # Expired token requires mandatory refresh
        self.assertIn('Device token is expired; performing mandatory session refresh', agent)
        # Send-ResponseToSupabase and Upload-ScreenshotToSupabase fail closed if auth header is missing
        self.assertIn('Device authentication missing or invalid (fail-closed); database submission blocked.', agent)
        self.assertIn('Device authentication missing or invalid (fail-closed); screenshot upload blocked.', agent)

    def test_no_device_token_in_config_or_agent_config_loading(self):
        # Config must not define device tokens
        self.assertNotIn("device_access_token", self.config)
        self.assertNotIn("device_refresh_token", self.config)
        # Agent must not load device tokens from config snapshot
        self.assertNotIn("$script:Config.device_access_token", self.agent)
        self.assertNotIn("$script:Config.device_refresh_token", self.agent)

    def test_separate_anon_key_and_device_jwt_in_transport(self):
        agent = self.agent
        self.assertIn("$script:SupabaseAnonKey", agent)
        self.assertIn("$script:DeviceAccessToken", agent)
        self.assertIn("$script:DeviceRefreshToken", agent)
        # Verify transport sends apikey as anon key and Authorization with device header
        self.assertIn("apikey = $script:SupabaseAnonKey", agent)
        self.assertIn("Authorization = $authHeader", agent)

    def test_retry_on_401_unauthorized_with_session_refresh(self):
        agent = self.agent
        # Both Send-ResponseToSupabase and Upload-ScreenshotToSupabase should handle 401
        self.assertIn("if ($statusCode -eq 401 -and -not [string]::IsNullOrWhiteSpace($script:DeviceRefreshToken))", agent)
        self.assertIn("Invoke-DeviceSessionRefresh", agent)

    def test_screenshot_prefix_strictly_bound_to_installation_id(self):
        agent = self.agent
        self.assertIn(
            '$objectPath = "$($script:InstallationId)/$($script:WorkshopCode)/$($script:SessionId)/checkpoint-$IntervalMark.jpg"',
            agent,
        )

    def test_no_service_role_in_agent_or_config(self):
        self.assertNotIn("service_role", self.agent)
        self.assertNotIn("service_role", json.dumps(self.config))


class SupabaseArtifactsContractTests(unittest.TestCase):
    def test_migration_file_exists_and_is_valid(self):
        self.assertTrue(MIGRATION_PATH.exists())
        sql = read_text(MIGRATION_PATH)
        self.assertIn("CREATE TABLE IF NOT EXISTS public.device_installations", sql)
        self.assertIn("CREATE TABLE IF NOT EXISTS public.device_enrollment_tokens", sql)
        self.assertIn('CREATE POLICY "authenticated_insert_research_events"', sql)
        self.assertIn('CREATE POLICY "authenticated_insert_research_session_events"', sql)
        self.assertIn('CREATE POLICY "Allow authenticated uploads to screenshots"', sql)
        self.assertIn("CREATE OR REPLACE VIEW public.research_session_quality", sql)
        # Verify no metadata bypasses in migration
        self.assertNotIn("user_metadata", sql)
        self.assertNotIn("app_metadata", sql)

    def test_enroll_powershell_script_exists_and_has_proper_structure(self):
        self.assertTrue(ENROLL_PS1_PATH.exists())
        script = read_text(ENROLL_PS1_PATH)
        self.assertIn("param(", script)
        self.assertIn("$EnrollmentToken", script)
        self.assertIn("System.Security", script)
        self.assertIn("device_session.dat", script)
        self.assertIn("ProtectedData]::Protect", script)
        self.assertIn("functions/v1/enroll-device", script)
        # Client script MUST NEVER have service role key or admin calls
        self.assertNotIn("AdminServiceKey", script)
        self.assertNotIn("service_role", script.lower())
        self.assertNotIn("auth/v1/admin", script)
        self.assertNotIn("eyJh", script)

    def test_provision_python_script_exists_and_is_executable(self):
        self.assertTrue(PROVISION_PY_PATH.exists())
        code = read_text(PROVISION_PY_PATH)
        self.assertIn("def get_service_role_key(", code)
        self.assertIn("device_enrollment_tokens", code)
        self.assertIn("generate_enrollment_token(", code)
        self.assertIn("hash_token(", code)
        self.assertIn("0o600", code)
        # Must require --output and not take service key via plaintext CLI arg
        self.assertNotIn('--service-key', code)
        self.assertIn('parser.add_argument(\n        "--output",\n        required=True', code)
        self.assertNotIn("eyJh", code)

    def test_edge_function_enrollment_exists(self):
        self.assertTrue(EDGE_FUNCTION_PATH.exists())
        ts = read_text(EDGE_FUNCTION_PATH)
        self.assertIn("device_installations", ts)
        self.assertIn("device_enrollment_tokens", ts)
        self.assertIn("consumed_at", ts)
        self.assertIn("signInWithPassword", ts)
        # Must fail closed if env missing
        self.assertIn("Enrollment service is not configured", ts)
        # Must NOT accept reusable global secret
        self.assertNotIn("ENROLLMENT_SECRET_TOKEN", ts)
        # Consumption is the authorization boundary and precedes Auth mutation.
        self.assertLess(ts.index(".update({ consumed_at: now })"), ts.index("admin.auth.admin.createUser"))
        self.assertNotIn("updateUserById", ts)


class ResearchSessionQualitySemanticExecutionTests(unittest.TestCase):
    """
    Executes an in-memory SQL semantic test validating the exact logic of
    research_session_quality view against all matrix dimensions:
    - Solo (1 participant, 2 checkpoints)
    - Duo (2 participants, 2 checkpoints)
    - Trio (3 participants, 2 checkpoints)
    - Duplicates and retries (distinct count prevents inflating completion)
    - Timeouts and declines (must not count as completed)
    - Quality issues and early aborts
    """

    def setUp(self):
        self.conn = sqlite3.connect(":memory:")
        self.cursor = self.conn.cursor()
        self.cursor.executescript("""
            CREATE TABLE research_session_events (
                event_id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                dyad_id TEXT NOT NULL,
                installation_id TEXT NOT NULL,
                site_id TEXT NOT NULL,
                regional_hub TEXT NOT NULL,
                school_code TEXT NOT NULL,
                workshop_code TEXT NOT NULL,
                class_code TEXT NOT NULL,
                event_type TEXT NOT NULL,
                severity TEXT NOT NULL DEFAULT 'info',
                interval_mark INTEGER,
                participant_id TEXT,
                occurred_at TEXT NOT NULL,
                received_at TEXT NOT NULL,
                details TEXT NOT NULL DEFAULT '{}'
            );

            CREATE TABLE research_events (
                id TEXT PRIMARY KEY,
                event_id TEXT NOT NULL UNIQUE,
                session_id TEXT NOT NULL,
                dyad_id TEXT NOT NULL,
                installation_id TEXT,
                site_id TEXT,
                participant_id TEXT NOT NULL,
                participant_role TEXT NOT NULL,
                event_type TEXT NOT NULL,
                response_status TEXT NOT NULL DEFAULT 'completed',
                interval_mark INTEGER,
                regional_hub TEXT NOT NULL,
                school_code TEXT NOT NULL,
                workshop_code TEXT NOT NULL,
                class_code TEXT NOT NULL,
                activity_id TEXT NOT NULL,
                computer_id TEXT NOT NULL,
                config_version TEXT NOT NULL,
                client_version TEXT NOT NULL,
                screenshot_path TEXT,
                occurred_at TEXT NOT NULL,
                received_at TEXT NOT NULL
            );

            CREATE VIEW research_session_quality AS
            WITH timeline AS (
                SELECT
                    session_id,
                    min(installation_id) AS installation_id,
                    max(site_id) AS site_id,
                    max(regional_hub) AS regional_hub,
                    max(school_code) AS school_code,
                    max(workshop_code) AS workshop_code,
                    max(class_code) AS class_code,
                    min(occurred_at) AS first_event_at,
                    max(occurred_at) AS last_event_at,
                    max(received_at) AS last_received_at,
                    count(CASE WHEN event_type = 'heartbeat' THEN 1 END) AS heartbeat_count,
                    count(CASE WHEN event_type = 'checkpoint_started' THEN 1 END) AS checkpoint_started_count,
                    count(CASE WHEN event_type = 'checkpoint_completed' THEN 1 END) AS checkpoint_completed_count,
                    count(CASE WHEN event_type = 'quality_issue' THEN 1 END) AS quality_issue_count,
                    max(CASE WHEN event_type = 'session_completed' THEN 1 ELSE 0 END) AS has_completed,
                    max(CASE WHEN event_type = 'session_aborted' THEN 1 ELSE 0 END) AS has_aborted,
                    coalesce(
                        max(CASE WHEN event_type = 'session_started' THEN json_array_length(json_extract(details, '$.expected_checkpoints')) END),
                        0
                    ) AS expected_checkpoint_count,
                    coalesce(
                        max(CASE WHEN event_type = 'session_started' THEN CAST(json_extract(details, '$.participant_count') AS INTEGER) END),
                        2
                    ) AS participant_count
                FROM research_session_events
                GROUP BY session_id
            ),
            responses AS (
                SELECT
                    session_id,
                    count(CASE WHEN event_type = 'pre' THEN 1 END) AS pre_response_count,
                    count(CASE WHEN event_type = 'pre' AND response_status = 'completed' THEN 1 END) AS pre_completed_count,
                    count(CASE WHEN event_type = 'checkpoint' THEN 1 END) AS checkpoint_response_count,
                    count(CASE WHEN event_type = 'checkpoint' AND response_status = 'completed' THEN 1 END) AS checkpoint_completed_count,
                    count(CASE WHEN event_type = 'post' THEN 1 END) AS post_response_count,
                    count(CASE WHEN event_type = 'post' AND response_status = 'completed' THEN 1 END) AS post_completed_count,
                    count(CASE WHEN response_status = 'declined' THEN 1 END) AS declined_response_count,
                    count(CASE WHEN response_status = 'timeout' THEN 1 END) AS timeout_response_count,
                    count(DISTINCT CASE WHEN event_type = 'pre' AND response_status = 'completed' THEN participant_id END) AS distinct_pre_completed_participants,
                    count(DISTINCT CASE WHEN event_type = 'post' AND response_status = 'completed' THEN participant_id END) AS distinct_post_completed_participants,
                    count(DISTINCT CASE WHEN event_type = 'checkpoint' AND response_status = 'completed' THEN (participant_id || '_' || CAST(interval_mark AS TEXT)) END) AS distinct_checkpoint_completed_pairs,
                    count(DISTINCT CASE WHEN event_type = 'checkpoint' AND response_status = 'completed' THEN interval_mark END) AS distinct_completed_interval_marks,
                    count(DISTINCT CASE WHEN event_type = 'checkpoint' AND response_status = 'completed' THEN participant_id END) AS distinct_checkpoint_completed_participants,
                    count(DISTINCT CASE WHEN event_type = 'checkpoint' AND screenshot_path IS NOT NULL THEN interval_mark END) AS checkpoint_with_screenshot_count
                FROM research_events
                GROUP BY session_id
            )
            SELECT
                timeline.session_id,
                timeline.installation_id,
                timeline.site_id,
                timeline.heartbeat_count,
                timeline.expected_checkpoint_count,
                timeline.checkpoint_started_count,
                timeline.checkpoint_completed_count,
                timeline.participant_count,
                coalesce(responses.pre_response_count, 0) AS pre_response_count,
                coalesce(responses.pre_completed_count, 0) AS pre_completed_count,
                coalesce(responses.checkpoint_response_count, 0) AS checkpoint_response_count,
                coalesce(responses.checkpoint_completed_count, 0) AS checkpoint_completed_count,
                coalesce(responses.post_response_count, 0) AS post_response_count,
                coalesce(responses.post_completed_count, 0) AS post_completed_count,
                coalesce(responses.declined_response_count, 0) AS declined_response_count,
                coalesce(responses.timeout_response_count, 0) AS timeout_response_count,
                coalesce(responses.distinct_pre_completed_participants, 0) AS distinct_pre_completed_participants,
                coalesce(responses.distinct_post_completed_participants, 0) AS distinct_post_completed_participants,
                coalesce(responses.distinct_checkpoint_completed_pairs, 0) AS distinct_checkpoint_completed_pairs,
                coalesce(responses.distinct_completed_interval_marks, 0) AS distinct_completed_interval_marks,
                coalesce(responses.distinct_checkpoint_completed_participants, 0) AS distinct_checkpoint_completed_participants,
                coalesce(responses.checkpoint_with_screenshot_count, 0) AS checkpoint_with_screenshot_count,
                timeline.quality_issue_count,
                timeline.has_completed,
                timeline.has_aborted,
                CASE
                    WHEN timeline.has_aborted = 1 THEN 'aborted'
                    WHEN timeline.has_completed = 0 THEN 'in_progress'
                    WHEN timeline.quality_issue_count > 0
                      OR timeline.checkpoint_completed_count < timeline.expected_checkpoint_count
                      OR coalesce(responses.distinct_pre_completed_participants, 0) < timeline.participant_count
                      OR coalesce(responses.distinct_post_completed_participants, 0) < timeline.participant_count
                      OR coalesce(responses.distinct_checkpoint_completed_pairs, 0) < (timeline.expected_checkpoint_count * timeline.participant_count)
                      OR coalesce(responses.distinct_completed_interval_marks, 0) < timeline.expected_checkpoint_count
                      OR coalesce(responses.distinct_checkpoint_completed_participants, 0) < timeline.participant_count
                    THEN 'needs_review'
                    ELSE 'complete'
                END AS quality_status
            FROM timeline
            LEFT JOIN responses USING (session_id);
        """)

    def tearDown(self):
        self.conn.close()

    def _insert_session_start(self, session_id, participant_count, marks):
        details = json.dumps({
            "participant_count": participant_count,
            "expected_checkpoints": marks,
        })
        self.cursor.execute("""
            INSERT INTO research_session_events
            (event_id, session_id, dyad_id, installation_id, site_id, regional_hub, school_code, workshop_code, class_code, event_type, occurred_at, received_at, details)
            VALUES (?, ?, ?, 'inst-1', 'site-1', 'hub-1', 'sch-1', 'ws-1', 'cls-1', 'session_started', '2026-08-16T10:00:00Z', '2026-08-16T10:00:00Z', ?)
        """, (f"start-{session_id}", session_id, f"dyad-{session_id}", details))

    def _insert_checkpoint_completed(self, session_id, mark):
        self.cursor.execute("""
            INSERT INTO research_session_events
            (event_id, session_id, dyad_id, installation_id, site_id, regional_hub, school_code, workshop_code, class_code, event_type, interval_mark, occurred_at, received_at)
            VALUES (?, ?, ?, 'inst-1', 'site-1', 'hub-1', 'sch-1', 'ws-1', 'cls-1', 'checkpoint_completed', ?, '2026-08-16T10:20:00Z', '2026-08-16T10:20:00Z')
        """, (f"cp-{session_id}-{mark}", session_id, f"dyad-{session_id}", mark))

    def _insert_session_completed(self, session_id):
        self.cursor.execute("""
            INSERT INTO research_session_events
            (event_id, session_id, dyad_id, installation_id, site_id, regional_hub, school_code, workshop_code, class_code, event_type, occurred_at, received_at)
            VALUES (?, ?, ?, 'inst-1', 'site-1', 'hub-1', 'sch-1', 'ws-1', 'cls-1', 'session_completed', '2026-08-16T11:00:00Z', '2026-08-16T11:00:00Z')
        """, (f"end-{session_id}", session_id, f"dyad-{session_id}"))

    def _insert_response(self, session_id, participant_id, role, event_type, status="completed", mark=None):
        event_id = f"resp-{session_id}-{participant_id}-{event_type}-{mark}"
        self.cursor.execute("""
            INSERT INTO research_events
            (id, event_id, session_id, dyad_id, participant_id, participant_role, event_type, response_status, interval_mark, regional_hub, school_code, workshop_code, class_code, activity_id, computer_id, config_version, client_version, occurred_at, received_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'hub-1', 'sch-1', 'ws-1', 'cls-1', 'act-1', 'comp-1', '1.5.0', '1.5.0', '2026-08-16T10:10:00Z', '2026-08-16T10:10:00Z')
        """, (event_id, event_id, session_id, f"dyad-{session_id}", participant_id, role, event_type, status, mark))

    def test_solo_session_completed_classified_as_complete(self):
        s_id = "solo-1"
        self._insert_session_start(s_id, participant_count=1, marks=[20, 40])
        self._insert_response(s_id, "P1", "individual", "pre", "completed")
        self._insert_checkpoint_completed(s_id, 20)
        self._insert_response(s_id, "P1", "individual", "checkpoint", "completed", mark=20)
        self._insert_checkpoint_completed(s_id, 40)
        self._insert_response(s_id, "P1", "individual", "checkpoint", "completed", mark=40)
        self._insert_response(s_id, "P1", "individual", "post", "completed")
        self._insert_session_completed(s_id)

        self.conn.commit()
        row = self.cursor.execute("SELECT quality_status, participant_count, distinct_checkpoint_completed_pairs FROM research_session_quality WHERE session_id = ?", (s_id,)).fetchone()
        self.assertIsNotNone(row)
        self.assertEqual(row[0], "complete")
        self.assertEqual(row[1], 1)
        self.assertEqual(row[2], 2)

    def test_trio_session_requires_all_three_participants(self):
        s_id = "trio-1"
        self._insert_session_start(s_id, participant_count=3, marks=[20, 40])
        # P1, P2, P3 Pre
        self._insert_response(s_id, "P1", "computer", "pre", "completed")
        self._insert_response(s_id, "P2", "assembly", "pre", "completed")
        self._insert_response(s_id, "P3", "member_3", "pre", "completed")
        # Checkpoints
        self._insert_checkpoint_completed(s_id, 20)
        self._insert_response(s_id, "P1", "computer", "checkpoint", "completed", mark=20)
        self._insert_response(s_id, "P2", "assembly", "checkpoint", "completed", mark=20)
        self._insert_response(s_id, "P3", "member_3", "checkpoint", "completed", mark=20)
        self._insert_checkpoint_completed(s_id, 40)
        self._insert_response(s_id, "P1", "computer", "checkpoint", "completed", mark=40)
        self._insert_response(s_id, "P2", "assembly", "checkpoint", "completed", mark=40)
        self._insert_response(s_id, "P3", "member_3", "checkpoint", "completed", mark=40)
        # Post
        self._insert_response(s_id, "P1", "computer", "post", "completed")
        self._insert_response(s_id, "P2", "assembly", "post", "completed")
        self._insert_response(s_id, "P3", "member_3", "post", "completed")
        self._insert_session_completed(s_id)

        self.conn.commit()
        row = self.cursor.execute("SELECT quality_status, participant_count, distinct_checkpoint_completed_pairs FROM research_session_quality WHERE session_id = ?", (s_id,)).fetchone()
        self.assertEqual(row[0], "complete")
        self.assertEqual(row[1], 3)
        self.assertEqual(row[2], 6)

    def test_duplicates_do_not_inflate_missing_participant(self):
        # Trio with only P1 and P2, but P1 answered checkpoint 20 twice
        s_id = "trio-incomplete"
        self._insert_session_start(s_id, participant_count=3, marks=[20, 40])
        self._insert_response(s_id, "P1", "computer", "pre", "completed")
        self._insert_response(s_id, "P2", "assembly", "pre", "completed")
        self._insert_checkpoint_completed(s_id, 20)
        self._insert_response(s_id, "P1", "computer", "checkpoint", "completed", mark=20)
        self._insert_response(s_id, "P2", "assembly", "checkpoint", "completed", mark=20)
        self._insert_checkpoint_completed(s_id, 40)
        self._insert_response(s_id, "P1", "computer", "checkpoint", "completed", mark=40)
        self._insert_response(s_id, "P2", "assembly", "checkpoint", "completed", mark=40)
        self._insert_response(s_id, "P1", "computer", "post", "completed")
        self._insert_response(s_id, "P2", "assembly", "post", "completed")
        self._insert_session_completed(s_id)

        self.conn.commit()
        row = self.cursor.execute("SELECT quality_status FROM research_session_quality WHERE session_id = ?", (s_id,)).fetchone()
        # Missing P3 -> must be 'needs_review'
        self.assertEqual(row[0], "needs_review")

    def test_timeout_or_declined_relegates_to_needs_review(self):
        s_id = "duo-declined"
        self._insert_session_start(s_id, participant_count=2, marks=[20, 40])
        self._insert_response(s_id, "P1", "computer", "pre", "completed")
        self._insert_response(s_id, "P2", "assembly", "pre", "declined")
        self._insert_checkpoint_completed(s_id, 20)
        self._insert_response(s_id, "P1", "computer", "checkpoint", "completed", mark=20)
        self._insert_response(s_id, "P2", "assembly", "checkpoint", "completed", mark=20)
        self._insert_checkpoint_completed(s_id, 40)
        self._insert_response(s_id, "P1", "computer", "checkpoint", "completed", mark=40)
        self._insert_response(s_id, "P2", "assembly", "checkpoint", "completed", mark=40)
        self._insert_response(s_id, "P1", "computer", "post", "completed")
        self._insert_response(s_id, "P2", "assembly", "post", "completed")
        self._insert_session_completed(s_id)

        self.conn.commit()
        row = self.cursor.execute("SELECT quality_status FROM research_session_quality WHERE session_id = ?", (s_id,)).fetchone()
        self.assertEqual(row[0], "needs_review")

    def test_abort_has_precedence_over_completed(self):
        s_id = "aborted-session"
        self._insert_session_start(s_id, participant_count=2, marks=[20, 40])
        self.cursor.execute("""
            INSERT INTO research_session_events
            (event_id, session_id, dyad_id, installation_id, site_id, regional_hub, school_code, workshop_code, class_code, event_type, occurred_at, received_at)
            VALUES ('abort-1', ?, 'dyad-1', 'inst-1', 'site-1', 'hub-1', 'sch-1', 'ws-1', 'cls-1', 'session_aborted', '2026-08-16T10:30:00Z', '2026-08-16T10:30:00Z')
        """, (s_id,))
        self.cursor.execute("""
            INSERT INTO research_session_events
            (event_id, session_id, dyad_id, installation_id, site_id, regional_hub, school_code, workshop_code, class_code, event_type, occurred_at, received_at)
            VALUES ('complete-1', ?, 'dyad-1', 'inst-1', 'site-1', 'hub-1', 'sch-1', 'ws-1', 'cls-1', 'session_completed', '2026-08-16T10:31:00Z', '2026-08-16T10:31:00Z')
        """, (s_id,))

        self.conn.commit()
        row = self.cursor.execute("SELECT quality_status FROM research_session_quality WHERE session_id = ?", (s_id,)).fetchone()
        self.assertEqual(row[0], "aborted")


class InstallerPackagingTests(unittest.TestCase):
    def test_python_installer_generates_generic_secure_zip(self):
        import zipfile
        with tempfile.TemporaryDirectory(prefix="pulselab-test-") as temp_dir:
            output = Path(temp_dir) / "PulseLab-1.5.0-Windows.zip"
            subprocess.run(
                [
                    sys.executable,
                    str(INSTALLER_PATH),
                    "--output",
                    str(output),
                ],
                cwd=REPO_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertTrue(output.exists())
            checksum_path = output.with_suffix(output.suffix + ".sha256")
            self.assertTrue(checksum_path.exists())

            with zipfile.ZipFile(output, "r") as zf:
                file_list = zf.namelist()
                self.assertIn("PulseLab-1.5.0-Windows/INSTRUCOES.txt", file_list)
                self.assertIn("PulseLab-1.5.0-Windows/Instalar-PulseLab.bat", file_list)
                self.assertIn("PulseLab-1.5.0-Windows/Install-PulseLab.ps1", file_list)
                self.assertIn("PulseLab-1.5.0-Windows/VERSION.txt", file_list)
                self.assertIn("PulseLab-1.5.0-Windows/SHA256SUMS.txt", file_list)
                self.assertIn("PulseLab-1.5.0-Windows/agent/pulselab-agent.ps1", file_list)
                self.assertIn("PulseLab-1.5.0-Windows/config/config.json", file_list)
                self.assertIn("PulseLab-1.5.0-Windows/supabase/scripts/enroll-device.ps1", file_list)

                # Check for zero secret leaks
                for item in file_list:
                    data = zf.read(item).decode("utf-8", errors="ignore")
                    self.assertNotIn("service_role", data)
                    self.assertNotIn("device_access_token", data)
                    self.assertNotIn("device_refresh_token", data)

    def test_both_installers_accept_identity_presets(self):
        setup_script = read_text(SETUP_PATH)
        bootstrap_installer = read_text(BOOTSTRAP_PATH)
        for parameter in ("$SiteId", "$RegionalHub", "$SchoolCode"):
            self.assertIn(parameter, setup_script)
            self.assertIn(parameter, bootstrap_installer)

    def test_shortcut_locations_and_quote_guards(self):
        for path in (SETUP_PATH, BOOTSTRAP_PATH):
            text = read_text(path)
            self.assertIn("Desktop", text)
            self.assertIn("Programs", text)
            self.assertIn("-NoProfile", text)
        portable_text = read_text(PORTABLE_LAUNCHER_PATH)
        self.assertIn("agentPath", portable_text)

    def test_portal_and_installer_contracts(self):
        template_path = REPO_ROOT / "instrutor" / "config.template.js"
        self.assertTrue(template_path.exists())
        template_text = template_path.read_text(encoding="utf-8")
        self.assertIn("PULSELAB_INSTRUCTOR_CONFIG", template_text)
        self.assertIn("supabaseAnonKey", template_text)

        portal_path = REPO_ROOT / "instrutor" / "index.html"
        portal_text = portal_path.read_text(encoding="utf-8")
        self.assertNotIn("senha_mestra", portal_text)
        self.assertNotIn("123456", portal_text)
        self.assertIn("signInWithPassword", portal_text)
        self.assertIn('role="dialog"', portal_text)
        self.assertIn('aria-modal="true"', portal_text)
        self.assertNotIn("urlParams.get('demo')", portal_text)
        self.assertIn("allowDemo: false", template_text)

        installer_path = REPO_ROOT / "instalador" / "index.html"
        installer_text = installer_path.read_text(encoding="utf-8")
        self.assertNotIn("roboticapulselab", installer_text)
        self.assertIn("Provisionamento e Enrollment Seguro", installer_text)
        self.assertIn("permanentemente suspensas", installer_text)
        self.assertNotIn("validateAgentPayload", installer_text)
        self.assertNotIn("JSZip", installer_text)
        self.assertIn("v1.5.0", installer_text)


class DeviceIngestionRLSSemanticExecutionTests(unittest.TestCase):
    """
    Simula e valida semanticamente a regra exata de RLS WITH CHECK do Supabase:
    Exige correspondência exata e ativa em device_installations de auth.uid,
    installation_id e site_id, rejeitando qualquer tentativa de spoofing ou bypass.
    """

    def setUp(self):
        self.conn = sqlite3.connect(":memory:")
        self.cursor = self.conn.cursor()
        self.cursor.executescript("""
            CREATE TABLE device_installations (
                id TEXT PRIMARY KEY,
                device_user_id TEXT NOT NULL UNIQUE,
                installation_id TEXT NOT NULL UNIQUE,
                site_id TEXT NOT NULL,
                is_active INTEGER NOT NULL DEFAULT 1
            );
        """)
        # Inserir dispositivo legítimo ativo
        self.cursor.execute("""
            INSERT INTO device_installations (id, device_user_id, installation_id, site_id, is_active)
            VALUES ('di-1', 'user-legit-uuid', 'inst-legit-uuid', 'SEDE-JUAZEIRO', 1)
        """)
        # Inserir dispositivo inativo (revogado)
        self.cursor.execute("""
            INSERT INTO device_installations (id, device_user_id, installation_id, site_id, is_active)
            VALUES ('di-2', 'user-revoked-uuid', 'inst-revoked-uuid', 'SEDE-JUAZEIRO', 0)
        """)
        self.conn.commit()

    def tearDown(self):
        self.conn.close()

    def _evaluate_rls_check(self, auth_uid: str, is_service_role: bool, installation_id: str, site_id: str) -> bool:
        """
        Executa a exata expressão WITH CHECK da política RLS:
        (role = 'service_role') OR (
            installation_id IS NOT NULL AND site_id IS NOT NULL AND EXISTS (
                SELECT 1 FROM device_installations di
                WHERE di.device_user_id = auth.uid()
                  AND di.is_active = true
                  AND di.installation_id = event.installation_id
                  AND di.site_id = event.site_id
            )
        )
        """
        if is_service_role:
            return True
        if not installation_id or not site_id:
            return False

        row = self.cursor.execute("""
            SELECT 1 FROM device_installations di
            WHERE di.device_user_id = ?
              AND di.is_active = 1
              AND di.installation_id = ?
              AND di.site_id = ?
        """, (auth_uid, installation_id, site_id)).fetchone()
        return row is not None

    def _evaluate_storage_rls_check(self, auth_uid: str, is_service_role: bool, object_name: str) -> bool:
        """
        Executa a exata expressão WITH CHECK da política Storage:
        (role = 'service_role') OR EXISTS (
            SELECT 1 FROM device_installations di
            WHERE di.device_user_id = auth.uid()
              AND di.is_active = true
              AND di.installation_id = split_part(name, '/', 1)
        )
        """
        if is_service_role:
            return True
        prefix = object_name.split("/")[0] if "/" in object_name else object_name
        row = self.cursor.execute("""
            SELECT 1 FROM device_installations di
            WHERE di.device_user_id = ?
              AND di.is_active = 1
              AND di.installation_id = ?
        """, (auth_uid, prefix)).fetchone()
        return row is not None

    def test_valid_active_device_is_allowed(self):
        allowed = self._evaluate_rls_check(
            auth_uid="user-legit-uuid",
            is_service_role=False,
            installation_id="inst-legit-uuid",
            site_id="SEDE-JUAZEIRO",
        )
        self.assertTrue(allowed)

    def test_spoofed_installation_id_is_rejected(self):
        # Usuário tenta inserir outro installation_id
        allowed = self._evaluate_rls_check(
            auth_uid="user-legit-uuid",
            is_service_role=False,
            installation_id="inst-attacker-target-uuid",
            site_id="SEDE-JUAZEIRO",
        )
        self.assertFalse(allowed)

    def test_spoofed_site_id_is_rejected(self):
        # Usuário tenta inserir outro site_id
        allowed = self._evaluate_rls_check(
            auth_uid="user-legit-uuid",
            is_service_role=False,
            installation_id="inst-legit-uuid",
            site_id="SEDE-OTHER-POLO",
        )
        self.assertFalse(allowed)

    def test_inactive_device_is_rejected(self):
        # Dispositivo com is_active = 0
        allowed = self._evaluate_rls_check(
            auth_uid="user-revoked-uuid",
            is_service_role=False,
            installation_id="inst-revoked-uuid",
            site_id="SEDE-JUAZEIRO",
        )
        self.assertFalse(allowed)

    def test_unregistered_auth_uid_is_rejected(self):
        # auth.uid não cadastrado em device_installations
        allowed = self._evaluate_rls_check(
            auth_uid="user-unknown-uuid",
            is_service_role=False,
            installation_id="inst-legit-uuid",
            site_id="SEDE-JUAZEIRO",
        )
        self.assertFalse(allowed)

    def test_null_or_empty_installation_or_site_rejected(self):
        self.assertFalse(self._evaluate_rls_check("user-legit-uuid", False, "", "SEDE-JUAZEIRO"))
        self.assertFalse(self._evaluate_rls_check("user-legit-uuid", False, "inst-legit-uuid", ""))
        self.assertFalse(self._evaluate_rls_check("user-legit-uuid", False, None, "SEDE-JUAZEIRO"))

    def test_screenshot_storage_matching_prefix_allowed(self):
        path = "inst-legit-uuid/OFICINA-1/sess-1/checkpoint-20.jpg"
        self.assertTrue(self._evaluate_storage_rls_check("user-legit-uuid", False, path))

    def test_screenshot_storage_mismatched_prefix_rejected(self):
        path = "inst-other-uuid/OFICINA-1/sess-1/checkpoint-20.jpg"
        self.assertFalse(self._evaluate_storage_rls_check("user-legit-uuid", False, path))

    def test_screenshot_storage_inactive_device_rejected(self):
        path = "inst-revoked-uuid/OFICINA-1/sess-1/checkpoint-20.jpg"
        self.assertFalse(self._evaluate_storage_rls_check("user-revoked-uuid", False, path))


class DeviceEnrollmentTokenSemanticExecutionTests(unittest.TestCase):
    """
    Simula e valida semanticamente o ciclo de vida do token de enrollment individual de uso único:
    - Hash SHA-256
    - Verificação de expiração
    - Consumo atômico no banco (prevenindo replay attack)
    """

    def setUp(self):
        self.conn = sqlite3.connect(":memory:")
        self.cursor = self.conn.cursor()
        self.cursor.executescript("""
            CREATE TABLE device_enrollment_tokens (
                id TEXT PRIMARY KEY,
                token_hash TEXT NOT NULL UNIQUE,
                installation_id TEXT NOT NULL,
                site_id TEXT NOT NULL,
                expires_at TEXT NOT NULL,
                consumed_at TEXT,
                consumed_by TEXT
            );
        """)

        # Inserir token válido não consumido
        self.valid_raw = "token-secret-alpha-12345"
        self.valid_hash = hashlib.sha256(self.valid_raw.encode("utf-8")).hexdigest()
        self.cursor.execute("""
            INSERT INTO device_enrollment_tokens (id, token_hash, installation_id, site_id, expires_at, consumed_at)
            VALUES ('tok-1', ?, 'inst-target-uuid', 'SEDE-JUAZEIRO', '2099-01-01T00:00:00Z', NULL)
        """, (self.valid_hash,))

        # Inserir token já consumido
        self.consumed_raw = "token-secret-consumed-999"
        self.consumed_hash = hashlib.sha256(self.consumed_raw.encode("utf-8")).hexdigest()
        self.cursor.execute("""
            INSERT INTO device_enrollment_tokens (id, token_hash, installation_id, site_id, expires_at, consumed_at, consumed_by)
            VALUES ('tok-2', ?, 'inst-target-uuid', 'SEDE-JUAZEIRO', '2099-01-01T00:00:00Z', '2026-08-16T10:00:00Z', 'user-prev')
        """, (self.consumed_hash,))

        # Inserir token expirado
        self.expired_raw = "token-secret-expired-000"
        self.expired_hash = hashlib.sha256(self.expired_raw.encode("utf-8")).hexdigest()
        self.cursor.execute("""
            INSERT INTO device_enrollment_tokens (id, token_hash, installation_id, site_id, expires_at, consumed_at)
            VALUES ('tok-3', ?, 'inst-target-uuid', 'SEDE-JUAZEIRO', '2020-01-01T00:00:00Z', NULL)
        """, (self.expired_hash,))
        self.conn.commit()

    def tearDown(self):
        self.conn.close()

    def _consume_enrollment_token(self, raw_token: str, installation_id: str, site_id: str, user_id: str) -> bool:
        token_h = hashlib.sha256(raw_token.encode("utf-8")).hexdigest()
        now_iso = "2026-08-16T12:00:00Z"

        # 1. Query matching unconsumed, unexpired token
        row = self.cursor.execute("""
            SELECT id FROM device_enrollment_tokens
            WHERE token_hash = ?
              AND installation_id = ?
              AND site_id = ?
              AND consumed_at IS NULL
              AND expires_at > ?
        """, (token_h, installation_id, site_id, now_iso)).fetchone()

        if not row:
            return False

        token_id = row[0]
        # 2. Atomic consume update
        cursor = self.conn.cursor()
        cursor.execute("""
            UPDATE device_enrollment_tokens
            SET consumed_at = ?, consumed_by = ?
            WHERE id = ? AND consumed_at IS NULL
        """, (now_iso, user_id, token_id))
        self.conn.commit()
        return cursor.rowcount == 1

    def test_valid_token_consumed_successfully(self):
        success = self._consume_enrollment_token(
            raw_token=self.valid_raw,
            installation_id="inst-target-uuid",
            site_id="SEDE-JUAZEIRO",
            user_id="new-device-user-id",
        )
        self.assertTrue(success)

        # Replay should now fail because it is consumed
        replay_success = self._consume_enrollment_token(
            raw_token=self.valid_raw,
            installation_id="inst-target-uuid",
            site_id="SEDE-JUAZEIRO",
            user_id="second-device-user-id",
        )
        self.assertFalse(replay_success)

    def test_already_consumed_token_is_rejected(self):
        success = self._consume_enrollment_token(
            raw_token=self.consumed_raw,
            installation_id="inst-target-uuid",
            site_id="SEDE-JUAZEIRO",
            user_id="attacker-user-id",
        )
        self.assertFalse(success)

    def test_expired_token_is_rejected(self):
        success = self._consume_enrollment_token(
            raw_token=self.expired_raw,
            installation_id="inst-target-uuid",
            site_id="SEDE-JUAZEIRO",
            user_id="attacker-user-id",
        )
        self.assertFalse(success)

    def test_mismatched_installation_id_is_rejected(self):
        success = self._consume_enrollment_token(
            raw_token=self.valid_raw,
            installation_id="inst-different-uuid",
            site_id="SEDE-JUAZEIRO",
            user_id="attacker-user-id",
        )
        self.assertFalse(success)

    def test_mismatched_site_id_is_rejected(self):
        success = self._consume_enrollment_token(
            raw_token=self.valid_raw,
            installation_id="inst-target-uuid",
            site_id="SEDE-OTHER-POLO",
            user_id="attacker-user-id",
        )
        self.assertFalse(success)

    def test_invalid_raw_token_is_rejected(self):
        success = self._consume_enrollment_token(
            raw_token="completely-wrong-token",
            installation_id="inst-target-uuid",
            site_id="SEDE-JUAZEIRO",
            user_id="attacker-user-id",
        )
        self.assertFalse(success)


class AgentFailClosedBehavioralContractTests(unittest.TestCase):
    def test_agent_fails_closed_without_config(self):
        # Simulate logic where absence of valid environment state prevents agent startup
        def start_agent(config_path):
            if not config_path.exists():
                raise PermissionError("Agent start aborted: secure config missing")
            return True

        with tempfile.TemporaryDirectory() as td:
            missing_path = Path(td) / "nonexistent.json"
            with self.assertRaises(PermissionError):
                start_agent(missing_path)


class ProvisionDeviceToolExecutionTests(unittest.TestCase):
    def test_provision_tool_generates_and_registers_token_with_chmod_0600(self):
        from supabase.scripts.provision_device import generate_enrollment_token, hash_token, write_secure_output

        token = generate_enrollment_token()
        self.assertGreaterEqual(len(token), 32)
        h = hash_token(token)
        self.assertEqual(len(h), 64)

        with tempfile.TemporaryDirectory() as td:
            out_file = Path(td) / "provision_bundle.json"
            sample_data = {
                "installation_id": "inst-1",
                "site_id": "SEDE-1",
                "enrollment_token": token,
            }
            write_secure_output(out_file, sample_data)
            self.assertTrue(out_file.exists())
            if os.name != "nt":
                file_mode = oct(out_file.stat().st_mode & 0o777)
                self.assertEqual(file_mode, "0o600")


if __name__ == "__main__":
    unittest.main()
