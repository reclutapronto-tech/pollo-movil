import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  resolveSupabasePublishableKey,
  resolveSupabaseSecretKey,
} from "./supabase-admin-key.ts";

Deno.test("resolves the default Supabase secret key without logging it", () => {
  assertEquals(
    resolveSupabaseSecretKey('{"default":"unit-test-key","other":"unused-key"}'),
    "unit-test-key",
  );
});

Deno.test("rejects missing or malformed Supabase secret key configuration", () => {
  assertThrows(() => resolveSupabaseSecretKey(undefined), Error);
  assertThrows(() => resolveSupabaseSecretKey("not-json"), Error);
  assertThrows(() => resolveSupabaseSecretKey('{"other":"key"}'), Error);
});

Deno.test("resolves the default Supabase publishable key without logging it", () => {
  assertEquals(
    resolveSupabasePublishableKey('{"default":"unit-test-public-key","other":"unused-key"}'),
    "unit-test-public-key",
  );
});

Deno.test("rejects missing or malformed Supabase publishable key configuration", () => {
  assertThrows(() => resolveSupabasePublishableKey(undefined), Error);
  assertThrows(() => resolveSupabasePublishableKey("not-json"), Error);
  assertThrows(() => resolveSupabasePublishableKey('{"other":"key"}'), Error);
});
