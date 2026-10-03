import {
  listPendingEvents,
  markEventDelivered,
  markEventQuarantined
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
 * Determina se uma resposta HTTP 409 é uma duplicata idempotente esperada (PostgreSQL 23505 unique_violation
 * na chave primária / constraint esperada do registro) ou se é uma violação de integridade que deve
 * ser rejeitada/quarentenada (outra restrição de unicidade, chave estrangeira ou check).
 */
export function isUniqueViolationConflict(status, bodyText, expectedField = "event_id") {
  if (status !== 409 || !bodyText) return false;
  try {
    const parsed = typeof bodyText === "string" ? JSON.parse(bodyText) : bodyText;
    const isCode23505 = parsed.code === "23505" || String(bodyText).includes("23505");
    const msg = String(parsed.message || "");
    const details = String(parsed.details || "");
    const fullText = `${msg} ${details} ${typeof bodyText === "string" ? bodyText : JSON.stringify(bodyText)}`.toLowerCase();

    const hasUniqueMarker =
      isCode23505 ||
      fullText.includes("duplicate key") ||
      fullText.includes("unique constraint") ||
      fullText.includes("already exists");

    if (!hasUniqueMarker) return false;

    // Comprovação estrita da constraint primária esperada:
    const normField = String(expectedField).toLowerCase();
    const matchesExpected =
      fullText.includes(`(${normField})=`) ||
      fullText.includes(`key (${normField})`) ||
      fullText.includes(`${normField}_pkey`) ||
      (normField === "event_id" && (
        fullText.includes("research_events_pkey") ||
        fullText.includes("research_session_events_pkey")
      )) ||
      (normField === "session_id" && (
        fullText.includes("research_bancada_sessions_pkey")
      ));

    return Boolean(matchesExpected);
  } catch {
    return false;
  }
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

  if (!response.ok) {
    const errorText = await response.text().catch(() => "");
    if (response.status === 409 && isUniqueViolationConflict(409, errorText, "event_id")) {
      return { success: true, duplicate: true };
    }
    const error = new Error(`HTTP ${response.status}: ${errorText}`);
    error.status = response.status;
    error.body = errorText;
    throw error;
  }

  return { success: true, duplicate: false };
}

/**
 * Tenta enviar um evento e, se bem-sucedido, marca como 'delivered' no IndexedDB.
 * Se ocorrer erro 4xx definitivo, coloca em quarentena sem mascarar como entregue.
 */
export async function syncSingleEvent(event, options = {}) {
  const key = options.key || (typeof process !== "undefined" ? process.env?.PULSELAB_OPERATIONAL_JWT : null);
  // PWA em modo offline-first: não realiza envio anônimo que falharia por falta de permissão (anon revogado)
  if (!key && !options.force) {
    return { success: false, syncDisabled: true, offline: true };
  }

  try {
    const result = await sendEventToSupabase(event, options.url || DEFAULT_SUPABASE_URL, key || DEFAULT_SUPABASE_ANON_KEY);
    try {
      await markEventDelivered(event.event_id);
    } catch {}
    return { success: true, duplicate: Boolean(result?.duplicate) };
  } catch (err) {
    if (err.status && err.status >= 400 && err.status < 500 && err.status !== 408 && err.status !== 429) {
      try {
        await markEventQuarantined(event.event_id, err.message || `HTTP ${err.status}`);
      } catch {}
      return { success: false, quarantined: true, error: err };
    }
    return { success: false, offline: true, error: err };
  }
}

/**
 * Varre o IndexedDB em busca de todos os eventos pendentes ('queued')
 * e envia um a um para o Supabase.
 */
let isFlushing = false;

export async function flushPendingEvents(onEventSyncedOrOptions = null, maybeOptions = {}) {
  let onEventSynced = null;
  let options = {};

  if (typeof onEventSyncedOrOptions === "function") {
    onEventSynced = onEventSyncedOrOptions;
    options = maybeOptions || {};
  } else if (typeof onEventSyncedOrOptions === "object" && onEventSyncedOrOptions !== null) {
    options = onEventSyncedOrOptions;
    onEventSynced = typeof maybeOptions === "function" ? maybeOptions : null;
  } else {
    options = maybeOptions || {};
  }

  if (isFlushing) return { total: 0, synced: 0, busy: true };
  if (typeof navigator !== "undefined" && !navigator.onLine && !options.force) {
    return { total: 0, synced: 0, offline: true };
  }

  const key = options.key || (typeof process !== "undefined" ? process.env?.PULSELAB_OPERATIONAL_JWT : null);
  const url = options.url || DEFAULT_SUPABASE_URL;

  // PWA em modo offline-first: não tenta envio anônimo remoto sem chave operacional
  if (!key && !options.force) {
    const pendingList = await listPendingEvents().catch(() => []);
    return { total: pendingList?.length || 0, synced: 0, syncDisabled: true, offline: true };
  }

  isFlushing = true;
  try {
    const pending = options.pendingEvents || (await listPendingEvents());
    if (!pending || pending.length === 0) {
      return { total: 0, synced: 0, duplicates: 0, quarantined: 0 };
    }

    let syncedCount = 0;
    let duplicateCount = 0;
    let quarantinedCount = 0;

    for (const event of pending) {
      try {
        const result = await sendEventToSupabase(event, url, key);
        try {
          await markEventDelivered(event.event_id);
        } catch {}
        if (result?.duplicate) {
          duplicateCount += 1;
        } else {
          syncedCount += 1;
        }
        if (typeof onEventSynced === "function") {
          onEventSynced(event.event_id);
        }
      } catch (error) {
        if (error.status && error.status >= 400 && error.status < 500 && error.status !== 408 && error.status !== 429) {
          console.warn(`[SyncEngine] Quarentenando evento com erro HTTP ${error.status}: ${event.event_id}`, error);
          try {
            await markEventQuarantined(event.event_id, error.message);
          } catch {}
          quarantinedCount += 1;
          continue;
        }
        // Queda de rede ou erro transitório 5xx: interrompe fila para próxima tentativa
        break;
      }
    }

    return {
      total: pending.length,
      synced: syncedCount,
      duplicates: duplicateCount,
      quarantined: quarantinedCount,
      remaining: pending.length - (syncedCount + duplicateCount + quarantinedCount)
    };
  } finally {
    isFlushing = false;
  }
}
