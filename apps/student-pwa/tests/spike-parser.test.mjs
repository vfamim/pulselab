import assert from "node:assert/strict";
import test from "node:test";
import { inferStage, parseProjectJson } from "../lib/spike-parser.js";

test("identifica projeto vazio", () => {
  const empty = parseProjectJson(null);
  assert.equal(empty.executable_blocks, 0);
  assert.equal(empty.inferred_stage, "empty");
  assert.equal(empty.project_saved, false);
});

test("analisa blocos Scratch e ignora blocos sombra (shadow)", () => {
  const mockProject = {
    targets: [
      {
        blocks: {
          b1: { opcode: "event_whenflagclicked", topLevel: true, shadow: false },
          b2: { opcode: "spike_motor_run_for_degrees", topLevel: false, shadow: false },
          s1: { opcode: "math_number", topLevel: false, shadow: true }
        }
      }
    ]
  };

  const metrics = parseProjectJson(mockProject);
  assert.equal(metrics.total_blocks, 3);
  assert.equal(metrics.executable_blocks, 2);
  assert.equal(metrics.top_level_stacks, 1);
  assert.equal(metrics.uses_motor, true);
  assert.equal(metrics.uses_sensor, false);
  assert.equal(metrics.inferred_stage, "basic_movement");
});

test("detecta sensores e estruturas de repetição para inferir missão integrada", () => {
  const integratedProject = {
    targets: [
      {
        blocks: {
          b1: { opcode: "event_whenflagclicked", topLevel: true, shadow: false },
          b2: { opcode: "control_forever", topLevel: false, shadow: false },
          b3: { opcode: "control_if", topLevel: false, shadow: false },
          b4: { opcode: "sensing_touchingobject", topLevel: false, shadow: false },
          b5: { opcode: "motion_movesteps", topLevel: false, shadow: false }
        }
      }
    ]
  };

  const metrics = parseProjectJson(integratedProject);
  assert.equal(metrics.uses_motor, true);
  assert.equal(metrics.uses_sensor, true);
  assert.equal(metrics.uses_loop, true);
  assert.equal(metrics.uses_condition, true);
  assert.equal(metrics.inferred_stage, "integrated_mission");
  assert.ok(metrics.inference_confidence >= 0.9);
});

test("calcula delta de blocos entre marcos de checkpoint", () => {
  const previous = { executable_blocks: 5 };
  const currentProject = {
    targets: [
      {
        blocks: {
          b1: { opcode: "event_whenflagclicked", topLevel: true, shadow: false },
          b2: { opcode: "motion_movesteps", topLevel: false, shadow: false },
          b3: { opcode: "motion_turnright", topLevel: false, shadow: false },
          b4: { opcode: "motion_turnleft", topLevel: false, shadow: false },
          b5: { opcode: "control_repeat", topLevel: false, shadow: false },
          b6: { opcode: "spike_sensor_distance", topLevel: false, shadow: false },
          b7: { opcode: "control_if", topLevel: false, shadow: false },
          b8: { opcode: "wedo_motor_stop", topLevel: false, shadow: false }
        }
      }
    ]
  };

  const metrics = parseProjectJson(currentProject, previous);
  assert.equal(metrics.executable_blocks, 8);
  assert.equal(metrics.blocks_added_since_previous, 3);
  assert.equal(metrics.blocks_removed_since_previous, 0);
});

test("suporta entrada em string JSON válida", () => {
  const jsonStr = JSON.stringify({
    targets: [{ blocks: { b1: { opcode: "spike_motor_run", shadow: false } } }]
  });
  const metrics = parseProjectJson(jsonStr);
  assert.equal(metrics.executable_blocks, 1);
  assert.equal(metrics.uses_motor, true);
  assert.equal(metrics.format, "llsp3");
});

test("retorna erro legível perante string JSON corrompida ou malformada", () => {
  const corrupted = "{ targets: [ invalid json";
  const metrics = parseProjectJson(corrupted);
  assert.equal(metrics.project_saved, false);
  assert.equal(metrics.format, "corrupted_or_invalid_json");
  assert.equal(metrics.error_code, "json_parse_error");
  assert.equal(metrics.inferred_stage, "invalid");
});

test("identifica explicitamente projetos Python sem mascarar como vazios", () => {
  const pythonProject = { projectType: "python", script: "import motor\nmotor.run(10)" };
  const metrics = parseProjectJson(pythonProject);
  assert.equal(metrics.format, "python");
  assert.equal(metrics.language, "python");
  assert.equal(metrics.error_code, "unsupported_block_parser_for_python");
  assert.equal(metrics.inferred_stage, "unsupported_python");
  assert.equal(metrics.executable_blocks, 0);
});

test("processa alvos com elementos nulos e blocos malformados de forma fail-safe", () => {
  const malformed = {
    targets: [
      null,
      "invalid_target",
      { blocks: null },
      { blocks: [null, { opcode: "sensing_touchingobject", shadow: false }] }
    ]
  };
  const metrics = parseProjectJson(malformed);
  assert.equal(metrics.executable_blocks, 1);
  assert.equal(metrics.uses_sensor, true);
});

test("separa blocos conectados de blocos órfãos ou desconectados do grafo principal", () => {
  const projectWithOrphans = {
    targets: [
      {
        blocks: {
          // Pilha conectada válida iniciada por chapéu
          h1: { opcode: "event_whenflagclicked", topLevel: true, shadow: false, next: "m1" },
          m1: { opcode: "spike_motor_run_for_degrees", topLevel: false, shadow: false, next: null },
          // Bloco sombra ligado a m1
          s1: { opcode: "math_number", topLevel: false, shadow: true },
          // Bloco órfão topLevel sem chapéu (ex: loop desanexado)
          o1: { opcode: "control_forever", topLevel: true, shadow: false, next: "o2" },
          // Bloco em sequência no órfão (com sensor que não deve ser contabilizado)
          o2: { opcode: "sensing_touchingobject", topLevel: false, shadow: false, next: null },
          // Bloco solto sem topLevel e sem pai
          o3: { opcode: "control_if", topLevel: false, shadow: false, next: null }
        }
      }
    ]
  };

  const metrics = parseProjectJson(projectWithOrphans);
  assert.equal(metrics.executable_blocks, 2); // apenas h1 e m1
  assert.equal(metrics.orphan_blocks, 3); // o1, o2, o3
  assert.equal(metrics.total_blocks, 6); // h1, m1, s1, o1, o2, o3
  assert.equal(metrics.top_level_stacks, 1); // apenas h1
  assert.equal(metrics.uses_motor, true);
  assert.equal(metrics.uses_sensor, false); // o2 é órfão, não deve ativar sensor
  assert.equal(metrics.uses_loop, false); // o1 é órfão, não deve ativar loop
  assert.equal(metrics.uses_condition, false); // o3 é órfão, não deve ativar condition
  assert.equal(metrics.inferred_stage, "basic_movement"); // não virou integrated_mission nem autonomous_loop
});

