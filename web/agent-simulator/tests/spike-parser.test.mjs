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
