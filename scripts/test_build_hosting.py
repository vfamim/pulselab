import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("build_hosting", ROOT / "scripts" / "build-hosting.py")
build_hosting = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_hosting)


class BuildHostingTest(unittest.TestCase):
    def make_repo(self, root: Path) -> None:
        for entry in build_hosting.PUBLIC_ENTRIES:
            target = root / entry
            if "." in entry:
                target.write_text("ok", encoding="utf-8")
            else:
                target.mkdir()
                (target / "index.html").write_text("ok", encoding="utf-8")
        (root / "pulselab-robotica-edu-firebase-adminsdk-x.json").write_text("{}", encoding="utf-8")
        (root / "dados_locais").mkdir()
        (root / "dados_locais" / "pulselab_consolidado.sqlite").write_text("x", encoding="utf-8")
        (root / "instalador" / "algo-adminsdk-y.json").write_text("{}", encoding="utf-8")
        (root / "instrutor" / ".env").write_text("SECRET=1", encoding="utf-8")

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

    def test_firebase_points_to_dedicated_folder(self):
        config = json.loads((ROOT / "firebase.json").read_text(encoding="utf-8"))
        self.assertEqual(config["hosting"]["public"], build_hosting.OUTPUT_DIR_NAME)


if __name__ == "__main__":
    unittest.main()
