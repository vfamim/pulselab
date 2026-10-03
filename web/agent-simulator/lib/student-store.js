const DATABASE_NAME = "pulselab-student-runner";
const DATABASE_VERSION = 1;
const EVENTS_STORE = "events";
const SESSIONS_STORE = "sessions";

function openDatabase() {
  if (typeof indexedDB === "undefined") {
    return Promise.reject(new Error("IndexedDB não está disponível neste navegador."));
  }

  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DATABASE_NAME, DATABASE_VERSION);

    request.onupgradeneeded = () => {
      const database = request.result;

      if (!database.objectStoreNames.contains(EVENTS_STORE)) {
        const events = database.createObjectStore(EVENTS_STORE, {
          keyPath: "event_id"
        });
        events.createIndex("session_id", "session_id", { unique: false });
        events.createIndex("delivery_state", "_delivery_state", { unique: false });
      }

      if (!database.objectStoreNames.contains(SESSIONS_STORE)) {
        database.createObjectStore(SESSIONS_STORE, { keyPath: "session_id" });
      }
    };

    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function runTransaction(storeName, mode, operation) {
  const database = await openDatabase();

  try {
    return await new Promise((resolve, reject) => {
      const transaction = database.transaction(storeName, mode);
      const store = transaction.objectStore(storeName);
      let result;

      transaction.oncomplete = () => resolve(result);
      transaction.onerror = () => reject(transaction.error);
      transaction.onabort = () => reject(transaction.error);

      result = operation(store);
    });
  } finally {
    database.close();
  }
}

export function saveEvent(event) {
  return runTransaction(EVENTS_STORE, "readwrite", (store) => store.put(event));
}

export function saveSession(session) {
  return runTransaction(SESSIONS_STORE, "readwrite", (store) => store.put(session));
}

export function removeSession(sessionId) {
  return runTransaction(SESSIONS_STORE, "readwrite", (store) => store.delete(sessionId));
}

export const deleteSession = removeSession;

export async function deleteSessionEvents(sessionId) {
  if (!sessionId) return 0;
  const database = await openDatabase();
  try {
    return await new Promise((resolve, reject) => {
      const transaction = database.transaction(EVENTS_STORE, "readwrite");
      const index = transaction.objectStore(EVENTS_STORE).index("session_id");
      const request = index.openCursor(IDBKeyRange.only(sessionId));
      let deletedCount = 0;

      request.onsuccess = () => {
        const cursor = request.result;
        if (!cursor) return;
        cursor.delete();
        deletedCount++;
        cursor.continue();
      };
      request.onerror = () => reject(request.error);
      transaction.oncomplete = () => resolve(deletedCount);
      transaction.onerror = () => reject(transaction.error);
    });
  } finally {
    database.close();
  }
}

export async function purgeSession(sessionId) {
  if (!sessionId) return { sessionDeleted: false, eventsDeleted: 0 };
  const eventsDeleted = await deleteSessionEvents(sessionId);
  await removeSession(sessionId);
  return { sessionDeleted: true, eventsDeleted };
}

export async function listQuarantinedEvents() {
  const database = await openDatabase();
  try {
    return await new Promise((resolve, reject) => {
      const transaction = database.transaction(EVENTS_STORE, "readonly");
      const index = transaction.objectStore(EVENTS_STORE).index("delivery_state");
      const request = index.getAll(IDBKeyRange.only("quarantined"));

      request.onsuccess = () => resolve(request.result || []);
      request.onerror = () => reject(request.error);
    });
  } finally {
    database.close();
  }
}

export async function listSessionEvents(sessionId) {
  const database = await openDatabase();

  try {
    return await new Promise((resolve, reject) => {
      const transaction = database.transaction(EVENTS_STORE, "readonly");
      const index = transaction.objectStore(EVENTS_STORE).index("session_id");
      const request = index.getAll(sessionId);

      request.onsuccess = () => resolve(request.result || []);
      request.onerror = () => reject(request.error);
    });
  } finally {
    database.close();
  }
}

export async function listPendingEvents() {
  const database = await openDatabase();

  try {
    return await new Promise((resolve, reject) => {
      const transaction = database.transaction(EVENTS_STORE, "readonly");
      const index = transaction.objectStore(EVENTS_STORE).index("delivery_state");
      const request = index.getAll(IDBKeyRange.only("queued"));

      request.onsuccess = () => resolve(request.result || []);
      request.onerror = () => reject(request.error);
    });
  } finally {
    database.close();
  }
}

export async function markEventDelivered(eventId) {
  const database = await openDatabase();

  try {
    return await new Promise((resolve, reject) => {
      const transaction = database.transaction(EVENTS_STORE, "readwrite");
      const store = transaction.objectStore(EVENTS_STORE);
      const getReq = store.get(eventId);

      getReq.onsuccess = () => {
        if (getReq.result) {
          store.put({
            ...getReq.result,
            _delivery_state: "delivered",
            _synced_at: new Date().toISOString()
          });
        }
      };
      getReq.onerror = () => reject(getReq.error);
      transaction.oncomplete = () => resolve();
      transaction.onerror = () => reject(transaction.error);
    });
  } finally {
    database.close();
  }
}

