"""Parser de projetos LEGO SPIKE (bridge/spike-parser.ps1).

Gera projetos .llsp3 sintéticos (zip com manifest.json + scratch.sb3 aninhado) com
opcodes reais do SPIKE 3 e confere métricas, flags, pontuação de pensamento
computacional, hash estrutural, status de erro e ausência de texto digitado/caminhos.

Roda o parser real em pwsh (PowerShell 7). Sem pwsh no PATH, o teste é pulado.
"""

from __future__ import annotations

import copy
import io
import json
import os
import shutil
import subprocess
import tempfile
import time
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PARSER = ROOT / "bridge" / "spike-parser.ps1"
PWSH = shutil.which("pwsh")
SECRET = "JOAO DA SILVA"


def blk(opcode, next_=None, parent=None, inputs=None, fields=None, shadow=False, top=False, **extra):
    block = {
        "opcode": opcode,
        "next": next_,
        "parent": parent,
        "inputs": inputs or {},
        "fields": fields or {},
        "shadow": shadow,
        "topLevel": top,
    }
    if top:
        block["x"] = 100
        block["y"] = 200
    block.update(extra)
    return block


def known_blocks() -> dict:
    """Programa com valor CT conhecido (ver test_ct_score_known_fixture)."""
    b = {}
    # Pilha A: início -> velocidade -> texto -> sempre { se distância senão }
    b["a1"] = blk("flipperevents_whenProgramStarts", "a2", top=True)
    b["a2"] = blk("flippermove_movementSpeed", "a3", "a1", inputs={"SPEED": [1, [4, "50"]]})
    b["a3"] = blk("flipperlight_lightDisplayText", "a4", "a2", inputs={"TEXT": [1, [10, SECRET]]})
    b["a4"] = blk("control_forever", None, "a3", inputs={"SUBSTACK": [2, "a5"]})
    b["a5"] = blk("control_if_else", None, "a4",
                  inputs={"CONDITION": [2, "a6"], "SUBSTACK": [2, "a7"], "SUBSTACK2": [2, "a8"]})
    b["a6"] = blk("flippersensors_isDistance", None, "a5",
                  inputs={"PORT": [1, "s1"], "VALUE": [1, [4, "10"]]},
                  fields={"COMPARATOR": ["<", None], "UNIT": ["cm", None]})
    b["s1"] = blk("flippersensors_custom-sensor-port-selector", None, "a6",
                  fields={"field_flippersensors_custom-sensor-port-selector": ["C", None]}, shadow=True)
    b["a7"] = blk("flippermotor_motorTurnForDirection", "a7b", "a5",
                  inputs={"PORT": [1, "s2"], "DIRECTION": [1, "s3"], "VALUE": [1, [4, "1"]]},
                  fields={"UNIT": ["rotations", None]})
    b["s2"] = blk("flippermotor_multiple-port-selector", None, "a7",
                  fields={"field_flippermotor_multiple-port-selector": ["A", None]}, shadow=True)
    b["s3"] = blk("flippermotor_custom-icon-direction", None, "a7",
                  fields={"field_flippermotor_custom-icon-direction": ["clockwise", None]}, shadow=True)
    b["a7b"] = blk("control_wait", None, "a7", inputs={"DURATION": [1, [5, "1"]]})
    b["a8"] = blk("flippermove_move", "a9", "a5", inputs={"VALUE": [1, [4, "10"]]},
                  fields={"UNIT": ["cm", None]})
    b["a9"] = blk("data_setvariableto", None, "a8", inputs={"VALUE": [1, [10, "JOAO"]]},
                  fields={"VARIABLE": ["velocidade do JOAO", "var1"]})
    # Pilha B: início -> lista -> mensagem -> bloco próprio duas vezes
    b["b1"] = blk("flipperevents_whenProgramStarts", "b2", top=True)
    b["b2"] = blk("data_addtolist", "b3", "b1", inputs={"ITEM": [1, [10, "item JOAO"]]},
                  fields={"LIST": ["lista do JOAO", "list1"]})
    b["b3"] = blk("event_broadcast", "b4", "b2", inputs={"BROADCAST_INPUT": [1, [11, "mensagem JOAO", "msg1"]]})
    b["b4"] = blk("procedures_call", "b5", "b3", inputs={"arg_x1": [1, [10, "JOAO"]]},
                  mutation={"tagName": "mutation", "proccode": "girar JOAO %s", "argumentids": "[\"arg_x1\"]"})
    b["b5"] = blk("procedures_call", None, "b4", inputs={"arg_x1": [1, [10, "JOAO"]]},
                  mutation={"tagName": "mutation", "proccode": "girar JOAO %s", "argumentids": "[\"arg_x1\"]"})
    # Pilha C: ao receber -> esperar até não(pressionado) -> texto em bloco-sombra
    b["c1"] = blk("event_whenbroadcastreceived", "c2", top=True,
                  fields={"BROADCAST_OPTION": ["mensagem JOAO", "msg1"]})
    b["c2"] = blk("control_wait_until", "c5", "c1", inputs={"CONDITION": [2, "c3"]})
    b["c3"] = blk("operator_not", None, "c2", inputs={"OPERAND": [2, "c4"]})
    b["c4"] = blk("flippersensors_isPressed", None, "c3", inputs={"PORT": [1, "s4"]})
    b["s4"] = blk("flippersensors_force-sensor-selector", None, "c4",
                  fields={"field_flippersensors_force-sensor-selector": ["E", None]}, shadow=True)
    b["c5"] = blk("flipperlight_lightDisplayText", None, "c2", inputs={"TEXT": [1, "s5"]})
    b["s5"] = blk("text", None, "c5", fields={"TEXT": [SECRET, None]}, shadow=True)
    # Pilha D: definição do bloco próprio
    b["d1"] = blk("procedures_definition", "d2", top=True, inputs={"custom_block": [1, "p1"]})
    b["p1"] = blk("procedures_prototype", None, "d1", shadow=True,
                  mutation={"tagName": "mutation", "proccode": "girar JOAO %s", "argumentids": "[\"arg_x1\"]",
                            "argumentnames": "[\"nome JOAO\"]"})
    b["d2"] = blk("flippermotor_motorStartDirection", None, "d1", inputs={"PORT": [1, "s6"]})
    b["s6"] = blk("flippermotor_multiple-port-selector", None, "d2",
                  fields={"field_flippermotor_multiple-port-selector": ["B", None]}, shadow=True)
    # Variável solta no canvas: [12, nome, id, x, y]
    b["solta"] = [12, "velocidade do JOAO", "var1", 300, 400]
    return b


