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
import uuid
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

    def test_aula_nao_autorizada_fica_fora(self):
        antes, _ = rel.ler_sqlite(self.sqlite)
        alvo = antes[0]["session_id"]
        conn = sqlite3.connect(str(self.sqlite))
        with conn:
            conn.execute(
                "INSERT INTO unauthorized_sessions (session_id, status, marked_at) VALUES (?, 'nao_autorizada', ?)",
                (alvo, "2026-10-14T12:00:00Z"),
            )
        conn.close()
        depois, _ = rel.ler_sqlite(self.sqlite)
        self.assertEqual(len(depois), len(antes) - 1)
        self.assertNotIn(alvo, {a["session_id"] for a in depois})

    def test_encerrada_por_inatividade_nao_e_problema_mas_sem_programa_e(self):
        base = {"polo": "PET", "installation_id": INST_A, "data_local": "2026-10-09", "hora_inicio": "08:00",
                "fase": "completed", "interrompida": False, "spike_status": "ok", "origem": "nuvem"}
        com_programa = rel.aula_da_nuvem(dict(base, session_id="c1000000-0000-4000-8000-000000000001", encerrada_por="inatividade",
                                              duracao_min=95.0, versoes_programa=4, inicio_em="2026-10-09T11:00:00+00:00"))
        sem_programa = rel.aula_da_nuvem(dict(base, session_id="c1000000-0000-4000-8000-000000000002", encerrada_por="inatividade",
                                              duracao_min=40.0, versoes_programa=0, spike_status="sem_alteracao",
                                              inicio_em="2026-10-09T13:00:00+00:00"))
        aulas = rel.juntar_aulas([com_programa, sem_programa])
        por_id = {a["session_id"]: a for a in aulas}
        self.assertEqual((por_id[com_programa["session_id"]]["qualidade"], por_id[com_programa["session_id"]]["motivo_qualidade"]), ("boa", ""))
        self.assertEqual((por_id[sem_programa["session_id"]]["qualidade"], por_id[sem_programa["session_id"]]["motivo_qualidade"]),
                         ("ruim", "nenhum programa salvo"))
        ind = rel.indicadores(aulas)
        self.assertEqual((ind["pct_sem_spike"], ind["pct_encerradas_instrutor"], ind["pct_interrompidas"]), (50.0, 0.0, 0.0))
        self.assertEqual(rel.ENCERRAMENTO_LEIGO["inatividade"], "sem uso do SPIKE por 40 min")
        # Sessão sem programa fechada por inatividade é PC ligado sem aula: fica fora das contagens no main.
        self.assertEqual((rel.sessao_vazia(sem_programa), rel.sessao_vazia(com_programa)), (True, False))
        md = rel.gerar_markdown(aulas, rel.resumo_polos(aulas), [], rel.dt.date(2026, 10, 15), None, None, None, ["nuvem"], [])
        self.assertIn("| sem uso do SPIKE por 40 min |", md)

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
        # Uma resposta da criança vinda da nuvem (aula S5); a de ambiente de teste fica fora.
        respostas_nuvem = [{
            "event_id": "e5000000-0000-4000-8000-000000000001", "session_id": S5, "polo": "PET", "installation_id": INST_A,
            "maquina": "PET-LAB1-PC01", "parte": "crianca", "item_id": "crianca_gostou_v1", "valor": "sim", "recusou": False,
            "envio_id": "f5000000-0000-4000-8000-000000000001", "respondido_em": "2026-10-07T12:00:00+00:00",
            "data_local": "2026-10-07", "minutos_desde_inicio": 60, "ambiente": "production",
        }, {
            "event_id": "e5000000-0000-4000-8000-000000000002", "session_id": S5, "polo": "PET", "parte": "crianca",
            "item_id": "crianca_gostou_v1", "valor": "nao", "envio_id": "f5000000-0000-4000-8000-000000000002",
            "respondido_em": "2026-10-07T12:00:00+00:00", "data_local": "2026-10-07", "ambiente": "test",
        }]
        chave = "chave-secreta-de-teste"
        pedidos = []

        def responder(req, timeout=None):
            pedidos.append(req)
            if "research_questionario_respostas" in req.full_url:
                corpo = respostas_nuvem
            else:
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
        self.assertTrue(any("research_questionario_respostas" in p.full_url for p in pedidos))
        criancas = {(c["polo"], c["mes"], c["item_id"]): c for c in ler_csv(self.saida / "criancas.csv")}
        self.assertEqual((criancas[("PET", "2026-10", "crianca_gostou_v1")]["respostas"],
                          criancas[("PET", "2026-10", "crianca_gostou_v1")]["pct_sim"]), ("1", "100,0"), "resposta de teste fica fora")

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


