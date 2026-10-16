/**
 * Parser estrutural de projetos LEGO SPIKE (.llsp3 / scratch.sb3 / python).
 * Extrai métricas agregadas de programação para inferência de progresso técnico
 * garantindo privacidade estrita (sem nomes de variáveis, strings livres ou código bruto).
 */

export const MOTOR_OPCODES = [
  "spike_motor",
  "wedo_setmotorpower",
  "wedo_motor",
  "boost_motor",
  "ev3_motor",
  "motors",
  "motion_movesteps",
  "motion_turnright",
  "motion_turnleft",
  "motion_pointindirection"
];

export const SENSOR_OPCODES = [
  "spike_sensor",
  "sensing_touchingobject",
  "sensing_distanceto",
  "sensing_color",
  "sensing_loudness",
  "sensing_timer",
  "wedo_whendistance",
  "boost_whencolor",
  "ev3_sensor",
  "ultrasonic",
  "distance",
  "color",
  "force",
  "gyro",
  "yaw",
  "pitch",
  "roll"
];

export const LOOP_OPCODES = [
  "control_repeat",
  "control_forever",
  "control_repeat_until",
  "control_while"
];

export const CONDITION_OPCODES = [
  "control_if",
  "control_if_else",
  "control_wait_until"
];

export function classifyOpcode(opcode = "") {
  const lower = opcode.toLowerCase();
  const isHat =
    lower.startsWith("event_") ||
    lower.includes("events_when") ||
    lower.includes("when") ||
    lower === "procedures_definition";
  return {
    isMotor: MOTOR_OPCODES.some((pattern) => lower.includes(pattern)),
    isSensor: SENSOR_OPCODES.some((pattern) => lower.includes(pattern)),
    isLoop: LOOP_OPCODES.some((pattern) => lower.includes(pattern)),
    isCondition: CONDITION_OPCODES.some((pattern) => lower.includes(pattern)),
    isEvent: lower.startsWith("event_") || lower.includes("when"),
    isHat,
    isVariable: lower.startsWith("data_") || lower.includes("variable"),
    isProcedure: lower.startsWith("procedures_") || lower.includes("custom_block")
  };
}

export function inferStage(metrics) {
  const { executable_blocks, uses_motor, uses_sensor, uses_loop, uses_condition } = metrics;

  if (!executable_blocks || executable_blocks === 0) {
    return { stage: "empty", confidence: 0.99 };
  }

  if (uses_motor && uses_sensor && (uses_loop || uses_condition)) {
    return { stage: "integrated_mission", confidence: 0.92 };
  }

  if (uses_motor && uses_loop) {
    return { stage: "autonomous_loop", confidence: 0.88 };
  }

  if (uses_motor && uses_sensor) {
    return { stage: "sensor_reactive", confidence: 0.85 };
  }

  if (uses_motor) {
    return { stage: "basic_movement", confidence: 0.85 };
  }

  if (executable_blocks > 0 && !uses_motor && !uses_sensor) {
    return { stage: "initial_setup", confidence: 0.80 };
  }

  return { stage: "exploring", confidence: 0.70 };
}