def wait_until_blocks() -> dict:
    """Espera até sensor, sem laço: uses_loop falso, uses_condition verdadeiro."""
    return {
        "w1": blk("flipperevents_whenProgramStarts", "w2", top=True),
        "w2": blk("flippermotor_motorStartDirection", "w3", "w1", inputs={"PORT": [1, "ws1"]}),
        "ws1": blk("flippermotor_multiple-port-selector", None, "w2",
                   fields={"field_flippermotor_multiple-port-selector": ["A", None]}, shadow=True),
        "w3": blk("control_wait_until", "w5", "w2", inputs={"CONDITION": [2, "w4"]}),
        "w4": blk("flippersensors_isColor", None, "w3", inputs={"VALUE": [1, [4, "9"]]}),
        "w5": blk("flippermotor_motorStop", None, "w3"),
    }


def sensor_hat_blocks() -> dict:
    """Dois chapéus de cor iguais com duas pilhas cada + dois inícios: paralelismo 3."""
    b = {}
    for prefix, color in (("h", "red"), ("k", "red")):
        b[f"{prefix}1"] = blk("flipperevents_whenColor", f"{prefix}2", top=True,
                              inputs={"PORT": [1, f"{prefix}p"], "OPTION": [1, f"{prefix}c"]})
        b[f"{prefix}p"] = blk("flipperevents_color-sensor-selector", None, f"{prefix}1",
                              fields={"field_flipperevents_color-sensor-selector": ["F", None]}, shadow=True)
        b[f"{prefix}c"] = blk("flipperevents_color-selector", None, f"{prefix}1",
                              fields={"field_flipperevents_color-selector": [color, None]}, shadow=True)
        b[f"{prefix}2"] = blk("flippermotor_motorStop", None, f"{prefix}1")
    for prefix in ("i", "j"):
        b[f"{prefix}1"] = blk("flipperevents_whenProgramStarts", f"{prefix}2", top=True)
        b[f"{prefix}2"] = blk("control_repeat_until", None, f"{prefix}1", inputs={"SUBSTACK": [2, f"{prefix}3"]})
        b[f"{prefix}3"] = blk("flippermove_move", None, f"{prefix}2")
    return b


