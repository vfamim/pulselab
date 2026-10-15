import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("build_hosting", ROOT / "tooling" / "site" / "build-hosting.py")
build_hosting = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_hosting)


class BuildHostingTest(unittest.TestCase):
    def make_repo(self, root: Path) -> None:
        for entry, source in build_hosting.PUBLIC_ENTRIES.items():
            target = root / source
            target.parent.mkdir(parents=True, exist_ok=True)
            if "." in entry:
                target.write_text("ok", encoding="utf-8")
            else:
                target.mkdir()
                (target / "index.html").write_text("ok", encoding="utf-8")
        (root / "pulselab-robotica-edu-firebase-adminsdk-x.json").write_text("{}", encoding="utf-8")
        (root / "dados_locais").mkdir()
        (root / "dados_locais" / "pulselab_consolidado.sqlite").write_text("x", encoding="utf-8")
        (root / "apps" / "site" / "instalador" / "algo-adminsdk-y.json").write_text("{}", encoding="utf-8")
        (root / "alunos" / ".env").write_text("SECRET=1", encoding="utf-8")

    def test_publishes_only_allowlist(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.make_repo(root)
            out = root / "hosting-dist"
            published = build_hosting.build(root, out)
            self.assertIn("alunos/index.html", published)
            self.assertFalse(any("adminsdk" in p for p in published))
            self.assertFalse(any("dados_locais" in p for p in published))
            self.assertFalse(any(p.endswith(".env") for p in published))
            self.assertEqual(list(out.rglob("*adminsdk*")), [])

    def test_instrutor_and_downloads_not_published(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.make_repo(root)
            (root / "instrutor").mkdir()
            (root / "instrutor" / "index.html").write_text("ok", encoding="utf-8")
            downloads = root / "apps" / "site" / "instalador" / "downloads"
            downloads.mkdir()
            (downloads / "PulseLab-9.9.9-Windows.zip").write_text("z", encoding="utf-8")
            (downloads / "PulseLab-9.9.9-Windows.zip.sha256").write_text("h", encoding="utf-8")
            out = root / "hosting-dist"
            published = build_hosting.build(root, out)
            self.assertNotIn("instrutor", build_hosting.PUBLIC_ENTRIES)
            self.assertFalse(any(p.startswith("instrutor/") for p in published))
            self.assertFalse(any(p.endswith((".zip", ".sha256")) for p in published))
            self.assertIn("instalador/index.html", published)

    def test_firebase_points_to_dedicated_folder(self):
        config = json.loads((ROOT / "firebase.json").read_text(encoding="utf-8"))
        self.assertEqual(config["hosting"]["public"], build_hosting.OUTPUT_DIR_NAME)
        self.assertFalse(any("instrutor" in r["source"] for r in config["hosting"]["rewrites"]))


if __name__ == "__main__":
    unittest.main()
