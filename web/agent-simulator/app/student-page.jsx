import React, { useEffect, useMemo, useRef, useState } from "react";
import {
  CONFIG_HASH,
  PROTOCOL_VERSION,
  createUuid,
  formatEventName
} from "../lib/contracts.js";
import {
  enforceAbsoluteRetention,
  purgeSession,
  saveEvent,
  saveSession,
  getLocalStoreSummary
} from "../lib/student-store.js";
import {
  flushPendingEvents,
  syncSingleEvent
} from "../lib/sync-engine.js";
import {
  isResearchAuthorized,
  validateRestoredSession,
  downloadSessionData,
  structuralSpikeMetrics
} from "../lib/evaluation.js";

const ACTIVE_SESSION_KEY = "pulselab_student_active_session_v1";
const CONTEXT_KEY = "pulselab_student_context_v1";
const INSTALLATION_KEY = "pulselab_installation_id_v1";
const LEGACY_INSTALLATION_KEY = "pulselab_student_installation_id_v1";
const CLIENT_VERSION = "student-pwa/2.2.5";

const DEFAULT_CONTEXT = {
  regional: "Nordeste",
  site_id: "Polo-Nordeste",
  school: "geral",
  workshop: "oficina-spike",
  class: "turma-geral",
  activity: "atividade-01-spike"
};

const BRIDGE_PORT = 43128;
const BRIDGE_URL = `http://127.0.0.1:${BRIDGE_PORT}`;

async function notifyBridgeSession(sessionId, startedAt, marks = [], allowed = true) {
  if (!allowed) return;
  try {
    await fetch(`${BRIDGE_URL}/v1/sessions`, {
      signal: AbortSignal.timeout(1500),
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ session_id: sessionId, started_at: startedAt, marks })
    });
  } catch {
    // Operação normal mesmo sem o Bridge
  }
}

async function fetchBridgeSpikeMetrics() {
  try {
    const res = await fetch(`${BRIDGE_URL}/v1/spike/metrics`, { signal: AbortSignal.timeout(1500) });
    if (res.ok) {
      return structuralSpikeMetrics(await res.json());
    }
  } catch {
    // Bridge offline ou inacessível
  }
  return null;
}

async function fetchBridgeConfig() {
  try {
    const res = await fetch(`${BRIDGE_URL}/v1/config`, { signal: AbortSignal.timeout(1500) });
    if (res.ok) {
      return await res.json();
    }
  } catch {
    // Bridge offline ou inacessível
  }
  return null;
}

async function notifyBridgeEvent(event, allowed = true) {
  if (!allowed) return;
  try {
    await fetch(`${BRIDGE_URL}/v1/events`, {
      signal: AbortSignal.timeout(1500),
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(event)
    });
  } catch {
    // Operação normal mesmo sem o Bridge
  }
}

async function notifyBridgeSessionSave(sessionPayload, allowed = true) {
  if (!allowed) return;
  try {
    await fetch(`${BRIDGE_URL}/v1/sessions/save`, {
      signal: AbortSignal.timeout(1500),
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(sessionPayload)
    });
  } catch {
    // Operação normal mesmo sem o Bridge
  }
}

async function resetBridgeSession(sessionId = null, options = {}) {
  const response = await fetch(`${BRIDGE_URL}/v1/sessions/reset`, {
    signal: AbortSignal.timeout(1500),
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      session_id: sessionId,
      reason: options.reason || (options.purge ? "ethical_withdrawal" : "prepare_next"),
      purge: Boolean(options.purge),
      completed: Boolean(options.completed)
    })
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || (options.purge && (payload.purged !== true || payload.remote_pending === true))) {
    throw new Error(payload.error || payload.status || `Bridge reset failed (${response.status})`);
  }
  return payload;
}

function readJson(key, fallback) {
  try {
    const value = localStorage.getItem(key);
    return value ? JSON.parse(value) : fallback;
  } catch {
    return fallback;
  }
}

function getPersistedInstallationId() {
  try {
    return localStorage.getItem(INSTALLATION_KEY) || localStorage.getItem(LEGACY_INSTALLATION_KEY) || null;
  } catch {
    return null;
  }
}