def importar_coleta(root: Path, sqlite_path: Path, nome: str, sessoes: list[dict], eventos: list[dict], extras: dict | None = None):
    """Grava uma coleta no formato do bridge e importa com o importador (--no-cloud)."""
    files = {f"sessoes/sessao_{s['session_id']}.json": json.dumps(s).encode() for s in sessoes}
    files["events.jsonl"] = "\n".join(json.dumps(e) for e in eventos).encode()
    files.update(extras or {})
    folder = root / "coletas" / nome
    linhas = []
    for arquivo, conteudo in files.items():
        path = folder / arquivo
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(conteudo)
        linhas.append(f"{hashlib.sha256(conteudo).hexdigest().upper()}  {arquivo}")
    (folder / "manifesto_coleta.txt").write_text("INTEGRIDADE DOS ARQUIVOS (SHA-256):\n\n" + "\n".join(linhas) + "\n", encoding="utf-8")
    argv = ["importar", "--no-cloud", "--source", str(root / "coletas"), "--sqlite-path", str(sqlite_path)]
    with patch.object(imp, "__file__", str(root / "tooling" / "data" / "importar-para-supabase.py")), \
            patch.object(sys, "argv", argv), patch.dict(os.environ, {"PULSELAB_MANIFEST_HMAC_KEY": ""}), \
            contextlib.redirect_stdout(io.StringIO()):
        assert imp.main() == 0


Q1 = "c1000000-0000-4000-8000-000000000001"  # PET PC01, 05/10: bancada e duas crianças
Q2 = "c1000000-0000-4000-8000-000000000002"  # PET PC02, 06/10: uma criança respondeu 3h20 depois do início
Q3 = "c1000000-0000-4000-8000-000000000003"  # PET PC01, 03/11: nove respostas individuais
Q4 = "c1000000-0000-4000-8000-000000000004"  # PET PC02, 07/10: aula não autorizada
Q5 = "c1000000-0000-4000-8000-000000000005"  # JUA PC01, 07/10: aula retirada na coleta
Q6 = "c1000000-0000-4000-8000-000000000006"  # JUA PC01, 08/10: uma criança
ITENS_CRIANCA = ["crianca_gostou_v1", "crianca_outra_aula_v1", "crianca_confianca_antes_v1", "crianca_confianca_agora_v1", "crianca_ajudou_v1"]


def iso(base: str, minutos: float) -> str:
    return (rel.parse_iso(base) + rel.dt.timedelta(minutes=minutos)).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def respostas_bridge(sid, inst, site, inicio, minutos, parte, valores, envio=None):
    """Eventos como Save-BridgeQuestionario grava (um por pergunta, mesmo submission_id)."""
    envio = envio or str(uuid.uuid4())
    if parte == "bancada":
        tipo, itens, papel = "bancada_result_recorded", ["bancada_linha_v1", "bancada_corrida_v1", "bancada_quiz_v1"], "group"
    else:
        tipo, itens, papel = "student_feedback_recorded", ITENS_CRIANCA, "individual"
    quando = iso(inicio, minutos)
    eventos = []
    for ordem, (item, valor) in enumerate(zip(itens, valores), 1):
        ev = evento(sid, inst, site, tipo, quando, {
            "item_id": item, "value": valor, "refused": valor == "recusou", "instrument_version": "bancada-3.2.0",
            "submission_id": envio, "item_order": ordem, "session_active": True, "minutes_since_session_start": minutos,
        })
        ev.update(event_id=str(uuid.uuid4()), participant_role=papel, activity_stage="questionario_fim_aula", config_hash="a" * 64)
        eventos.append(ev)
    return eventos