export async function markEventQuarantined(eventId, reason = "rejected") {
  const database = await openDatabase();

  try {
    return await new Promise((resolve, reject) => {
      const transaction = database.transaction(EVENTS_STORE, "readwrite");
      const store = transaction.objectStore(EVENTS_STORE);
      const getReq = store.get(eventId);

      getReq.onsuccess = () => {
        if (getReq.result) {
          store.put({
            ...getReq.result,
            _delivery_state: "quarantined",
            _quarantine_reason: String(reason),
            _quarantined_at: new Date().toISOString()
          });
        }
      };
      getReq.onerror = () => reject(getReq.error);
      transaction.oncomplete = () => resolve();
      transaction.onerror = () => reject(transaction.error);
    });
  } finally {
    database.close();
  }
}

export async function markSessionEvents(sessionId, deliveryState) {
  const database = await openDatabase();

  try {
    return await new Promise((resolve, reject) => {
      const transaction = database.transaction(EVENTS_STORE, "readwrite");
      const index = transaction.objectStore(EVENTS_STORE).index("session_id");
      const request = index.openCursor(IDBKeyRange.only(sessionId));

      request.onsuccess = () => {
        const cursor = request.result;
        if (!cursor) return;
        cursor.update({ ...cursor.value, _delivery_state: deliveryState });
        cursor.continue();
      };
      request.onerror = () => reject(request.error);
      transaction.oncomplete = () => resolve();
      transaction.onerror = () => reject(transaction.error);
    });
  } finally {
    database.close();
  }
}

/**
 * Retenção absoluta de 7 dias definida em docs/inventario-dados-v2.md:
 * "Prazo absoluto: sete dias desde a criação, sem extensão por retomada.
 * Apagar/retirar elimina esse registro com todos os eventos juntos."
 *
 * Remove sessões com created_at/started_at acima de 7 dias com todos os
 * seus eventos associados, independentemente de delivered, queued ou quarantined.
 */
export async function enforceAbsoluteRetention(maxAgeDays = 7) {
  const database = await openDatabase();
  const thresholdMs = Date.now() - maxAgeDays * 24 * 60 * 60 * 1000;
  const expiredSessionIds = new Set();
  let purgedSessions = 0;
  let purgedEvents = 0;

  // 1. Identificar e expurgar sessões expiradas (> 7 dias da criação)
  try {
    await new Promise((resolve, reject) => {
      const transaction = database.transaction(SESSIONS_STORE, "readwrite");
      const store = transaction.objectStore(SESSIONS_STORE);
      const request = store.openCursor();

      request.onsuccess = () => {
        const cursor = request.result;
        if (!cursor) return;

        const session = cursor.value;
        const sessionTime = new Date(
          session.created_at || session.startedAt || session.started_at || 0
        ).getTime();

        // Prazo absoluto: sete dias desde a criação, sem extensão por retomada
        if (sessionTime > 0 && sessionTime < thresholdMs) {
          if (session.session_id) {
            expiredSessionIds.add(session.session_id);
          }
          cursor.delete();
          purgedSessions++;
        }
        cursor.continue();
      };

      request.onerror = () => reject(request.error);
      transaction.oncomplete = () => resolve();
      transaction.onerror = () => reject(transaction.error);
    });
  } catch (err) {
    console.warn("Aviso ao expurgar sessões expiradas:", err);
  }

  // 2. Expurgar TODOS os eventos das sessões expiradas (pendentes, entregues ou quarentenados)
  // bem como eventos avulsos/órfãos que excederam o prazo de retenção
  try {
    await new Promise((resolve, reject) => {
      const transaction = database.transaction(EVENTS_STORE, "readwrite");
      const store = transaction.objectStore(EVENTS_STORE);
      const request = store.openCursor();

      request.onsuccess = () => {
        const cursor = request.result;
        if (!cursor) return;

        const ev = cursor.value;
        const belongsToExpiredSession = ev.session_id && expiredSessionIds.has(ev.session_id);
        const evTime = new Date(ev._synced_at || ev.occurred_at || ev.timestamp || 0).getTime();
        const isOrphanExpired = evTime > 0 && evTime < thresholdMs;

        if (belongsToExpiredSession || isOrphanExpired) {
          cursor.delete();
          purgedEvents++;
        }
        cursor.continue();
      };

      request.onerror = () => reject(request.error);
      transaction.oncomplete = () => resolve();
      transaction.onerror = () => reject(transaction.error);
    });
  } catch (err) {
    console.warn("Aviso ao expurgar eventos na retenção:", err);
  }

  return { purgedSessions, purgedEvents };
}

/**
 * Remove eventos já entregues ou expurgados respeitando a retenção absoluta de 7 dias.
 */
export async function pruneDeliveredEvents(maxAgeDays = 7) {
  const result = await enforceAbsoluteRetention(maxAgeDays);
  return result.purgedEvents;
}
