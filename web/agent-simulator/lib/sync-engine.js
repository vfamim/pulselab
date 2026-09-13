import {
  listPendingEvents,
  markEventDelivered
} from "./student-store.js";

export const DEFAULT_SUPABASE_URL = "https://cylsqbmtglvdfubbarqe.supabase.co";
export const DEFAULT_SUPABASE_ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN5bHNxYm10Z2x2ZGZ1YmJhcnFlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5NjE1MzIsImV4cCI6MjA5MzUzNzUzMn0.tscU354WLjnYz6E6NOrDQK16ViWBc-Af5FYhvZikFbU";

const RESPONSE_EVENT_TYPES = new Set(["pre", "checkpoint", "post"]);

/**
 * Remove chaves internas de controle (com prefixo _) para envio ao Supabase.
 */
export function sanitizeEventForSupabase(event) {
  const payload = {};
  for (const [key, value] of Object.entries(event)) {
    if (!key.startsWith("_") && value !== undefined) {
      payload[key] = value;
    }
  }
  return payload;
}

/**
 * Determina a tabela correta no Supabase para o evento.
 */
export function resolveTargetTable(event) {
  if (event._target_table) {
    return event._target_table;
  }
  if (RESPONSE_EVENT_TYPES.has(event.event_type)) {
    return "research_events";
  }
  return "research_session_events";
}

/**
 * Envia um evento individual diretamente para a REST API do Supabase.
 * É idempotente via cabeçalho Prefer: resolution=ignore-duplicates.
 */
export async function sendEventToSupabase(
  event,
  url = DEFAULT_SUPABASE_URL,
  key = DEFAULT_SUPABASE_ANON_KEY
) {
  const targetTable = resolveTargetTable(event);
  const payload = sanitizeEventForSupabase(event);
  const endpoint = `${url}/rest/v1/${targetTable}`;

  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
      Prefer: "resolution=ignore-duplicates,return=minimal"
    },
    body: JSON.stringify(payload)
  });

  if (!response.ok && response.status !== 409) {
    const errorText = await response.text().catch(() => "");
    throw new Error(`HTTP ${response.status}: ${errorText}`);
  }

  return true;
}

/**
 * Tenta enviar um evento e, se bem-sucedido, marca como 'delivered' no IndexedDB.
 */
export async function syncSingleEvent(event) {
  try {
    await sendEventToSupabase(event);
    await markEventDelivered(event.event_id);
    return true;
  } catch (err) {
    // Falha esperada quando offline
    return false;
  }
}

/**
 * Varre o IndexedDB em busca de todos os eventos pendentes ('queued')
 * e envia um a um para o Supabase.
 */
let isFlushing = false;

export async function flushPendingEvents(onEventSynced = null) {
  if (isFlushing) return { total: 0, synced: 0, busy: true };
  if (typeof navigator !== "undefined" && !navigator.onLine) {
    return { total: 0, synced: 0, offline: true };
  }

  isFlushing = true;
  try {
    const pending = await listPendingEvents();
    if (!pending || pending.length === 0) {
      return { total: 0, synced: 0 };
    }

    let syncedCount = 0;
    for (const event of pending) {
      try {
        await sendEventToSupabase(event);
        await markEventDelivered(event.event_id);
        syncedCount += 1;
        if (typeof onEventSynced === "function") {
          onEventSynced(event.event_id);
        }
      } catch (error) {
        // Se falhou por queda de rede no meio, para a fila para tentar mais tarde
        break;
      }
    }

    return {
      total: pending.length,
      synced: syncedCount,
      remaining: pending.length - syncedCount
    };
  } finally {
    isFlushing = false;
  }
}
