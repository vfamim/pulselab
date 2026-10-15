#!/usr/bin/env python3
"""
Testes do relatório automático (tooling/data/relatorio-pulselab.py).

O SQLite sintético é montado pelo próprio importador (--no-cloud) a partir de uma coleta no
formato do bridge (sessoes/*.json, events.jsonl e manifesto), para usar o mesmo esquema.
"""

from __future__ import annotations

import contextlib
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch

import importlib.util

ROOT = Path(__file__).resolve().parents[2]


def _load(name: str, rel: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


rel = _load("relatorio_pulselab", "tooling/data/relatorio-pulselab.py")
imp = rel.imp

INST_A = "11111111-1111-4111-8111-111111111111"
INST_B = "22222222-2222-4222-8222-222222222222"
INST_C = "33333333-3333-4333-8333-333333333333"
S1 = "a1000000-0000-4000-8000-000000000001"  # PET, PC01, segunda 05/10, boa
S2 = "a1000000-0000-4000-8000-000000000002"  # PET, PC02, terça 06/10, interrompida e sem programa
S3 = "a1000000-0000-4000-8000-000000000003"  # JUA, PC01, 13/10, em andamento (só no pendrive)
S4 = "a1000000-0000-4000-8000-000000000004"  # PET, PC01, retirada
S5 = "a1000000-0000-4000-8000-000000000005"  # PET, PC01, 07/10, também na nuvem
NOME_CRIANCA = "Joaozinho da Silva"
HOJE = "2026-10-15"


def snapshot(sid, inst, label, site, started, completed=None, *, ended_by="instrutor", interrupted=False,
             telemetry=(), dq_extra=None, start_mode="atividade_spike"):
    """Snapshot como New-BridgeSnapshot/Close-BridgeSession grava em sessoes/sessao_<id>.json."""
    timeline = [{"event_type": "session_started", "details": {"start_mode": start_mode}}]
    for det in telemetry:
        timeline.append({"event_type": "spike_telemetry", "details": det})
    data = {
        "session_id": sid, "group_id": "b" + sid[1:], "installation_id": inst, "computer_id": label,
        "site_id": site, "regional_hub": "R", "school_code": "ESC-" + site, "workshop_code": "OF", "class_code": "T",
        "activity_id": "ACT", "protocol_version": "v2.4", "instrument_version": "bancada-2.4.0",
        "client_version": "bridge/3.0.9", "start_mode": start_mode, "started_at": started, "group_size": 4,
        "status": "completed" if completed else "in_progress", "phase": "completed" if completed else "in_progress",
        "timeline": timeline,
        # Campo de texto livre que nunca pode aparecer no relatório
        "free_feedback": NOME_CRIANCA,
    }
    if completed:
        dq = {"heartbeat_count": 10, "max_heartbeat_gap_min": 1.5, "bridge_restarts": 0, "corrupted_lines": 0,
              "spike_status": "ok", "telemetry_events": len(telemetry), "last_activity_at": completed}
        dq.update(dq_extra or {})
        data.update({"completed_at": completed, "ended_by": ended_by, "interrupted": interrupted, "data_quality": dq})
        start = rel.parse_iso(started)
        end = rel.parse_iso(completed)
        data["duration_seconds"] = int((end - start).total_seconds())
    return data


def evento(sid, inst, site, tipo, quando, details):
    """Linha de events.jsonl como Add-BridgeSessionEvent grava."""
    return {
        "event_id": hashlib.sha256(f"{sid}{tipo}{quando}".encode()).hexdigest()[:8] + "-0000-4000-8000-000000000000",
        "session_id": sid, "dyad_id": "b" + sid[1:], "group_id": "b" + sid[1:], "installation_id": inst,
        "site_id": site, "event_type": tipo, "occurred_at": quando, "client_version": "bridge/3.0.9",
        "details": details, "_target_table": "research_session_events",
    }


def telemetria(blocos, motor, sensor, laco, cond, ct, status="ok"):
    return {"executable_blocks": blocos, "uses_motor": motor, "uses_sensor": sensor, "uses_loop": laco,
            "uses_condition": cond, "ct_score": {"total": ct}, "spike_status": status,
            "opcode_counts": {"flipperevents_whenProgramStarts": 1}}


def ler_csv(path: Path) -> list[dict]:
    with path.open(encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f, delimiter=";"))