def project_json(blocks: dict) -> dict:
    return {
        "targets": [
            {"isStage": True, "name": "Stage", "variables": {}, "lists": {}, "broadcasts": {}, "blocks": {},
             "comments": {}},
            {"isStage": False, "name": "Projeto do JOAO", "variables": {"var1": ["velocidade do JOAO", 0]},
             "lists": {"list1": ["lista do JOAO", []]}, "broadcasts": {"msg1": "mensagem JOAO"},
             "blocks": blocks,
             "comments": {"cm1": {"blockId": "a1", "text": f"comentário de {SECRET}", "x": 0, "y": 0}}},
        ],
        "monitors": [],
        "extensions": [],
        "meta": {"semver": "3.0.0", "vm": "0.2.0", "agent": "SPIKE"},
    }


def sb3_bytes(project_text: str) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("project.json", project_text)
    return buffer.getvalue()


def write_llsp3(path: Path, project_text: str | None = None, manifest: dict | None = None,
                extra: dict | None = None) -> Path:
    manifest = manifest or {"type": "word-blocks", "name": f"Projeto {SECRET}", "autoDelete": False}
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("manifest.json", json.dumps(manifest))
        if project_text is not None:
            zf.writestr("scratch.sb3", sb3_bytes(project_text))
        zf.writestr("icon.svg", "<svg/>")
        for name, content in (extra or {}).items():
            zf.writestr(name, content)
    return path


def remap_ids(blocks: dict, prefix: str) -> dict:
    """Troca todos os ids de bloco (e ids de argumento) mantendo a estrutura."""
    ids = {key: f"{prefix}{key}" for key in blocks}
    ids["arg_x1"] = f"{prefix}arg_x1"

    def walk(value):
        if isinstance(value, str):
            return ids.get(value, value)
        if isinstance(value, list):
            return [walk(item) for item in value]
        if isinstance(value, dict):
            return {ids.get(k, k) if k in ("arg_x1",) else k: walk(v) for k, v in value.items()}
        return value

    out = {}
    for key, block in blocks.items():
        if isinstance(block, dict):
            new = dict(block)
            for field in ("next", "parent"):
                new[field] = walk(block[field])
            new["inputs"] = walk(block["inputs"])
            out[ids[key]] = new
        else:
            out[ids[key]] = block
    return out


