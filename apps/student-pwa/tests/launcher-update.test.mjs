import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "../../..");
const read = (rel) => fs.readFileSync(path.join(repoRoot, rel), "utf-8");

// O comportamento do atualizador é exercitado em tests/powershell/test-launcher-update.ps1 (pwsh no CI).
// Aqui ficam as garantias estáticas que não dependem de PowerShell.

test("Launcher: atualização só por manifesto assinado no canal de releases", () => {
  const launcher = read("runtime/windows/pulselab.ps1");
  const updater = read("runtime/windows/pulselab-update.ps1");

  assert.match(launcher, /pulselab-update\.ps1/, "launcher deve carregar o módulo de atualização");
  assert.match(launcher, /Complete-PulseLabUpdate/, "launcher deve confirmar a atualização após o servidor responder");
  assert.match(launcher, /Restore-PulseLabUpdate/, "launcher deve reverter quando o servidor não inicia");
  assert.doesNotMatch(launcher, /raw\.githubusercontent\.com/, "launcher não deve ler a branch main");

  assert.match(updater, /RSASignaturePadding\]::Pkcs1/, "manifesto deve ser verificado com RSA-SHA256");
  assert.match(updater, /releases\/latest\/download\/pulselab-update\.json/, "manifesto vem da última release publicada");
  assert.match(updater, /package_sha256/, "SHA-256 do pacote vem do manifesto assinado");
  assert.match(updater, /\$script:PulseLabProtectedItems = @\("dados_locais"/, "dados_locais nunca é trocado");
  assert.match(updater, /\[int\]\$ProbeTimeoutMs = 2000/, "consulta curta para não travar escolas offline");
  assert.doesNotMatch(updater, /raw\.githubusercontent\.com/, "atualizador não deve ler a branch main");
  assert.doesNotMatch(updater, /Copy-Item\s+-/, "troca de pastas usa Move-Item, sem cópia aninhada");
});

test("Bridge: não executa atualização própria", () => {
  const bridge = read("runtime/windows/bridge/pulselab-bridge.ps1");
  assert.match(bridge, /\$script:AutoUpdateEnabled\s*=\s*\$false/);
});

test("Pacote: chave pública de release distribuída quando existir", () => {
  const builder = read("tooling/release/build-installer.py");
  assert.match(builder, /release-public-key\.json/);
  assert.match(builder, /pulselab-update\.ps1/);
  assert.match(builder, /pulselab-installation\.ps1/);
});
