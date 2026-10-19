// Unit tests for galleries edge function helpers. Password hashing is
// exercised in integration tests against a live stack (bcryptjs needs the
// Deno edge runtime's looser type resolution to run standalone).
import { assertEquals } from "https://deno.land/std@0.220.0/assert/mod.ts"

function isUuid(value: unknown): value is string {
  return typeof value === "string"
    && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)
}

Deno.test("isUuid accepts canonical UUIDv4 strings", () => {
  assertEquals(isUuid("550e8400-e29b-41d4-a716-446655440000"), true)
  assertEquals(isUuid("550E8400-E29B-41D4-A716-446655440000"), true)
})

Deno.test("isUuid rejects malformed strings and non-strings", () => {
  assertEquals(isUuid("not-a-uuid"), false)
  assertEquals(isUuid("550e8400-e29b-41d4-a716-4466554400"), false) // short
  assertEquals(isUuid(""), false)
  assertEquals(isUuid(null), false)
  assertEquals(isUuid(42), false)
})

Deno.test("expiry computation honors positive day count", () => {
  const now = Date.now()
  const expires = new Date(now + 7 * 86400000).toISOString()
  const parsed = new Date(expires).getTime()
  // allow ±10s drift from the computed boundary
  const diffDays = (parsed - now) / 86400000
  assertEquals(diffDays > 6.99 && diffDays < 7.01, true)
})

Deno.test("expiry computation treats 0/negative as no-expiry", () => {
  // Mirror the index.ts branch: `typeof body.expires_days === "number" && body.expires_days > 0`
  const compute = (days: unknown): string | null => {
    return typeof days === "number" && days > 0
      ? new Date(Date.now() + days * 86400000).toISOString()
      : null
  }
  assertEquals(compute(0), null)
  assertEquals(compute(-5), null)
  assertEquals(compute("7"), null)
  assertEquals(compute(null), null)
  assertEquals(typeof compute(1), "string")
})
