// PulseLab Supabase Edge Function: enroll-device
// Exchanges one single-use enrollment token for a device session.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Cache-Control": "no-store",
  "Content-Type": "application/json",
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers });
}

function isUuid(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers });
  }
  if (request.method !== "POST") {
    return json(405, { error: "Method not allowed." });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !serviceKey || !anonKey) {
    return json(500, { error: "Enrollment service is not configured." });
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return json(400, { error: "Invalid JSON request body." });
  }

  const installationId = body.installation_id;
  const siteId = typeof body.site_id === "string" ? body.site_id.trim() : "";
  const enrollmentToken = typeof body.enrollment_token === "string"
    ? body.enrollment_token.trim()
    : "";

  if (!isUuid(installationId) || !siteId || enrollmentToken.length < 32) {
    return json(400, {
      error: "A valid installation_id, site_id, and enrollment_token are required.",
    });
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const now = new Date().toISOString();
  const tokenHash = await sha256(enrollmentToken);

  // This conditional UPDATE is the authorization boundary. Only one concurrent
  // caller can transition consumed_at from NULL, and it happens before any Auth
  // user is created or changed.
  const { data: tokenRows, error: consumeError } = await admin
    .from("device_enrollment_tokens")
    .update({ consumed_at: now })
    .eq("token_hash", tokenHash)
    .eq("installation_id", installationId)
    .eq("site_id", siteId)
    .is("consumed_at", null)
    .gt("expires_at", now)
    .select("id,installation_id,site_id,regional_hub,school_code,computer_id");

  if (consumeError || tokenRows?.length !== 1) {
    return json(401, { error: "Invalid, expired, or consumed enrollment token." });
  }
  const enrollment = tokenRows[0];

  // Re-enrollment is an explicit administrative operation: never silently
  // reactivate a revoked installation or rotate an existing user's password.
  const { data: existingInstallation, error: installationLookupError } = await admin
    .from("device_installations")
    .select("id")
    .eq("installation_id", installationId)
    .maybeSingle();
  if (installationLookupError) {
    return json(500, { error: "Could not verify installation state." });
  }
  if (existingInstallation) {
    return json(409, { error: "Installation is already registered." });
  }

  const deviceEmail = `device-${installationId}@device.pulselab.internal`;
  const devicePassword = `${crypto.randomUUID()}${crypto.randomUUID()}`;
  const { data: userData, error: createError } = await admin.auth.admin.createUser({
    email: deviceEmail,
    password: devicePassword,
    email_confirm: true,
    app_metadata: { role: "device" },
  });
  if (createError || !userData.user) {
    // The token remains consumed. An administrator must investigate and issue a
    // new token; this prevents retry races from mutating an existing account.
    return json(409, { error: "Device account already exists or could not be created." });
  }

  const userId = userData.user.id;
  const { error: bindingError } = await admin.from("device_installations").insert({
    device_user_id: userId,
    installation_id: installationId,
    site_id: siteId,
    regional_hub: enrollment.regional_hub,
    school_code: enrollment.school_code,
    computer_id: enrollment.computer_id,
    is_active: true,
    enrolled_at: now,
    updated_at: now,
  });
  if (bindingError) {
    await admin.auth.admin.deleteUser(userId).catch(() => undefined);
    return json(500, { error: "Could not bind the device installation." });
  }

  await admin.from("device_enrollment_tokens")
    .update({ consumed_by: userId })
    .eq("id", enrollment.id);

  const authClient = createClient(supabaseUrl, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: login, error: loginError } = await authClient.auth.signInWithPassword({
    email: deviceEmail,
    password: devicePassword,
  });
  if (loginError || !login.session) {
    await admin.from("device_installations")
      .update({ is_active: false, updated_at: new Date().toISOString() })
      .eq("device_user_id", userId);
    return json(500, { error: "Could not create the device session." });
  }

  return json(200, {
    installation_id: installationId,
    site_id: siteId,
    user_id: userId,
    access_token: login.session.access_token,
    refresh_token: login.session.refresh_token,
    expires_at: login.session.expires_at,
  });
});
