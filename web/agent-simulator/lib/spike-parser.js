import { unzipSync, strFromU8 } from "fflate";

export const PARSER_VERSION = "spike-structure-2.0.0-test.1";
const MAX_BYTES = 2 * 1024 * 1024;

export function parseProjectJson(project) {
  if (
    !Array.isArray(project?.targets) ||
    !project.targets.some((t) => t.blocks && typeof t.blocks === "object")
  ) {
    throw new Error(
      "Formato não suportado. Use um projeto de blocos com project.json; Python não é analisado nesta versão.",
    );
  }
  let total = 0,
    nonShadow = 0,
    stacks = 0;
  const features = {
    motor: false,
    sensor: false,
    loop: false,
    condition: false,
    variable: false,
    procedure: false,
  };
  for (const target of project.targets) {
    for (const block of Object.values(target.blocks || {})) {
      if (!block || typeof block !== "object") continue;
      total++;
      if (block.shadow === true) continue;
      nonShadow++;
      if (block.topLevel === true) stacks++;
      const opcode = String(block.opcode || "").toLowerCase();
      features.motor ||= /motor|^motion_|^spike_move|^movement_/.test(opcode);
      features.sensor ||=
        /sensor|distance|ultrasonic|color|force|touch|gyro/.test(opcode);
      features.loop ||= /^control_(repeat|forever|repeat_until|while)$/.test(
        opcode,
      );
      features.condition ||= /^control_(if|if_else|wait_until)$/.test(opcode);
      features.variable ||= /^data_|variable/.test(opcode);
      features.procedure ||= /^procedures_|custom_block/.test(opcode);
    }
  }
  return {
    parser_version: PARSER_VERSION,
    format: "scratch-blocks",
    total_blocks: total,
    non_shadow_blocks: nonShadow,
    top_level_stacks: stacks,
    features,
    interpretation: "structure_only_not_execution_or_learning",
  };
}

function unpack(bytes, depth = 0) {
  if (depth > 1 || bytes.length > MAX_BYTES)
    throw new Error("Projeto excede o limite de leitura (2 MB).");
  const files = unzipSync(bytes, {
    filter: (f) => {
      if (!["project.json", "scratch.sb3"].includes(f.name)) return false;
      if (f.originalSize > MAX_BYTES)
        throw new Error("Conteúdo descompactado excede 2 MB.");
      return true;
    },
  });
  if (files["project.json"])
    return JSON.parse(strFromU8(files["project.json"]));
  if (files["scratch.sb3"]) return unpack(files["scratch.sb3"], depth + 1);
  throw new Error(
    "O arquivo não contém um projeto de blocos reconhecido. Python não é analisado.",
  );
}

export async function readProjectFile(file) {
  if (file.size > MAX_BYTES) throw new Error("Escolha um projeto de até 2 MB.");
  const bytes = new Uint8Array(await file.arrayBuffer());
  const project = file.name.toLowerCase().endsWith(".json")
    ? JSON.parse(strFromU8(bytes))
    : unpack(bytes);
  return parseProjectJson(project);
}

export function artifactSnapshot(metrics, previous = null) {
  return {
    ...metrics,
    net_block_count_change: previous
      ? metrics.non_shadow_blocks - previous.non_shadow_blocks
      : null,
  };
}
