import { listSessions, saveSession } from "./student-store.js";

export const DEFAULT_SUPABASE_URL = "https://cylsqbmtglvdfubbarqe.supabase.co";
export const DEFAULT_SUPABASE_ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN5bHNxYm10Z2x2ZGZ1YmJhcnFlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5NjE1MzIsImV4cCI6MjA5MzUzNzUzMn0.tscU354WLjnYz6E6NOrDQK16ViWBc-Af5FYhvZikFbU";

const RESPONSE_EVENT_TYPES = new Set(["pre", "checkpoint", "post"]);

export function resolveTargetTable(event) {
  if (event._target_table) return event._target_table;
  if (RESPONSE_EVENT_TYPES.has(event.event_type)) {
    return "research_events";
  }
  return "research_session_events";
}

export function sanitizeEventForSupabase(event, sessionContext = {}) {
  const payload = {};
  for (const [key, value] of Object.entries(event)) {
    if (!key.startsWith("_") && value !== undefined) {
      payload[key] = value;
    }
  }
  if (payload.occurred_at && typeof payload.occurred_at === "number") {
    payload.occurred_at = new Date(payload.occurred_at).toISOString();
  }
  payload.site_id = payload.site_id || sessionContext.site || "default-site";
  payload.school_code = payload.school_code || sessionContext.school || "default-school";
  payload.workshop_code = payload.workshop_code || sessionContext.workshop || "default-workshop";
  payload.class_code = payload.class_code || sessionContext.class || "default-class";
  payload.activity_id = payload.activity_id || "distance-stop";
  payload.client_version = payload.client_version || "2.0.1";
  payload.group_id = payload.group_id || sessionContext.group_id;
  return payload;
}

export async function sendSessionToSupabase(
  session,
  url = DEFAULT_SUPABASE_URL,
  key = DEFAULT_SUPABASE_ANON_KEY
) {
  if (!session || !session.id) return false;

  const payload = {
    session_id: session.id,
    group_id: session.group_id,
    site_id: session.context?.site || "default-site",
    school_code: session.context?.school || "default-school",
    workshop_code: session.context?.workshop || "default-workshop",
    class_code: session.context?.class || "default-class",
    environment: session.environment || "production",
    protocol_version: session.protocol_version || "pulselab-bancada-v2",
    instrument_version: session.instrument_version || "bancada-2.0.1",
    group_size: session.group_size || 2,
    phase: session.phase || "activity",
    session_payload: session,
    created_at: new Date(session.created_at || Date.now()).toISOString(),
    updated_at: new Date(session.updated_at || Date.now()).toISOString()
  };

  const endpoint = `${url}/rest/v1/research_bancada_sessions?on_conflict=session_id`;
  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
      Prefer: "resolution=merge-duplicates,return=minimal"
    },
    body: JSON.stringify(payload)
  });

  if (!response.ok && response.status !== 409) {
    const errorText = await response.text().catch(() => "");
    throw new Error(`HTTP ${response.status}: ${errorText}`);
  }

  // Also sync all atomic events from session if available
  if (Array.isArray(session.events)) {
    for (const evt of session.events) {
      try {
        await sendEventToSupabase(evt, url, key, session.context || {});
      } catch (e) {
        // Individual event failures don't abort session sync
      }
    }
  }

  return true;
}

export async function sendEventToSupabase(
  event,
  url = DEFAULT_SUPABASE_URL,
  key = DEFAULT_SUPABASE_ANON_KEY,
  sessionContext = {}
) {
  const targetTable = resolveTargetTable(event);
  const payload = sanitizeEventForSupabase(event, sessionContext);
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
    throw new Error(`HTTP ${response.status}: ${errorText}`);
  }

  return true;
}

export async function syncSingleEvent(event, sessionContext = {}) {
  try {
    return await sendEventToSupabase(event, DEFAULT_SUPABASE_URL, DEFAULT_SUPABASE_ANON_KEY, sessionContext);
  } catch (err) {
    return false;
  }
}

export async function syncSession(session) {
  try {
    await sendSessionToSupabase(session);
    if (session && session.id) {
      session._synced = true;
      session._synced_at = Date.now();
      await saveSession(session);
    }
    return true;
  } catch (err) {
    return false;
  }
}

let isFlushing = false;

export async function flushPendingEvents() {
  if (isFlushing) return { total: 0, synced: 0, busy: true };
  if (typeof navigator !== "undefined" && !navigator.onLine) {
    return { total: 0, synced: 0, offline: true };
  }

  isFlushing = true;
  try {
    const sessions = await listSessions();
    if (!sessions || sessions.length === 0) {
      return { total: 0, synced: 0 };
    }

    let syncedCount = 0;
    for (const session of sessions) {
      if (!session._synced || (session.updated_at && session.updated_at > (session._synced_at || 0))) {
        try {
          await sendSessionToSupabase(session);
          session._synced = true;
          session._synced_at = Date.now();
          await saveSession(session);
          syncedCount++;
        } catch (e) {
          // Break on network failure
          break;
        }
      }
    }

    return {
      total: sessions.length,
      synced: syncedCount,
      remaining: sessions.length - syncedCount
    };
  } finally {
    isFlushing = false;
  }
}
