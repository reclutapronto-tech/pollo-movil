/**
 * Resolves the current server-side Supabase secret API key.
 *
 * Supabase injects SUPABASE_SECRET_KEYS as a JSON map keyed by API-key name.
 * Keep the legacy service-role environment variable out of application code so
 * deployed functions cannot silently fall back to a compromised key.
 */
export function resolveSupabaseSecretKey(rawSecretKeys: string | undefined): string {
  if (!rawSecretKeys) {
    throw new Error("Supabase secret API key configuration is missing.");
  }

  let secretKeys: unknown;
  try {
    secretKeys = JSON.parse(rawSecretKeys);
  } catch {
    throw new Error("Supabase secret API key configuration is invalid.");
  }

  if (
    typeof secretKeys !== "object" ||
    secretKeys === null ||
    !("default" in secretKeys) ||
    typeof secretKeys.default !== "string" ||
    secretKeys.default.length === 0
  ) {
    throw new Error("The default Supabase secret API key is not configured.");
  }

  return secretKeys.default;
}

export function getSupabaseSecretKey(): string {
  return resolveSupabaseSecretKey(Deno.env.get("SUPABASE_SECRET_KEYS"));
}

/**
 * Resolves the current Supabase publishable API key. Edge Functions use this
 * key for requests carrying an end-user JWT; privileged operations use the
 * secret key above.
 */
export function resolveSupabasePublishableKey(rawPublishableKeys: string | undefined): string {
  if (!rawPublishableKeys) {
    throw new Error("Supabase publishable API key configuration is missing.");
  }

  let publishableKeys: unknown;
  try {
    publishableKeys = JSON.parse(rawPublishableKeys);
  } catch {
    throw new Error("Supabase publishable API key configuration is invalid.");
  }

  if (
    typeof publishableKeys !== "object" ||
    publishableKeys === null ||
    !("default" in publishableKeys) ||
    typeof publishableKeys.default !== "string" ||
    publishableKeys.default.length === 0
  ) {
    throw new Error("The default Supabase publishable API key is not configured.");
  }

  return publishableKeys.default;
}

export function getSupabasePublishableKey(): string {
  return resolveSupabasePublishableKey(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS"));
}
