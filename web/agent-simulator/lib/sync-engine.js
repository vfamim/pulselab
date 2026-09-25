// Explicit fail-closed boundary. Test data has no remote ingestion path.
// Kept so accidental imports from legacy screens cannot upload data.
export async function sendEventToSupabase() {
  throw new Error(
    "Envio à nuvem desativado nesta versão de teste. Exporte localmente.",
  );
}
export async function syncSingleEvent() {
  return false;
}
export async function flushPendingEvents() {
  return { disabled: true, environment: "test", total: 0, synced: 0 };
}
