import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile, unlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { createClient } from "@supabase/supabase-js";

const phaseIndex = process.argv.indexOf("--phase");
const phase = phaseIndex >= 0 ? process.argv[phaseIndex + 1] : "";
const fixturePath = join(process.env.RUNNER_TEMP || tmpdir(), "pollo-movil-restaurant-fixture.json");
const supabaseUrl = process.env.SUPABASE_URL;
const anonKey = process.env.SUPABASE_ANON_KEY;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const functionUrl = supabaseUrl ? supabaseUrl + "/functions/v1/restaurant_ops" : "";

assert.ok(["real", "fallback", "cleanup"].includes(phase), "Pass --phase real, fallback, or cleanup.");
assert.ok(supabaseUrl && anonKey && serviceRoleKey, "Local Supabase environment is required.");
const supabaseHost = new URL(supabaseUrl).hostname;
assert.ok(
  ["127.0.0.1", "localhost", "[::1]"].includes(supabaseHost),
  "Restaurant operations integration must only run against local Supabase.",
);

const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function must(result, label) {
  if (result.error) throw new Error(label + ": " + result.error.message);
  return result.data;
}

function actorClient(accessToken) {
  return createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: "Bearer " + accessToken } },
  });
}

async function authenticate(email, password) {
  const client = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const result = await client.auth.signInWithPassword({ email, password });
  if (result.error || !result.data.session) {
    throw new Error("Local Auth sign-in failed: " + (result.error?.message || "no session returned"));
  }
  return { token: result.data.session.access_token, client: actorClient(result.data.session.access_token) };
}

async function callFunction(action, branchId, token, extra = {}, expectedStatus = 200) {
  const headers = { "Content-Type": "application/json", apikey: anonKey };
  if (token) headers.Authorization = "Bearer " + token;
  const response = await fetch(functionUrl, {
    method: "POST",
    headers,
    body: JSON.stringify({ action, branch_id: branchId, ...extra }),
  });
  const responseText = await response.text();
  let data;
  try {
    data = responseText ? JSON.parse(responseText) : null;
  } catch {
    data = { message: "Response was not JSON." };
  }
  assert.equal(
    response.status,
    expectedStatus,
    "restaurant_ops action " + action + " returned " + response.status + " instead of " + expectedStatus +
      (data?.error ? " (" + data.error + ")" : ""),
  );
  return data;
}

function utcDate(date = new Date()) {
  return date.toISOString().slice(0, 10);
}

function nextUtcDate(value) {
  const date = new Date(value + "T12:00:00.000Z");
  date.setUTCDate(date.getUTCDate() + 1);
  return utcDate(date);
}

async function cleanupFixture(fixture) {
  if (!fixture) return;
  // This workflow owns a disposable local Supabase stack that is stopped after
  // the job. Keep its append-only restaurant events intact; deleting a branch
  // would cascade into event tables and correctly be rejected by their triggers.
}

async function createAuthUser(fixture, companyId, label, role) {
  const id = randomUUID();
  const email = "pollo-ci-" + id + "@example.com";
  const password = "ci-" + randomUUID() + "-Aa9!";
  const result = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: {
      company_id: companyId,
      role,
      full_name: "CI " + label,
    },
  });
  if (result.error || !result.data.user) {
    throw new Error("Create isolated CI Auth user: " + (result.error?.message || "no user returned"));
  }
  fixture.authUserIds.push(result.data.user.id);
  const profile = must(
    await admin.from("users").select("id, company_id, role, is_active").eq("id", result.data.user.id).single(),
    "Read Auth profile created by the existing trigger",
  );
  assert.equal(profile.company_id, companyId);
  assert.equal(profile.role, role);
  assert.equal(profile.is_active, true);
  return { id: result.data.user.id, email, password };
}

async function createPlatformSuperadmin(fixture) {
  const id = randomUUID();
  const email = "pollo-ci-platform-" + id + "@example.com";
  const password = "ci-" + randomUUID() + "-Aa9!";
  const result = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { full_name: "CI Temporary Platform Superadmin" },
  });
  if (result.error || !result.data.user) {
    throw new Error("Create temporary CI platform superadmin: " + (result.error?.message || "no user returned"));
  }
  fixture.authUserIds.push(result.data.user.id);
  must(
    await admin.from("platform_admins").insert({
      auth_user_id: result.data.user.id,
      email,
      full_name: "CI Temporary Platform Superadmin",
      role: "platform_superadmin",
      is_active: true,
    }),
    "Register temporary CI platform superadmin",
  );
  return result.data.user.id;
}

