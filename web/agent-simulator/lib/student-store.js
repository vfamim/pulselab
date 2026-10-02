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
 * Remove eventos já entregues com mais de `maxAgeDays` dias para evitar
 * crescimento descontrolado do IndexedDB em máquinas compartilhadas.
 */
export async function pruneDeliveredEvents(maxAgeDays = 7) {
  const database = await openDatabase();
  const thresholdMs = Date.now() - maxAgeDays * 24 * 60 * 60 * 1000;

  try {
    return await new Promise((resolve, reject) => {
      const transaction = database.transaction(EVENTS_STORE, "readwrite");
      const index = transaction.objectStore(EVENTS_STORE).index("delivery_state");
      const request = index.openCursor(IDBKeyRange.only("delivered"));
      let prunedCount = 0;

      request.onsuccess = () => {
        const cursor = request.result;
        if (!cursor) return;

        const event = cursor.value;
        const eventTime = new Date(event._synced_at || event.occurred_at || 0).getTime();
        if (eventTime > 0 && eventTime < thresholdMs) {
          cursor.delete();
          prunedCount++;
        }
        cursor.continue();
      };

      request.onerror = () => reject(request.error);
      transaction.oncomplete = () => resolve(prunedCount);
      transaction.onerror = () => reject(transaction.error);
    });
  } finally {
    database.close();
  }
}