export function parseProjectJson(projectJson, previousMetrics = null) {
  let parsed = projectJson;

  // Se receber string, tenta fazer parse seguro de JSON
  if (typeof projectJson === "string") {
    try {
      parsed = JSON.parse(projectJson);
    } catch {
      return {
        source: "spike_project",
        project_saved: false,
        format: "corrupted_or_invalid_json",
        error_code: "json_parse_error",
        executable_blocks: 0,
        orphan_blocks: 0,
        top_level_stacks: 0,
        uses_motor: false,
        uses_sensor: false,
        uses_loop: false,
        uses_condition: false,
        uses_variable: false,
        uses_procedure: false,
        blocks_added_since_previous: 0,
        blocks_removed_since_previous: 0,
        inferred_stage: "invalid",
        inference_confidence: 0
      };
    }
  }

  if (!parsed || typeof parsed !== "object") {
    return {
      source: "spike_project",
      project_saved: false,
      format: "unknown",
      executable_blocks: 0,
      orphan_blocks: 0,
      top_level_stacks: 0,
      uses_motor: false,
      uses_sensor: false,
      uses_loop: false,
      uses_condition: false,
      uses_variable: false,
      uses_procedure: false,
      blocks_added_since_previous: 0,
      blocks_removed_since_previous: 0,
      inferred_stage: "empty",
      inference_confidence: 0.99
    };
  }

  // Detecção explícita de projetos Python do LEGO SPIKE Prime
  const isPythonProject =
    parsed.projectType === "python" ||
    parsed.type === "python" ||
    parsed.language === "python" ||
    typeof parsed["main.py"] === "string" ||
    (typeof parsed.script === "string" && !Array.isArray(parsed.targets));

  if (isPythonProject) {
    return {
      source: "spike_project",
      project_saved: true,
      format: "python",
      language: "python",
      error_code: "unsupported_block_parser_for_python",
      executable_blocks: 0,
      orphan_blocks: 0,
      top_level_stacks: 0,
      uses_motor: false,
      uses_sensor: false,
      uses_loop: false,
      uses_condition: false,
      uses_variable: false,
      uses_procedure: false,
      blocks_added_since_previous: 0,
      blocks_removed_since_previous: 0,
      inferred_stage: "unsupported_python",
      inference_confidence: 0
    };
  }

  let targets = Array.isArray(parsed.targets) ? parsed.targets : [];
  // Suporte a formatos planos com blocks diretamente no objeto raiz
  if (targets.length === 0 && parsed.blocks && typeof parsed.blocks === "object") {
    targets = [{ blocks: parsed.blocks }];
  }

  let totalBlocks = 0;
  let executableBlocks = 0;
  let orphanBlocks = 0;
  let topLevelStacks = 0;

  let usesMotor = false;
  let usesSensor = false;
  let usesLoop = false;
  let usesCondition = false;
  let usesVariable = false;
  let usesProcedure = false;

  for (const target of targets) {
    if (!target || typeof target !== "object") continue;
    const blocks = target.blocks;
    if (!blocks || typeof blocks !== "object") continue;

    // Suporta tanto objeto com chaves de ID quanto array de blocos
    const entries = Array.isArray(blocks)
      ? blocks.map((b, idx) => [b?.id || String(idx), b])
      : Object.entries(blocks);

    const validEntries = [];
    let hasGraphOrNonHatTop = false;

    for (const [blockId, blockData] of entries) {
      if (!blockData || typeof blockData !== "object" || Array.isArray(blockData)) continue;
      validEntries.push([blockId, blockData]);

      if (
        blockData.next !== undefined ||
        blockData.parent !== undefined ||
        blockData.inputs !== undefined
      ) {
        hasGraphOrNonHatTop = true;
      }

      if (blockData.topLevel === true) {
        const { isHat } = classifyOpcode(blockData.opcode || "");
        if (!isHat) {
          hasGraphOrNonHatTop = true;
        }
      }
    }

    if (hasGraphOrNonHatTop) {
      const blocksById = new Map();
      const allNonShadowIds = new Set();
      const hatRootIds = [];

      for (const [blockId, blockData] of validEntries) {
        blocksById.set(blockId, blockData);
        totalBlocks += 1;

        if (blockData.shadow !== true) {
          allNonShadowIds.add(blockId);
          if (blockData.topLevel === true) {
            const { isHat } = classifyOpcode(blockData.opcode || "");
            if (isHat) {
              hatRootIds.push(blockId);
            }
          }
        }
      }

      const connectedIds = new Set();
      const stack = [...hatRootIds];

      while (stack.length > 0) {
        const id = stack.pop();
        if (!id || typeof id !== "string") continue;
        if (connectedIds.has(id)) continue;
        const block = blocksById.get(id);
        if (!block || typeof block !== "object") continue;
        if (block.shadow === true) continue;

        connectedIds.add(id);

        if (block.next && typeof block.next === "string") {
          const nextBlock = blocksById.get(block.next);
          if (nextBlock && nextBlock.shadow !== true) {
            stack.push(block.next);
          }
        }

        if (block.inputs && typeof block.inputs === "object") {
          for (const inputVal of Object.values(block.inputs)) {
            if (!Array.isArray(inputVal) || inputVal.length < 2) continue;
            const ref = inputVal[1];
            if (typeof ref === "string") {
              const child = blocksById.get(ref);
              if (child && child.shadow !== true) {
                stack.push(ref);
              }
            }
          }
        }
      }

      executableBlocks += connectedIds.size;
      topLevelStacks += hatRootIds.length;

      for (const id of allNonShadowIds) {
        if (!connectedIds.has(id)) {
          orphanBlocks += 1;
        }
      }

      for (const id of connectedIds) {
        const block = blocksById.get(id);
        const classification = classifyOpcode(block.opcode || "");

        if (classification.isMotor) usesMotor = true;
        if (classification.isSensor) usesSensor = true;
        if (classification.isLoop) usesLoop = true;
        if (classification.isCondition) usesCondition = true;
        if (classification.isVariable) usesVariable = true;
        if (classification.isProcedure) usesProcedure = true;

        if (block.inputs && typeof block.inputs === "object") {
          for (const inputVal of Object.values(block.inputs)) {
            if (Array.isArray(inputVal)) {
              for (const item of inputVal) {
                if (Array.isArray(item) && item.length > 0) {
                  if (item[0] === 12 || item[0] === 13) {
                    usesVariable = true;
                  }
                }
              }
            }
          }
        }
      }
    } else {
      // Mock plano legado de teste (sem next/parent/inputs e sem topLevel: true em blocos não-chapéu)
      for (const [blockId, blockData] of validEntries) {
        totalBlocks += 1;
        if (blockData.shadow !== true) {
          executableBlocks += 1;
        }
        if (blockData.topLevel === true) {
          topLevelStacks += 1;
        }

        const opcode = blockData.opcode || "";
        const classification = classifyOpcode(opcode);

        if (classification.isMotor) usesMotor = true;
        if (classification.isSensor) usesSensor = true;
        if (classification.isLoop) usesLoop = true;
        if (classification.isCondition) usesCondition = true;
        if (classification.isVariable) usesVariable = true;
        if (classification.isProcedure) usesProcedure = true;
      }
    }
  }

  let blocksAdded = 0;
  let blocksRemoved = 0;

  if (previousMetrics && typeof previousMetrics.executable_blocks === "number") {
    const delta = executableBlocks - previousMetrics.executable_blocks;
    if (delta > 0) blocksAdded = delta;
    if (delta < 0) blocksRemoved = Math.abs(delta);
  }

  const baseMetrics = {
    source: "spike_project",
    project_saved: true,
    format: "llsp3",
    language: "word-blocks",
    total_blocks: totalBlocks,
    executable_blocks: executableBlocks,
    orphan_blocks: orphanBlocks,
    top_level_stacks: topLevelStacks,
    uses_motor: usesMotor,
    uses_sensor: usesSensor,
    uses_loop: usesLoop,
    uses_condition: usesCondition,
    uses_variable: usesVariable,
    uses_procedure: usesProcedure,
    blocks_added_since_previous: blocksAdded,
    blocks_removed_since_previous: blocksRemoved
  };

  const inference = inferStage(baseMetrics);
  baseMetrics.inferred_stage = inference.stage;
  baseMetrics.inference_confidence = inference.confidence;

  return baseMetrics;
}