@unittest.skipUnless(PWSH, "pwsh não encontrado")
class SpikeParserTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp(prefix="pulselab-spike-JOAO-"))
        cls.spike_dir = cls.tmp / "LEGO SPIKE"
        cls.spike_dir.mkdir()
        base = known_blocks()
        cls.paths = {}

        cls.paths["known"] = write_llsp3(cls.spike_dir / "missao JOAO.llsp3", json.dumps(project_json(base)))

        reordered = copy.deepcopy(base)
        # a2 <-> a3 na sequência principal
        reordered["a1"]["next"] = "a3"
        reordered["a3"].update(next="a2", parent="a1")
        reordered["a2"].update(next="a4", parent="a3")
        reordered["a4"]["parent"] = "a2"
        cls.paths["reordered"] = write_llsp3(cls.tmp / "reordered.llsp3", json.dumps(project_json(reordered)))

        swapped = copy.deepcopy(base)
        # troca os ramos do se/senão
        swapped["a5"]["inputs"]["SUBSTACK"] = [2, "a8"]
        swapped["a5"]["inputs"]["SUBSTACK2"] = [2, "a7"]
        cls.paths["swapped"] = write_llsp3(cls.tmp / "swapped.llsp3", json.dumps(project_json(swapped)))

        cosmetic = remap_ids(copy.deepcopy(base), "zz")
        for block in cosmetic.values():
            if isinstance(block, dict):
                if block["topLevel"]:
                    block["x"] = 9999
                    block["y"] = -42
                for field in block["fields"].values():
                    if isinstance(field[0], str):
                        field[0] = "MARIA"
        cls.paths["cosmetic"] = write_llsp3(cls.tmp / "cosmetic.llsp3", json.dumps(project_json(cosmetic)))

        cls.paths["wait_until"] = write_llsp3(cls.tmp / "wait.llsp3", json.dumps(project_json(wait_until_blocks())))
        cls.paths["sensor_hats"] = write_llsp3(cls.tmp / "hats.llsp3", json.dumps(project_json(sensor_hat_blocks())))
        cls.paths["empty"] = write_llsp3(cls.tmp / "empty.llsp3", json.dumps(project_json({})))

        cls.paths["python"] = write_llsp3(
            cls.tmp / "python.llsp3",
            manifest={"type": "python", "name": f"Python {SECRET}"},
            extra={"projectbody.json": json.dumps({"main": f"print('{SECRET}')"})},
        )

        corrupt = cls.tmp / "corrupt.llsp3"
        corrupt.write_bytes(b"PK\x03\x04" + b"lixo JOAO DA SILVA" * 20)
        cls.paths["corrupt"] = corrupt

        full_text = json.dumps(project_json(base))
        cls.paths["truncated"] = write_llsp3(cls.tmp / "truncated.llsp3", full_text[: len(full_text) // 2])

        cls.paths["missing"] = cls.tmp / "nao-existe.llsp3"

        script = (
            "$paths = $env:SPIKE_TEST_PATHS | ConvertFrom-Json; $out = [ordered]@{}; "
            "foreach ($p in $paths.PSObject.Properties) { $out[$p.Name] = Get-SpikeProjectMetrics -ProjectPath $p.Value }; "
            "$prev = $out['known']; $out['with_previous'] = Get-SpikeProjectMetrics -ProjectPath $paths.wait_until -PreviousMetrics $prev; "
            "ConvertTo-Json -InputObject $out -Depth 8"
        )
        cls.raw_metrics = cls.run_ps(script, {"SPIKE_TEST_PATHS": json.dumps({k: str(v) for k, v in cls.paths.items()})})
        cls.metrics = json.loads(cls.raw_metrics)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    @classmethod
    def run_ps(cls, script: str, env: dict | None = None) -> str:
        full_env = {**os.environ, "PULSELAB_SPIKE_DIR": str(cls.spike_dir), **(env or {})}
        command = f". '{PARSER}'; {script}"
        proc = subprocess.run([PWSH, "-NoProfile", "-NonInteractive", "-Command", command],
                              capture_output=True, text=True, env=full_env, timeout=120)
        if proc.returncode != 0:
            raise AssertionError(f"pwsh falhou: {proc.stderr}")
        return proc.stdout

    def assert_private(self, text: str):
        self.assertNotIn("JOAO", text)
        self.assertNotIn("MARIA", text)
        self.assertNotIn(str(self.tmp), text)
        self.assertNotIn(self.tmp.name, text)
        self.assertNotIn("velocidade", text)

    def test_counts_and_flags(self):
        m = self.metrics["known"]
        self.assertEqual(m["spike_status"], "ok")
        self.assertTrue(m["project_saved"])
        self.assertEqual(m["format"], "llsp3")
        self.assertEqual(m["language"], "word-blocks")
        self.assertEqual(m["executable_blocks"], 22)
        self.assertEqual(m["total_blocks"], 29)  # 22 + 7 sombras
        self.assertEqual(m["top_level_stacks"], 4)
        for flag in ("uses_motor", "uses_sensor", "uses_loop", "uses_condition", "uses_variable", "uses_procedure"):
            self.assertTrue(m[flag], flag)
        self.assertEqual(m["inferred_stage"], "integrated_mission")
        self.assertEqual(m["opcode_counts"]["procedures_call"], 2)
        self.assertEqual(m["opcode_counts"]["flipperevents_whenProgramStarts"], 2)
        self.assertNotIn("text", m["opcode_counts"])  # sombras ficam fora
        self.assertEqual(list(m["opcode_counts"]), sorted(m["opcode_counts"]))
        self.assertEqual(m["ct_score_version"], "drscratch-adaptado-spike-v0")

    def test_wait_until_is_condition_not_loop(self):
        m = self.metrics["wait_until"]
        self.assertFalse(m["uses_loop"])
        self.assertTrue(m["uses_condition"])
        self.assertTrue(m["uses_motor"])
        self.assertTrue(m["uses_sensor"])
        ct = m["ct_score"]
        self.assertEqual(ct["flow_control"], 1)
        self.assertEqual(ct["synchronization"], 3)
        self.assertEqual(ct["user_interactivity"], 2)
        self.assertEqual(ct["parallelism"], 0)
        self.assertEqual(ct["abstraction"], 0)

    def test_ct_score_known_fixture(self):
        self.assertEqual(self.metrics["known"]["ct_score"], {
            "flow_control": 2,
            "logic": 3,
            "synchronization": 3,
            "parallelism": 1,
            "user_interactivity": 2,
            "data_representation": 3,
            "abstraction": 3,
            "total": 17,
        })

    def test_ct_score_sensor_hats_and_parallelism(self):
        ct = self.metrics["sensor_hats"]["ct_score"]
        self.assertEqual(ct["parallelism"], 3)
        self.assertEqual(ct["user_interactivity"], 3)
        self.assertEqual(ct["flow_control"], 3)
        self.assertEqual(ct["synchronization"], 3)
        self.assertEqual(ct["abstraction"], 1)
        self.assertEqual(ct["data_representation"], 0)

    def test_structure_hash(self):
        known = self.metrics["known"]["structure_hash"]
        self.assertRegex(known, r"^[0-9a-f]{64}$")
        self.assertEqual(self.metrics["cosmetic"]["structure_hash"], known)
        self.assertEqual(self.metrics["cosmetic"]["executable_blocks"], 22)
        self.assertNotEqual(self.metrics["reordered"]["structure_hash"], known)
        self.assertNotEqual(self.metrics["swapped"]["structure_hash"], known)
        self.assertNotEqual(self.metrics["reordered"]["structure_hash"], self.metrics["swapped"]["structure_hash"])
        self.assertEqual(self.metrics["reordered"]["opcode_counts"], self.metrics["known"]["opcode_counts"])

    def test_empty_project(self):
        m = self.metrics["empty"]
        self.assertEqual(m["spike_status"], "ok")
        self.assertEqual(m["executable_blocks"], 0)
        self.assertIsNone(m["structure_hash"])
        self.assertEqual(m["ct_score"]["total"], 0)
        self.assertEqual(m["inferred_stage"], "empty")

    def test_python_project(self):
        m = self.metrics["python"]
        self.assertEqual(m["spike_status"], "python")
        self.assertTrue(m["project_saved"])
        self.assertEqual(m["language"], "python")
        self.assertEqual(m["executable_blocks"], 0)
        for flag in ("uses_motor", "uses_sensor", "uses_loop", "uses_condition", "uses_variable", "uses_procedure"):
            self.assertFalse(m[flag], flag)
        self.assertNotEqual(m["inferred_stage"], "initial_setup")

    def test_error_statuses(self):
        self.assertEqual(self.metrics["corrupt"]["spike_status"], "arquivo_invalido")
        self.assertFalse(self.metrics["corrupt"]["project_saved"])
        self.assertEqual(self.metrics["truncated"]["spike_status"], "arquivo_invalido")
        self.assertEqual(self.metrics["missing"]["spike_status"], "sem_projeto")
        self.assertEqual(self.metrics["missing"]["error"], "project_not_found")

    def test_previous_metrics_delta(self):
        m = self.metrics["with_previous"]
        self.assertEqual(m["blocks_removed_since_previous"], 22 - 5)
        self.assertEqual(m["blocks_added_since_previous"], 0)

    def test_output_never_leaks_text_or_paths(self):
        self.assert_private(self.raw_metrics)

    def test_project_directories_and_files(self):
        out = self.run_ps("ConvertTo-Json -InputObject @(Get-SpikeProjectDirectories) -Compress")
        self.assertEqual([Path(p).resolve() for p in json.loads(out)], [self.spike_dir.resolve()])

        (self.spike_dir / "sub").mkdir()
        older = write_llsp3(self.spike_dir / "sub" / "antigo.llsp", json.dumps(project_json({})))
        (self.spike_dir / "ignorar.txt").write_text("x")
        now = time.time()
        os.utime(older, (now - 7200, now - 7200))
        os.utime(self.paths["known"], (now - 60, now - 60))
        try:
            script = (
                "$all = @(Get-SpikeProjectFiles | ForEach-Object { $_.Name }); "
                "$cut = [DateTime]::UtcNow.AddHours(-1); "
                "$recent = @(Get-SpikeProjectFiles -MinLastWriteTime $cut | ForEach-Object { $_.Name }); "
                "$latest = Split-Path -Leaf (Find-LatestSpikeProject); "
                "$exact = @(Get-SpikeProjectFiles -MinLastWriteTime (Get-Item -LiteralPath $env:KNOWN).LastWriteTimeUtc); "
                "ConvertTo-Json -Compress -InputObject ([ordered]@{ all = $all; recent = $recent; latest = $latest; exact = $exact.Count })"
            )
            result = json.loads(self.run_ps(script, {"KNOWN": str(self.paths["known"])}))
            self.assertEqual(result["all"], ["missao JOAO.llsp3", "antigo.llsp"])
            self.assertEqual(result["recent"], ["missao JOAO.llsp3"])
            self.assertEqual(result["latest"], "missao JOAO.llsp3")
            self.assertEqual(result["exact"], 0)  # MinLastWriteTime é exclusivo

            status_raw = self.run_ps("ConvertTo-Json -InputObject (Get-SpikeEnvironmentStatus) -Compress",
                                     {"OneDrive": ""})
            status = json.loads(status_raw)
            self.assertEqual(list(status), ["status", "directories_found", "onedrive_documents", "project_count",
                                            "newest_project_utc"])
            self.assertEqual(status["status"], "ok")
            self.assertEqual(status["directories_found"], 1)
            self.assertIs(status["onedrive_documents"], False)
            self.assertEqual(status["project_count"], 2)
            self.assertTrue(status["newest_project_utc"])
            self.assert_private(status_raw)

            missing_raw = self.run_ps("ConvertTo-Json -InputObject (Get-SpikeEnvironmentStatus) -Compress",
                                      {"PULSELAB_SPIKE_DIR": str(self.tmp / "nao-existe")})
            missing = json.loads(missing_raw)
            self.assertEqual(missing["status"], "pasta_nao_encontrada")
            self.assertEqual(missing["directories_found"], 0)
            self.assertEqual(missing["project_count"], 0)
            self.assertIsNone(missing["newest_project_utc"])
        finally:
            shutil.rmtree(self.spike_dir / "sub", ignore_errors=True)
            (self.spike_dir / "ignorar.txt").unlink(missing_ok=True)

    def test_mission_coverage(self):
        script = (
            "$m = Get-SpikeProjectMetrics -ProjectPath $env:WAIT; "
            "$mission = [pscustomobject]@{ mission_id = 'M03'; criteria = [pscustomobject]@{ "
            "uses_motor = $true; uses_sensor = $true; uses_loop = $true; uses_condition = $false; "
            "min_executable_blocks = 10; required_opcodes = @('flippersensors_isColor', 'flippersensors_isDistance') } }; "
            "$empty = [pscustomobject]@{ mission_id = 'M00'; criteria = [pscustomobject]@{ uses_loop = $false } }; "
            "$json = $m | ConvertTo-Json -Depth 8 | ConvertFrom-Json; "
            "ConvertTo-Json -Depth 6 -Compress -InputObject ([ordered]@{ "
            "a = (Measure-SpikeMissionCoverage -Metrics $m -Mission $mission); "
            "b = (Measure-SpikeMissionCoverage -Metrics $json -Mission $mission); "
            "c = (Measure-SpikeMissionCoverage -Metrics $m -Mission $empty) })"
        )
        result = json.loads(self.run_ps(script, {"WAIT": str(self.paths["wait_until"])}))
        expected = {
            "mission_id": "M03",
            "criteria_total": 6,
            "criteria_met": 3,
            "coverage": 0.5,
            "missing": ["uses_loop", "min_executable_blocks", "opcode:flippersensors_isDistance"],
        }
        self.assertEqual(result["a"], expected)
        self.assertEqual(result["b"], expected)  # métricas já serializadas em JSON
        self.assertEqual(result["c"], {"mission_id": "M00", "criteria_total": 0, "criteria_met": 0,
                                       "coverage": None, "missing": []})

    def test_resolve_mission(self):
        catalog = {"missoes": [
            {"mission_id": "M01", "titulo": "Andar reto", "criterios": {"uses_motor": True, "min_executable_blocks": 3}},
            {"mission_id": "M02", "titulo": "Parar na linha",
             "criterios": {"usa_sensor": True, "usa_condicao": "true", "opcodes_obrigatorios": ["flippersensors_isColor"]}},
        ]}
        calendar = [{"data": "2026-10-13", "mission_id": "M01"}, {"data": "2026-10-14", "mission_id": "M02"}]
        script = (
            "$cat = $env:CAT | ConvertFrom-Json; $cal = $env:CAL | ConvertFrom-Json; "
            "$hit = Resolve-SpikeMission -Catalog $cat -Calendar $cal -Date (Get-Date -Year 2026 -Month 10 -Day 14 -Hour 23 -Minute 30); "
            "$miss = Resolve-SpikeMission -Catalog $cat -Calendar $cal -Date (Get-Date -Year 2026 -Month 10 -Day 15); "
            "$m = Get-SpikeProjectMetrics -ProjectPath $env:WAIT; "
            "ConvertTo-Json -Depth 6 -Compress -InputObject ([ordered]@{ hit = $hit; miss = $miss; "
            "cov = (Measure-SpikeMissionCoverage -Metrics $m -Mission $hit) })"
        )
        result = json.loads(self.run_ps(script, {"CAT": json.dumps(catalog), "CAL": json.dumps(calendar),
                                                 "WAIT": str(self.paths["wait_until"])}))
        self.assertIsNone(result["miss"])
        hit = result["hit"]
        self.assertEqual(hit["mission_id"], "M02")
        self.assertEqual(hit["titulo"], "Parar na linha")
        self.assertEqual(hit["criteria"], {
            "uses_motor": False, "uses_sensor": True, "uses_loop": False, "uses_condition": True,
            "min_executable_blocks": 0, "required_opcodes": ["flippersensors_isColor"],
        })
        self.assertEqual(result["cov"]["coverage"], 1.0)
        self.assertEqual(result["cov"]["criteria_total"], 3)


class SpikeParserSourceTest(unittest.TestCase):
    def test_crlf_and_no_ps7_only_syntax(self):
        raw = PARSER.read_bytes()
        self.assertNotIn(b"\n", raw.replace(b"\r\n", b""), "spike-parser.ps1 precisa de CRLF")
        text = raw.decode("utf-8")
        code = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))
        for token in ("??", "?.", "-Parallel", "using namespace", "&&", "||"):
            self.assertNotIn(token, code, token)


if __name__ == "__main__":
    unittest.main()
