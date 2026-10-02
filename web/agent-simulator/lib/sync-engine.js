import {
  listPendingEvents,
  markEventDelivered
} from "./student-store.js";

export const DEFAULT_SUPABASE_URL = "https://cylsqbmtglvdfubbarqe.supabase.co";
export const DEFAULT_SUPABASE_ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN5bHNxYm10Z2x2ZGZ1YmJhcnFlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5NjE1MzIsImV4cCI6MjA5MzUzNzUzMn0.tscU354WLjnYz6E6NOrDQK16ViWBc-Af5FYhvZikFbU";

const RESPONSE_EVENT_TYPES = new Set(["pre", "checkpoint", "post", "rubric"]);

const SESSION_EVENT_COLUMNS = new Set([
  "event_id",
  "session_id",
  "dyad_id",
  "group_id",
  "installation_id",
  "site_id",
  "regional_hub",
  "school_code",
  "workshop_code",
  "class_code",
  "grade_band",
  "activity_id",
  "computer_id",
  "protocol_version",
  "config_version",
  "config_hash",
  "client_version",
  "event_type",
  "severity",
  "interval_mark",
  "participant_id",
  "participant_role",
  "activity_stage",
  "elapsed_ms",
  "scheduled_at",
  "occurred_at",
  "received_at",
  "details"
]);

/**
 * Remove chaves internas de controle (com prefixo _) e preserva
 * campos extras de sessão dentro do objeto jsonb `details`,
 * evitando erros HTTP 400 do PostgREST por colunas inexistentes.
 */
export function sanitizeEventForSupabase(event) {
  const targetTable = resolveTargetTable(event);
  const payload = {};
  const isSessionEvent = targetTable === "research_session_events";
  const extraDetails = {};

  for (const [key, value] of Object.entries(event)) {
    if (key.startsWith("_") || value === undefined) {
      continue;
    }
    if (isSessionEvent && !SESSION_EVENT_COLUMNS.has(key)) {
      extraDetails[key] = value;
    } else {
      payload[key] = value;
    }
  }

  if (isSessionEvent) {
    const existingDetails = typeof payload.details === "object" && payload.details !== null ? payload.details : {};
    payload.details = {
      ...existingDetails,
      ...extraDetails
    };
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
  const endpoint = `${url}/rest/v1/${targetTable}?on_conflict=event_id`;

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
    const error = new Error(`HTTP ${response.status}: ${errorText}`);
    error.status = response.status;
    throw error;
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
        // Se for erro de cliente definitivo (ex: 400 Bad Request por coluna legada em banco antigo),
        // marca como delivered com aviso para não travar a fila inteira para sempre
        if (error.status && error.status >= 400 && error.status < 500 && error.status !== 408 && error.status !== 429) {
          console.warn(`[SyncEngine] Descartando evento com erro de contrato HTTP ${error.status}: ${event.event_id}`, error);
          await markEventDelivered(event.event_id);
          continue;
        }
        // Se falhou por queda de rede ou instabilidade 5xx, interrompe a fila para nova tentativa posterior
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
