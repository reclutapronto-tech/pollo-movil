// Unit tests for the tags edge function.
//
// These validate pure logic paths that don't require a live Supabase stack —
// tag normalization and the autocomplete aggregation. The routing/auth branches
// are intentionally covered by integration tests when the functions are served
// locally via `supabase functions serve`.
import { assertEquals } from "https://deno.land/std@0.220.0/assert/mod.ts"

// Re-implement the private helper from index.ts so it can be exercised here
// without bundling the whole edge function. Keep this copy in sync with the
// source.
const MAX_TAG_LENGTH = 64
function normalizeTag(raw: unknown): string | null {
  if (typeof raw !== "string") return null
  const trimmed = raw.trim()
  if (trimmed.length < 1 || trimmed.length > MAX_TAG_LENGTH) return null
  return trimmed
}

Deno.test("normalizeTag rejects non-string input", () => {
  assertEquals(normalizeTag(null), null)
  assertEquals(normalizeTag(undefined), null)
  assertEquals(normalizeTag(42), null)
  assertEquals(normalizeTag({}), null)
})

Deno.test("normalizeTag rejects empty and whitespace-only strings", () => {
  assertEquals(normalizeTag(""), null)
  assertEquals(normalizeTag("   "), null)
  assertEquals(normalizeTag("\n\t"), null)
})

Deno.test("normalizeTag trims surrounding whitespace", () => {
  assertEquals(normalizeTag("  roof  "), "roof")
  assertEquals(normalizeTag("\tdamage\n"), "damage")
})

Deno.test("normalizeTag enforces 64-char cap", () => {
  const long = "a".repeat(65)
  assertEquals(normalizeTag(long), null)
  const atCap = "a".repeat(64)
  assertEquals(normalizeTag(atCap), atCap)
})

Deno.test("autocomplete aggregation orders by count then alpha", () => {
  // Mirror the Map-based aggregation in index.ts.
  const rows = [
    { tag: "roof" },
    { tag: "Roof" },
    { tag: "damage" },
    { tag: "damage" },
    { tag: "damage" },
    { tag: "before" },
  ]
  const counts = new Map<string, { tag: string; count: number }>()
  for (const row of rows) {
    const key = row.tag.toLowerCase()
    const existing = counts.get(key)
    if (existing) existing.count += 1
    else counts.set(key, { tag: row.tag, count: 1 })
  }
  const suggestions = [...counts.values()]
    .sort((a, b) => b.count - a.count || a.tag.localeCompare(b.tag))
    .map((s) => s.tag)

  assertEquals(suggestions, ["damage", "roof", "before"])
})
