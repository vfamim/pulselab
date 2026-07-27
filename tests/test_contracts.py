import base64
import json
import re
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


def read_text(path):
    return path.read_text(encoding="utf-8")


class ConfigContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config = json.loads(read_text(CONFIG_PATH))

    def test_version_and_protocol_are_explicit(self):
        self.assertEqual(self.config["version"], "1.4.0")
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
            self.assertIn(f"GRANT INSERT ON TABLE public.{table} TO anon;", self.schema)
        self.assertIn(
            "REVOKE ALL ON TABLE public.research_session_quality FROM anon, authenticated;",
            self.schema,
        )
        self.assertNotRegex(
            self.schema,
            r"GRANT\s+(SELECT|UPDATE|DELETE|ALL).*?\bTO\s+anon\b",
        )

    def test_idempotency_and_private_storage_are_declared(self):
        self.assertRegex(
            self.schema,
            r"event_id\s+uuid\s+PRIMARY KEY",
        )
        self.assertIn("VALUES ('screenshots', 'screenshots', false)", self.schema)
        self.assertNotIn("FOR SELECT\n    TO anon", self.schema)


class AgentStaticTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.agent = read_text(AGENT_PATH)
        cls.config = json.loads(read_text(CONFIG_PATH))

    def test_component_versions_match(self):
        version_match = re.search(r'\$script:VERSION\s*=\s*"([^"]+)"', self.agent)
        self.assertIsNotNone(version_match)
        self.assertEqual(version_match.group(1), self.config["version"])
        self.assertIn(f"version={self.config['version']}", read_text(SETUP_PATH))
        for path in (BOOTSTRAP_PATH, PORTABLE_LAUNCHER_PATH):
            self.assertIn(f"Version    : {self.config['version']}", read_text(path))

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


class InstallerPackagingTests(unittest.TestCase):
    def test_python_installer_embeds_current_agent_and_config(self):
        with tempfile.TemporaryDirectory(prefix="pulselab-test-") as temp_dir:
            output = Path(temp_dir) / "Install-Pulselab-Test.bat"
            subprocess.run(
                [
                    sys.executable,
                    str(INSTALLER_PATH),
                    "--url",
                    "https://example.supabase.co",
                    "--key",
                    "test-anon-key",
                    "--output",
                    str(output),
                ],
                cwd=REPO_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            content = output.read_text(encoding="utf-8")
            agent_match = re.search(r'\$agentB64 = "([A-Za-z0-9+/=]+)"', content)
            config_match = re.search(r'\$configB64 = "([A-Za-z0-9+/=]+)"', content)
            self.assertIsNotNone(agent_match)
            self.assertIsNotNone(config_match)
            self.assertEqual(
                base64.b64decode(agent_match.group(1)),
                AGENT_PATH.read_bytes(),
            )
            self.assertEqual(
                base64.b64decode(config_match.group(1)),
                CONFIG_PATH.read_bytes(),
            )


if __name__ == "__main__":
    unittest.main()
