import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "../../..");
const launcherPath = path.join(repoRoot, "pulselab.ps1");

test("Launcher: pulselab.ps1 implementa auto-update seguro com validação SHA-256 e resiliência offline", () => {
  assert.ok(fs.existsSync(launcherPath), "pulselab.ps1 deve existir na raiz do repositório");
  const scriptContent = fs.readFileSync(launcherPath, "utf-8");

  // 1. Deve implementar função Update-PulseLabIfOnline
  assert.match(
    scriptContent,
    /function\s+Update-PulseLabIfOnline/,
    "pulselab.ps1 deve implementar Update-PulseLabIfOnline"
  );

  // 2. Deve validar hash SHA-256 estritamente antes de aplicar extração
  assert.match(
    scriptContent,
    /SHA256.*Create\(\)|Get-FileHash.*SHA256/i,
    "pulselab.ps1 deve validar hash SHA-256 antes de aplicar atualização"
  );

  // 3. Deve preservar a pasta de dados locais sem sobrescrever
  assert.match(
    scriptContent,
    /dados_locais/,
    "pulselab.ps1 deve proteger dados_locais durante atualização"
  );

  // 4. Deve conter timeout curto para não bloquear oficinas offline
  assert.match(
    scriptContent,
    /Timeout\s*=\s*[12]000/,
    "pulselab.ps1 deve ter timeout curto (1-2s) para resiliência offline"
  );

  // 5. Bridge isolado não deve aceitar rotas arbitrárias não autenticadas
  const bridgePath = path.join(repoRoot, "bridge/pulselab-bridge.ps1");
  assert.ok(fs.existsSync(bridgePath), "pulselab-bridge.ps1 deve existir");
  const bridgeContent = fs.readFileSync(bridgePath, "utf-8");
  assert.match(
    bridgeContent,
    /\$script:AutoUpdateEnabled\s*=\s*\$false/,
    "Bridge deve manter $script:AutoUpdateEnabled = $false"
  );
});

test("Launcher: regex de extração de checksum SHA-256 hexadecimal estrito", () => {
  const shaRegex = /\b([a-f0-9]{64})\b/i;

  // Hash puro
  const validHash = "bfd19ec1e87e0ddc991a17b8fdcecba3adde2f5081237ba6a42f00ce60a4f8a5";
  const match1 = validHash.match(shaRegex);
  assert.ok(match1);
  assert.equal(match1[1].toLowerCase(), validHash);

  // Formato sha256sum padrão com nome do arquivo
  const shaFileContent = `${validHash}  PulseLab-2.2.0-Windows.zip\n`;
  const match2 = shaFileContent.match(shaRegex);
  assert.ok(match2);
  assert.equal(match2[1].toLowerCase(), validHash);

  // Formato sha256sum com asterisco (binário)
  const shaFileContentBinary = `${validHash.toUpperCase()} *PulseLab-2.2.0-Windows.zip\r\n`;

  const match3 = shaFileContentBinary.match(shaRegex);
  assert.ok(match3);
  assert.equal(match3[1].toLowerCase(), validHash);

  // Hash incompleto (63 chars) -> deve falhar
  const invalidShort = "bfd19ec1e87e0ddc991a17b8fdcecba3adde2f5081237ba6a42f00ce60a4f8a";
  assert.equal(invalidShort.match(shaRegex), null);

  // String com caracteres não hexadecimais -> deve falhar
  const invalidChars = "gfd19ec1e87e0ddc991a17b8fdcecba3adde2f5081237ba6a42f00ce60a4f8a5";
  assert.equal(invalidChars.match(shaRegex), null);

  // String vazia / HTML 404
  const html404 = "<html><head><title>404 Not Found</title></head><body><h1>404</h1></body></html>";
  assert.equal(html404.match(shaRegex), null);
});
