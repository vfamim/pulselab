import { ENVIRONMENT } from "./research-session.js";

export const DATABASE_NAME = "pulselab-test-bancada-v2";
const STORE = "sessions";

async function database() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DATABASE_NAME, 1);
    request.onupgradeneeded = () =>
      request.result.createObjectStore(STORE, { keyPath: "id" });
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function transaction(mode, operation) {
  const db = await database();
  try {
    return await new Promise((resolve, reject) => {
      const tx = db.transaction(STORE, mode);
      const result = operation(tx.objectStore(STORE));
      tx.oncomplete = () => resolve(result?.result);
      tx.onerror = () => reject(tx.error);
      tx.onabort = () =>
        reject(tx.error || new Error("Gravação interrompida."));
    });
  } finally {
    db.close();
  }
}

export function saveSession(session) {
  if (
    session.environment !== ENVIRONMENT ||
    !session.consent?.length ||
    !session.consent.every((c) => c.accepted)
  ) {
    return Promise.reject(
      new Error("Sessão não autorizada para este armazenamento."),
    );
  }
  // One transaction includes responses, events, outcomes and the resumable state.
  return transaction("readwrite", (store) => store.put(session));
}

export function listSessions() {
  return transaction("readonly", (store) => store.getAll());
}
export function removeSession(id) {
  return transaction("readwrite", (store) => store.delete(id));
}

export async function pruneExpiredSessions(now = Date.now()) {
  const db = await database();
  try {
    return await new Promise((resolve, reject) => {
      const tx = db.transaction(STORE, "readwrite");
      const request = tx.objectStore(STORE).openCursor();
      let removed = 0;
      request.onsuccess = () => {
        const cursor = request.result;
        if (!cursor) return;
        if (
          !Number.isFinite(cursor.value.expires_at) ||
          cursor.value.expires_at <= now
        ) {
          cursor.delete();
          removed++;
        }
        cursor.continue();
      };
      tx.oncomplete = () => resolve(removed);
      tx.onerror = () => reject(tx.error);
    });
  } finally {
    db.close();
  }
}
