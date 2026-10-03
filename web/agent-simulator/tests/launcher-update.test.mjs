import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "../../..");
const launcherPath = path.join(repoRoot, "pulselab.ps1");

test("Launcher: pulselab.ps1 desabilita completamente auto-update remoto e orienta atualizacao manual", () => {
  assert.ok(fs.existsSync(launcherPath), "pulselab.ps1 deve existir na raiz do repositório");
  const scriptContent = fs.readFileSync(launcherPath, "utf-8");

  // 1. -AllowUpdate deve falhar com mensagem clara orientando atualização manual institucional
  assert.match(
    scriptContent,
    /if\s*\(\$AllowUpdate\)\s*\{\s*throw\s*["'].*atualiza[cç][aã]o manual.*institucional.*["']/i,
    "-AllowUpdate deve lançar exceção clara orientando atualização manual por pacote institucional previamente verificado"
  );

  // 2. Não deve conter nenhuma URL remota de download ou de versão
  assert.doesNotMatch(
    scriptContent,
    /https?:\/\/(?:raw\.githubusercontent\.com|github\.com|pulselab-robotica-edu\.web\.app)/i,
    "pulselab.ps1 não deve conter URLs remotas de download de atualizações"
  );

  // 3. Não deve conter métodos de download ou extração de ZIP remoto
  assert.doesNotMatch(
    scriptContent,
    /\.DownloadFile\s*\(|\.DownloadString\s*\(|ZipFile\]::ExtractToDirectory/i,
    "pulselab.ps1 não deve conter métodos de download remoto ou extração automática de pacote"
  );

  // 4. Bridge também deve ter auto-update completamente desabilitado e sem URLs remotas
  const bridgePath = path.join(repoRoot, "bridge/pulselab-bridge.ps1");
  assert.ok(fs.existsSync(bridgePath), "pulselab-bridge.ps1 deve existir");
  const bridgeContent = fs.readFileSync(bridgePath, "utf-8");

  assert.match(
    bridgeContent,
    /\$script:AutoUpdateEnabled\s*=\s*\$false/,
    "Bridge deve forçar $script:AutoUpdateEnabled = $false"
  );

  assert.doesNotMatch(
    bridgeContent,
    /https?:\/\/(?:raw\.githubusercontent\.com|github\.com|pulselab-robotica-edu\.web\.app)/i,
    "Bridge não deve conter URLs remotas de auto-update"
  );

  assert.match(
    bridgeContent,
    /if\s*\(\$path\s*-eq\s*"\/update"\s*-or\s*\$path\s*-eq\s*"\/v1\/update"\)\s*\{[\s\S]*?\$response\.StatusCode\s*=\s*403/,
    "Endpoints /update e /v1/update devem responder com 403 Forbidden"
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
  const shaFileContent = `${validHash}  PulseLab-2.1.0-Windows.zip\n`;
  const match2 = shaFileContent.match(shaRegex);
  assert.ok(match2);
  assert.equal(match2[1].toLowerCase(), validHash);

  // Formato sha256sum com asterisco (binário)
  const shaFileContentBinary = `${validHash.toUpperCase()} *PulseLab-2.1.0-Windows.zip\r\n`;
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
