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
  return {
    isMotor: MOTOR_OPCODES.some((pattern) => lower.includes(pattern)),
    isSensor: SENSOR_OPCODES.some((pattern) => lower.includes(pattern)),
    isLoop: LOOP_OPCODES.some((pattern) => lower.includes(pattern)),
    isCondition: CONDITION_OPCODES.some((pattern) => lower.includes(pattern)),
    isEvent: lower.startsWith("event_") || lower.includes("when"),
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
  if (!projectJson || typeof projectJson !== "object") {
    return {
      source: "spike_project",
      project_saved: false,
      format: "unknown",
      executable_blocks: 0,
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

  const targets = Array.isArray(projectJson.targets) ? projectJson.targets : [];
  let totalBlocks = 0;
  let executableBlocks = 0;
  let topLevelStacks = 0;

  let usesMotor = false;
  let usesSensor = false;
  let usesLoop = false;
  let usesCondition = false;
  let usesVariable = false;
  let usesProcedure = false;

  const currentBlockIds = new Set();

  for (const target of targets) {
    const blocks = target.blocks || {};
    for (const [blockId, blockData] of Object.entries(blocks)) {
      if (!blockData || typeof blockData !== "object") continue;

      currentBlockIds.add(blockId);
      totalBlocks += 1;

      // Bloco sombra (argumento interno) não é bloco executável principal
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
