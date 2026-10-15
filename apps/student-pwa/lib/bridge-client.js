// Chamadas ao servidor local do PulseLab (bridge), que serve esta página em http://127.0.0.1:43128/alunos/.
export const BRIDGE_URL = "http://127.0.0.1:43128";

export async function bridgeGet(path) {
  const response = await fetch(`${BRIDGE_URL}${path}`, { signal: AbortSignal.timeout(3000), cache: "no-store" });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
}

export async function bridgePost(path, payload) {
  const response = await fetch(`${BRIDGE_URL}${path}`, {
    signal: AbortSignal.timeout(10000),
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  });
  const body = await response.json().catch(() => ({}));
  return { status: response.status, body };
}