async function authorizeCiBranchPackage(actorId, companyId) {
  must(
    await admin.rpc("platform_set_company_branch_license", {
      p_actor_id: actorId,
      p_company_id: companyId,
      p_package_count: 1,
      p_additional_branch_count: 0,
      p_contract_reference: "CI: isolated five-branch package " + randomUUID(),
      p_annual_price_override_cents: null,
      p_annual_approval_reference: null,
    }),
    "Authorize isolated CI five-branch package through platform RPC",
  );
}

async function expectBranchActivationDenied(companyId, managerId, name, expectedError) {
  const result = await admin.from("restaurant_branches").insert({
    company_id: companyId,
    name,
    timezone: "UTC",
    created_by: managerId,
  }).select("id").single();
  assert.ok(result.error, "Branch activation must be rejected: " + expectedError);
  assert.equal(result.error.code, "23514");
  assert.ok(
    result.error.message.includes(expectedError),
    "Expected " + expectedError + " but received: " + result.error.message,
  );
}

async function realSolverAndOperations() {
  const fixture = { authUserIds: [], branchIds: [] };
  let saved = false;
  try {
    const company = must(
      await admin.from("companies").insert({
        name: "Pollo Móvil CI " + randomUUID().slice(0, 8),
        slug: "pollo-movil-ci-" + randomUUID(),
        timezone: "UTC",
      }).select("id").single(),
      "Create isolated CI company",
    );
    fixture.companyId = company.id;
    const platformSuperadminId = await createPlatformSuperadmin(fixture);
    await authorizeCiBranchPackage(platformSuperadminId, company.id);

    const manager = await createAuthUser(fixture, company.id, "Supervisor", "supervisor");
    const cookA = await createAuthUser(fixture, company.id, "Cook A", "worker");
    const cookB = await createAuthUser(fixture, company.id, "Cook B", "worker");
    const cashier = await createAuthUser(fixture, company.id, "Cashier", "worker");
    const absentCook = await createAuthUser(fixture, company.id, "Absent Cook", "worker");
    fixture.manager = { email: manager.email, password: manager.password };
    fixture.workerIds = [cookA.id, cookB.id, cashier.id, absentCook.id];

    const unlicensedCompany = must(
      await admin.from("companies").insert({
        name: "Pollo Móvil CI Unlicensed " + randomUUID().slice(0, 8),
        slug: "pollo-movil-ci-unlicensed-" + randomUUID(),
        timezone: "UTC",
      }).select("id").single(),
      "Create isolated unlicensed CI company",
    );
    const unlicensedManager = await createAuthUser(fixture, unlicensedCompany.id, "Unlicensed Supervisor", "supervisor");
    await expectBranchActivationDenied(
      unlicensedCompany.id,
      unlicensedManager.id,
      "CI must reject branch without license " + randomUUID().slice(0, 8),
      "BRANCH_LICENSE_REQUIRED",
    );

    const managerAuth = await authenticate(manager.email, manager.password);
    const workerAAuth = await authenticate(cookA.email, cookA.password);
    const workerBAuth = await authenticate(cookB.email, cookB.password);
    const cashierAuth = await authenticate(cashier.email, cashier.password);
    const branch = must(
      await admin.from("restaurant_branches").insert({
        company_id: company.id,
        name: "CI Operations " + randomUUID().slice(0, 8),
        timezone: "UTC",
        created_by: manager.id,
      }).select("id, enable_time_clock, require_gps_for_time_clock").single(),
      "Create isolated CI branch",
    );
    fixture.branchIds.push(branch.id);
    const otherBranch = must(
      await admin.from("restaurant_branches").insert({
        company_id: company.id,
        name: "CI Isolated " + randomUUID().slice(0, 8),
        timezone: "UTC",
        created_by: manager.id,
      }).select("id").single(),
      "Create branch for row-isolation check",
    );
    fixture.branchIds.push(otherBranch.id);

    // Fill the authorized five-branch package, then prove the sixth activation
    // is rejected by the production capacity trigger rather than bypassed.
    for (let index = 0; index < 3; index += 1) {
      const capacityBranch = must(
        await admin.from("restaurant_branches").insert({
          company_id: company.id,
          name: "CI Capacity " + (index + 1) + " " + randomUUID().slice(0, 8),
          timezone: "UTC",
          created_by: manager.id,
        }).select("id").single(),
        "Fill isolated CI package capacity",
      );
      fixture.branchIds.push(capacityBranch.id);
    }
    await expectBranchActivationDenied(
      company.id,
      manager.id,
      "CI must reject branch above package capacity " + randomUUID().slice(0, 8),
      "BRANCH_LICENSE_CAPACITY_EXCEEDED",
    );

    assert.equal(branch.enable_time_clock, false, "Attendance must default to disabled.");
    assert.equal(branch.require_gps_for_time_clock, false, "GPS must default to disabled.");

    const memberships = [
      { user_id: manager.id, access_role: "supervisor" },
      { user_id: cookA.id, access_role: "employee" },
      { user_id: cookB.id, access_role: "employee" },
      { user_id: cashier.id, access_role: "employee" },
      { user_id: absentCook.id, access_role: "employee" },
    ].map((membership) => ({
      branch_id: branch.id,
      company_id: company.id,
      created_by: manager.id,
      ...membership,
    }));
    must(await admin.from("restaurant_memberships").insert(memberships), "Create branch memberships");

    const positions = must(
      await admin.from("restaurant_positions").insert([
        { branch_id: branch.id, name: "CI Cook" },
        { branch_id: branch.id, name: "CI Cashier" },
      ]).select("id, name"),
      "Create role positions",
    );
    const cookPositionId = positions.find((position) => position.name === "CI Cook").id;
    const cashierPositionId = positions.find((position) => position.name === "CI Cashier").id;
    must(await admin.from("restaurant_member_positions").insert([
      { branch_id: branch.id, user_id: cookA.id, position_id: cookPositionId },
      { branch_id: branch.id, user_id: cookB.id, position_id: cookPositionId },
      { branch_id: branch.id, user_id: absentCook.id, position_id: cookPositionId },
      { branch_id: branch.id, user_id: cashier.id, position_id: cashierPositionId },
    ]), "Set worker position qualifications");

    const today = utcDate();
    const shiftRows = [cookA.id, cookB.id, cashier.id, absentCook.id].map((employeeId) => ({
      branch_id: branch.id,
      employee_id: employeeId,
      shift_date: today,
      start_time: "00:00:00",
      end_time: "23:59:00",
      status: "published",
      created_by: manager.id,
    }));
    must(await admin.from("restaurant_shifts").insert(shiftRows), "Create published CI shifts");
    must(await admin.from("restaurant_absences").insert({
      branch_id: branch.id,
      employee_id: absentCook.id,
      start_date: today,
      end_date: today,
      status: "approved",
      note: "Automated CI fixture",
      created_by: manager.id,
    }), "Create approved CI absence");

    const otherBranchTask = must(
      await admin.from("restaurant_tasks").insert({
        branch_id: otherBranch.id,
        scheduled_for: today,
        task_source: "conditional",
        name: "Isolated CI record",
        estimated_minutes: 10,
        difficulty: 1,
        priority: 1,
      }).select("id").single(),
      "Create a protected record in the other branch",
    );
    assert.ok(otherBranchTask.id);

    const weekday = new Date(today + "T12:00:00.000Z").getUTCDay() || 7;
    const templates = must(
      await admin.from("restaurant_activity_templates").insert(
        Array.from({ length: 5 }, (_, index) => ({
          branch_id: branch.id,
          name: "CI scheduled task " + (index + 1),
          activity_type: "scheduled",
          schedule_days: [weekday],
          estimated_minutes: 10,
          difficulty: 2,
          priority: 3,
          is_divisible: false,
          interruptible: true,
        })),
      ).select("id"),
      "Create scheduled activity templates",
    );
    must(await admin.from("restaurant_activity_positions").insert(
      templates.map((template) => ({
        branch_id: branch.id,
        activity_template_id: template.id,
        position_id: cookPositionId,
      })),
    ), "Configure required positions for scheduled activities");

    const noAuth = await callFunction("branches", branch.id, null, {}, 401);
    assert.ok(noAuth, "Unauthenticated requests must return a structured response.");
    await callFunction("auto_assign", branch.id, cashierAuth.token, { for_date: today }, 403);

    const isolation = must(
      await cashierAuth.client.from("restaurant_tasks").select("id").eq("branch_id", otherBranch.id),
      "Check cross-branch RLS isolation",
    );
    assert.deepEqual(isolation, [], "A member without access must not read another branch.");

    const schedule = await callFunction("schedule_tasks", branch.id, managerAuth.token, { for_date: today });
    assert.equal(schedule.created_count, 5, "All scheduled templates should materialize for the configured weekday.");
    const beforeAssignment = must(
      await admin.from("restaurant_tasks").select("id, activity_template_id").eq("branch_id", branch.id)
        .eq("scheduled_for", today).eq("task_source", "scheduled"),
      "Read materialized scheduled tasks",
    );
    assert.equal(beforeAssignment.length, 5);

    const moveTaskId = beforeAssignment[0].id;
    const tomorrow = nextUtcDate(today);
    await callFunction("reschedule_task", branch.id, managerAuth.token, {
      task_id: moveTaskId,
      scheduled_for: tomorrow,
    });
    const movedTask = must(
      await admin.from("restaurant_tasks").select("scheduled_for").eq("id", moveTaskId).single(),
      "Verify calendar reprogramming persisted",
    );
    assert.equal(movedTask.scheduled_for, tomorrow);

    const timefoldResult = await callFunction("auto_assign", branch.id, managerAuth.token, { for_date: today });
    assert.equal(timefoldResult.planner, "timefold", "Assignments must be produced by the real Timefold service.");
    assert.equal("fallback_reason" in timefoldResult, false, "A successful Timefold run must not report a fallback.");
    assert.equal(timefoldResult.assigned_count, 4);
    const assignedTasks = must(
      await admin.from("restaurant_tasks").select("id, assigned_to, status").eq("branch_id", branch.id)
        .eq("scheduled_for", today).eq("task_source", "scheduled"),
      "Verify assignment persistence in PostgreSQL",
    );
    const assignedForToday = assignedTasks.filter((task) => task.assigned_to);
    assert.equal(assignedForToday.length, 4);
    assert.ok(assignedForToday.every((task) => [cookA.id, cookB.id].includes(task.assigned_to)),
      "Wrong-position and absent employees must never receive a cook task.");
    const loadA = assignedForToday.filter((task) => task.assigned_to === cookA.id).length;
    const loadB = assignedForToday.filter((task) => task.assigned_to === cookB.id).length;
    assert.ok(Math.abs(loadA - loadB) <= 1, "Assignments should be distributed fairly across eligible workers.");
    const visibleOwnTasks = must(
      await cashierAuth.client.from("restaurant_tasks").select("id").eq("branch_id", branch.id),
      "Check branch-member RLS visibility",
    );
    assert.equal(visibleOwnTasks.length, 5);

    const employeeForAssignedTask = assignedForToday.find((task) => task.assigned_to === cookA.id)
      ? { id: cookA.id, auth: workerAAuth }
      : { id: cookB.id, auth: workerBAuth };
    const taskForLifecycle = assignedForToday.find((task) => task.assigned_to === employeeForAssignedTask.id);
    assert.ok(taskForLifecycle);
    const actionBase = Date.now() - 30_000;
    const lifecycleEvents = ["start", "pause", "resume", "complete"].map(() => randomUUID());
    for (let index = 0; index < 4; index += 1) {
      await callFunction("task_action", branch.id, employeeForAssignedTask.auth.token, {
        task_id: taskForLifecycle.id,
        task_action: ["start", "pause", "resume", "complete"][index],
        client_event_id: lifecycleEvents[index],
        offline_replay: true,
        occurred_at: new Date(actionBase + index * 5_000).toISOString(),
      });
    }
    const replay = await callFunction("task_action", branch.id, employeeForAssignedTask.auth.token, {
      task_id: taskForLifecycle.id,
      task_action: "complete",
      client_event_id: lifecycleEvents[3],
      offline_replay: true,
      occurred_at: new Date(actionBase + 15_000).toISOString(),
    });
    assert.equal(replay.replayed, true, "Replaying an offline event must be idempotent.");
    const completedTask = must(
      await admin.from("restaurant_tasks").select("status, completed_by").eq("id", taskForLifecycle.id).single(),
      "Verify task completion persistence",
    );
    assert.equal(completedTask.status, "completed");
    assert.equal(completedTask.completed_by, employeeForAssignedTask.id);
    const lifecycleRows = must(
      await admin.from("restaurant_task_events").select("id").eq("task_id", taskForLifecycle.id)
        .eq("actor_id", employeeForAssignedTask.id),
      "Verify offline task events were persisted",
    );
    assert.equal(lifecycleRows.length, 4);

    const featureUpdate = await callFunction("save_branch_features", branch.id, managerAuth.token, {
      enable_time_clock: true,
      require_gps_for_time_clock: false,
    });
    assert.equal(featureUpdate.enable_time_clock, true);
    assert.equal(featureUpdate.require_gps_for_time_clock, false);
    const clockBase = Date.now() - 60_000;
    const clockInEvent = randomUUID();
    const clockOutEvent = randomUUID();
    const clockIn = await callFunction("record_time_event", branch.id, employeeForAssignedTask.auth.token, {
      event_type: "clock_in",
      client_event_id: clockInEvent,
      occurred_at: new Date(clockBase).toISOString(),
    });
    await callFunction("record_time_event", branch.id, employeeForAssignedTask.auth.token, {
      event_type: "clock_out",
      client_event_id: clockOutEvent,
      occurred_at: new Date(clockBase + 10_000).toISOString(),
    });
    const clockSession = must(
      await admin.from("restaurant_time_sessions").select("clock_in_latitude, clock_in_longitude, clock_out_latitude")
        .eq("id", clockIn.session_id).single(),
      "Verify attendance persisted without GPS collection",
    );
    assert.equal(clockSession.clock_in_latitude, null);
    assert.equal(clockSession.clock_in_longitude, null);
    assert.equal(clockSession.clock_out_latitude, null);

    const wasteBins = must(
      await admin.from("restaurant_waste_bins").insert(["CI Bin 1", "CI Bin 2", "CI Bin 3"].map((name, index) => ({
        branch_id: branch.id,
        name,
        sort_order: index,
        bag_change_activity_name: name + " bag change",
        bag_change_minutes: 10,
        bag_change_difficulty: 2,
        bag_change_priority: 3,
      }))).select("id, name"),
      "Create three isolated waste bins with their configured replacement policy",
    );
    must(await admin.from("restaurant_waste_positions").insert({
      branch_id: branch.id,
      position_id: cookPositionId,
    }), "Configure eligible positions for waste tasks");
    const wasteInspection = await callFunction("inspect_waste", branch.id, employeeForAssignedTask.auth.token, {
      client_event_id: randomUUID(),
      offline_replay: true,
      occurred_at: new Date().toISOString(),
      results: wasteBins.map((bin, index) => ({
        bin_id: bin.id,
        state: index === 1 ? "half" : "full",
      })),
    }, 201);
    assert.ok(wasteInspection.inspection_id);
    const inspectionResults = must(
      await admin.from("restaurant_waste_inspection_results").select("bin_id, declared_state")
        .eq("inspection_id", wasteInspection.inspection_id),
      "Verify all three bin inspection results persisted",
    );
    assert.equal(inspectionResults.length, 3);
    const fullBins = inspectionResults.filter((result) => result.declared_state === "full");
    assert.equal(fullBins.length, 2);
    const wasteTasks = must(
      await admin.from("restaurant_tasks").select("id, assigned_to").eq("branch_id", branch.id)
        .eq("task_source", "waste"),
      "Verify full bins produced corrective waste tasks",
    );
    assert.equal(wasteTasks.length, 2);
    const wasteAssignment = await callFunction("auto_assign", branch.id, managerAuth.token, { for_date: today });
    assert.equal(wasteAssignment.planner, "timefold");
    assert.equal(wasteAssignment.assigned_count, 2);
    const persistedWasteTasks = must(
      await admin.from("restaurant_tasks").select("assigned_to").eq("branch_id", branch.id)
        .eq("task_source", "waste"),
      "Verify waste task assignments were persisted",
    );
    assert.ok(persistedWasteTasks.every((task) => [cookA.id, cookB.id].includes(task.assigned_to)));

    const incidentResponse = await callFunction("create_incident", branch.id, employeeForAssignedTask.auth.token, {
      description: "CI inspection found a maintenance issue.",
      urgency: "high",
      client_event_id: randomUUID(),
      offline_replay: true,
      occurred_at: new Date().toISOString(),
    }, 201);
    assert.ok(incidentResponse.incident_id);
    const incident = must(
      await admin.from("restaurant_incidents").select("description, urgency, reported_by")
        .eq("id", incidentResponse.incident_id).single(),
      "Verify offline incident persistence",
    );
    assert.equal(incident.urgency, "high");
    assert.equal(incident.reported_by, employeeForAssignedTask.id);

    const fallbackTemplate = must(
      await admin.from("restaurant_activity_templates").insert({
        branch_id: branch.id,
        name: "CI explicit fallback task",
        activity_type: "conditional",
        schedule_days: [],
        estimated_minutes: 10,
        difficulty: 1,
        priority: 2,
        is_divisible: false,
        interruptible: true,
      }).select("id").single(),
      "Create conditional task for the explicit fallback check",
    );
    must(await admin.from("restaurant_activity_positions").insert({
      branch_id: branch.id,
      activity_template_id: fallbackTemplate.id,
      position_id: cookPositionId,
    }), "Set the conditional task's required position");
    const fallbackTask = await callFunction("create_task", branch.id, managerAuth.token, {
      template_id: fallbackTemplate.id,
      scheduled_for: today,
      client_event_id: randomUUID(),
    }, 201);
    fixture.fallbackTaskId = fallbackTask.task_id;
    fixture.manager = { email: manager.email, password: manager.password };
    await writeFile(fixturePath, JSON.stringify(fixture), { mode: 0o600 });
    saved = true;
    console.log("PASS Auth, role denial, and branch-isolated RLS.");
    console.log("PASS CI-only platform superadmin authorized the five-branch package through the real licensing RPC.");
    console.log("PASS Branch activation is rejected without a license and above the licensed capacity.");
    console.log("PASS Calendar materialization and rescheduling.");
    console.log("PASS Timefold authenticated optimization, eligibility, fairness, and PostgreSQL persistence.");
    console.log("PASS Offline start/pause/resume/complete replay and event idempotency.");
    console.log("PASS Optional attendance with GPS disabled and no location values stored.");
    console.log("PASS Three-bin waste inspection and two generated/assigned corrective tasks.");
    console.log("PASS Offline incident persistence.");
  } finally {
    if (!saved) await cleanupFixture(fixture);
  }
}