class TestRelatorioQuestionario(unittest.TestCase):
    """Seções "Testes com os carrinhos" e "O que as crianças disseram" com dados sintéticos."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.sqlite = self.root / "consolidado.sqlite"
        self.saida = self.root / "saida"
        t = telemetria(6, True, True, False, False, 3)
        inicios = {Q1: "2026-10-05T11:00:00.000Z", Q2: "2026-10-06T11:00:00.000Z", Q3: "2026-11-03T11:00:00.000Z",
                   Q4: "2026-10-07T11:00:00.000Z", Q5: "2026-10-07T12:00:00.000Z", Q6: "2026-10-08T12:00:00.000Z"}
        maquinas = {Q1: (INST_A, "PET-LAB1-PC01", "PET"), Q2: (INST_B, "PET-LAB1-PC02", "PET"), Q3: (INST_A, "PET-LAB1-PC01", "PET"),
                    Q4: (INST_B, "PET-LAB1-PC02", "PET"), Q5: (INST_C, "JUA-PC01", "JUA"), Q6: (INST_C, "JUA-PC01", "JUA")}
        sessoes = [snapshot(sid, inst, label, site, inicios[sid], iso(inicios[sid], 90), telemetry=[t])
                   for sid, (inst, label, site) in maquinas.items()]
        r = lambda sid, minutos, parte, valores: respostas_bridge(sid, *(maquinas[sid][0], maquinas[sid][2]), inicios[sid], minutos, parte, valores)
        eventos = [
            *r(Q1, 60, "bancada", ["sim", "ganhamos", "quase_todas"]),
            *r(Q1, 62, "crianca", ["sim", "sim", "nao", "sim", "sim"]),                 # autoconfiança melhorou
            *r(Q1, 64, "crianca", ["mais_ou_menos", "nao", "sim", "sim", "recusou"]),    # igual; recusou a 8
            *r(Q2, 70, "bancada", ["em_parte", "nao_participamos", "sem_quiz"]),
            *r(Q2, 200, "crianca", ["nao", "mais_ou_menos", "mais_ou_menos", "nao", "sim"]),  # piorou; 3h20 depois
            *r(Q3, 50, "bancada", ["recusou", "recusou", "recusou"]),
            *[ev for _ in range(9) for ev in r(Q3, 55, "crianca", ["sim", "sim", "sim", "sim", "sim"])],
            *r(Q4, 60, "bancada", ["nao", "nao_terminamos", "poucas"]),
            *r(Q4, 61, "crianca", ["nao", "nao", "nao", "nao", "nao"]),
            *r(Q5, 60, "crianca", ["nao", "nao", "nao", "nao", "nao"]),
            *r(Q6, 30, "crianca", ["sim", "recusou", "recusou", "sim", "mais_ou_menos"]),
            # Texto fora do instrumento nunca entra no relatório
            *r(Q6, 31, "crianca", [NOME_CRIANCA, "sim", "sim", "sim", "sim"]),
        ]
        importar_coleta(self.root, self.sqlite, "Coleta_Q_20261104_120000", sessoes, eventos,
                        {"sessions_withdrawn.txt": f"{Q5}\n".encode()})
        conn = sqlite3.connect(str(self.sqlite))
        with conn:
            conn.execute("INSERT INTO unauthorized_sessions (session_id, status, marked_at) VALUES (?, 'nao_autorizada', ?)",
                         (Q4, "2026-10-07T13:00:00Z"))
        conn.close()

    def tearDown(self):
        self.tmp.cleanup()

    def rodar(self, *extra):
        argv = ["--sqlite", str(self.sqlite), "--saida", str(self.saida), "--hoje", "2026-11-10", "--sem-nuvem", *extra]
        with patch("urllib.request.urlopen", MagicMock(side_effect=AssertionError("sem rede"))), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(rel.main(argv), 0)

    def test_respostas_do_sqlite_sem_aulas_nao_autorizadas_ou_retiradas(self):
        respostas = rel.ler_questionario_sqlite(self.sqlite)
        sessoes = {r["session_id"] for r in respostas}
        self.assertNotIn(Q4, sessoes, "aula não autorizada fica fora")
        self.assertNotIn(Q5, sessoes, "aula retirada fica fora")
        self.assertEqual(sessoes, {Q1, Q2, Q3, Q6})
        q1 = [r for r in respostas if r["session_id"] == Q1]
        self.assertEqual({(r["polo"], r["maquina"], r["installation_id"], r["mes"]) for r in q1}, {("PET", "PET-LAB1-PC01", INST_A, "2026-10")})
        self.assertNotIn(NOME_CRIANCA, json.dumps([{k: v for k, v in r.items() if k != "respondido_em"} for r in respostas]))

    def test_testes_com_os_carrinhos(self):
        self.rodar()
        linhas = {(r["polo"], r["mes"]): r for r in ler_csv(self.saida / "testes-carrinho.csv")}
        self.assertEqual(list(next(iter(linhas.values())).keys()), rel.COLUNAS_CARRINHO)
        out = linhas[("PET", "2026-10")]
        self.assertEqual((out["bancadas_responderam"], out["linha_respostas"], out["pct_linha_ate_o_fim"], out["pct_linha_em_parte"]),
                         ("2", "2", "50,0", "50,0"))
        self.assertEqual((out["corrida_participaram"], out["pct_corrida_ganharam"], out["corrida_nao_participaram"]), ("1", "100,0", "1"),
                         "corrida só onde a bancada participou")
        self.assertEqual((out["quiz_tiveram"], out["pct_quiz_quase_todas"], out["quiz_sem_jogo"]), ("1", "100,0", "1"))
        nov = linhas[("PET", "2026-11")]
        self.assertEqual((nov["bancadas_responderam"], nov["linha_respostas"], nov["pct_linha_ate_o_fim"], nov["linha_recusas"],
                          nov["corrida_recusas"], nov["quiz_recusas"]), ("1", "0", "", "1", "1", "1"))
        self.assertNotIn(("JUA", "2026-10"), linhas, "JUA não respondeu a parte da bancada (Q5 retirada)")

    def test_o_que_as_criancas_disseram(self):
        self.rodar()
        perguntas = {(r["polo"], r["mes"], r["item_id"]): r for r in ler_csv(self.saida / "criancas.csv")}
        gostou = perguntas[("PET", "2026-10", "crianca_gostou_v1")]
        self.assertEqual((gostou["numero"], gostou["respostas"], gostou["pct_sim"], gostou["pct_mais_ou_menos"], gostou["pct_nao"], gostou["recusas"]),
                         ("4", "3", "33,3", "33,3", "33,3", "0"))
        ajudou = perguntas[("PET", "2026-10", "crianca_ajudou_v1")]
        self.assertEqual((ajudou["respostas"], ajudou["recusas"], ajudou["pct_sim"]), ("2", "1", "100,0"))
        jua_antes = perguntas[("JUA", "2026-10", "crianca_confianca_antes_v1")]
        self.assertEqual((jua_antes["respostas"], jua_antes["recusas"]), ("0", "1"))
        resumo = {(r["polo"], r["mes"]): r for r in ler_csv(self.saida / "criancas-resumo.csv")}
        pet = resumo[("PET", "2026-10")]
        # Pares 6/7: (nao->sim) melhorou, (sim->sim) igual, (mais_ou_menos->nao) piorou
        self.assertEqual((pet["criancas_responderam"], pet["pares_autoconfianca"], pet["pct_sim_antes"], pet["pct_sim_agora"],
                          pet["pct_melhorou"], pet["pct_igual"], pet["pct_piorou"]), ("3", "3", "33,3", "66,7", "33,3", "33,3", "33,3"))
        self.assertEqual((resumo[("PET", "2026-11")]["criancas_responderam"], resumo[("PET", "2026-11")]["pct_sim_agora"]), ("9", "100,0"))
        jua = resumo[("JUA", "2026-10")]
        self.assertEqual((jua["criancas_responderam"], jua["pares_autoconfianca"], jua["pct_melhorou"]), ("1", "0", ""),
                         "recusa numa das duas perguntas não forma par; envio com texto estranho é descartado")

    def test_sinalizacoes_e_markdown(self):
        self.rodar()
        sinais = ler_csv(self.saida / "questionario-sinalizacoes.csv")
        self.assertEqual(list(sinais[0].keys()), rel.COLUNAS_SINALIZACOES)
        por_aula = {(s["session_id"], s["motivo"].split(" ")[0]) for s in sinais}
        self.assertIn((Q3, "9"), por_aula, "mais de 8 respostas individuais")
        self.assertTrue(any(s["session_id"] == Q2 and "mais de 3 h" in s["motivo"] for s in sinais))
        self.assertFalse(any(s["session_id"] == Q1 for s in sinais))
        md = (self.saida / "relatorio.md").read_text(encoding="utf-8")
        self.assertIn("## Testes com os carrinhos", md)
        self.assertIn("## O que as crianças disseram", md)
        self.assertIn("### Mudança de autoconfiança (pergunta 6 contra pergunta 7)", md)
        self.assertIn("### Questionário do fim da aula a conferir", md)
        self.assertIn("| PET | 10/2026 | 2 | 50% de 2 |", md)
        self.assertIn("| PET | 10/2026 | 3 | 3 | 33,3% | 66,7% | 33,3% |", md)
        self.assertIn("| 03/11/2026 | PET | PET-LAB1-PC01 | 9 respostas individuais na aula (mais de 8) |", md)
        self.assertIn("**3** bancada(s) e **13** criança(s) responderam", md, "envio com resposta fora do instrumento é descartado inteiro")
        for nome in ("relatorio.md", "criancas.csv", "testes-carrinho.csv", "criancas-resumo.csv", "questionario-sinalizacoes.csv"):
            texto = (self.saida / nome).read_text(encoding="utf-8-sig")
            self.assertNotIn(NOME_CRIANCA, texto, nome)
            self.assertNotIn(Q4, texto, nome)
            self.assertNotIn(Q5, texto, nome)

    def test_filtro_de_mes_e_polo(self):
        self.rodar("--de", "2026-11-01", "--polo", "pet")
        self.assertEqual({(r["polo"], r["mes"]) for r in ler_csv(self.saida / "criancas-resumo.csv")}, {("PET", "2026-11")})

    def test_mesma_resposta_pela_nuvem_e_pelo_pendrive_conta_uma_vez(self):
        pendrive = rel.ler_questionario_sqlite(self.sqlite)
        r = next(x for x in pendrive if x["session_id"] == Q6 and x["item_id"] == "crianca_gostou_v1")
        nuvem = rel.resposta_da_nuvem({
            "event_id": r["event_id"].upper(), "session_id": Q6, "polo": "JUA", "parte": "crianca", "item_id": "crianca_gostou_v1",
            "valor": r["valor"], "envio_id": r["envio_id"], "respondido_em": r["respondido_em"].isoformat(), "ambiente": "production",
        })
        juntas = rel.juntar_respostas([nuvem], pendrive)
        self.assertEqual(len(juntas), len(pendrive))
        self.assertEqual(next(x for x in juntas if x["event_id"] == r["event_id"])["origem"], "nuvem+pendrive")
        self.assertIsNone(rel.resposta_da_nuvem({"parte": "crianca", "item_id": "crianca_gostou_v1", "valor": "talvez",
                                                 "session_id": Q6, "respondido_em": "2026-10-08T12:00:00Z"}))


if __name__ == "__main__":
    unittest.main()