function getInstallationId(fallbackId = null) {
  return getPersistedInstallationId() || fallbackId || createUuid();
}

function getComputerId(installationId) {
  const id = installationId || getPersistedInstallationId() || "000000";
  return `PC-${id.slice(0, 6).toUpperCase()}`;
}

function getSystemMetadata() {
  if (typeof window === "undefined") return { os: "Desktop", screen_resolution: "1920x1080" };
  const userAgent = navigator.userAgent || "";
  let os = "Desktop";
  if (userAgent.includes("Windows")) os = "Windows";
  else if (userAgent.includes("Linux")) os = "Linux";
  else if (userAgent.includes("Android")) os = "Android";
  else if (userAgent.includes("Mac")) os = "macOS";
  else if (userAgent.includes("CrOS")) os = "ChromeOS";

  return {
    os,
    screen_resolution: `${window.screen?.width || 0}x${window.screen?.height || 0}`
  };
}

function EvidencePanel({ events }) {
  const ordered = [...events].sort((left, right) => (right._sequence || 0) - (left._sequence || 0));
  return (
    <aside className="evidence-panel">
      <header className="evidence-panel__header">
        <div>
          <span>Somente laboratório</span>
          <h2>Outbox local</h2>
        </div>
        <span className="quality-pill quality-pill--neutral">{events.length} eventos</span>
      </header>
      <div className="event-list">
        {ordered.length ? ordered.map((event) => (
          <article className="event-row" key={event.event_id}>
            <span className="event-row__icon">•</span>
            <span>
              <strong>{formatEventName(event.event_type)}</strong>
              <small>{event.activity_stage || "sessão"}</small>
            </span>
            <span className={`delivery delivery--${event._delivery_state}`}>{event._delivery_state}</span>
          </article>
        )) : (
          <div className="empty-events">
            <span>○</span>
            <p>Os eventos da bancada aparecerão aqui.</p>
          </div>
        )}
      </div>
    </aside>
  );
}

