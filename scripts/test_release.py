import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load(name: str, rel: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


release = load("publicar_release", "scripts/publicar-release.py")
polo = load("gerar_pacote_polo", "scripts/gerar-pacote-polo.py")


class ReleaseSigningTest(unittest.TestCase):
    def test_signed_manifest_verifies_with_openssl(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            key = tmp_path / "key.pem"
            public_json = tmp_path / "release-public-key.json"
            jwk = release.generate_key(key, public_json)
            self.assertEqual(jwk["kty"], "RSA")
            self.assertEqual(json.loads(public_json.read_text())["n"], jwk["n"])

            package = tmp_path / "PulseLab-9.9.9-Windows.zip"
            package.write_bytes(b"conteudo")
            manifest, sig = release.write_signed_manifest(
                package, "9.9.9", key, tmp_path / "out", release.release_url("9.9.9", package.name)
            )
            data = json.loads(manifest.read_text())
            self.assertEqual(data["version"], "9.9.9")
            self.assertEqual(data["package_sha256"], release.sha256_file(package))
            self.assertTrue(data["package_url"].startswith("https://github.com/vfamim/pulselab/releases/download/v9.9.9/"))

            pub_pem = tmp_path / "pub.pem"
            subprocess.run(["openssl", "rsa", "-in", str(key), "-pubout", "-out", str(pub_pem)], check=True, capture_output=True)
            ok = subprocess.run(
                ["openssl", "dgst", "-sha256", "-verify", str(pub_pem), "-signature", str(sig), str(manifest)],
                capture_output=True,
            )
            self.assertEqual(ok.returncode, 0, ok.stdout + ok.stderr)

    def test_existing_private_key_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as tmp:
            key = Path(tmp) / "key.pem"
            release.generate_key(key, Path(tmp) / "pub.json")
            with self.assertRaises(FileExistsError):
                release.generate_key(key, Path(tmp) / "pub.json")

    def test_private_key_never_inside_repository(self):
        self.assertFalse(release.DEFAULT_PRIVATE_KEY.resolve().is_relative_to(ROOT))
        self.assertEqual(list(ROOT.glob("*.pem")), [])


class PoloProvisioningTest(unittest.TestCase):
    def test_caae_required_for_research(self):
        data = polo.build_provisioning("PET", "Petrolina", "12345678.9.0000.1234", None)
        self.assertTrue(data["research_collection_enabled"])
        self.assertEqual(data["research_authorized_purposes"], ["academic_research"])
        with self.assertRaises(ValueError):
            polo.build_provisioning("PET", "Petrolina", "v2.0-piloto", None)

    def test_without_research_keeps_collection_off(self):
        data = polo.build_provisioning("SBF", "Senhor do Bonfim", None, None)
        self.assertFalse(data["research_collection_enabled"])
        self.assertIsNone(data["research_authorization_version"])
        self.assertEqual(data["research_authorized_purposes"], [])

    def test_polo_code_validated(self):
        with self.assertRaises(ValueError):
            polo.build_provisioning("pet lab", "Petrolina", None, None)


class GenericPackageDefaultsTest(unittest.TestCase):
    def test_shipped_configs_never_enable_research(self):
        for name in ("config.json", "defaults.json"):
            data = json.loads((ROOT / "config" / name).read_text(encoding="utf-8"))
            self.assertIs(data.get("research_collection_enabled"), False, name)
            self.assertIsNone(data.get("research_authorization_version"), name)
            self.assertEqual(data.get("research_authorized_purposes"), [], name)

    def test_bridge_takes_authorization_only_from_provisioning(self):
        bridge = (ROOT / "bridge" / "pulselab-bridge.ps1").read_text(encoding="utf-8")
        self.assertIn("$publicConfig.research_collection_enabled = $false", bridge)
        self.assertIn('Join-Path $DataDir "installation.json"', bridge)

    def test_export_has_no_windows_identifiers(self):
        exporter = (ROOT / "scripts" / "exportar-pendrive.ps1").read_text(encoding="utf-8")
        self.assertNotIn("$env:COMPUTERNAME", exporter)
        self.assertNotIn("$env:USERNAME", exporter)
        self.assertIn("machine_label", exporter)


if __name__ == "__main__":
    unittest.main()
