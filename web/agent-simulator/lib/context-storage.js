export const STORED_CONTEXT_KEY = "pulselab_stored_context";

export const PERSISTED_CONTEXT_FIELDS = [
  "site_id",
  "regional_hub",
  "school_code",
  "workshop_code",
  "class_code",
  "group_size",
  "activity_id"
];

function normalizeGroupSize(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 2;
  return Math.max(1, Math.min(4, Math.trunc(parsed)));
}

export function createStoredContext(context) {
  const stored = {};

  for (const field of PERSISTED_CONTEXT_FIELDS) {
    if (field === "group_size") {
      stored[field] = normalizeGroupSize(context[field]);
      continue;
    }

    if (typeof context[field] === "string") {
      stored[field] = context[field];
    }
  }

  return stored;
}

export function sanitizeStoredContext(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return createStoredContext(value);
}