export default function StudentPage() {
  const labMode = useMemo(() => {
    if (typeof window === "undefined") return false;
    return new URLSearchParams(window.location.search).get("lab") === "1";
  }, []);

  const [configResolved, setConfigResolved] = useState(false);
  const [isResearchActive, setIsResearchActive] = useState(false);
  const [isFreeMode, setIsFreeMode] = useState(true);
  const [groupSize, setGroupSize] = useState(2);

  const [sessionId, setSessionId] = useState(null);
  const [groupId, setGroupId] = useState(null);
  const [installationId, setInstallationId] = useState(() => getInstallationId());
  const [startedAt, setStartedAt] = useState(null);
  const [timeline, setTimeline] = useState([]);
  const [spikeTelemetry, setSpikeTelemetry] = useState(null);
  const [context, setContext] = useState(() => readJson(CONTEXT_KEY, DEFAULT_CONTEXT));

  const [toast, setToast] = useState("");
  const [storageError, setStorageError] = useState("");
  const [dbPendingCount, setDbPendingCount] = useState(0);
  const [dbQuarantinedCount, setDbQuarantinedCount] = useState(0);
  const [dbTotalStoredCount, setDbTotalStoredCount] = useState(0);

  const configResolvedRef = useRef(false);
  const isResearchActiveRef = useRef(false);
  const isFreeModeRef = useRef(true);
  const isWithdrawnRef = useRef(false);
  const sessionStartedEmittedRef = useRef(false);
  const sequenceRef = useRef(0);
  const startedAtRef = useRef(null);
  const monotonicAnchorRef = useRef(null);
  const writesRef = useRef(new Set());
  const bridgeWritesRef = useRef(new Set());
  const generationRef = useRef(0);
  const withdrawalChannelRef = useRef(null);
  const telemetryRef = useRef(null);
  const isSubmittingRef = useRef(false);

  function computeElapsedMs() {
    if (monotonicAnchorRef.current && typeof performance !== "undefined" && typeof performance.now === "function") {
      const delta = Math.round(performance.now() - monotonicAnchorRef.current.perfStart);
      return Math.max(0, (monotonicAnchorRef.current.elapsedBase || 0) + delta);
    }
    const now = Date.now();
    return startedAtRef.current ? Math.max(0, now - startedAtRef.current) : 0;
  }

  function trackWrite(promise) {
    writesRef.current.add(promise);
    promise.then(() => writesRef.current.delete(promise), () => writesRef.current.delete(promise));
    return promise;
  }

  function trackBridgeWrite(promise) {
    bridgeWritesRef.current.add(promise);
    promise.then(() => bridgeWritesRef.current.delete(promise), () => bridgeWritesRef.current.delete(promise));
    return promise;
  }

  function reportStorageError() {
    setStorageError("Aviso de armazenamento local; o uso do robô permanece inalterado.");
  }

  const refreshDeliveryCounts = React.useCallback(async () => {
    try {
      const summary = await getLocalStoreSummary();
      setDbPendingCount(summary.pendingCount);
      setDbQuarantinedCount(summary.quarantinedCount);
      setDbTotalStoredCount(summary.totalRecords);
    } catch {
      // IndexedDB indisponível
    }
  }, []);

  function flash(message) {
    setToast(message);
    window.setTimeout(() => setToast(""), 3200);
  }

  async function withdrawSession(broadcast = true) {
    isWithdrawnRef.current = true;
    isResearchActiveRef.current = false;
    isFreeModeRef.current = true;
    generationRef.current += 1;
    isSubmittingRef.current = true;

    setIsResearchActive(false);
    setIsFreeMode(true);
    setTimeline([]);
    setSpikeTelemetry(null);
    telemetryRef.current = null;
    startedAtRef.current = null;
    monotonicAnchorRef.current = null;

    try {
      localStorage.removeItem(ACTIVE_SESSION_KEY);
      localStorage.removeItem(INSTALLATION_KEY);
      localStorage.removeItem(LEGACY_INSTALLATION_KEY);
      if (typeof sessionStorage !== "undefined") {
        sessionStorage.removeItem("pulselab_tab_session_id");
      }
    } catch {
      reportStorageError();
    }

    if (broadcast && sessionId) {
      withdrawalChannelRef.current?.postMessage({ type: "withdraw", sessionId });
    }

    isSubmittingRef.current = false;

    await Promise.allSettled([...writesRef.current]);
    if (sessionId) {
      await purgeSession(sessionId).catch(reportStorageError);
      void refreshDeliveryCounts();
      await Promise.allSettled([...bridgeWritesRef.current]);
      try {
        await resetBridgeSession(sessionId, { reason: "ethical_withdrawal", purge: true });
      } catch {
        setStorageError("Os dados foram expurgados no navegador; o computador confirma a exclusão.");
      }
    }
  }

  useEffect(() => {
    const channel = new BroadcastChannel("pulselab-session-control");
    withdrawalChannelRef.current = channel;
    channel.onmessage = ({ data }) => {
      if (data?.type === "withdraw" && data.sessionId === sessionId) {
        void withdrawSession(false);
      }
    };
    return () => {
      channel.close();
      withdrawalChannelRef.current = null;
    };
  }, [sessionId]);

  function eventBase(eventType, overrides = {}) {
    const now = Date.now();
    sequenceRef.current += 1;
    const sysMeta = getSystemMetadata();
    return {
      event_id: createUuid(),
      session_id: sessionId,
      dyad_id: groupId,
      group_id: groupId,
      installation_id: installationId,
      site_id: context.site_id || `Polo-${context.regional || "Nordeste"}`,
      regional_hub: context.regional || "Nordeste",
      school_code: context.school || "geral",
      workshop_code: context.workshop || "oficina-spike",
      class_code: context.class || "turma-geral",
      activity_id: context.activity || "atividade-01-spike",
      computer_id: getComputerId(installationId),
      protocol_version: PROTOCOL_VERSION,
      occurred_at: new Date(now).toISOString(),
      elapsed_ms: overrides.elapsed_ms !== undefined ? overrides.elapsed_ms : computeElapsedMs(),
      client_version: CLIENT_VERSION,
      config_version: "student-pwa-v2",
      config_hash: CONFIG_HASH,
      _delivery_state: "queued",
      _sequence: sequenceRef.current,
      _client_occurred_at: new Date(now).toISOString(),
      event_type: eventType,
      ...(labMode ? { is_synthetic: true } : {}),
      ...overrides
    };
  }

  function updateEventDeliveryState(eventId, state) {
    setTimeline((prev) =>
      prev.map((ev) => (ev.event_id === eventId ? { ...ev, _delivery_state: state } : ev))
    );
    void refreshDeliveryCounts();
  }

  function persist(event) {
    if (
      !configResolvedRef.current ||
      !isResearchActiveRef.current ||
      isFreeModeRef.current ||
      isWithdrawnRef.current
    ) return;
    void trackWrite(saveEvent(event)).then(() => {
      void refreshDeliveryCounts();
    }).catch(reportStorageError);
    void trackBridgeWrite(notifyBridgeEvent(event, isResearchActiveRef.current));
    if (typeof navigator !== "undefined" && navigator.onLine) {
      void syncSingleEvent(event).then((result) => {
        if (result && result.success === true) {
          updateEventDeliveryState(event.event_id, "delivered");
        } else if (result && result.quarantined) {
          updateEventDeliveryState(event.event_id, "quarantined");
        }
        void refreshDeliveryCounts();
      });
    }
  }

  function emitTimeline(eventType, overrides = {}) {
    if (
      !configResolvedRef.current ||
      !isResearchActiveRef.current ||
      isFreeModeRef.current ||
      isWithdrawnRef.current
    ) return null;
    const sysMeta = getSystemMetadata();
    const event = eventBase(eventType, {
      _target_table: "research_session_events",
      severity: "info",
      interval_mark: null,
      participant_id: null,
      participant_role: null,
      activity_stage: overrides.activity_stage || "oficina_coletiva",
      scheduled_at: null,
      details: {
        runtime: "browser_pwa",
        os: sysMeta.os,
        screen_resolution: sysMeta.screen_resolution,
        group_size: groupSize,
        collective_unit: "bancada",
        ...(labMode ? { is_synthetic: true } : {}),
        ...overrides.details
      },
      ...overrides
    });
    setTimeline((current) => [...current, event]);
    persist(event);
    return event;
  }

  useEffect(() => {
    let isMounted = true;

    async function resolveConfigAndSession() {
      // 1. Retenção absoluta de 7 dias executada no mount
      enforceAbsoluteRetention(7).catch(() => {});
      void refreshDeliveryCounts();

      // 2. Busca configuração institucional do Bridge
      const cfg = await fetchBridgeConfig();
      if (!isMounted) return;

      configResolvedRef.current = true;
      setConfigResolved(true);

      const authorized = isResearchAuthorized(cfg);
      if (!authorized) {
        // Configuração inválida ou ausente => Modo Livre interno, zero pesquisa!
        // Não apaga indiscriminadamente sessões válidas de outra autorização ainda vigente,
        // mas garante Modo Livre com zero transmissão e zero persistência de pesquisa.
        setIsFreeMode(true);
        isFreeModeRef.current = true;
        setIsResearchActive(false);
        isResearchActiveRef.current = false;
        return;
      }

      // Configuração válida => ativa bancada coletiva de pesquisa
      setIsFreeMode(false);
      isFreeModeRef.current = false;
      setIsResearchActive(true);
      isResearchActiveRef.current = true;
      setGroupSize(cfg.group_size);

      if (cfg.site_id && cfg.site_id !== "CONFIGURE_SEDE") {
        setContext((prev) => ({ ...prev, site_id: cfg.site_id }));
      }
      if (cfg.regional_hub) {
        setContext((prev) => ({ ...prev, regional: cfg.regional_hub }));
      }
      if (cfg.school_code && cfg.school_code !== "CONFIGURE_ESCOLA") {
        setContext((prev) => ({ ...prev, school: cfg.school_code }));
      }
      if (cfg.workshop_code && cfg.workshop_code !== "CONFIGURE_OFICINA") {
        setContext((prev) => ({ ...prev, workshop: cfg.workshop_code }));
      }
      if (cfg.class_code && cfg.class_code !== "CONFIGURE_TURMA") {
        setContext((prev) => ({ ...prev, class: cfg.class_code }));
      }
      if (cfg.activity_id) {
        setContext((prev) => ({ ...prev, activity: cfg.activity_id }));
      }

      // 3. Verifica sessão ativa salva para manter idempotência após reload na mesma aba
      const rawSaved = readJson(ACTIVE_SESSION_KEY, null);
      let isSameTab = false;
      try {
        isSameTab =
          typeof sessionStorage !== "undefined" &&
          sessionStorage.getItem("pulselab_tab_session_id") === rawSaved?.sessionId;
      } catch {}

      // Apenas restaura se for a mesma sessão na mesma aba recarregada e salva recentemente (< 30 min)
      const isFresh =
        rawSaved?.savedAt &&
        Date.now() - new Date(rawSaved.savedAt).getTime() < 30 * 60 * 1000;

      const restored = validateRestoredSession(rawSaved, { maxAgeMs: 30 * 60 * 1000 });

      if (restored && restored.sessionId && isSameTab && isFresh) {
        // Reload idempotente da mesma bancada em andamento sem duplicar session_started
        setSessionId(restored.sessionId);
        setGroupId(restored.groupId || restored.sessionId);
        setStartedAt(restored.startedAt);
        startedAtRef.current = restored.startedAt;
        const lastElapsed = Array.isArray(restored.timeline) && restored.timeline.length > 0
          ? Math.max(0, ...restored.timeline.map((ev) => Number(ev?.elapsed_ms) || 0))
          : (Number(restored.elapsed_ms) || 0);
        if (typeof performance !== "undefined" && typeof performance.now === "function") {
          monotonicAnchorRef.current = { perfStart: performance.now(), elapsedBase: lastElapsed };
        }
        setTimeline(Array.isArray(restored.timeline) ? restored.timeline : []);
        sessionStartedEmittedRef.current = true;
        if (restored.spikeTelemetry) {
          setSpikeTelemetry(restored.spikeTelemetry);
          telemetryRef.current = restored.spikeTelemetry;
        }
        return;
      }

      // Se havia sessão antiga de outro grupo ou stale, descarta da superfície infantil e inicia estado neutro limpo
      if (rawSaved) {
        try {
          localStorage.removeItem(ACTIVE_SESSION_KEY);
        } catch {}
      }

      // 4. Inicia sessão coletiva automaticamente se ainda não iniciada
      if (!sessionStartedEmittedRef.current) {
        const newSessionId = createUuid();
        const newGroupId = createUuid();
        const now = Date.now();
        setSessionId(newSessionId);
        setGroupId(newGroupId);
        setStartedAt(now);
        startedAtRef.current = now;
        sessionStartedEmittedRef.current = true;
        if (typeof performance !== "undefined" && typeof performance.now === "function") {
          monotonicAnchorRef.current = { perfStart: performance.now(), elapsedBase: 0 };
        }

        try {
          localStorage.setItem(INSTALLATION_KEY, installationId);
          if (typeof sessionStorage !== "undefined") {
            sessionStorage.setItem("pulselab_tab_session_id", newSessionId);
          }
        } catch {}

        const startEvent = {
          event_id: createUuid(),
          session_id: newSessionId,
          dyad_id: newGroupId,
          group_id: newGroupId,
          installation_id: installationId,
          site_id: cfg.site_id && cfg.site_id !== "CONFIGURE_SEDE" ? cfg.site_id : (context.site_id || "Polo-Nordeste"),
          regional_hub: cfg.regional_hub || context.regional || "Nordeste",
          school_code: cfg.school_code && cfg.school_code !== "CONFIGURE_ESCOLA" ? cfg.school_code : "geral",
          workshop_code: cfg.workshop_code && cfg.workshop_code !== "CONFIGURE_OFICINA" ? cfg.workshop_code : "oficina-spike",
          class_code: cfg.class_code && cfg.class_code !== "CONFIGURE_TURMA" ? cfg.class_code : "turma-geral",
          activity_id: cfg.activity_id || context.activity || "atividade-01-spike",
          computer_id: getComputerId(installationId),
          protocol_version: PROTOCOL_VERSION,
          occurred_at: new Date(now).toISOString(),
          elapsed_ms: 0,
          client_version: CLIENT_VERSION,
          config_version: "student-pwa-v2",
          config_hash: CONFIG_HASH,
          _delivery_state: "queued",
          _sequence: 1,
          _client_occurred_at: new Date(now).toISOString(),
          _target_table: "research_session_events",
          event_type: "session_started",
          severity: "info",
          interval_mark: null,
          participant_id: null,
          participant_role: null,
          activity_stage: "oficina_coletiva",
          scheduled_at: null,
          details: {
            runtime: "browser_pwa",
            group_size: cfg.group_size,
            research_authorization_version: cfg.research_authorization_version,
            collective_unit: "bancada",
            ...(labMode ? { is_synthetic: true } : {})
          }
        };

        sequenceRef.current = 1;
        setTimeline([startEvent]);

        void trackWrite(saveEvent(startEvent)).then(() => {
          void refreshDeliveryCounts();
        }).catch(reportStorageError);

        void trackBridgeWrite(notifyBridgeSession(newSessionId, now, [], true));
        void trackBridgeWrite(notifyBridgeEvent(startEvent, true));

        const snapshot = {
          sessionId: newSessionId,
          session_id: newSessionId,
          groupId: newGroupId,
          group_id: newGroupId,
          installation_id: installationId,
          startedAt: now,
          started_at: new Date(now).toISOString(),
          group_size: cfg.group_size,
          teamSize: cfg.group_size,
          isFreeMode: false,
          timeline: [startEvent],
          status: "in_progress",
          savedAt: new Date().toISOString()
        };

        try {
          localStorage.setItem(ACTIVE_SESSION_KEY, JSON.stringify(snapshot));
        } catch {}

        void trackWrite(saveSession(snapshot)).catch(reportStorageError);
      }
    }

    resolveConfigAndSession();

    // Expurgador periódico de hora em hora
    const retentionInterval = setInterval(() => {
      enforceAbsoluteRetention(7).catch(() => {});
    }, 60 * 60 * 1000);

    return () => {
      isMounted = false;
      clearInterval(retentionInterval);
    };
  }, []);

  // Monitora e atualiza snapshot coletivo de sessão
  useEffect(() => {
    if (
      !configResolvedRef.current ||
      !isResearchActiveRef.current ||
      isFreeModeRef.current ||
      isWithdrawnRef.current ||
      !sessionId
    ) return;

    const snapshot = {
      sessionId,
      session_id: sessionId,
      groupId,
      group_id: groupId,
      installation_id: installationId,
      startedAt,
      started_at: startedAt ? new Date(startedAt).toISOString() : null,
      group_size: groupSize,
      teamSize: groupSize,
      timeline,
      spikeTelemetry,
      isFreeMode: false,
      status: "in_progress",
      savedAt: new Date().toISOString()
    };

    try {
      localStorage.setItem(ACTIVE_SESSION_KEY, JSON.stringify(snapshot));
    } catch {}

    void trackWrite(saveSession(snapshot)).catch(reportStorageError);
    void trackBridgeWrite(notifyBridgeSessionSave(snapshot, isResearchActiveRef.current));
  }, [timeline, spikeTelemetry, sessionId, groupId, startedAt, groupSize]);

  // Coleta periódica de telemetria estrutural do robô LEGO SPIKE
  useEffect(() => {
    if (!configResolved || !isResearchActive || isFreeMode || !sessionId) return undefined;

    let cancelled = false;
    const generation = generationRef.current;

    const pollSpike = async () => {
      if (cancelled || generation !== generationRef.current || !isResearchActiveRef.current || isFreeModeRef.current || isWithdrawnRef.current || isSubmittingRef.current) return;
      const metrics = await fetchBridgeSpikeMetrics();
      if (cancelled || generation !== generationRef.current || !isResearchActiveRef.current || isFreeModeRef.current || isWithdrawnRef.current || isSubmittingRef.current) return;
      if (metrics && metrics.project_saved !== false) {
        const previous = telemetryRef.current;
        const first = !previous || (!previous.executable_blocks && metrics.executable_blocks > 0);
        if (first || previous.executable_blocks !== metrics.executable_blocks) {
          emitTimeline("spike_telemetry", {
            activity_stage: first ? "primeira_programacao_detectada" : "atualizacao_codigo_spike",
            details: {
              executable_blocks: metrics.executable_blocks,
              top_level_stacks: metrics.top_level_stacks,
              uses_motor: metrics.uses_motor,
              uses_sensor: metrics.uses_sensor,
              uses_loop: metrics.uses_loop,
              uses_condition: metrics.uses_condition,
              first_coding_detected: first,
              elapsed_ms: startedAtRef.current ? Math.max(0, Date.now() - startedAtRef.current) : 0
            }
          });
        }
        telemetryRef.current = metrics;
        setSpikeTelemetry(metrics);
      }
    };

    const firstCheck = window.setTimeout(pollSpike, 2000);
    const spikeInterval = window.setInterval(pollSpike, 10000);

    return () => {
      cancelled = true;
      window.clearTimeout(firstCheck);
      window.clearInterval(spikeInterval);
    };
  }, [configResolved, isResearchActive, isFreeMode, sessionId]);

  // Sincronização em background store-and-forward fail-closed
  useEffect(() => {
    if (!configResolved || !isResearchActive || isFreeMode) {
      return undefined;
    }

    const handleOnline = () => {
      if (
        !configResolvedRef.current ||
        !isResearchActiveRef.current ||
        isFreeModeRef.current ||
        isWithdrawnRef.current
      ) {
        return;
      }
      void runSync();
    };

    window.addEventListener("online", handleOnline);
    void runSync();

    const syncTimer = window.setInterval(() => {
      if (
        configResolvedRef.current &&
        isResearchActiveRef.current &&
        !isFreeModeRef.current &&
        !isWithdrawnRef.current &&
        typeof navigator !== "undefined" &&
        navigator.onLine
      ) {
        void runSync();
      }
    }, 20000);

    return () => {
      window.removeEventListener("online", handleOnline);
      window.clearInterval(syncTimer);
    };
  }, [configResolved, isResearchActive, isFreeMode]);

  async function runSync() {
    if (
      !configResolvedRef.current ||
      !isResearchActiveRef.current ||
      isFreeModeRef.current ||
      isWithdrawnRef.current
    ) {
      return;
    }
    if (typeof navigator !== "undefined" && !navigator.onLine) return;
    try {
      await flushPendingEvents((syncedId) => {
        updateEventDeliveryState(syncedId, "delivered");
      });
      await refreshDeliveryCounts();
    } catch {
      // Falha de rede silenciosa
    }
  }

  // Ações exclusivas para diagnóstico no Modo Laboratório (?lab=1)
  function triggerSyntheticSpike() {
    if (!labMode) return;
    const synthMetrics = {
      executable_blocks: Math.floor(Math.random() * 20) + 5,
      top_level_stacks: 2,
      uses_motor: true,
      uses_sensor: true,
      uses_loop: true,
      uses_condition: false,
      project_saved: true
    };
    setSpikeTelemetry(synthMetrics);
    telemetryRef.current = synthMetrics;
    emitTimeline("spike_telemetry", {
      activity_stage: "simulacao_laboratorio",
      details: synthMetrics
    });
    flash("Telemetria SPIKE sintética simulada com sucesso.");
  }

  function downloadSession() {
    if (!labMode) return;
    const rawData = {
      session_id: sessionId,
      group_id: groupId,
      installation_id: installationId,
      site_id: context.site_id,
      regional_hub: context.regional,
      school_code: context.school,
      workshop_code: context.workshop,
      class_code: context.class,
      activity_id: context.activity,
      started_at: startedAt ? new Date(startedAt).toISOString() : null,
      group_size: groupSize,
      is_free_mode: isFreeMode,
      spike_telemetry: spikeTelemetry,
      events: timeline
    };

    const validated = downloadSessionData(rawData, {
      isFreeMode,
      researchAuthorized: isResearchActive
    });
    if (!validated) {
      flash("Exportação bloqueada no Modo Livre ou sem autorização válida.");
      return;
    }

    const payload = JSON.stringify(validated, null, 2);
    const blob = new Blob([payload], { type: "application/json" });
    const link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = `sessao-bancada-${(sessionId || "vazia").slice(0, 8)}.json`;
    link.click();
    URL.revokeObjectURL(link.href);
    flash("Sessão exportada em JSON.");
  }

  // ROTA NORMAL SILENCIOSA DE ALUNOS:
  // Não mostra formulários, perguntas, cartões de etapas, botões, Área do Educador, IDs, status técnicos ou avaliações.
  // Renderiza somente o fallback não interativo: “Oficina de robótica em andamento. Use o aplicativo LEGO SPIKE.”
  if (!labMode) {
    return (
      <main className="app-shell student-app student-app--silent">
        <div className="silent-bench-container">
          <div className="silent-bench-icon" aria-hidden="true">
            <svg className="student-brand__mark" viewBox="0 0 32 32" aria-hidden="true" focusable="false" width="48" height="48">
              <path d="M3 17h6l4-9 6 16 4-7h6" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
              <circle cx="3" cy="17" r="2" fill="currentColor" />
              <circle cx="29" cy="17" r="2" fill="currentColor" />
            </svg>
          </div>
          <h1 className="silent-bench-message">Oficina de robótica em andamento. Use o aplicativo LEGO SPIKE.</h1>
          <p className="silent-bench-guidance">Monte, programe e teste o seu robô na bancada.</p>
          <div className="silent-bench-status" role="status" aria-live="polite">
            <span className="silent-bench-status__dot" aria-hidden="true" />
            <span>Oficina pronta</span>
          </div>
          {storageError && <div className="silent-bench-notice" role="status">{storageError}</div>}
        </div>
      </main>
    );
  }

  // DIAGNÓSTICO SINTÉTICO SEPARADO PARA LABORATÓRIO (?lab=1)
  return (
    <main className="app-shell student-app student-app--lab">
      <div className="silent-bench-container">
        <h1 className="silent-bench-message">Oficina de robótica em andamento. Use o aplicativo LEGO SPIKE.</h1>
      </div>
      <aside className="lab-diagnostic" aria-label="Diagnóstico Sintético">
        <div className="lab-diagnostic__card">
          <span className="eyebrow">Diagnóstico de Laboratório</span>
          <h2>Modo de Inspeção Sintética (?lab=1)</h2>
          <p>oficina de robótica · v2.2.5</p>
          <div className="lab-diagnostic__status">
            <div>Configuração: {configResolved ? (isResearchActive ? "Pesquisa autorizada" : "Modo Livre (sem pesquisa)") : "Resolvendo..."}</div>
            <div>Bancada: Coletiva (Tamanho: {groupSize})</div>
            <div>Sessão ID: {sessionId || "nenhuma"}</div>
            <div>Eventos na sessão: {timeline.length}</div>
            <div>IndexedDB: {dbTotalStoredCount} registros ({dbPendingCount} pendentes, {dbQuarantinedCount} quarentena)</div>
            {spikeTelemetry && (
              <div>SPIKE: {spikeTelemetry.executable_blocks ?? 0} blocos executáveis | Motores: {spikeTelemetry.uses_motor ? "Sim" : "Não"}</div>
            )}
          </div>
          <div className="action-row">
            <button className="button button--ghost" type="button" onClick={triggerSyntheticSpike}>Simular Telemetria SPIKE</button>
            <button className="button button--ghost" type="button" onClick={() => void withdrawSession()}>Testar Retirada Ética</button>
            {isResearchActive && <button className="button button--ghost" type="button" onClick={downloadSession}>Exportar Dados da Sessão (.json)</button>}
          </div>
          <EvidencePanel events={timeline} />
        </div>
      </aside>
      {toast && <div className="toast" role="status">{toast}</div>}
      {storageError && <div className="storage-notice" role="alert">{storageError}</div>}
    </main>
  );
}
