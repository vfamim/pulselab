import test from "node:test";
import assert from "node:assert/strict";
import { zipSync, strToU8 } from "fflate";
import {
  parseProjectJson,
  readProjectFile,
  artifactSnapshot,
} from "../lib/spike-parser.js";
const disconnected = {
  targets: [
    {
      name: "private student name",
      blocks: {
        a: {
          opcode: "spike_motor_run",
          shadow: false,
          topLevel: true,
          next: null,
        },
        b: {
          opcode: "spike_sensor_distance",
          shadow: false,
          topLevel: true,
          next: null,
        },
        c: {
          opcode: "control_forever",
          shadow: false,
          topLevel: true,
          next: null,
        },
      },
    },
  ],
};
test("disconnected blocks do not imply a mission, execution or calibrated confidence", () => {
  const m = parseProjectJson(disconnected);
  assert.equal(m.non_shadow_blocks, 3);
  assert.equal(m.features.motor, true);
  assert.equal(m.features.sensor, true);
  assert.equal(m.inferred_stage, undefined);
  assert.equal(m.inference_confidence, undefined);
  assert.equal(m.interpretation, "structure_only_not_execution_or_learning");
  assert.ok(!JSON.stringify(m).includes("private student name"));
});
test("equal counts mean zero NET variation, not zero editing activity", () => {
  const m = parseProjectJson(disconnected);
  assert.equal(artifactSnapshot(m, m).net_block_count_change, 0);
  assert.equal(artifactSnapshot(m, m).blocks_added_since_previous, undefined);
});
test("unsupported/missing projects are missing data, not initial setup", () => {
  assert.throws(() => parseProjectJson(null));
  assert.throws(() => parseProjectJson({ code: "print(1)" }));
});
test("reads an explicitly chosen nested SPIKE archive without exporting raw content", async () => {
  const nested = zipSync({
    "project.json": strToU8(JSON.stringify(disconnected)),
  });
  const archive = zipSync({
    "scratch.sb3": nested,
    "private.txt": strToU8("sensitive"),
  });
  const result = await readProjectFile(new File([archive], "child-name.llsp3"));
  assert.equal(result.non_shadow_blocks, 3);
  assert.ok(!JSON.stringify(result).includes("child-name"));
});
test("rejects zip decompression over the size limit", async () => {
  const archive = zipSync({ "project.json": new Uint8Array(3 * 1024 * 1024) });
  await assert.rejects(
    readProjectFile(new File([archive], "oversized.llsp3")),
    /excede/,
  );
});
