import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "../../..");
const checkerScript = path.join(repoRoot, "scripts/check-version-consistency.py");
const versionFile = path.join(repoRoot, "VERSION");

test("Version Consistency: todas as superfícies operacionais devem estar sincronizadas com VERSION", () => {
  assert.ok(fs.existsSync(versionFile), "VERSION deve existir");
  assert.ok(fs.existsSync(checkerScript), "scripts/check-version-consistency.py deve existir");

  const canonicalVersion = fs.readFileSync(versionFile, "utf-8").trim();
  assert.match(canonicalVersion, /^\d+\.\d+\.\d+/, "Versão canônica deve seguir SemVer");

  // Executa o verificador Python oficial
  try {
    const output = execFileSync("python3", [checkerScript], {
      cwd: repoRoot,
      encoding: "utf-8",
      stdio: ["ignore", "pipe", "pipe"]
    });
    assert.match(output, /SUCESSO/);
  } catch (err) {
    const stderr = err.stderr ? err.stderr.toString() : err.message;
    const stdout = err.stdout ? err.stdout.toString() : "";
    assert.fail(`Verificador de consistência de versão falhou:\nSTDOUT:\n${stdout}\nSTDERR:\n${stderr}`);
  }
});
