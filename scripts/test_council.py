#!/usr/bin/env python3
"""
Testes unitários automatizados para o LLM Council do PulseLab (scripts/council.py).
Valida:
1. Parsing de ranking a partir de texto (inglês, português, formatações ricas com markdown).
2. Cálculo de ranking agregado (média aritmética dos postos / método ordinal).
3. Anonimização e mapeamento de identificadores (Response A, B, C...).
4. Estrutura do modo persona offline e geração do parecer do Chairman.
5. Salvamento e formatação de logs de deliberação em Markdown.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "council",
    Path(__file__).resolve().parent / "council.py",
)
council = importlib.util.module_from_spec(spec)
spec.loader.exec_module(council)


class TestCouncilLogic(unittest.TestCase):
    def test_parse_ranking_standard_english(self):
        sample = """
        Response A has good points but lacks detail.
        Response B is very thorough and safe.
        Response C is too complex.

        FINAL RANKING:
        1. Response B
        2. Response A
        3. Response C
        """
        parsed = council.parse_ranking_from_text(sample)
        self.assertEqual(parsed, ["Response B", "Response A", "Response C"])

    def test_parse_ranking_portuguese_and_markdown(self):
        sample = """
        Avaliação crítica:
        A proposta A atende perfeitamente ao isolamento do loopback.
        A proposta B tem risco de quebra no Windows.

        **RANKING FINAL:**
        1. **Resposta A**
        2. **Resposta B**
        """
        parsed = council.parse_ranking_from_text(sample)
        self.assertEqual(parsed, ["Response A", "Response B"])

    def test_parse_ranking_fallback_without_header(self):
        sample = "Prefiro Response C sobre Response A e por último Response B."
        parsed = council.parse_ranking_from_text(sample)
        self.assertEqual(parsed, ["Response C", "Response A", "Response B"])

    def test_calculate_aggregate_rankings_math(self):
        label_to_model = {
            "Response A": "Model-Alpha",
            "Response B": "Model-Beta",
            "Response C": "Model-Gamma",
        }
        stage2_results = [
            {"model": "Model-Alpha", "parsed_ranking": ["Response B", "Response A", "Response C"]},
            {"model": "Model-Beta", "parsed_ranking": ["Response B", "Response C", "Response A"]},
            {"model": "Model-Gamma", "parsed_ranking": ["Response A", "Response B", "Response C"]},
        ]
        # Posições de B: 1 (por Alpha) + 1 (por Beta) + 2 (por Gamma) = 4 / 3 = 1.33
        # Posições de A: 2 (por Alpha) + 3 (por Beta) + 1 (por Gamma) = 6 / 3 = 2.00
        # Posições de C: 3 (por Alpha) + 2 (por Beta) + 3 (por Gamma) = 8 / 3 = 2.67

        aggregate = council.calculate_aggregate_rankings(stage2_results, label_to_model)

        self.assertEqual(len(aggregate), 3)
        self.assertEqual(aggregate[0]["model"], "Model-Beta")
        self.assertAlmostEqual(aggregate[0]["average_rank"], 1.33, places=2)
        self.assertEqual(aggregate[1]["model"], "Model-Alpha")
        self.assertAlmostEqual(aggregate[1]["average_rank"], 2.00, places=2)
        self.assertEqual(aggregate[2]["model"], "Model-Gamma")
        self.assertAlmostEqual(aggregate[2]["average_rank"], 2.67, places=2)

    def test_offline_persona_council_execution(self):
        query = "Como tratar a exclusão definitiva de dados de bancada?"
        res = council.run_offline_persona_council(query)

        self.assertIn("stage1", res)
        self.assertIn("stage2", res)
        self.assertIn("stage3", res)
        self.assertIn("aggregate_rankings", res)
        self.assertIn("label_to_model", res)

        self.assertEqual(len(res["stage1"]), 3)
        self.assertEqual(len(res["stage2"]), 3)
        self.assertTrue(len(res["aggregate_rankings"]) > 0)
        self.assertIn("Presidente", res["stage3"]["model"])
        self.assertIn("Veredito", res["stage3"]["response"])

    def test_save_council_log_file(self):
        with tempfile.TemporaryDirectory() as tmp_dir:
            out_file = Path(tmp_dir) / "test-council-report.md"
            label_to_model = {"Response A": "M1", "Response B": "M2"}
            stage1 = [{"model": "M1", "response": "Resp 1"}, {"model": "M2", "response": "Resp 2"}]
            stage2 = [{"model": "M1", "ranking": "FINAL RANKING:\n1. Response B", "parsed_ranking": ["Response B"]}]
            stage3 = {"model": "Chairman", "response": "Parecer conclusivo"}
            agg = [{"model": "M2", "average_rank": 1.0, "rankings_count": 1}]

            saved = council.save_council_log(
                "Teste de log", stage1, stage2, stage3, agg, label_to_model, out_file
            )

            self.assertTrue(saved.is_file())
            content = saved.read_text(encoding="utf-8")
            self.assertIn("# Relatório de Deliberação do LLM Council (PulseLab)", content)
            self.assertIn("Parecer conclusivo", content)
            self.assertIn("M2", content)


if __name__ == "__main__":
    unittest.main()