class TestRelatorio(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.sqlite = self.root / "consolidado.sqlite"
        self.saida = self.root / "saida"
        self._montar_sqlite()

    def tearDown(self):
        self.tmp.cleanup()

    def _montar_sqlite(self):
        t1a = telemetria(3, False, False, False, False, 2)
        t1b = telemetria(12, True, True, True, False, 7)
        t5 = telemetria(8, True, False, True, True, 5)
        sessoes = [
            snapshot(S1, INST_A, "PET-LAB1-PC01", "PET", "2026-10-05T11:00:00.000Z", "2026-10-05T11:50:00.000Z", telemetry=[t1a, t1b]),
            snapshot(S2, INST_B, "PET-LAB1-PC02", "PET", "2026-10-06T11:00:00.000Z", "2026-10-06T11:30:00.000Z",
                     ended_by="sem_encerramento", interrupted=True, dq_extra={"bridge_restarts": 1, "spike_status": "pasta_nao_encontrada"}),
            snapshot(S3, INST_C, "JUA-PC01", "JUA", "2026-10-13T12:00:00.000Z"),
            snapshot(S4, INST_A, "PET-LAB1-PC01", "PET", "2026-10-08T11:00:00.000Z", "2026-10-08T11:40:00.000Z", telemetry=[t1a]),
            snapshot(S5, INST_A, "PET-LAB1-PC01", "PET", "2026-10-07T11:00:00.000Z", "2026-10-07T12:10:00.000Z", telemetry=[t5]),
        ]
        eventos = [
            evento(S1, INST_A, "PET", "session_started", "2026-10-05T11:00:00.000Z", {"start_mode": "atividade_spike", "instrument_version": "bancada-2.4.0"}),
            evento(S1, INST_A, "PET", "spike_telemetry", "2026-10-05T11:10:00.000Z", t1a),
            evento(S1, INST_A, "PET", "spike_telemetry", "2026-10-05T11:40:00.000Z", t1b),
            evento(S1, INST_A, "PET", "heartbeat", "2026-10-05T11:45:00.000Z", {"spike_status": "ok"}),
            evento(S2, INST_B, "PET", "heartbeat", "2026-10-06T11:05:00.000Z", {"spike_status": "ok"}),
            evento(S3, INST_C, "JUA", "session_started", "2026-10-13T12:00:00.000Z", {"start_mode": "abertura_app"}),
            evento(S3, INST_C, "JUA", "spike_telemetry", "2026-10-13T12:20:00.000Z", telemetria(4, True, False, False, False, 1)),
            evento(S5, INST_A, "PET", "spike_telemetry", "2026-10-07T11:30:00.000Z", t5),
        ]
        files = {f"sessoes/sessao_{s['session_id']}.json": json.dumps(s).encode() for s in sessoes}
        files["events.jsonl"] = "\n".join(json.dumps(e) for e in eventos).encode()
        files["sessions_withdrawn.txt"] = f"{S4}\n".encode()
        folder = self.root / "coletas" / "Coleta_PET_20261014_120000"
        linhas = []
        for nome, conteudo in files.items():
            path = folder / nome
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(conteudo)
            linhas.append(f"{hashlib.sha256(conteudo).hexdigest().upper()}  {nome}")
        (folder / "manifesto_coleta.txt").write_text("INTEGRIDADE DOS ARQUIVOS (SHA-256):\n\n" + "\n".join(linhas) + "\n", encoding="utf-8")

        argv = ["importar", "--no-cloud", "--source", str(self.root / "coletas"), "--sqlite-path", str(self.sqlite)]
        with patch.object(imp, "__file__", str(self.root / "tooling" / "data" / "importar-para-supabase.py")), \
                patch.object(sys, "argv", argv), patch.dict(os.environ, {"PULSELAB_MANIFEST_HMAC_KEY": ""}), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(imp.main(), 0)
        # S4 é retirada na coleta; a mesma sessão aparece depois num SQLite antigo e não pode voltar.
        conn = sqlite3.connect(str(self.sqlite))
        with conn:
            conn.execute("INSERT INTO sessions (session_id, site_id, started_at, status) VALUES (?, 'PET', '2026-10-08T11:00:00Z', 'completed')", (S4,))
        conn.close()

    def rodar(self, *extra, env=None):
        argv = ["--sqlite", str(self.sqlite), "--saida", str(self.saida), "--hoje", HOJE, *extra]
        out = io.StringIO()
        sem_rede = MagicMock(side_effect=AssertionError("acesso à rede não esperado"))
        with patch.dict(os.environ, env or {}, clear=False), patch("urllib.request.urlopen", sem_rede), \
                contextlib.redirect_stdout(out):
            for var in ("PULSELAB_SERVICE_ROLE_KEY", "PULSELAB_OPERATIONAL_JWT"):
                if not env or var not in env:
                    os.environ.pop(var, None)
            code = rel.main(argv)
        return code, out.getvalue(), sem_rede

    # --- SQLite do importador -------------------------------------------------

    def test_importador_grava_identificacao_da_maquina(self):
        conn = sqlite3.connect(str(self.sqlite))
        row = conn.execute(
            "SELECT installation_id, machine_label, start_mode, client_version, instrument_version FROM sessions WHERE session_id = ?", (S1,)
        ).fetchone()
        conn.close()
        self.assertEqual(row, (INST_A, "PET-LAB1-PC01", "atividade_spike", "bridge/3.0.9", "bancada-2.4.0"))

    # --- aulas.csv --------------------------------------------------------------

    def test_aulas_csv_uma_linha_por_aula_sem_rede(self):
        code, out, sem_rede = self.rodar()
        self.assertEqual(code, 0, out)
        sem_rede.assert_not_called()
        aulas = ler_csv(self.saida / "aulas.csv")
        self.assertEqual(list(aulas[0].keys()), rel.COLUNAS_AULAS)
        self.assertEqual([a["session_id"] for a in aulas], [S1, S2, S5, S3], "S4 retirada fica de fora")

        a1 = aulas[0]
        self.assertEqual(
            (a1["polo"], a1["escola"], a1["maquina"], a1["installation_id"], a1["data_local"], a1["hora_inicio"], a1["hora_fim"]),
            ("PET", "ESC-PET", "PET-LAB1-PC01", INST_A, "2026-10-05", "08:00", "08:50"),
        )
        self.assertEqual((a1["duracao_min"], a1["encerrada_por"], a1["interrompida"], a1["fase"], a1["modo_inicio"]),
                         ("50,0", "instrutor", "não", "completed", "atividade_spike"))
        self.assertEqual(
            (a1["versoes_programa"], a1["blocos_executaveis"], a1["usa_motor"], a1["usa_sensor"], a1["usa_laco"], a1["usa_condicao"], a1["ct_score"], a1["spike_status"]),
            ("2", "12", "sim", "sim", "sim", "não", "7,0", "ok"),
        )
        self.assertEqual((a1["client_version"], a1["instrument_version"], a1["origem"], a1["qualidade"], a1["motivo_qualidade"]),
                         ("bridge/3.0.9", "bancada-2.4.0", "pendrive", "boa", ""))

        a2 = aulas[1]
        self.assertEqual((a2["versoes_programa"], a2["blocos_executaveis"], a2["reinicios"], a2["qualidade"]), ("0", "", "1", "ruim"))
        self.assertEqual(a2["motivo_qualidade"], "interrompida; nenhum programa salvo; problema no SPIKE (pasta_nao_encontrada)")

        a3 = aulas[3]
        self.assertEqual((a3["fase"], a3["hora_fim"], a3["duracao_min"], a3["versoes_programa"], a3["blocos_executaveis"], a3["modo_inicio"]),
                         ("in_progress", "", "", "1", "4", "atividade_spike"))
        self.assertEqual(a3["motivo_qualidade"], "aula não encerrada")

    def test_nenhum_texto_livre_nem_nome(self):
        self.rodar()
        for nome in ("aulas.csv", "resumo-polos.csv", "maquinas-sem-envio.csv", "relatorio.md"):
            self.assertNotIn(NOME_CRIANCA, (self.saida / nome).read_text(encoding="utf-8-sig"), nome)

    def test_filtros_de_periodo_e_polo(self):
        self.rodar("--de", "2026-10-06", "--ate", "2026-10-07", "--polo", "pet")
        self.assertEqual([a["session_id"] for a in ler_csv(self.saida / "aulas.csv")], [S2, S5])
        maquinas = ler_csv(self.saida / "maquinas-sem-envio.csv")
        self.assertEqual({m["polo"] for m in maquinas}, {"PET"})

    # --- deduplicação -----------------------------------------------------------

    def test_juntar_nao_duplica_e_prefere_aula_encerrada(self):
        pendrive, _ = rel.ler_sqlite(self.sqlite)
        nuvem_s5 = rel.aula_da_nuvem({
            "session_id": S5.upper(), "polo": "PET", "escola": "ESC-PET", "maquina": None, "installation_id": INST_A,
            "data_local": "2026-10-07", "hora_inicio": "08:00", "hora_fim": "09:10", "inicio_em": "2026-10-07T11:00:00+00:00",
            "duracao_min": 70.0, "encerrada_por": "instrutor", "interrompida": False, "fase": "completed",
            "versoes_programa": 1, "blocos_executaveis": 8, "ct_score": 5, "ambiente": "production", "origem": "nuvem",
        })
        nuvem_s3 = rel.aula_da_nuvem({
            "session_id": S3, "polo": "JUA", "installation_id": INST_C, "data_local": "2026-10-13", "fase": "in_progress",
            "inicio_em": "2026-10-13T12:00:00+00:00", "origem": "nuvem",
        })
        aulas = rel.juntar_aulas([nuvem_s5, nuvem_s3], pendrive, retiradas={S4})
        ids = [a["session_id"] for a in aulas]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(sorted(ids), sorted([S1, S2, S3, S5]))
        s5 = next(a for a in aulas if a["session_id"] == S5)
        self.assertEqual((s5["origem"], s5["maquina"], s5["duracao_min"]), ("nuvem+pendrive", "PET-LAB1-PC01", 70.0))
        s3 = next(a for a in aulas if a["session_id"] == S3)
        self.assertEqual((s3["origem"], s3["blocos_executaveis"]), ("nuvem+pendrive", 4))

        # Pendrive encerrado prevalece sobre nuvem ainda em andamento
        nuvem_aberta = dict(nuvem_s5, fase="in_progress", duracao_min=None, encerrada_por=None)
        s5b = next(a for a in rel.juntar_aulas([nuvem_aberta], pendrive) if a["session_id"] == S5)
        self.assertEqual((s5b["fase"], s5b["encerrada_por"], s5b["duracao_min"]), ("completed", "instrutor", 70.0))

    def test_nuvem_e_pendrive_juntos_pelo_main(self):
        view = [{
            "session_id": S5, "polo": "PET", "escola": "ESC-PET", "maquina": "PET-LAB1-PC01", "installation_id": INST_A,
            "data_local": "2026-10-07", "hora_inicio": "08:00", "hora_fim": "09:10", "inicio_em": "2026-10-07T11:00:00+00:00",
            "fim_em": "2026-10-07T12:10:00+00:00", "duracao_min": 70.0, "encerrada_por": "instrutor", "interrompida": False,
            "fase": "completed", "versoes_programa": 1, "blocos_executaveis": 8, "ct_score": 5, "spike_status": "ok",
            "ambiente": "production", "origem": "nuvem",
        }, {
            "session_id": "a1000000-0000-4000-8000-0000000000ff", "polo": "PET", "data_local": "2026-10-07",
            "inicio_em": "2026-10-07T11:00:00+00:00", "fase": "completed", "ambiente": "test", "origem": "nuvem",
        }]
        last_seen = [
            {"installation_id": INST_A, "site_id": "PET", "last_received_at": "2026-10-14T12:00:00+00:00",
             "last_occurred_at": "2026-10-07T12:10:00+00:00", "days_since_last_received": 1, "sessions_last_30d": 3},
            {"installation_id": "44444444-4444-4444-8444-444444444444", "site_id": "PET", "last_received_at": None,
             "last_occurred_at": None, "days_since_last_received": None, "sessions_last_30d": 0},
        ]
        chave = "chave-secreta-de-teste"
        pedidos = []

        def responder(req, timeout=None):
            pedidos.append(req)
            corpo = view if "research_aula_bancada" in req.full_url else last_seen
            resp = MagicMock()
            resp.read.return_value = json.dumps(corpo).encode()
            resp.__enter__.return_value = resp
            return resp

        out = io.StringIO()
        with patch.dict(os.environ, {"PULSELAB_OPERATIONAL_JWT": chave, "PULSELAB_SUPABASE_URL": "https://exemplo.supabase.co"}), \
                patch("urllib.request.urlopen", side_effect=responder), contextlib.redirect_stdout(out):
            os.environ.pop("PULSELAB_SERVICE_ROLE_KEY", None)
            code = rel.main(["--sqlite", str(self.sqlite), "--saida", str(self.saida), "--hoje", HOJE])
        self.assertEqual(code, 0, out.getvalue())
        self.assertNotIn(chave, out.getvalue())
        self.assertEqual(pedidos[0].get_header("Authorization"), f"Bearer {chave}")
        self.assertEqual(pedidos[0].get_header("Apikey"), imp.DEFAULT_SUPABASE_ANON_KEY)

        aulas = ler_csv(self.saida / "aulas.csv")
        self.assertEqual([a["session_id"] for a in aulas], [S1, S2, S5, S3], "sessão de teste e duplicata fora")
        self.assertEqual(next(a for a in aulas if a["session_id"] == S5)["origem"], "nuvem+pendrive")

        maquinas = {m["installation_id"]: m for m in ler_csv(self.saida / "maquinas-sem-envio.csv")}
        self.assertEqual(maquinas[INST_A]["ultimo_envio_nuvem"], "2026-10-14 09:00")
        self.assertEqual((maquinas[INST_A]["dias_sem_dados"], maquinas[INST_A]["situacao"]), ("1", "ok"))
        self.assertEqual(maquinas["44444444-4444-4444-8444-444444444444"]["situacao"], "nunca enviou dados")
        md = (self.saida / "relatorio.md").read_text(encoding="utf-8")
        self.assertIn("nuvem (Supabase)", md)

    # --- resumo e máquinas -----------------------------------------------------

    def test_resumo_por_polo_e_semana(self):
        self.rodar()
        resumo = ler_csv(self.saida / "resumo-polos.csv")
        self.assertEqual(list(resumo[0].keys()), rel.COLUNAS_RESUMO)
        pet = next(r for r in resumo if r["polo"] == "PET")
        self.assertEqual(
            (pet["semana_inicio"], pet["aulas"], pet["maquinas"], pet["duracao_mediana_min"],
             pet["pct_encerradas_instrutor"], pet["pct_interrompidas"], pet["pct_sem_spike"]),
            ("2026-10-05", "3", "2", "50,0", "66,7", "33,3", "33,3"),
        )
        jua = next(r for r in resumo if r["polo"] == "JUA")
        self.assertEqual((jua["semana_inicio"], jua["aulas"], jua["duracao_mediana_min"]), ("2026-10-12", "1", ""))

    def test_maquinas_sem_dados_do_sqlite(self):
        self.rodar()
        maquinas = ler_csv(self.saida / "maquinas-sem-envio.csv")
        self.assertEqual(list(maquinas[0].keys()), rel.COLUNAS_MAQUINAS)
        self.assertEqual([m["maquina"] for m in maquinas], ["PET-LAB1-PC02", "PET-LAB1-PC01", "JUA-PC01"])
        pc02 = maquinas[0]
        self.assertEqual((pc02["ultima_aula_pendrive"], pc02["dias_sem_dados"], pc02["situacao"]),
                         ("2026-10-06", "9", "sem dados há mais de 7 dias"))
        self.assertEqual((maquinas[1]["dias_sem_dados"], maquinas[1]["situacao"]), ("8", "sem dados há mais de 7 dias"))
        self.assertEqual((maquinas[2]["dias_sem_dados"], maquinas[2]["situacao"]), ("2", "ok"))

    # --- relatorio.md ------------------------------------------------------------

    def test_markdown_legivel_com_atencao(self):
        self.rodar()
        md = (self.saida / "relatorio.md").read_text(encoding="utf-8")
        self.assertIn("# Relatório PulseLab — 15/10/2026", md)
        self.assertIn("**4** aulas de bancada em **2** polo(s) e **3** máquina(s)", md)
        atencao = md.split("## Atenção", 1)[1].split("## Resumo semanal", 1)[0]
        self.assertIn("| PET | PET-LAB1-PC02 | 06/10/2026 | 9 | sem dados há mais de 7 dias |", atencao)
        self.assertNotIn("JUA-PC01 | 13/10/2026", atencao)
        self.assertIn("| 06/10/2026 | 08:00 | PET | PET-LAB1-PC02 | interrompida; nenhum programa salvo; problema no SPIKE (pasta_nao_encontrada) |", atencao)
        self.assertIn("| 13/10/2026 | 09:00 | JUA | JUA-PC01 | aula não encerrada |", atencao)
        self.assertIn("computador desligado ou suspenso", md)
        self.assertIn("pendrive (SQLite", md)

    def test_sqlite_antigo_sem_identificacao_da_maquina(self):
        antigo = self.root / "antigo.sqlite"
        conn = sqlite3.connect(str(antigo))
        with conn:
            conn.execute("CREATE TABLE sessions (session_id TEXT PRIMARY KEY, site_id TEXT, school_code TEXT, started_at TEXT, completed_at TEXT, duration_seconds INTEGER, status TEXT)")
            conn.execute("INSERT INTO sessions VALUES (?, 'PET', 'E', '2026-10-05T11:00:00Z', '2026-10-05T11:30:00Z', 1800, 'completed')", (S1,))
        conn.close()
        code, out, _ = self.rodar("--sqlite", str(antigo))
        self.assertEqual(code, 0, out)
        aulas = ler_csv(self.saida / "aulas.csv")
        self.assertEqual((aulas[0]["duracao_min"], aulas[0]["versoes_programa"], aulas[0]["installation_id"]), ("30,0", "", ""))
        self.assertIn("importe os pendrives de novo", (self.saida / "relatorio.md").read_text(encoding="utf-8"))

    def test_sem_fonte_falha(self):
        out = io.StringIO()
        with patch.object(rel, "ROOT", self.root), patch("urllib.request.urlopen", MagicMock(side_effect=AssertionError)), \
                contextlib.redirect_stdout(out):
            code = rel.main(["--sem-nuvem", "--saida", str(self.saida)])
        self.assertEqual(code, 1)
        self.assertFalse(self.saida.exists())


if __name__ == "__main__":
    unittest.main()