async function fallbackAndCleanup() {
  let fixture;
  try {
    fixture = JSON.parse(await readFile(fixturePath, "utf8"));
    const managerAuth = await authenticate(fixture.manager.email, fixture.manager.password);
    const response = await callFunction("auto_assign", fixture.branchIds[0], managerAuth.token, {
      for_date: utcDate(),
    });
    assert.equal(response.planner, "local", "A stopped Timefold service must use the explicit local fallback.");
    assert.equal(response.fallback_reason, "request_failed", "The fallback reason must identify the solver connection failure.");
    assert.ok(response.assigned_count >= 1, "The explicit fallback should persist the pending CI assignment.");
    const assignment = must(
      await admin.from("restaurant_tasks").select("assigned_to").eq("id", fixture.fallbackTaskId).single(),
      "Verify explicit fallback assignment persisted",
    );
    assert.ok(fixture.workerIds.includes(assignment.assigned_to));
    console.log("PASS Timefold outage was surfaced as planner=local with fallback_reason=request_failed.");
  } finally {
    if (fixture) await cleanupFixture(fixture);
    await unlink(fixturePath).catch((error) => {
      if (error.code !== "ENOENT") throw error;
    });
  }
}

async function cleanupOnly() {
  try {
    const fixture = JSON.parse(await readFile(fixturePath, "utf8"));
    await cleanupFixture(fixture);
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  } finally {
    await unlink(fixturePath).catch((error) => {
      if (error.code !== "ENOENT") throw error;
    });
  }
}

if (phase === "real") await realSolverAndOperations();
if (phase === "fallback") await fallbackAndCleanup();
if (phase === "cleanup") await cleanupOnly();
