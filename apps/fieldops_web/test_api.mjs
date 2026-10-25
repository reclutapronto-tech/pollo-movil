import { createClient } from "@supabase/supabase-js";

async function run() {
  const supabaseUrl = process.env.SUPABASE_URL ?? "http://127.0.0.1:54321";
  const supabaseAnonKey = process.env.SUPABASE_ANON_KEY;
  const email = process.env.CI_TEST_EMAIL;
  const password = process.env.CI_TEST_PASSWORD;
  if (!supabaseAnonKey || !email || !password) {
    throw new Error("Set SUPABASE_ANON_KEY, CI_TEST_EMAIL, and CI_TEST_PASSWORD for this local integration script.");
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey);

  const { data: { session }, error: signinError } = await supabase.auth.signInWithPassword({
    email,
    password,
  });

  if (signinError) {
    throw new Error(`Sign in failed: ${signinError.message}`);
  }

  const token = session.access_token;
  const response = await fetch("http://127.0.0.1:54321/functions/v1/schedule?date_from=2026-04-06&date_to=2026-04-12", {
    headers: { Authorization: `Bearer ${token}` }
  });

  const payload = await response.json();
  console.log("GET /schedule successful:", response.ok);
  if (!response.ok) {
    throw new Error(`GET /schedule failed with HTTP ${response.status}: ${JSON.stringify(payload)}`);
  }
  console.log("pto_requests fetched:", Array.isArray(payload.pto_requests) ? payload.pto_requests.length : "NO");

  const copyResponse = await fetch("http://127.0.0.1:54321/functions/v1/schedule", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      "Idempotency-Key": "test-" + Date.now()
    },
    body: JSON.stringify({
      action: "copy_week",
      source_start: "2026-04-06",
      source_end: "2026-04-12",
      target_start: "2026-04-13"
    })
  });

  let copyPayload = null;
  if(copyResponse.headers.get("content-type")?.includes("application/json")) {
    copyPayload = await copyResponse.json();
  } else {
    copyPayload = await copyResponse.text();
  }
  if (!copyResponse.ok) {
    throw new Error(`POST /schedule copy_week failed with HTTP ${copyResponse.status}: ${JSON.stringify(copyPayload)}`);
  }
  console.log("POST /schedule copy_week successful:", copyResponse.ok, copyPayload);
}
run().catch((error) => {
  console.error("Schedule API verification failed.", error.message);
  process.exitCode = 1;
});
