import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.4"
import { corsHeaders, errorResponse, jsonResponse, logRequestError, makeRequestId } from "../_shared/api.ts"
import { planRestaurantAssignments, type AssignmentCandidate, type AssignmentUnit } from "../_shared/restaurant-optimizer.ts"
import { tryTimefoldAssignmentPlan } from "../_shared/timefold-client.ts"

const ENDPOINT = "restaurant_ops"
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

class OpsError extends Error {
  constructor(readonly status: number, readonly code: string, message: string) {
    super(message)
  }
}

function fail(status: number, code: string, message: string): never {
  throw new OpsError(status, code, message)
}

function requiredString(value: unknown, field: string, maxLength = 160): string {
  if (typeof value !== "string" || !value.trim() || value.trim().length > maxLength) {
    fail(400, "INVALID_PAYLOAD", `${field} is required.`)
  }
  return value.trim()
}

function requiredUuid(value: unknown, field: string): string {
  if (typeof value !== "string" || !UUID.test(value)) fail(400, "INVALID_PAYLOAD", `${field} must be a UUID.`)
  return value
}

function dateInZone(timezone: string, date = new Date()): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date)
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]))
  return `${values.year}-${values.month}-${values.day}`
}

function timeInZone(timezone: string, value: unknown): string | null {
  if (typeof value !== "string") return null
  const date = new Date(value)
  if (!Number.isFinite(date.getTime())) return null
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: timezone, hour: "2-digit", minute: "2-digit", hourCycle: "h23",
  }).format(date)
}

function localClockToUtc(date: string, time: string, timezone: string): string {
  const [year, month, day] = date.split("-").map(Number)
  const [hour, minute] = time.split(":").map(Number)
  const target = Date.UTC(year, month - 1, day, hour, minute)
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone, year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", hourCycle: "h23",
  }).formatToParts(new Date(target))
  const values = Object.fromEntries(parts.map((part) => [part.type, Number(part.value)]))
  const represented = Date.UTC(values.year, values.month - 1, values.day, values.hour, values.minute)
  return new Date(target + (target - represented)).toISOString()
}

function localDateTimeToUtc(value: string, timezone: string): string | null {
  const match = /^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2})$/.exec(value)
  if (!match || !isCalendarDate(match[1])) return null
  const [hour, minute] = match[2].split(":").map(Number)
  if (hour > 23 || minute > 59) return null
  const utc = localClockToUtc(match[1], match[2], timezone)
  const parsed = new Date(utc)
  if (dateInZone(timezone, parsed) !== match[1] || timeInZone(timezone, utc) !== match[2]) return null
  return utc
}

function declaredTimestamp(value: unknown, timezone: string): string | null {
  if (value == null || value === "") return null
  if (typeof value !== "string") fail(400, "INVALID_DECLARED_MEAL_TIME", "La hora declarada debe ser una fecha válida.")
  const absoluteTimestamp = /(?:Z|[+-]\d{2}:\d{2})$/i.test(value)
  const parsed = absoluteTimestamp
    ? new Date(value)
    : new Date(localDateTimeToUtc(value, timezone) ?? Number.NaN)
  if (!Number.isFinite(parsed.getTime()) || parsed.getTime() > Date.now() + 60_000) {
    fail(400, "INVALID_DECLARED_MEAL_TIME", "La hora declarada debe ser válida y no futura.")
  }
  return parsed.toISOString()
}

function addDays(date: string, days: number): string {
  const result = new Date(`${date}T12:00:00Z`)
  result.setUTCDate(result.getUTCDate() + days)
  return result.toISOString().slice(0, 10)
}

function isCalendarDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false
  const parsed = new Date(`${value}T00:00:00Z`)
  return Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value
}

async function stableFingerprint(value: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(JSON.stringify(value))
  const digest = await crypto.subtle.digest("SHA-256", bytes)
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("")
}

function assertNoError<T>(result: { data: T; error: { message: string } | null }): T {
  if (result.error) throw new Error(result.error.message)
  return result.data
}

async function memberForBranch(
  admin: SupabaseClient,
  branchId: string,
  userId: string,
  managerOnly = false,
) {
  const { data, error } = await admin.from("restaurant_memberships")
    .select("branch_id, company_id, user_id, access_role, is_active, customer_service_active")
    .eq("branch_id", branchId).eq("user_id", userId).eq("is_active", true).maybeSingle()
  if (error) throw error
  if (!data) fail(403, "BRANCH_ACCESS_REQUIRED", "You are not an active member of this branch.")
  if (managerOnly && !["admin", "supervisor"].includes(data.access_role)) {
    fail(403, "MANAGER_REQUIRED", "A branch administrator or supervisor must perform this action.")
  }
  return data
}

async function ensureEmployeeAvailableForNewAssignment(
  admin: SupabaseClient, branchId: string, employeeId: string, scheduledFor: string, localDate: string,
) {
  if (scheduledFor !== localDate) return
  const [stateResult, mealResult] = await Promise.all([
    admin.from("restaurant_member_operational_states").select("state")
      .eq("branch_id", branchId).eq("employee_id", employeeId).maybeSingle(),
    admin.from("restaurant_meal_sessions").select("id")
      .eq("branch_id", branchId).eq("employee_id", employeeId).is("return_confirmed_at", null).limit(1),
  ])
  const state = assertNoError(stateResult)?.state
  const activeMeal = assertNoError(mealResult) ?? []
  if (["meal", "rest", "off_shift"].includes(String(state)) || activeMeal.length > 0) {
    fail(409, "EMPLOYEE_OPERATIONALLY_UNAVAILABLE", "No se pueden crear asignaciones nuevas mientras la persona está en comida, descanso o fuera de turno.")
  }
}

async function getBranches(admin: SupabaseClient, userId: string) {
  const memberships = assertNoError(await admin.from("restaurant_memberships")
    .select("branch_id, access_role").eq("user_id", userId).eq("is_active", true)) ?? []
  const ids = memberships.map((row: { branch_id: string }) => row.branch_id)
  if (ids.length === 0) return []
  const branches = assertNoError(await admin.from("restaurant_branches")
    .select("id, company_id, name, timezone, is_active, enable_time_clock, require_gps_for_time_clock, meal_duration_minutes, collaboration_reservation_seconds, collaboration_manager_escalation_seconds, minimum_area_coverage").in("id", ids).eq("is_active", true)) ?? []
  return branches.map((branch: Record<string, unknown>) => ({
    ...branch,
    access_role: memberships.find((item: { branch_id: string }) => item.branch_id === branch.id)?.access_role,
  }))
}

async function getSettings(admin: SupabaseClient, branchId: string, companyId: string, requestedShiftStart?: string | null) {
  const branch = assertNoError(await admin.from("restaurant_branches")
    .select("id, name, timezone, company_id, enable_time_clock, require_gps_for_time_clock, meal_duration_minutes, collaboration_reservation_seconds, receipt_escalation_seconds_by_priority, collaboration_manager_escalation_seconds, minimum_area_coverage, assignment_load_balance_weight, assignment_heavy_rotation_weight, assignment_priority_weight").eq("id", branchId).single())
  const localDate = dateInZone(branch.timezone)
  const requestedDate = requestedShiftStart && /^\d{4}-\d{2}-\d{2}$/.test(requestedShiftStart)
    ? new Date(`${requestedShiftStart}T00:00:00.000Z`) : null
  const shiftStart = typeof requestedShiftStart === "string" && requestedDate && Number.isFinite(requestedDate.getTime())
    && requestedDate.toISOString().slice(0, 10) === requestedShiftStart ? requestedShiftStart : localDate
  const shiftEnd = addDays(shiftStart, 6)
  const [areas, positions, templates, templatePositions, zones, memberships, users, shifts, breaks, absences, bins, memberPositions, wastePositions, inspectionTemplates, inspectionItems, scheduledTasks] = await Promise.all([
    admin.from("restaurant_areas").select("id, name, sort_order, is_active").eq("branch_id", branchId).order("sort_order"),
    admin.from("restaurant_positions").select("id, name, is_active, area_id").eq("branch_id", branchId).order("name"),
    admin.from("restaurant_activity_templates").select("*").eq("branch_id", branchId).order("name"),
    admin.from("restaurant_activity_positions").select("activity_template_id, position_id").eq("branch_id", branchId),
    admin.from("restaurant_activity_zones").select("id, activity_template_id, name, estimated_minutes, difficulty, sort_order").eq("branch_id", branchId).order("sort_order"),
    admin.from("restaurant_memberships").select("user_id, access_role, is_active, customer_service_active").eq("branch_id", branchId),
    admin.from("users").select("id, full_name, email, is_active").eq("company_id", companyId).eq("is_active", true),
    admin.from("restaurant_shifts").select("id, employee_id, shift_date, start_time, end_time, status").eq("branch_id", branchId).gte("shift_date", addDays(shiftStart, -1)).lte("shift_date", shiftEnd).order("shift_date").order("start_time"),
    admin.from("restaurant_shift_breaks").select("id, shift_id, start_time, end_time").eq("branch_id", branchId),
    admin.from("restaurant_absences").select("id, employee_id, start_date, end_date, status, note").eq("branch_id", branchId).neq("status", "denied").order("start_date"),
    admin.from("restaurant_waste_bins").select("id, name, sort_order, is_active, inspection_interval_minutes, last_state, last_inspected_at, last_bag_changed_at, bag_change_activity_name, bag_change_minutes, bag_change_difficulty, bag_change_priority").eq("branch_id", branchId).order("sort_order"),
    admin.from("restaurant_member_positions").select("user_id, position_id").eq("branch_id", branchId),
    admin.from("restaurant_waste_positions").select("position_id").eq("branch_id", branchId),
    admin.from("restaurant_inspection_templates").select("*").eq("branch_id", branchId).order("name"),
    admin.from("restaurant_inspection_items").select("*").eq("branch_id", branchId).order("sort_order"),
    admin.from("restaurant_tasks").select("id, activity_template_id, name, area_id, scheduled_for, task_source, status, assigned_to, estimated_minutes, priority")
      .eq("branch_id", branchId).gte("scheduled_for", shiftStart).lte("scheduled_for", shiftEnd)
      .order("scheduled_for").order("priority", { ascending: false }).order("created_at"),
  ])
  const data = {
    branch, areas: assertNoError(areas) ?? [], positions: assertNoError(positions) ?? [],
    templates: assertNoError(templates) ?? [], templatePositions: assertNoError(templatePositions) ?? [],
    zones: assertNoError(zones) ?? [], memberships: assertNoError(memberships) ?? [],
    users: assertNoError(users) ?? [], shifts: assertNoError(shifts) ?? [], breaks: assertNoError(breaks) ?? [],
    absences: assertNoError(absences) ?? [], bins: assertNoError(bins) ?? [],
    memberPositions: assertNoError(memberPositions) ?? [], wastePositions: assertNoError(wastePositions) ?? [],
    inspectionTemplates: assertNoError(inspectionTemplates) ?? [],
    inspectionItems: assertNoError(inspectionItems) ?? [],
    scheduledTasks: assertNoError(scheduledTasks) ?? [],
  }
  return {
    ...data,
    members: data.memberships.map((membership: Record<string, unknown>) => ({
      ...membership,
      user: data.users.find((user: Record<string, unknown>) => user.id === membership.user_id) ?? null,
      position_ids: data.memberPositions.filter((row: Record<string, unknown>) => row.user_id === membership.user_id)
        .map((row: { position_id: string }) => row.position_id),
    })).filter((membership: Record<string, unknown>) => membership.is_active),
    users: data.users,
    employees_available_to_add: data.users.filter((user: Record<string, unknown>) =>
      user.is_active && !data.memberships.some((membership: Record<string, unknown>) =>
        membership.user_id === user.id && membership.is_active)),
    waste_position_ids: data.wastePositions.map((row: { position_id: string }) => row.position_id),
    inspection_templates: data.inspectionTemplates.map((template: Record<string, unknown>) => ({
      ...template,
      items: data.inspectionItems.filter((item: Record<string, unknown>) =>
        item.template_id === template.id && item.is_active),
    })),
    scheduled_tasks: data.scheduledTasks.map((task: Record<string, unknown>) => ({
      ...task,
      area_name: data.areas.find((area: Record<string, unknown>) => area.id === task.area_id)?.name ?? null,
      assigned_name: data.users.find((employee: Record<string, unknown>) => employee.id === task.assigned_to)?.full_name
        ?? data.users.find((employee: Record<string, unknown>) => employee.id === task.assigned_to)?.email ?? null,
    })),
  }
}

async function getNotificationInbox(admin: SupabaseClient, branchId: string, userId: string) {
  const operationalState = assertNoError(await admin.from("restaurant_member_operational_states")
    .select("state").eq("branch_id", branchId).eq("employee_id", userId).maybeSingle())
  const activeMeal = assertNoError(await admin.from("restaurant_meal_sessions").select("id")
    .eq("branch_id", branchId).eq("employee_id", userId).is("return_confirmed_at", null).limit(1)) ?? []
  if (["meal", "rest"].includes(String(operationalState?.state)) || activeMeal.length > 0) {
    return { notifications: [], unread_count: 0, delivery_paused: true }
  }
  const [notifications, unread] = await Promise.all([
    admin.from("restaurant_notifications")
      .select("id, notification_type, title, body, entity_type, entity_id, data, created_at, read_at")
      .eq("branch_id", branchId).eq("recipient_id", userId)
      .order("created_at", { ascending: false }).limit(100),
    admin.from("restaurant_notifications")
      .select("id", { count: "exact", head: true })
      .eq("branch_id", branchId).eq("recipient_id", userId).is("read_at", null),
  ])
  if (notifications.error) throw notifications.error
  if (unread.error) throw unread.error
  const rows = notifications.data ?? []
  const taskIds = [...new Set(rows
    .filter((item: Record<string, unknown>) => item.entity_type === "task")
    .map((item: Record<string, unknown>) => item.entity_id)
    .filter((id: unknown): id is string => typeof id === "string"))]
  const taskRows = taskIds.length
    ? assertNoError(await admin.from("restaurant_tasks")
      .select("id, scheduled_for").eq("branch_id", branchId).in("id", taskIds)) ?? []
    : []
  const scheduledDateByTask = new Map(taskRows.map((task: Record<string, unknown>) => [task.id, task.scheduled_for]))
  return {
    notifications: rows.map((item: Record<string, unknown>) => {
      if (item.entity_type !== "task") return item
      const currentData = typeof item.data === "object" && item.data !== null && !Array.isArray(item.data)
        ? item.data as Record<string, unknown>
        : {}
      const scheduledFor = scheduledDateByTask.get(item.entity_id)
      return {
        ...item,
        data: {
          ...currentData,
          task_id: currentData.task_id ?? item.entity_id,
          ...(typeof scheduledFor === "string" ? { scheduled_for: scheduledFor } : {}),
        },
      }
    }),
    unread_count: unread.count ?? 0,
  }
}

async function getDashboard(admin: SupabaseClient, branchId: string, userId: string) {
  const branch = assertNoError(await admin.from("restaurant_branches")
    .select("id, name, timezone, enable_time_clock, require_gps_for_time_clock, meal_duration_minutes").eq("id", branchId).single())
  const localDate = dateInZone(branch.timezone)
  const localClock = new Intl.DateTimeFormat("en-GB", {
    timeZone: branch.timezone, hour: "2-digit", minute: "2-digit", hourCycle: "h23",
  }).format(new Date())
  const localMinute = minutesOfDay(localClock)
  assertNoError(await admin.rpc("materialize_restaurant_tasks", {
    p_branch_id: branchId, p_for_date: localDate,
  }))
  const timeSessionWindowStart = new Date(`${addDays(localDate, -2)}T00:00:00.000Z`).toISOString()
  const timeSessionWindowEnd = new Date(`${addDays(localDate, 2)}T00:00:00.000Z`).toISOString()
  const [tasks, areas, templates, templatePositions, members, parts, incidents, bins, inspections, shifts, wastePositions, timeSession, activeSessions, unreadNotifications, handoffs, myAbsences, areaInspectionTemplates, areaInspections, todayTimeSessions] = await Promise.all([
    admin.from("restaurant_tasks").select("*").eq("branch_id", branchId).eq("scheduled_for", localDate).order("priority", { ascending: false }).order("created_at"),
    admin.from("restaurant_areas").select("id, name, is_active").eq("branch_id", branchId),
    admin.from("restaurant_activity_templates").select("id, name, activity_type, area_id, is_divisible, interruptible, requires_evidence").eq("branch_id", branchId),
    admin.from("restaurant_activity_positions").select("activity_template_id, position_id").eq("branch_id", branchId),
    admin.from("restaurant_memberships").select("user_id, access_role, customer_service_active").eq("branch_id", branchId).eq("is_active", true),
    admin.from("restaurant_task_parts").select("*").eq("branch_id", branchId),
    admin.from("restaurant_incidents").select("*").eq("branch_id", branchId).neq("status", "resolved").order("created_at", { ascending: false }),
    admin.from("restaurant_waste_bins").select("*").eq("branch_id", branchId).eq("is_active", true).order("sort_order"),
    admin.from("restaurant_waste_inspections").select("id, inspector_id, inspected_at").eq("branch_id", branchId).order("inspected_at", { ascending: false }).limit(1),
    admin.from("restaurant_shifts").select("id, employee_id, shift_date, start_time, end_time, status").eq("branch_id", branchId)
      .eq("employee_id", userId).gte("shift_date", addDays(localDate, -1)).lte("shift_date", addDays(localDate, 13))
      .eq("status", "published").order("shift_date").order("start_time"),
    admin.from("restaurant_waste_positions").select("position_id").eq("branch_id", branchId),
    admin.from("restaurant_time_sessions").select("id, clock_in_at, clock_out_at").eq("branch_id", branchId).eq("employee_id", userId).is("clock_out_at", null).maybeSingle(),
    branch.enable_time_clock
      ? admin.from("restaurant_time_sessions").select("id, employee_id, clock_in_at").eq("branch_id", branchId).is("clock_out_at", null).order("clock_in_at")
      : Promise.resolve({ data: [], error: null }),
    admin.from("restaurant_notifications").select("id", { count: "exact", head: true })
      .eq("branch_id", branchId).eq("recipient_id", userId).is("read_at", null),
    admin.from("restaurant_shift_handoffs").select("*")
      .eq("branch_id", branchId).gte("shift_date", addDays(localDate, -14))
      .order("delivered_at", { ascending: false }).limit(30),
    admin.from("restaurant_absences").select("id, start_date, end_date, status, note, created_at")
      .eq("branch_id", branchId).eq("employee_id", userId)
      .order("start_date", { ascending: false }).limit(30),
    admin.from("restaurant_inspection_templates")
      .select("id, area_id, name, inspection_interval_minutes, last_inspected_at, is_active")
      .eq("branch_id", branchId).order("name"),
    admin.from("restaurant_inspections")
      .select("id, template_id, inspector_id, inspection_date, inspected_at, note, needs_attention_count")
      .eq("branch_id", branchId).order("inspected_at", { ascending: false }).limit(30),
    branch.enable_time_clock
      ? admin.from("restaurant_time_sessions").select("id, employee_id, clock_in_at, clock_out_at")
        .eq("branch_id", branchId).gte("clock_in_at", timeSessionWindowStart)
        .lt("clock_in_at", timeSessionWindowEnd).order("clock_in_at", { ascending: false }).limit(500)
      : Promise.resolve({ data: [], error: null }),
  ])
  if (unreadNotifications.error) throw unreadNotifications.error
  const timeSessionRows = [
    ...(assertNoError(todayTimeSessions) ?? []),
    ...(assertNoError(activeSessions) ?? []),
  ] as Record<string, unknown>[]
  const seenTimeSessionIds = new Set<string>()
  const visibleTimeSessions = timeSessionRows
    .map((session) => {
      if (typeof session.id !== "string" || typeof session.clock_in_at !== "string") return null
      const clockInLocalDate = dateInZone(branch.timezone, new Date(session.clock_in_at))
      const clockOutLocalDate = typeof session.clock_out_at === "string"
        ? dateInZone(branch.timezone, new Date(session.clock_out_at)) : null
      if (clockInLocalDate !== localDate && clockOutLocalDate !== localDate && session.clock_out_at != null) return null
      if (seenTimeSessionIds.has(session.id)) return null
      seenTimeSessionIds.add(session.id)
      return { ...session, clock_in_local_date: clockInLocalDate }
    })
    .filter((session): session is Record<string, unknown> => session !== null)
    .sort((left, right) => String(right.clock_in_at).localeCompare(String(left.clock_in_at)))
  const data = {
    tasks: assertNoError(tasks) ?? [], areas: assertNoError(areas) ?? [],
    templates: assertNoError(templates) ?? [], templatePositions: assertNoError(templatePositions) ?? [],
    members: assertNoError(members) ?? [], parts: assertNoError(parts) ?? [],
    incidents: assertNoError(incidents) ?? [], bins: assertNoError(bins) ?? [],
    inspections: assertNoError(inspections) ?? [], shifts: assertNoError(shifts) ?? [],
    wastePositions: assertNoError(wastePositions) ?? [], currentTimeSession: assertNoError(timeSession),
    activeTimeSessions: assertNoError(activeSessions) ?? [],
    handoffs: assertNoError(handoffs) ?? [],
    myAbsences: assertNoError(myAbsences) ?? [],
    areaInspectionTemplates: assertNoError(areaInspectionTemplates) ?? [],
    areaInspections: assertNoError(areaInspections) ?? [],
    todayTimeSessions: visibleTimeSessions,
  }
  const taskIds = data.tasks.map((task: { id: string }) => task.id)
  const partIds = data.parts.map((part: { id: string }) => part.id)
  const zoneIds = [...new Set(data.parts.map((part: { zone_id: string }) => part.zone_id))]
  const pauseEvents = taskIds.length
    ? assertNoError(await admin.from("restaurant_task_events")
      .select("task_id, part_id, note, occurred_at")
      .eq("branch_id", branchId).in("task_id", taskIds).eq("event_type", "pause")
      .not("note", "is", null).order("occurred_at", { ascending: false }).limit(500)) ?? []
    : []
  const latestPauseByUnit = new Map<string, Record<string, unknown>>()
  for (const event of pauseEvents as Record<string, unknown>[]) {
    const unitId = `${event.task_id}:${event.part_id ?? "task"}`
    if (!latestPauseByUnit.has(unitId)) latestPauseByUnit.set(unitId, event)
  }
  const memberIds = [...new Set([
    ...data.members.map((member: { user_id: string }) => member.user_id),
    ...data.activeTimeSessions.map((session: { employee_id: string }) => session.employee_id),
    ...data.todayTimeSessions.map((session: { employee_id: string }) => session.employee_id),
    ...data.tasks.map((task: { assigned_to: string | null }) => task.assigned_to).filter(Boolean),
    ...data.parts.map((part: { assigned_to: string | null }) => part.assigned_to).filter(Boolean),
    ...data.incidents.map((incident: { assigned_to: string | null }) => incident.assigned_to).filter(Boolean),
    ...data.shifts.map((shift: { employee_id: string }) => shift.employee_id),
    ...data.handoffs.flatMap((handoff: Record<string, unknown>) => [
      handoff.created_by, handoff.recipient_id, handoff.acknowledged_by,
    ]).filter((id: unknown): id is string => typeof id === "string"),
    ...data.areaInspections.map((inspection: { inspector_id: string }) => inspection.inspector_id),
  ])]
  const inspectionIds = data.areaInspections.map((inspection: { id: string }) => inspection.id)
  const activeInspectionTemplateIds = data.areaInspectionTemplates
    .filter((template: Record<string, unknown>) => template.is_active === true)
    .map((template: { id: string }) => template.id)
  const [users, zones, results, areaInspectionResults, areaInspectionItems] = await Promise.all([
    memberIds.length ? admin.from("users").select("id, full_name").in("id", memberIds) : Promise.resolve({ data: [], error: null }),
    zoneIds.length ? admin.from("restaurant_activity_zones").select("id, name").in("id", zoneIds) : Promise.resolve({ data: [], error: null }),
    data.inspections.length ? admin.from("restaurant_waste_inspection_results").select("bin_id, declared_state").eq("inspection_id", data.inspections[0].id) : Promise.resolve({ data: [], error: null }),
    inspectionIds.length ? admin.from("restaurant_inspection_results")
      .select("inspection_id, item_id, item_label, result_state, note")
      .in("inspection_id", inspectionIds) : Promise.resolve({ data: [], error: null }),
    activeInspectionTemplateIds.length ? admin.from("restaurant_inspection_items")
      .select("id, template_id, label, sort_order")
      .eq("branch_id", branchId).eq("is_active", true)
      .in("template_id", activeInspectionTemplateIds).order("sort_order") : Promise.resolve({ data: [], error: null }),
  ])
  const userRows = assertNoError(users) ?? []
  const zoneRows = assertNoError(zones) ?? []
  const resultRows = assertNoError(results) ?? []
  const areaInspectionResultRows = assertNoError(areaInspectionResults) ?? []
  const areaInspectionItemRows = assertNoError(areaInspectionItems) ?? []
  const allTasksForClient = data.tasks.map((task: Record<string, unknown>) => {
    const template = data.templates.find((row: Record<string, unknown>) => row.id === task.activity_template_id) ?? null
    const taskParts = data.parts.filter((part: Record<string, unknown>) => part.task_id === task.id)
      .map((part: Record<string, unknown>) => ({
        ...part,
        zone_name: zoneRows.find((zone: Record<string, unknown>) => zone.id === part.zone_id)?.name ?? null,
        assignee_name: userRows.find((user: Record<string, unknown>) => user.id === part.assigned_to)?.full_name ?? null,
        latest_pause_note: latestPauseByUnit.get(`${task.id}:${part.id}`)?.note ?? null,
        latest_pause_at: latestPauseByUnit.get(`${task.id}:${part.id}`)?.occurred_at ?? null,
      }))
    const allowedPositions = data.templatePositions.filter((row: Record<string, unknown>) => row.activity_template_id === task.activity_template_id)
    return {
      ...task,
      activity: template,
      area_name: data.areas.find((area: Record<string, unknown>) => area.id === task.area_id)?.name ?? null,
      assignee_name: userRows.find((user: Record<string, unknown>) => user.id === task.assigned_to)?.full_name ?? null,
      configuration_pending: (task.task_source === "waste" && data.wastePositions.length === 0) ||
        Boolean(template && allowedPositions.length === 0) || Boolean(template?.is_divisible && taskParts.length === 0),
      latest_pause_note: latestPauseByUnit.get(`${task.id}:task`)?.note ?? null,
      latest_pause_at: latestPauseByUnit.get(`${task.id}:task`)?.occurred_at ?? null,
      parts: taskParts,
    }
  })
  const now = Date.now()
  const wasteBins = data.bins.map((bin: Record<string, unknown>) => {
    const anchors = [bin.last_inspected_at, bin.last_bag_changed_at]
      .filter((value): value is string => typeof value === "string")
      .map((value) => new Date(value).getTime())
      .filter(Number.isFinite)
    const lastActionAt = anchors.length ? Math.max(...anchors) : null
    const nextInspectionAt = lastActionAt !== null && bin.inspection_interval_minutes
      ? lastActionAt + Number(bin.inspection_interval_minutes) * 60_000
      : null
    return {
      ...bin,
      task_policy_configured: typeof bin.bag_change_activity_name === "string"
        && Number.isInteger(Number(bin.bag_change_minutes)) && Number(bin.bag_change_minutes) >= 1 && Number(bin.bag_change_minutes) <= 1440
        && Number.isInteger(Number(bin.bag_change_difficulty)) && Number(bin.bag_change_difficulty) >= 1 && Number(bin.bag_change_difficulty) <= 5
        && Number.isInteger(Number(bin.bag_change_priority)) && Number(bin.bag_change_priority) >= 1 && Number(bin.bag_change_priority) <= 5,
      last_declared_state: resultRows.find((result: Record<string, unknown>) => result.bin_id === bin.id)?.declared_state ?? null,
      next_inspection_at: nextInspectionAt === null ? null : new Date(nextInspectionAt).toISOString(),
      inspection_due: nextInspectionAt !== null && now >= nextInspectionAt,
    }
  })
  const userById = new Map(userRows.map((user: Record<string, unknown>) => [user.id, user.full_name]))
  const currentMembership = data.members.find((member: Record<string, unknown>) => member.user_id === userId)
  const canManage = ["admin", "supervisor"].includes(String(currentMembership?.access_role))
  const tasksForClient = canManage ? allTasksForClient : allTasksForClient.filter((task: Record<string, unknown>) =>
    task.assigned_to === userId || (Array.isArray(task.parts) && (task.parts as Record<string, unknown>[])
      .some((part) => part.assigned_to === userId)))
  return {
    branch, local_date: localDate,
    areas: data.areas.filter((area: Record<string, unknown>) => area.is_active === true)
      .map((area: Record<string, unknown>) => ({ id: area.id, name: area.name })),
    unread_notification_count: unreadNotifications.count ?? 0,
    handoffs: data.handoffs.map((handoff: Record<string, unknown>) => ({
      ...handoff,
      creator_name: userById.get(handoff.created_by) ?? null,
      recipient_name: userById.get(handoff.recipient_id) ?? null,
      acknowledged_by_name: userById.get(handoff.acknowledged_by) ?? null,
    })),
    area_inspection_templates: data.areaInspectionTemplates
      .filter((template: Record<string, unknown>) => template.is_active === true)
      .map((template: Record<string, unknown>) => {
        const interval = template.inspection_interval_minutes == null
          ? null : Number(template.inspection_interval_minutes)
        const lastInspectedAt = typeof template.last_inspected_at === "string"
          ? template.last_inspected_at : null
        const lastTime = lastInspectedAt === null ? null : new Date(lastInspectedAt).getTime()
        const nextTime = interval !== null && lastTime !== null
          ? lastTime + interval * 60_000 : null
        return {
          ...template,
          area_name: data.areas.find((area: Record<string, unknown>) => area.id === template.area_id)?.name ?? null,
          items: areaInspectionItemRows.filter((item: Record<string, unknown>) => item.template_id === template.id),
          last_inspected_at: lastInspectedAt,
          next_inspection_at: nextTime === null ? null : new Date(nextTime).toISOString(),
          inspection_due: interval !== null && (lastTime === null || now >= (nextTime ?? Infinity)),
        }
      }),
    area_inspections: data.areaInspections.map((inspection: Record<string, unknown>) => ({
      ...inspection,
      inspector_name: userById.get(inspection.inspector_id) ?? null,
      template_name: data.areaInspectionTemplates.find((template: Record<string, unknown>) => template.id === inspection.template_id)?.name ?? null,
      results: areaInspectionResultRows.filter((result: Record<string, unknown>) => result.inspection_id === inspection.id),
    })),
    my_absences: data.myAbsences,
    tasks: tasksForClient,
    incidents: canManage ? data.incidents.map((incident: Record<string, unknown>) => ({
      ...incident,
      assignee_name: userById.get(incident.assigned_to) ?? null,
      area_name: data.areas.find((area: Record<string, unknown>) => area.id === incident.area_id)?.name ?? null,
    })) : [],
    members: (canManage ? data.members : data.members.filter((member: Record<string, unknown>) => member.user_id === userId)).map((member: Record<string, unknown>) => ({
      ...member, user_name: userById.get(member.user_id) ?? null,
    })),
    ...(canManage ? {} : { coworker_tasks: allTasksForClient
      .filter((task: Record<string, unknown>) => task.status !== "completed" && (
        (task.assigned_to != null && task.assigned_to !== userId) ||
        (Array.isArray(task.parts) && (task.parts as Record<string, unknown>[])
          .some((part) => part.assigned_to != null && part.assigned_to !== userId && part.status !== "completed"))
      ))
      .map((task: Record<string, unknown>) => ({
        id: task.id, name: task.name, area_id: task.area_id, area_name: task.area_name,
        assigned_to: task.assigned_to, assignee_name: task.assignee_name, status: task.status,
        requires_evidence: task.requires_evidence, evidence_policy: task.evidence_policy,
        parts: (Array.isArray(task.parts) ? task.parts : []).filter((part: Record<string, unknown>) =>
          part.assigned_to != null && part.assigned_to !== userId && part.status !== "completed"),
      })) }),
    active_time_sessions: canManage ? data.activeTimeSessions.map((session: Record<string, unknown>) => ({
      ...session, employee_name: userById.get(session.employee_id) ?? null,
      clock_in_local_time: timeInZone(branch.timezone, session.clock_in_at),
    })) : [],
    today_time_sessions: canManage && branch.enable_time_clock
      ? data.todayTimeSessions.map((session: Record<string, unknown>) => ({
        ...session, employee_name: userById.get(session.employee_id) ?? null,
        clock_in_local_time: timeInZone(branch.timezone, session.clock_in_at),
        clock_out_local_time: timeInZone(branch.timezone, session.clock_out_at),
      }))
      : [],
    my_time_sessions: branch.enable_time_clock
      ? data.todayTimeSessions
        .filter((session: Record<string, unknown>) => session.employee_id === userId)
        .map((session: Record<string, unknown>) => ({
          id: session.id,
          clock_in_at: session.clock_in_at,
          clock_out_at: session.clock_out_at,
          clock_in_local_date: session.clock_in_local_date,
          clock_in_local_time: timeInZone(branch.timezone, session.clock_in_at),
          clock_out_local_time: timeInZone(branch.timezone, session.clock_out_at),
        }))
      : [],
    waste_bins: wasteBins,
    shifts: data.shifts.filter((shift: Record<string, string>) =>
      shift.shift_date >= localDate || isCurrentShift(shift, localDate, localMinute))
      .map((shift: Record<string, unknown>) => ({
        ...shift, currently_active: isCurrentShift(shift as Record<string, string>, localDate, localMinute),
        employee_name: userById.get(shift.employee_id) ?? null,
      })),
    handoff: {
      completed_tasks: tasksForClient.filter((task: Record<string, unknown>) => task.status === "completed"),
      outstanding_tasks: tasksForClient.filter((task: Record<string, unknown>) => task.status !== "completed"),
      open_incidents: data.incidents,
    },
    latest_waste_inspection: data.inspections[0] ?? null,
    current_time_session: data.currentTimeSession ? {
      ...data.currentTimeSession,
      clock_in_local_time: timeInZone(branch.timezone, data.currentTimeSession.clock_in_at),
    } : null,
    assignment_configuration_pending: tasksForClient.filter((task: Record<string, unknown>) => task.configuration_pending).map((task: Record<string, unknown>) => task.id),
    assignable_unassigned_count: tasksForClient.reduce((count: number, task: Record<string, unknown>) => {
      if (task.configuration_pending) return count
      const parts = Array.isArray(task.parts) ? task.parts as Record<string, unknown>[] : []
      if (parts.length) {
        if (task.status !== "pending" && task.status !== "in_progress") return count
        return count + parts.filter((part) => part.status === "pending" && !part.assigned_to).length
      }
      return count + (task.status === "pending" && !task.assigned_to ? 1 : 0)
    }, 0),
  }
}

function minutesOfDay(value: string): number {
  const [hours, minutes] = value.split(":").map(Number)
  return hours * 60 + minutes
}

function isCurrentShift(shift: Record<string, string>, localDate: string, minute: number): boolean {
  const start = minutesOfDay(shift.start_time)
  const end = minutesOfDay(shift.end_time)
  if (shift.shift_date === localDate) return start < end ? minute >= start && minute < end : minute >= start
  return shift.shift_date === addDays(localDate, -1) && start > end && minute < end
}

async function autoAssign(admin: SupabaseClient, branchId: string, requestId: string, requestedDate?: string) {
  const branch = assertNoError(await admin.from("restaurant_branches")
    .select("timezone, assignment_load_balance_weight, assignment_heavy_rotation_weight, assignment_priority_weight")
    .eq("id", branchId).single())
  const policy: AssignmentPolicy = {
    loadBalanceWeight: Number(branch.assignment_load_balance_weight ?? DEFAULT_ASSIGNMENT_POLICY.loadBalanceWeight),
    heavyRotationWeight: Number(branch.assignment_heavy_rotation_weight ?? DEFAULT_ASSIGNMENT_POLICY.heavyRotationWeight),
    priorityWeight: Number(branch.assignment_priority_weight ?? DEFAULT_ASSIGNMENT_POLICY.priorityWeight),
  }
  const now = new Date()
  const localDate = dateInZone(branch.timezone, now)
  const assignmentDate = requestedDate ?? localDate
  if (!isCalendarDate(assignmentDate)) fail(400, "INVALID_ASSIGNMENT_DATE", "for_date must be a valid calendar date in YYYY-MM-DD format.")
  if (assignmentDate < localDate) fail(409, "PAST_ASSIGNMENT_DATE", "Activities cannot be auto-assigned retroactively.")
  const localClock = new Intl.DateTimeFormat("en-GB", {
    timeZone: branch.timezone, hour: "2-digit", minute: "2-digit", hourCycle: "h23",
  }).format(now)
  const minute = minutesOfDay(localClock)
  const [members, shifts, absences, tasks, parts, templates, allowed, memberPositions, wastePositions] = await Promise.all([
    admin.from("restaurant_memberships").select("user_id, customer_service_active").eq("branch_id", branchId).eq("is_active", true),
    admin.from("restaurant_shifts").select("id, employee_id, shift_date, start_time, end_time").eq("branch_id", branchId).eq("status", "published").gte("shift_date", addDays(assignmentDate, -1)).lte("shift_date", assignmentDate),
    admin.from("restaurant_absences").select("employee_id, start_date, end_date").eq("branch_id", branchId).eq("status", "approved").lte("start_date", assignmentDate).gte("end_date", assignmentDate),
    admin.from("restaurant_tasks").select("id, activity_template_id, assigned_to, status, task_source, waste_bin_id, estimated_minutes, difficulty, priority, scheduled_for").eq("branch_id", branchId).gte("scheduled_for", addDays(assignmentDate, -6)).lte("scheduled_for", assignmentDate),
    admin.from("restaurant_task_parts").select("id, task_id, assigned_to, status, estimated_minutes, difficulty").eq("branch_id", branchId),
    admin.from("restaurant_activity_templates").select("id, is_divisible, interruptible").eq("branch_id", branchId),
    admin.from("restaurant_activity_positions").select("activity_template_id, position_id").eq("branch_id", branchId),
    admin.from("restaurant_member_positions").select("user_id, position_id").eq("branch_id", branchId),
    admin.from("restaurant_waste_positions").select("position_id").eq("branch_id", branchId),
  ])
  const operationalStateRows = assertNoError(await admin.from("restaurant_member_operational_states")
    .select("employee_id, state").eq("branch_id", branchId)) ?? []
  const operationalStateByEmployee = new Map(operationalStateRows.map((row: Record<string, string>) => [row.employee_id, row.state]))
  const data = {
    members: assertNoError(members) ?? [], shifts: assertNoError(shifts) ?? [],
    absences: assertNoError(absences) ?? [], tasks: assertNoError(tasks) ?? [], parts: assertNoError(parts) ?? [],
    templates: assertNoError(templates) ?? [], allowed: assertNoError(allowed) ?? [], memberPositions: assertNoError(memberPositions) ?? [],
    wastePositions: assertNoError(wastePositions) ?? [],
  }
  const shiftIds = data.shifts.map((shift: { id: string }) => shift.id)
  const breaks = shiftIds.length
    ? assertNoError(await admin.from("restaurant_shift_breaks").select("shift_id, start_time, end_time").eq("branch_id", branchId).in("shift_id", shiftIds)) ?? []
    : []
  const rosterIds = data.members.map((membership: Record<string, unknown>) => String(membership.user_id)).sort()
  const rotationOffset = rosterIds.length
    ? Math.floor(Date.parse(`${assignmentDate}T00:00:00.000Z`) / 86_400_000) % rosterIds.length
    : 0
  const rotationRankById = new Map(rosterIds.map((id, index) => [
    id, (index - rotationOffset + rosterIds.length) % Math.max(rosterIds.length, 1),
  ]))
  const capacityUntilShiftEnd = (shift: Record<string, string>) => {
    const end = minutesOfDay(shift.end_time)
    const start = minutesOfDay(shift.start_time)
    const endAbsolute = end + (end <= start ? 1440 : 0)
    const nowAbsolute = minute + (shift.shift_date !== localDate ? 1440 : 0)
    return Math.max(0, endAbsolute - nowAbsolute)
  }
  const remainingBreakMinutes = (shift: Record<string, string>) => {
    const shiftStart = minutesOfDay(shift.start_time)
    const nowAbsolute = minute + (shift.shift_date !== localDate ? 1440 : 0)
    return breaks
      .filter((item: Record<string, string>) => item.shift_id === shift.id)
      .reduce((remaining: number, item: Record<string, string>) => {
        let start = minutesOfDay(item.start_time)
        let end = minutesOfDay(item.end_time)
        if (end <= start) end += 1440
        if (start < shiftStart) { start += 1440; end += 1440 }
        return remaining + Math.max(0, end - Math.max(nowAbsolute, start))
      }, 0)
  }
  const scheduledMinutesForDate = (shift: Record<string, string>) => {
    const shiftStart = minutesOfDay(shift.start_time)
    const shiftEnd = minutesOfDay(shift.end_time)
    const absoluteStart = shiftStart + (shift.shift_date === assignmentDate ? 0 : -1440)
    const absoluteEnd = shiftEnd + (shiftEnd <= shiftStart ? 1440 : 0) + (shift.shift_date === assignmentDate ? 0 : -1440)
    return Math.max(0, Math.min(1440, absoluteEnd) - Math.max(0, absoluteStart))
  }
  const scheduledBreakMinutesForDate = (shift: Record<string, string>) => {
    const shiftStart = minutesOfDay(shift.start_time)
    const dayOffset = shift.shift_date === assignmentDate ? 0 : -1440
    return breaks
      .filter((item: Record<string, string>) => item.shift_id === shift.id)
      .reduce((total: number, item: Record<string, string>) => {
        let start = minutesOfDay(item.start_time)
        let end = minutesOfDay(item.end_time)
        if (end <= start) end += 1440
        if (start < shiftStart) { start += 1440; end += 1440 }
        const absoluteStart = start + dayOffset
        const absoluteEnd = end + dayOffset
        return total + Math.max(0, Math.min(1440, absoluteEnd) - Math.max(0, absoluteStart))
      }, 0)
  }
  const taskIdsForAssignmentDate = new Set(data.tasks
    .filter((task: Record<string, unknown>) => task.scheduled_for === assignmentDate)
    .map((task: Record<string, unknown>) => String(task.id)))
  const candidates: AssignmentCandidate[] = data.members.map((membership: Record<string, unknown>) => {
    const userShifts = data.shifts.filter((shift: Record<string, string>) => shift.employee_id === membership.user_id &&
      (shift.shift_date === assignmentDate || (shift.shift_date === addDays(assignmentDate, -1) && minutesOfDay(shift.end_time) <= minutesOfDay(shift.start_time))))
    const activeShift = assignmentDate === localDate
      ? userShifts.find((shift: Record<string, string>) => isCurrentShift(shift, localDate, minute))
      : null
    const onBreak = Boolean(activeShift && breaks.some((item: Record<string, string>) => {
      if (item.shift_id !== activeShift.id) return false
      const start = minutesOfDay(item.start_time)
      const end = minutesOfDay(item.end_time)
      return start < end ? minute >= start && minute < end : minute >= start || minute < end
    }))
    const userTasks = data.tasks.filter((task: Record<string, unknown>) => task.assigned_to === membership.user_id)
    const userParts = data.parts.filter((part: Record<string, unknown>) => part.assigned_to === membership.user_id)
    const recentTaskIds = new Set(data.tasks.map((task: Record<string, unknown>) => task.id))
    const recentUserParts = userParts.filter((part: Record<string, unknown>) =>
      recentTaskIds.has(String(part.task_id)))
    const openWeighted = userTasks.filter((task: Record<string, unknown>) => task.status !== "completed")
      .reduce((total: number, task: Record<string, number>) => total + task.estimated_minutes * task.difficulty, 0) +
      recentUserParts.filter((part: Record<string, unknown>) => part.status !== "completed")
        .reduce((total: number, part: Record<string, number>) => total + part.estimated_minutes * part.difficulty, 0)
    const openMinutes = userTasks.filter((task: Record<string, unknown>) => task.status !== "completed")
      .reduce((total: number, task: Record<string, number>) => total + task.estimated_minutes, 0) +
      recentUserParts.filter((part: Record<string, unknown>) => part.status !== "completed")
        .reduce((total: number, part: Record<string, number>) => total + part.estimated_minutes, 0)
    const recentHeavyTasks = userTasks.filter((task: Record<string, unknown>) =>
      task.status === "completed" && Number(task.difficulty) >= 4).length +
      recentUserParts.filter((part: Record<string, unknown>) =>
        part.status === "completed" && Number(part.difficulty) >= 4).length
    const historicWeighted = userTasks.filter((task: Record<string, unknown>) => task.status === "completed")
      .reduce((total: number, task: Record<string, number>) => total + task.estimated_minutes * task.difficulty, 0) +
      recentUserParts.filter((part: Record<string, unknown>) => part.status === "completed")
        .reduce((total: number, part: Record<string, number>) => total + part.estimated_minutes * part.difficulty, 0)
    const absent = data.absences.some((absence: Record<string, string>) =>
      absence.employee_id === membership.user_id && absence.start_date <= assignmentDate && absence.end_date >= assignmentDate)
    const futureShiftCapacity = userShifts.reduce((total: number, shift: Record<string, string>) =>
      total + scheduledMinutesForDate(shift) - scheduledBreakMinutesForDate(shift), 0)
    const targetDayOpenMinutes = userTasks.filter((task: Record<string, unknown>) =>
      task.scheduled_for === assignmentDate && task.status !== "completed")
      .reduce((total: number, task: Record<string, number>) => total + task.estimated_minutes, 0) +
      recentUserParts.filter((part: Record<string, unknown>) =>
        taskIdsForAssignmentDate.has(String(part.task_id)) && part.status !== "completed")
        .reduce((total: number, part: Record<string, number>) => total + part.estimated_minutes, 0)
    const isToday = assignmentDate === localDate
    const operationalState = isToday ? operationalStateByEmployee.get(String(membership.user_id)) : undefined
    const unavailableForAssignment = operationalState === "meal" || operationalState === "rest" || operationalState === "off_shift"
    return {
      id: String(membership.user_id),
      positionIds: data.memberPositions.filter((row: Record<string, string>) => row.user_id === membership.user_id).map((row: Record<string, string>) => row.position_id),
      onShift: (isToday ? Boolean(activeShift) : futureShiftCapacity > 0) && operationalState !== "off_shift",
      onBreak: (isToday && onBreak) || unavailableForAssignment,
      absent,
      servingCustomers: isToday && Boolean(membership.customer_service_active),
      capacityMinutes: unavailableForAssignment ? 0 : isToday
        ? activeShift ? Math.max(0, capacityUntilShiftEnd(activeShift) - remainingBreakMinutes(activeShift) - openMinutes) : 0
        : Math.max(0, futureShiftCapacity - targetDayOpenMinutes),
      assignedWeightedMinutes: historicWeighted + openWeighted,
      recentHeavyTasks,
      rotationRank: rotationRankById.get(String(membership.user_id)) ?? 0,
    }
  })

  const pending = data.tasks.filter((task: Record<string, unknown>) =>
    task.scheduled_for === assignmentDate && ["pending", "in_progress"].includes(String(task.status)))
  const units: AssignmentUnit[] = []
  const unitCountByTask = new Map<string, number>()
  const assignmentNeedTaskIds = new Set<string>()
  for (const task of pending) {
    const template = data.templates.find((item: Record<string, unknown>) => item.id === task.activity_template_id)
    const requiredPositionIds = task.task_source === "waste"
      ? data.wastePositions.map((item: Record<string, string>) => item.position_id)
      : data.allowed.filter((item: Record<string, unknown>) =>
        item.activity_template_id === task.activity_template_id).map((item: Record<string, string>) => item.position_id)
    if (template?.is_divisible) {
      const unassignedParts = data.parts.filter((item: Record<string, unknown>) =>
        item.task_id === task.id && item.status === "pending" && !item.assigned_to)
      if (unassignedParts.length === 0) continue
      assignmentNeedTaskIds.add(String(task.id))
      if (requiredPositionIds.length === 0) continue
      for (const part of unassignedParts) {
        units.push({
          id: String(part.id), groupId: String(task.id), requiredPositionIds,
          estimatedMinutes: Number(part.estimated_minutes), difficulty: Number(part.difficulty),
          priority: Number(task.priority), interruptible: Boolean(template?.interruptible ?? true),
        })
      }
      const count = units.filter((unit) => unit.groupId === task.id).length
      if (count) unitCountByTask.set(String(task.id), count)
    } else {
      if (task.status !== "pending" || task.assigned_to) continue
      assignmentNeedTaskIds.add(String(task.id))
      if ((task.task_source !== "waste" && !template) || requiredPositionIds.length === 0) continue
      units.push({
        id: String(task.id), groupId: String(task.id), requiredPositionIds,
        estimatedMinutes: Number(task.estimated_minutes), difficulty: Number(task.difficulty),
        priority: Number(task.priority), interruptible: Boolean(template?.interruptible ?? true),
      })
      unitCountByTask.set(String(task.id), 1)
    }
  }
  const timefoldAttempt = await tryTimefoldAssignmentPlan(
    units,
    candidates,
    policy,
    Deno.env.get("TIMEFOLD_SERVICE_URL"),
    Deno.env.get("TIMEFOLD_SERVICE_TOKEN"),
  )
  if (timefoldAttempt.fallbackReason) {
    console.warn("assignment_solver_fallback", {
      request_id: requestId,
      branch_id: branchId,
      planner: "local",
      reason: timefoldAttempt.fallbackReason,
      ...(timefoldAttempt.httpStatus ? { http_status: timefoldAttempt.httpStatus } : {}),
    })
  }
  const timefoldPlan = timefoldAttempt.plan
  const plan = timefoldPlan ?? planRestaurantAssignments(units, candidates, policy)
  let assigned = 0
  const assignedUnitIds = new Set<string>()
  for (const assignment of plan.assignments) {
    const part = data.parts.find((item: Record<string, unknown>) => item.id === assignment.unitId)
    if (part) {
      const result = await admin.from("restaurant_task_parts").update({ assigned_to: assignment.candidateId })
        .eq("id", part.id).eq("branch_id", branchId).eq("status", "pending").is("assigned_to", null).select("id")
      if (assertNoError(result)?.length) { assigned += 1; assignedUnitIds.add(String(part.id)) }
    } else {
      const result = await admin.from("restaurant_tasks").update({ assigned_to: assignment.candidateId })
        .eq("id", assignment.unitId).eq("branch_id", branchId).eq("status", "pending").is("assigned_to", null).select("id")
      if (assertNoError(result)?.length) { assigned += 1; assignedUnitIds.add(String(assignment.unitId)) }
    }
  }
  const fullyAssignedTaskIds = new Set([...unitCountByTask.entries()]
    .filter(([taskId, count]) => {
      const assignedUnits = units.filter((unit) => unit.groupId === taskId && assignedUnitIds.has(unit.id)).length
      return assignedUnits === count
    }).map(([taskId]) => taskId))
  return {
    assigned_count: assigned,
    unassigned_count: [...assignmentNeedTaskIds].filter((taskId) => !fullyAssignedTaskIds.has(taskId)).length,
    planner: timefoldPlan ? "timefold" : "local",
    ...(timefoldAttempt.fallbackReason
      ? { fallback_reason: timefoldAttempt.fallbackReason }
      : {}),
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(req) })
  const requestId = makeRequestId(req)
  try {
    if (req.method !== "GET" && req.method !== "POST") fail(405, "METHOD_NOT_ALLOWED", "Use GET or POST.")
    const authorization = req.headers.get("Authorization")
    if (!authorization?.startsWith("Bearer ")) fail(401, "UNAUTHORIZED", "Sign in to continue.")
    const url = Deno.env.get("SUPABASE_URL") ?? ""
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? ""
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    if (!url || !anonKey || !serviceKey) throw new Error("Supabase server configuration is missing.")
    const userClient = createClient(url, anonKey, { global: { headers: { Authorization: authorization } } })
    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
    const { data: { user }, error: authError } = await userClient.auth.getUser()
    if (authError || !user) fail(401, "UNAUTHORIZED", "Your session has expired.")
    const profile = assertNoError(await admin.from("users")
      .select("id, company_id, role, is_active").eq("id", user.id).maybeSingle())
    if (!profile?.is_active) fail(403, "FORBIDDEN", "Your account is inactive.")

    if (req.method === "GET") {
      const action = urlFrom(req).searchParams.get("action") ?? "branches"
      if (action === "branches") return jsonResponse({ branches: await getBranches(admin, user.id) }, 200, requestId)
      const branchId = requiredUuid(urlFrom(req).searchParams.get("branch_id"), "branch_id")
      const membership = await memberForBranch(
        admin, branchId, user.id,
        action === "settings" || action === "pending_absences" || action === "shift_schedule" ||
          action === "team_directory" || action === "branch_structure",
      )
      if (action === "attendance_history") {
        const params = urlFrom(req).searchParams
        const selectedDate = params.get("for_date") ?? ""
        if (!isCalendarDate(selectedDate)) {
          fail(400, "INVALID_DATE", "Provide a valid attendance date.")
        }
        const branch = assertNoError(await admin.from("restaurant_branches")
          .select("timezone, enable_time_clock").eq("id", branchId).single())
        if (!branch.enable_time_clock) {
          fail(409, "TIME_CLOCK_DISABLED", "Attendance tracking is disabled for this branch.")
        }
        const canManage = ["admin", "supervisor"].includes(membership.access_role)
        // Cover every timezone offset around the selected local date; filter
        // the fetched rows by the branch's actual timezone below.
        const rangeStart = `${addDays(selectedDate, -1)}T00:00:00.000Z`
        const rangeEnd = `${addDays(selectedDate, 2)}T00:00:00.000Z`
        let sessionsQuery = admin.from("restaurant_time_sessions")
          .select("id, employee_id, clock_in_at, clock_out_at")
          .eq("branch_id", branchId)
          .or(`and(clock_in_at.gte.${rangeStart},clock_in_at.lt.${rangeEnd}),and(clock_out_at.gte.${rangeStart},clock_out_at.lt.${rangeEnd})`)
        if (!canManage) sessionsQuery = sessionsQuery.eq("employee_id", user.id)
        const rows = assertNoError(await sessionsQuery
          .order("clock_in_at", { ascending: false }).limit(500)) ?? []
        const matchingRows = (rows as Record<string, unknown>[]).filter((session) => {
          if (typeof session.clock_in_at !== "string") return false
          const clockInDate = dateInZone(branch.timezone, new Date(session.clock_in_at))
          const clockOutDate = typeof session.clock_out_at === "string"
            ? dateInZone(branch.timezone, new Date(session.clock_out_at)) : null
          return clockInDate === selectedDate || clockOutDate === selectedDate
        })
        const employeeIds = canManage
          ? [...new Set(matchingRows.map((session) => session.employee_id)
            .filter((id): id is string => typeof id === "string"))]
          : []
        const employees = employeeIds.length
          ? assertNoError(await admin.from("users").select("id, full_name").in("id", employeeIds)) ?? []
          : []
        const employeeNames = new Map((employees as Record<string, unknown>[])
          .map((employee) => [employee.id, employee.full_name]))
        return jsonResponse({
          date: selectedDate,
          timezone: branch.timezone,
          can_manage: canManage,
          sessions: matchingRows.map((session) => ({
            id: session.id,
            employee_name: canManage ? employeeNames.get(session.employee_id) ?? null : null,
            clock_in_at: session.clock_in_at,
            clock_out_at: session.clock_out_at,
            clock_in_local_date: dateInZone(branch.timezone, new Date(String(session.clock_in_at))),
            clock_out_local_date: typeof session.clock_out_at === "string"
              ? dateInZone(branch.timezone, new Date(session.clock_out_at)) : null,
            clock_in_local_time: timeInZone(branch.timezone, session.clock_in_at),
            clock_out_local_time: timeInZone(branch.timezone, session.clock_out_at),
          })),
        }, 200, requestId)
      }
      if (action === "inspection_setup") {
        const [areas, bins, templates, items] = await Promise.all([
          admin.from("restaurant_areas").select("id, name").eq("branch_id", branchId),
          admin.from("restaurant_waste_bins")
            .select("id, name, is_active, last_state, last_inspected_at, last_bag_changed_at, inspection_interval_minutes")
            .eq("branch_id", branchId).eq("is_active", true).order("sort_order"),
          admin.from("restaurant_inspection_templates")
            .select("id, name, area_id, is_active, inspection_interval_minutes, last_inspected_at")
            .eq("branch_id", branchId).eq("is_active", true).order("name"),
          admin.from("restaurant_inspection_items")
            .select("id, template_id, label, sort_order")
            .eq("branch_id", branchId).eq("is_active", true).order("sort_order"),
        ])
        const areaRows = assertNoError(areas) ?? []
        const binRows = assertNoError(bins) ?? []
        const templateRows = assertNoError(templates) ?? []
        const itemRows = assertNoError(items) ?? []
        return jsonResponse({
          areas: areaRows,
          bins: binRows,
          inspection_templates: templateRows.map((template: Record<string, unknown>) => ({
            ...template,
            items: itemRows.filter((item: Record<string, unknown>) => item.template_id === template.id),
          })),
        }, 200, requestId)
      }
      if (action === "settings") return jsonResponse(await getSettings(
        admin, branchId, membership.company_id, urlFrom(req).searchParams.get("week_start"),
      ), 200, requestId)
      if (action === "pending_absences") {
        const absences = assertNoError(await admin.from("restaurant_absences")
          .select("id, employee_id, start_date, end_date, note, created_at")
          .eq("branch_id", branchId).eq("status", "pending")
          .order("created_at", { ascending: true })) ?? []
        const employeeIds = [...new Set(absences.map((absence: Record<string, unknown>) => String(absence.employee_id)))]
        const users = employeeIds.length
          ? assertNoError(await admin.from("users").select("id, full_name").in("id", employeeIds)) ?? []
          : []
        return jsonResponse({ absences: absences.map((absence: Record<string, unknown>) => ({
          ...absence,
          employee_name: users.find((employee: Record<string, unknown>) => employee.id === absence.employee_id)?.full_name ?? null,
        })) }, 200, requestId)
      }
      if (action === "shift_schedule") {
        const weekStart = urlFrom(req).searchParams.get("week_start") ?? ""
        if (!isCalendarDate(weekStart)) fail(400, "INVALID_DATE_RANGE", "Provide a valid week_start date.")
        const weekEnd = addDays(weekStart, 6)
        const [memberRows, shiftRows] = await Promise.all([
          admin.from("restaurant_memberships").select("user_id")
            .eq("branch_id", branchId).eq("is_active", true),
          admin.from("restaurant_shifts").select("id, employee_id, shift_date, start_time, end_time, status")
            .eq("branch_id", branchId).gte("shift_date", weekStart).lte("shift_date", weekEnd)
            .neq("status", "cancelled").order("shift_date").order("start_time"),
        ])
        const members = assertNoError(memberRows) ?? []
        const shifts = assertNoError(shiftRows) ?? []
        const memberIds = [...new Set(members.map((item: Record<string, unknown>) => String(item.user_id)))]
        const shiftIds = shifts.map((item: Record<string, unknown>) => String(item.id))
        const [users, breaks] = await Promise.all([
          memberIds.length
            ? admin.from("users").select("id, full_name").in("id", memberIds)
            : Promise.resolve({ data: [], error: null }),
          shiftIds.length
            ? admin.from("restaurant_shift_breaks").select("id, shift_id, start_time, end_time")
              .eq("branch_id", branchId).in("shift_id", shiftIds)
            : Promise.resolve({ data: [], error: null }),
        ])
        const userRows = assertNoError(users) ?? []
        return jsonResponse({
          week_start: weekStart,
          week_end: weekEnd,
          employees: members.map((item: Record<string, unknown>) => ({
            user_id: item.user_id,
            full_name: userRows.find((employee: Record<string, unknown>) => employee.id === item.user_id)?.full_name ?? null,
          })).sort((left: Record<string, unknown>, right: Record<string, unknown>) =>
            String(left.full_name ?? "").localeCompare(String(right.full_name ?? ""))),
          shifts: shifts.map((shift: Record<string, unknown>) => ({
            ...shift,
            employee_name: userRows.find((employee: Record<string, unknown>) => employee.id === shift.employee_id)?.full_name ?? null,
            breaks: (assertNoError(breaks) ?? []).filter((item: Record<string, unknown>) => item.shift_id === shift.id),
          })),
        }, 200, requestId)
      }
      if (action === "shift_cover_requests") {
        const isManager = ["admin", "supervisor"].includes(membership.access_role)
        const branch = assertNoError(await admin.from("restaurant_branches")
          .select("timezone").eq("id", branchId).single())
        const localDate = dateInZone(branch.timezone)
        const localTime = timeInZone(branch.timezone, new Date().toISOString()) ?? "00:00"
        let requestsQuery = admin.from("restaurant_shift_cover_requests")
          .select("id, shift_id, requester_id, status, note, decision_note, replacement_employee_id, replacement_shift_id, client_event_id, reviewed_by, reviewed_at, created_at")
          .eq("branch_id", branchId).order("created_at", { ascending: false }).limit(100)
        if (!isManager) requestsQuery = requestsQuery.eq("requester_id", user.id)
        const requests = assertNoError(await requestsQuery) ?? []
        const shiftIds = [...new Set(requests.flatMap((item: Record<string, unknown>) =>
          [item.shift_id, item.replacement_shift_id].filter((id): id is string => typeof id === "string")))]
        const requestUserIds = [...new Set(requests.flatMap((item: Record<string, unknown>) =>
          [item.requester_id, item.replacement_employee_id].filter((id): id is string => typeof id === "string")))]
        const [shiftRows, requestUsers, candidateMemberships, myShifts, pendingForMyShifts] = await Promise.all([
          shiftIds.length
            ? admin.from("restaurant_shifts").select("id, employee_id, shift_date, start_time, end_time, status")
              .eq("branch_id", branchId).in("id", shiftIds)
            : Promise.resolve({ data: [], error: null }),
          requestUserIds.length
            ? admin.from("users").select("id, full_name").in("id", requestUserIds)
            : Promise.resolve({ data: [], error: null }),
          isManager
            ? admin.from("restaurant_memberships").select("user_id")
              .eq("branch_id", branchId).eq("is_active", true).eq("access_role", "employee")
            : Promise.resolve({ data: [], error: null }),
          admin.from("restaurant_shifts").select("id, employee_id, shift_date, start_time, end_time, status")
            .eq("branch_id", branchId).eq("employee_id", user.id).eq("status", "published")
            .gte("shift_date", localDate).order("shift_date").order("start_time"),
          admin.from("restaurant_shift_cover_requests").select("shift_id")
            .eq("branch_id", branchId).eq("requester_id", user.id).eq("status", "pending"),
        ])
        const shiftRowsData = assertNoError(shiftRows) ?? []
        const userRows = assertNoError(requestUsers) ?? []
        const candidateRows = assertNoError(candidateMemberships) ?? []
        const candidateIds = candidateRows.map((item: Record<string, unknown>) => String(item.user_id))
        const candidates = candidateIds.length
          ? assertNoError(await admin.from("users").select("id, full_name").in("id", candidateIds).eq("is_active", true)) ?? []
          : []
        const openShiftIds = new Set((assertNoError(pendingForMyShifts) ?? [])
          .map((item: Record<string, unknown>) => item.shift_id))
        const shiftById = new Map(shiftRowsData.map((item: Record<string, unknown>) => [item.id, item]))
        const userById = new Map(userRows.map((item: Record<string, unknown>) => [item.id, item.full_name]))
        const candidateById = new Map(candidates.map((item: Record<string, unknown>) => [item.id, item.full_name]))
        const availableShifts = (assertNoError(myShifts) ?? []).filter((shift: Record<string, unknown>) =>
          !openShiftIds.has(shift.id) && (shift.shift_date > localDate ||
            (shift.shift_date === localDate && String(shift.start_time).slice(0, 5) > localTime)))
        return jsonResponse({
          requests: requests.map((item: Record<string, unknown>) => ({
            ...item,
            requester_name: userById.get(item.requester_id) ?? null,
            replacement_employee_name: userById.get(item.replacement_employee_id) ?? null,
            shift: shiftById.get(item.shift_id) ?? null,
            replacement_shift: shiftById.get(item.replacement_shift_id) ?? null,
          })),
          available_shifts: availableShifts,
          replacement_candidates: [...candidates].sort((left: Record<string, unknown>, right: Record<string, unknown>) =>
            String(left.full_name ?? "").localeCompare(String(right.full_name ?? ""))),
          can_manage: isManager,
        }, 200, requestId)
      }
      if (action === "team_directory") {
        const [memberRows, positions, memberPositions] = await Promise.all([
          admin.from("restaurant_memberships").select("user_id, access_role, is_active")
            .eq("branch_id", branchId).order("is_active", { ascending: false }),
          admin.from("restaurant_positions").select("id, name, area_id").eq("branch_id", branchId)
            .eq("is_active", true).order("name"),
          admin.from("restaurant_member_positions").select("user_id, position_id").eq("branch_id", branchId),
        ])
        const members = assertNoError(memberRows) ?? []
        const memberIds = [...new Set(members.map((item: Record<string, unknown>) => String(item.user_id)))]
        const users = memberIds.length
          ? assertNoError(await admin.from("users").select("id, full_name").in("id", memberIds)) ?? []
          : []
        const positionRows = assertNoError(positions) ?? []
        const positionRowsByUser = assertNoError(memberPositions) ?? []
        return jsonResponse({
          positions: positionRows,
          members: members.map((member: Record<string, unknown>) => ({
            ...member,
            full_name: users.find((employee: Record<string, unknown>) => employee.id === member.user_id)?.full_name ?? null,
            position_ids: positionRowsByUser.filter((row: Record<string, unknown>) => row.user_id === member.user_id)
              .map((row: Record<string, unknown>) => row.position_id),
          })),
        }, 200, requestId)
      }
      if (action === "branch_structure") {
        const [areas, positions, branch] = await Promise.all([
          admin.from("restaurant_areas").select("id, name, sort_order, is_active")
            .eq("branch_id", branchId).order("sort_order").order("name"),
          admin.from("restaurant_positions").select("id, name, is_active, area_id")
            .eq("branch_id", branchId).order("name"),
          admin.from("restaurant_branches").select("enable_time_clock, require_gps_for_time_clock, meal_duration_minutes, collaboration_reservation_seconds")
            .eq("id", branchId).single(),
        ])
        return jsonResponse({
          areas: assertNoError(areas) ?? [],
          positions: assertNoError(positions) ?? [],
          features: assertNoError(branch),
        }, 200, requestId)
      }
      if (action === "dashboard") return jsonResponse(await getDashboard(admin, branchId, user.id), 200, requestId)
      if (action === "task_calendar") {
        const params = urlFrom(req).searchParams
        const fromDate = params.get("from_date") ?? ""
        const toDate = params.get("to_date") ?? fromDate
        if (!isCalendarDate(fromDate) || !isCalendarDate(toDate) || toDate < fromDate || toDate > addDays(fromDate, 6)) {
          fail(400, "INVALID_DATE_RANGE", "Provide a valid calendar range of no more than seven days.")
        }
        const taskRows = assertNoError(await admin.from("restaurant_tasks")
          .select("id, name, status, scheduled_for, assigned_to, area_id, activity_template_id, estimated_minutes, priority, task_source")
          .eq("branch_id", branchId).gte("scheduled_for", fromDate).lte("scheduled_for", toDate)
          .order("scheduled_for").order("priority", { ascending: false }).order("created_at")) ?? []
        const taskIds = [...new Set(taskRows.map((task: Record<string, unknown>) => task.id)
          .filter((id: unknown): id is string => typeof id === "string"))]
        const taskParts = taskIds.length
          ? assertNoError(await admin.from("restaurant_task_parts")
            .select("id, task_id, zone_id, assigned_to, status, estimated_minutes")
            .eq("branch_id", branchId).in("task_id", taskIds)) ?? []
          : []
        const assignedIds = [...new Set([
          ...taskRows.map((task: Record<string, unknown>) => task.assigned_to),
          ...taskParts.map((part: Record<string, unknown>) => part.assigned_to),
        ]
          .filter((id: unknown): id is string => typeof id === "string"))]
        const areaIds = [...new Set(taskRows.map((task: Record<string, unknown>) => task.area_id)
          .filter((id: unknown): id is string => typeof id === "string"))]
        const templateIds = [...new Set(taskRows.map((task: Record<string, unknown>) => task.activity_template_id)
          .filter((id: unknown): id is string => typeof id === "string"))]
        const zoneIds = [...new Set(taskParts.map((part: Record<string, unknown>) => part.zone_id)
          .filter((id: unknown): id is string => typeof id === "string"))]
        const [areas, users, templates, memberships, zones, templatePositions, wastePositions, branchSettings] = await Promise.all([
          areaIds.length
            ? admin.from("restaurant_areas").select("id, name").eq("branch_id", branchId).in("id", areaIds)
            : Promise.resolve({ data: [], error: null }),
          assignedIds.length
            ? admin.from("users").select("id, full_name").in("id", assignedIds)
            : Promise.resolve({ data: [], error: null }),
          templateIds.length
            ? admin.from("restaurant_activity_templates").select("id, is_divisible").eq("branch_id", branchId).in("id", templateIds)
            : Promise.resolve({ data: [], error: null }),
          ["admin", "supervisor"].includes(membership.access_role)
            ? admin.from("restaurant_memberships").select("user_id").eq("branch_id", branchId).eq("is_active", true)
            : Promise.resolve({ data: [], error: null }),
          zoneIds.length
            ? admin.from("restaurant_activity_zones").select("id, name").eq("branch_id", branchId).in("id", zoneIds)
            : Promise.resolve({ data: [], error: null }),
          templateIds.length
            ? admin.from("restaurant_activity_positions").select("activity_template_id").eq("branch_id", branchId).in("activity_template_id", templateIds)
            : Promise.resolve({ data: [], error: null }),
          admin.from("restaurant_waste_positions").select("position_id").eq("branch_id", branchId),
          admin.from("restaurant_branches").select("timezone").eq("id", branchId).single(),
        ])
        const areaById = new Map((assertNoError(areas) ?? []).map((area: Record<string, unknown>) => [area.id, area.name]))
        const userById = new Map((assertNoError(users) ?? []).map((user: Record<string, unknown>) => [user.id, user.full_name]))
        const divisibleByTemplate = new Map((assertNoError(templates) ?? []).map((template: Record<string, unknown>) => [template.id, Boolean(template.is_divisible)]))
        const zoneById = new Map((assertNoError(zones) ?? []).map((zone: Record<string, unknown>) => [zone.id, zone.name]))
        const templateIdsWithPositions = new Set((assertNoError(templatePositions) ?? [])
          .map((row: Record<string, unknown>) => row.activity_template_id))
        const hasWastePositions = (assertNoError(wastePositions) ?? []).length > 0
        const partsByTask = new Map<string, Record<string, unknown>[]>()
        for (const part of taskParts as Record<string, unknown>[]) {
          const taskId = String(part.task_id)
          const parts = partsByTask.get(taskId) ?? []
          parts.push({
            ...part,
            zone_name: zoneById.get(part.zone_id) ?? null,
            assignee_name: userById.get(part.assigned_to) ?? null,
          })
          partsByTask.set(taskId, parts)
        }
        const memberIds = [...new Set((assertNoError(memberships) ?? []).map((item: Record<string, unknown>) => item.user_id)
          .filter((id: unknown): id is string => typeof id === "string"))]
        const memberUsers = memberIds.length
          ? assertNoError(await admin.from("users").select("id, full_name").in("id", memberIds).eq("is_active", true)) ?? []
          : []
        const branchTimeZone = assertNoError(branchSettings)?.timezone
        if (typeof branchTimeZone !== "string") throw new Error("Branch timezone is unavailable.")
        return jsonResponse({ local_date: dateInZone(branchTimeZone), tasks: taskRows.map((task: Record<string, unknown>) => ({
          ...task,
          area_name: areaById.get(task.area_id) ?? null,
          assignee_name: userById.get(task.assigned_to) ?? null,
          is_divisible: divisibleByTemplate.get(task.activity_template_id) ?? false,
          configuration_pending: (task.task_source === "waste" && !hasWastePositions) ||
            (divisibleByTemplate.has(task.activity_template_id) && !templateIdsWithPositions.has(task.activity_template_id)) ||
            (divisibleByTemplate.get(task.activity_template_id) === true && (partsByTask.get(String(task.id)) ?? []).length === 0),
          parts: partsByTask.get(String(task.id)) ?? [],
        })), assignable_members: memberUsers.map((item: Record<string, unknown>) => ({
          id: item.id, full_name: item.full_name,
        })).sort((left: Record<string, unknown>, right: Record<string, unknown>) =>
          String(left.full_name ?? "").localeCompare(String(right.full_name ?? ""))),
        can_manage_assignments: ["admin", "supervisor"].includes(membership.access_role) }, 200, requestId)
      }
      if (action === "notification_inbox") return jsonResponse(await getNotificationInbox(admin, branchId, user.id), 200, requestId)
      if (action === "task_receipts") {
        let query = admin.from("restaurant_task_receipts")
          .select("id, task_id, employee_id, assignment_recorded_at, receipt_state, confirmed_at, confirmed_by, confirmation_channel")
          .eq("branch_id", branchId)
        if (!["admin", "supervisor"].includes(membership.access_role)) query = query.eq("employee_id", user.id)
        const rows = assertNoError(await query.order("assignment_recorded_at", { ascending: false })) ?? []
        if (!rows.length || !["admin", "supervisor"].includes(membership.access_role)) {
          return jsonResponse({ receipts: rows }, 200, requestId)
        }
        const taskIds = [...new Set(rows.map((row: Record<string, unknown>) => String(row.task_id)))]
        const [tasksResult, branchResult] = await Promise.all([
          admin.from("restaurant_tasks").select("id, priority").eq("branch_id", branchId).in("id", taskIds),
          admin.from("restaurant_branches").select("timezone, receipt_escalation_seconds_by_priority").eq("id", branchId).single(),
        ])
        const tasksById = new Map((assertNoError(tasksResult) ?? []).map((task: Record<string, unknown>) => [String(task.id), task]))
        const escalationPolicy = assertNoError(branchResult).receipt_escalation_seconds_by_priority as Record<string, unknown>
        const now = Date.now()
        return jsonResponse({ receipts: rows.map((row: Record<string, unknown>) => {
          const task = tasksById.get(String(row.task_id))
          const priority = String(task?.priority ?? "")
          const threshold = Number(escalationPolicy[priority])
          const configured = Number.isInteger(threshold) && threshold >= 30 && threshold <= 86400
          const assignedAt = Date.parse(String(row.assignment_recorded_at))
          const dueAt = configured && Number.isFinite(assignedAt) ? assignedAt + threshold * 1000 : null
          return { ...row, priority: task?.priority ?? null, escalation_threshold_seconds: configured ? threshold : null,
            escalation_due_at: dueAt === null ? null : new Date(dueAt).toISOString(),
            escalation_remaining_seconds: dueAt === null ? null : Math.max(0, Math.ceil((dueAt - now) / 1000)),
            needs_escalation: row.receipt_state === "awaiting" && dueAt !== null && dueAt <= now }
        }) }, 200, requestId)
      }
      if (action === "collaboration_inbox") {
        const rows = assertNoError(await admin.from("restaurant_collaboration_requests")
          .select("id, task_id, target_employee_id, created_by, request_source, manager_escalated_at, status, claimed_by, claimed_until, resolution, resolved_by, resolved_at, created_at")
          .eq("branch_id", branchId).in("status", ["open", "claimed", "resolved", "cancelled"])
          .order("created_at", { ascending: false }).limit(100)) ?? []
        // Keep recent resolved notices visible so clients can reconcile stale push notifications.
        // A claim is a reservation, not a reason to hide the notice from other eligible coworkers.
        const availableIds = new Set(assertNoError(await admin.rpc("restaurant_get_available_collaborator_ids", { p_branch_id: branchId })) ?? [])
        const manager = ["admin", "supervisor"].includes(membership.access_role)
        const visible = rows.filter((row: Record<string, unknown>) => row.target_employee_id !== user.id
          && (manager || row.status === "resolved" || row.status === "cancelled" || availableIds.has(user.id)))
        const taskIds = [...new Set(visible.map((row: Record<string, unknown>) => String(row.task_id)))]
        const tasks = taskIds.length ? assertNoError(await admin.from("restaurant_tasks")
          .select("id, name, area_id, scheduled_for, status, assigned_to")
          .eq("branch_id", branchId).in("id", taskIds)) ?? [] : []
        const taskById = new Map(tasks.map((task: Record<string, unknown>) => [task.id, task]))
        return jsonResponse({ requests: visible.map((row: Record<string, unknown>) => ({
          ...row, task: taskById.get(row.task_id) ?? null,
        })) }, 200, requestId)
      }
      if (action === "operational_workspace") {
        const canManage = ["admin", "supervisor"].includes(membership.access_role)
        const employeeFilter = canManage ? null : user.id
        const [branchConfig, states, meals, reports, reviews, mealPlans, mealSlots, recommendations] = await Promise.all([
          admin.from("restaurant_branches").select("timezone").eq("id", branchId).single(),
          admin.from("restaurant_member_operational_states").select("*").eq("branch_id", branchId),
          admin.from("restaurant_meal_sessions").select("*").eq("branch_id", branchId).is("return_confirmed_at", null),
          admin.from("restaurant_task_reports").select("*").eq("branch_id", branchId)
            .order("recorded_at", { ascending: false }).limit(100),
          admin.from("restaurant_task_report_reviews").select("*").eq("branch_id", branchId)
            .order("reviewed_at", { ascending: false }).limit(200),
          admin.from("restaurant_meal_plan_proposals").select("*").eq("branch_id", branchId)
            .order("generated_at", { ascending: false }).limit(50),
          admin.from("restaurant_meal_plan_slots").select("*").eq("branch_id", branchId)
            .order("starts_at", { ascending: true }).limit(500),
          admin.from("restaurant_operational_recommendations").select("*").eq("branch_id", branchId)
            .order("created_at", { ascending: false }).limit(100),
        ])
        const allReports = assertNoError(reports) ?? []
        const visibleReports = canManage ? allReports : allReports.filter((row: Record<string, unknown>) =>
          row.responsible_employee_id === user.id || row.recorded_by === user.id)
        const reportIds = visibleReports.map((row: Record<string, unknown>) => row.id)
        const branchTimezone = assertNoError(branchConfig).timezone
        const today = dateInZone(branchTimezone)
        const visibleMealSlots = (assertNoError(mealSlots) ?? []).filter((slot: Record<string, unknown>) =>
          (canManage || slot.employee_id === user.id) && dateInZone(branchTimezone, new Date(String(slot.starts_at))) >= today)
          .map((slot: Record<string, unknown>) => ({ ...slot,
            starts_at_local: `${dateInZone(branchTimezone, new Date(String(slot.starts_at)))} ${timeInZone(branchTimezone, slot.starts_at)}`,
            scheduled_end_at_local: `${dateInZone(branchTimezone, new Date(String(slot.scheduled_end_at)))} ${timeInZone(branchTimezone, slot.scheduled_end_at)}`,
          }))
        let peerMealCandidates: Record<string, unknown>[] = []
        let canRecordPeerMeals = canManage
        if (!canManage) {
          const availableActorIds = new Set(assertNoError(await admin.rpc(
            "restaurant_get_available_collaborator_ids", { p_branch_id: branchId },
          )) ?? [])
          canRecordPeerMeals = availableActorIds.has(user.id)
          const previousDate = addDays(today, -1)
          const [rosterResult, shiftsResult, absencesResult, taskResult, partResult] = await Promise.all([
            admin.from("restaurant_memberships").select("user_id").eq("branch_id", branchId).eq("is_active", true),
            admin.from("restaurant_shifts").select("id, employee_id, shift_date, start_time, end_time, status")
              .eq("branch_id", branchId).eq("status", "published").gte("shift_date", previousDate).lte("shift_date", today),
            admin.from("restaurant_absences").select("employee_id").eq("branch_id", branchId).eq("status", "approved")
              .lte("start_date", today).gte("end_date", today),
            admin.from("restaurant_tasks").select("assigned_to").eq("branch_id", branchId).eq("status", "in_progress"),
            admin.from("restaurant_task_parts").select("assigned_to").eq("branch_id", branchId).eq("status", "in_progress"),
          ])
          const rosterIds = new Set((assertNoError(rosterResult) ?? []).map((row: Record<string, unknown>) => String(row.user_id)))
          const absentIds = new Set((assertNoError(absencesResult) ?? []).map((row: Record<string, unknown>) => String(row.employee_id)))
          const busyIds = new Set([
            ...(assertNoError(taskResult) ?? []).map((row: Record<string, unknown>) => String(row.assigned_to ?? "")),
            ...(assertNoError(partResult) ?? []).map((row: Record<string, unknown>) => String(row.assigned_to ?? "")),
          ])
          const stateByEmployee = new Map((assertNoError(states) ?? []).map((row: Record<string, unknown>) =>
            [String(row.employee_id), String(row.state)]))
          const mealByEmployee = new Map((assertNoError(meals) ?? []).map((row: Record<string, unknown>) =>
            [String(row.employee_id), row]))
          const now = new Date()
          const localTime = timeInZone(branchTimezone, now) ?? "00:00"
          const localMinute = minutesOfDay(localTime)
          const onShiftIds = new Set((assertNoError(shiftsResult) ?? [])
            .filter((shift: Record<string, string>) => isCurrentShift(shift, today, localMinute))
            .map((shift: Record<string, unknown>) => String(shift.employee_id)))
          const breaksResult = await admin.from("restaurant_shift_breaks")
            .select("shift_id, start_time, end_time").eq("branch_id", branchId)
          const scheduledBreakIds = new Set((assertNoError(shiftsResult) ?? []).filter((shift: Record<string, string>) =>
            onShiftIds.has(String(shift.employee_id)) && (assertNoError(breaksResult) ?? []).some((br: Record<string, string>) => {
              if (br.shift_id !== shift.id) return false
              const breakStart = minutesOfDay(br.start_time)
              const breakEnd = minutesOfDay(br.end_time)
              return breakStart < breakEnd
                ? localMinute >= breakStart && localMinute < breakEnd
                : localMinute >= breakStart || localMinute < breakEnd
            }))
            .map((shift: Record<string, unknown>) => String(shift.employee_id)))
          peerMealCandidates = [...onShiftIds]
            .filter((employeeId) => employeeId !== user.id && rosterIds.has(employeeId))
            .map((employeeId) => {
              const activeMeal = mealByEmployee.get(employeeId) as Record<string, unknown> | undefined
              const state = stateByEmployee.get(employeeId) ?? "available"
              return {
                employee_id: employeeId,
                employee_name: userById.get(employeeId) ?? null,
                state: activeMeal ? "meal" : state,
                active_meal_session_id: activeMeal?.id ?? null,
                can_start_meal: !activeMeal && !absentIds.has(employeeId) && !busyIds.has(employeeId)
                  && !scheduledBreakIds.has(employeeId) && !["occupied", "meal", "rest", "off_shift"].includes(state),
              }
            })
          if (peerMealCandidates.length) {
            const names = assertNoError(await admin.from("users").select("id, full_name")
              .in("id", peerMealCandidates.map((candidate) => String(candidate.employee_id)))) ?? []
            const nameById = new Map((names as Record<string, unknown>[])
              .map((row) => [String(row.id), row.full_name]))
            peerMealCandidates = peerMealCandidates.map((candidate) => ({
              ...candidate, employee_name: nameById.get(String(candidate.employee_id)) ?? null,
            }))
          }
        }
        return jsonResponse({
          operational_states: (assertNoError(states) ?? []).filter((row: Record<string, unknown>) => canManage || row.employee_id === employeeFilter),
          active_meals: (assertNoError(meals) ?? []).filter((row: Record<string, unknown>) => canManage || row.employee_id === employeeFilter),
          peer_meal_candidates: peerMealCandidates,
          can_record_peer_meals: canRecordPeerMeals,
          task_reports: visibleReports,
          task_report_reviews: (assertNoError(reviews) ?? []).filter((row: Record<string, unknown>) => reportIds.includes(row.report_id)),
          meal_plans: canManage ? assertNoError(mealPlans) ?? [] : (assertNoError(mealPlans) ?? []).filter((plan: Record<string, unknown>) =>
            ["approved", "modified"].includes(String(plan.status))
            && Array.isArray(plan.approved_schedule)
            && (plan.approved_schedule as Array<Record<string, unknown>>).some((slot) => slot.employee_id === user.id)),
          meal_plan_slots: visibleMealSlots,
          recommendations: canManage ? assertNoError(recommendations) ?? [] : [],
        }, 200, requestId)
      }
      fail(400, "INVALID_ACTION", "Unknown read action.")
    }

    const payload = await req.json().catch(() => fail(400, "INVALID_PAYLOAD", "Request body must be valid JSON.")) as Record<string, unknown>
    const action = requiredString(payload.action, "action", 64)
    if (action === "create_branch") {
      if (!["owner", "admin"].includes(profile.role)) fail(403, "MANAGER_REQUIRED", "Only a company administrator can create a branch.")
      const name = requiredString(payload.name, "name", 120)
      const timezone = requiredString(payload.timezone, "timezone", 64)
      const branchId = assertNoError(await admin.rpc("create_restaurant_branch", {
        p_company_id: profile.company_id, p_creator_id: user.id, p_name: name, p_timezone: timezone,
      }))
      return jsonResponse({ branch_id: branchId }, 201, requestId)
    }

    const branchId = requiredUuid(payload.branch_id, "branch_id")
      const managerOnly = ["auto_assign", "assign_task", "assign_task_part", "reschedule_task", "save_area", "save_position", "save_member", "invite_member", "set_member_active", "save_member_positions", "save_waste_positions", "save_bin", "save_template", "save_inspection_template", "save_shift", "cancel_shift", "save_absence", "review_absence", "review_shift_cover_request", "save_branch_features", "save_assignment_policy", "update_incident", "schedule_tasks", "create_task", "request_collaborative_notice", "review_task_report", "get_task_report_evidence", "generate_meal_plan", "decide_meal_plan", "decide_recommendation", "analyze_operational_coverage", "analyze_operational_history"].includes(action)
    const membership = await memberForBranch(admin, branchId, user.id, managerOnly)

    if (action === "confirm_task_receipt") {
      const taskId = requiredUuid(payload.task_id, "task_id")
      const result = assertNoError(await admin.rpc("confirm_restaurant_task_receipt", {
        p_branch_id: branchId, p_task_id: taskId, p_actor_id: user.id,
      }))
      return jsonResponse(result, 200, requestId)
    }

    if (action === "request_collaborative_notice") {
      const taskId = requiredUuid(payload.task_id, "task_id")
      const clientEventId = requiredUuid(payload.client_event_id, "client_event_id")
      const noticeId = assertNoError(await admin.rpc("create_restaurant_collaboration_request", {
        p_branch_id: branchId, p_task_id: taskId, p_actor_id: user.id, p_client_event_id: clientEventId,
      }))
      return jsonResponse({ request_id: noticeId }, 201, requestId)
    }

    if (action === "claim_collaborative_notice") {
      const noticeId = requiredUuid(payload.request_id, "request_id")
      const branchPolicy = assertNoError(await admin.from("restaurant_branches")
        .select("collaboration_reservation_seconds").eq("id", branchId).single())
      const reservationSeconds = Number(branchPolicy.collaboration_reservation_seconds)
      if (!Number.isInteger(reservationSeconds)) fail(409, "COLLABORATION_RESERVATION_NOT_CONFIGURED", "La sucursal debe configurar el tiempo de reserva de avisos.")
      const result = assertNoError(await admin.rpc("claim_restaurant_collaboration_request", {
        p_branch_id: branchId, p_request_id: noticeId, p_actor_id: user.id,
        p_reservation_seconds: reservationSeconds,
      }))
      return jsonResponse(result, 200, requestId)
    }

    if (action === "resolve_collaborative_notice") {
      const noticeId = requiredUuid(payload.request_id, "request_id")
      const resolution = requiredString(payload.resolution, "resolution", 24)
      const result = assertNoError(await admin.rpc("resolve_restaurant_collaboration_request", {
        p_branch_id: branchId, p_request_id: noticeId, p_actor_id: user.id, p_resolution: resolution,
      }))
      return jsonResponse(result, 200, requestId)
    }

    if (action === "record_task_report") {
      const declaredAt = typeof payload.declared_completed_at === "string"
        ? new Date(payload.declared_completed_at) : new Date()
      if (!Number.isFinite(declaredAt.getTime()) || declaredAt.getTime() > Date.now() + 60_000) {
        fail(400, "INVALID_DECLARED_COMPLETION_TIME", "La hora declarada debe ser válida y no futura.")
      }
      const evidencePath = typeof payload.evidence_path === "string" ? requiredString(payload.evidence_path, "evidence_path", 1024) : null
      const reportId = assertNoError(await admin.rpc("restaurant_record_task_report", {
        p_branch_id: branchId, p_task_id: requiredUuid(payload.task_id, "task_id"),
        p_part_id: payload.part_id == null ? null : requiredUuid(payload.part_id, "part_id"),
        p_responsible_employee_id: requiredUuid(payload.responsible_employee_id, "responsible_employee_id"),
        p_recorded_by: user.id, p_declared_completed_at: declaredAt.toISOString(),
        p_evidence_path: evidencePath,
        p_note: typeof payload.note === "string" ? payload.note.slice(0, 1000) : null,
        p_client_event_id: requiredUuid(payload.client_event_id, "client_event_id"),
      }))
      return jsonResponse({ report_id: reportId, recorded_by: user.id, recorded_at: new Date().toISOString() }, 201, requestId)
    }

    if (action === "review_task_report") {
      const result = assertNoError(await admin.rpc("restaurant_review_task_report", {
        p_branch_id: branchId, p_report_id: requiredUuid(payload.report_id, "report_id"),
        p_reviewer_id: user.id, p_decision: requiredString(payload.decision, "decision", 16),
        p_note: typeof payload.note === "string" ? payload.note.slice(0, 1000) : null,
      }))
      return jsonResponse(result, 200, requestId)
    }

    if (action === "get_task_report_evidence") {
      const report = assertNoError(await admin.from("restaurant_task_reports")
        .select("task_id, evidence_path").eq("branch_id", branchId)
        .eq("id", requiredUuid(payload.report_id, "report_id")).maybeSingle())
      if (!report || typeof report.evidence_path !== "string" || !report.evidence_path.startsWith(`${branchId}/${report.task_id}/`)) {
        fail(404, "TASK_REPORT_EVIDENCE_NOT_FOUND", "No hay evidencia asociada a este reporte.")
      }
      const signed = assertNoError(await admin.storage.from("restaurant-evidence")
        .createSignedUrl(report.evidence_path, 90))
      return jsonResponse({ signed_url: signed.signedUrl, expires_in_seconds: 90 }, 200, requestId)
    }

    if (action === "set_operational_state") {
      const requestedState = requiredString(payload.state, "state", 20)
      if (["rest", "off_shift"].includes(requestedState) && !["admin", "supervisor"].includes(membership.access_role)) {
        fail(403, "MANAGER_REQUIRED", "Solo una persona gerente puede autorizar descanso o fin de turno.")
      }
      const result = assertNoError(await admin.rpc("restaurant_set_operational_state", {
        p_branch_id: branchId, p_employee_id: payload.employee_id == null ? user.id : requiredUuid(payload.employee_id, "employee_id"),
        p_actor_id: user.id, p_state: requestedState,
        p_note: typeof payload.note === "string" ? payload.note.slice(0, 500) : null,
      }))
      return jsonResponse(result, 200, requestId)
    }

    if (action === "start_meal") {
      const branch = assertNoError(await admin.from("restaurant_branches")
        .select("timezone").eq("id", branchId).single())
      const declaredStartedAt = declaredTimestamp(payload.declared_at, branch.timezone)
      const result = assertNoError(await admin.rpc("restaurant_start_meal", {
        p_branch_id: branchId, p_employee_id: payload.employee_id == null ? user.id : requiredUuid(payload.employee_id, "employee_id"),
        p_actor_id: user.id, p_note: typeof payload.note === "string" ? payload.note.slice(0, 500) : null,
        p_declared_started_at: declaredStartedAt,
      }))
      return jsonResponse({ meal_session_id: result, started: true }, 201, requestId)
    }

    if (action === "confirm_meal_return") {
      const branch = assertNoError(await admin.from("restaurant_branches")
        .select("timezone").eq("id", branchId).single())
      const declaredReturnAt = declaredTimestamp(payload.declared_at, branch.timezone)
      const result = assertNoError(await admin.rpc("restaurant_confirm_meal_return", {
        p_branch_id: branchId, p_session_id: requiredUuid(payload.session_id, "session_id"),
        p_actor_id: user.id, p_state: requiredString(payload.state_after_return ?? "available", "state_after_return", 20),
        p_declared_return_at: declaredReturnAt,
      }))
      return jsonResponse(result, 200, requestId)
    }

    if (action === "generate_meal_plan") {
      const shiftDate = requiredString(payload.shift_date, "shift_date", 10)
      if (!isCalendarDate(shiftDate)) fail(400, "INVALID_SHIFT_DATE", "shift_date must be YYYY-MM-DD.")
      const branch = assertNoError(await admin.from("restaurant_branches")
        .select("timezone, meal_duration_minutes, minimum_area_coverage").eq("id", branchId).single())
      if (shiftDate < dateInZone(branch.timezone)) fail(400, "INVALID_SHIFT_DATE", "No se pueden generar propuestas para fechas pasadas.")
      const duration = Number(branch.meal_duration_minutes)
      if (!Number.isInteger(duration) || duration < 1 || duration > 240) fail(409, "MEAL_DURATION_NOT_CONFIGURED", "Configura la duración autorizada de comida en la sucursal antes de planificar.")
      const mealDayStart = localClockToUtc(shiftDate, "00:00", branch.timezone)
      const mealDayEnd = localClockToUtc(addDays(shiftDate, 1), "00:00", branch.timezone)
      const [shiftsResult, breaksResult, absencesResult, membershipsResult, positionsResult, memberPositionsResult, statesResult, mealsResult, consumedMealsResult, tasksResult, areasResult] = await Promise.all([
        admin.from("restaurant_shifts").select("id, employee_id, start_time, end_time").eq("branch_id", branchId).eq("shift_date", shiftDate).eq("status", "published"),
        admin.from("restaurant_shift_breaks").select("shift_id, start_time, end_time").eq("branch_id", branchId),
        admin.from("restaurant_absences").select("employee_id").eq("branch_id", branchId).eq("status", "approved").lte("start_date", shiftDate).gte("end_date", shiftDate),
        admin.from("restaurant_memberships").select("user_id, is_active").eq("branch_id", branchId).eq("is_active", true),
        admin.from("restaurant_positions").select("id, area_id").eq("branch_id", branchId).eq("is_active", true),
        admin.from("restaurant_member_positions").select("user_id, position_id").eq("branch_id", branchId),
        admin.from("restaurant_member_operational_states").select("employee_id, state").eq("branch_id", branchId),
        admin.from("restaurant_meal_sessions").select("employee_id").eq("branch_id", branchId).is("return_confirmed_at", null),
        admin.from("restaurant_meal_sessions").select("employee_id").eq("branch_id", branchId).gte("started_at", mealDayStart).lt("started_at", mealDayEnd),
        admin.from("restaurant_tasks").select("id, assigned_to").eq("branch_id", branchId).eq("scheduled_for", shiftDate).eq("status", "in_progress"),
        admin.from("restaurant_areas").select("id, name").eq("branch_id", branchId).eq("is_active", true),
      ])
      const shifts = assertNoError(shiftsResult) ?? []
      if (!shifts.length) fail(409, "PUBLISHED_SHIFTS_REQUIRED", "No hay turnos publicados para generar una propuesta de comida.")
      const absent = new Set((assertNoError(absencesResult) ?? []).map((row: { employee_id: string }) => row.employee_id))
      const activeMembers = new Set((assertNoError(membershipsResult) ?? []).map((row: { user_id: string }) => row.user_id))
      const currentUnavailable = new Set<string>(shiftDate === dateInZone(branch.timezone) ? [
        ...(assertNoError(statesResult) ?? []).filter((row: { state: string }) => ["meal", "rest", "off_shift"].includes(row.state)).map((row: { employee_id: string }) => row.employee_id),
        ...(assertNoError(mealsResult) ?? []).map((row: { employee_id: string }) => row.employee_id),
      ] : [])
      const alreadyAte = new Set((assertNoError(consumedMealsResult) ?? []).map((row: { employee_id: string }) => row.employee_id))
      const inProgressTasks = assertNoError(tasksResult) ?? []
      const inProgressTaskIds = inProgressTasks.map((row: { id: string }) => row.id)
      const inProgressParts = inProgressTaskIds.length
        ? assertNoError(await admin.from("restaurant_task_parts").select("assigned_to").eq("branch_id", branchId).in("task_id", inProgressTaskIds).eq("status", "in_progress")) ?? []
        : []
      const inProgress = new Set<string>([
        ...inProgressTasks.map((row: { assigned_to: string | null }) => row.assigned_to).filter((id: string | null): id is string => Boolean(id)),
        ...inProgressParts.map((row: { assigned_to: string | null }) => row.assigned_to).filter((id: string | null): id is string => Boolean(id)),
      ])
      const positionArea = new Map((assertNoError(positionsResult) ?? []).filter((row: { area_id: string | null }) => row.area_id).map((row: { id: string; area_id: string }) => [row.id, row.area_id]))
      const employeeAreas = new Map<string, Set<string>>()
      for (const row of assertNoError(memberPositionsResult) ?? []) {
        const areaId = positionArea.get(row.position_id)
        if (!areaId) continue
        const values = employeeAreas.get(row.user_id) ?? new Set<string>()
        values.add(areaId); employeeAreas.set(row.user_id, values)
      }
      const minimums = branch.minimum_area_coverage as Record<string, unknown>
      const areaNames = new Map((assertNoError(areasResult) ?? []).map((row: { id: string; name: string }) => [row.id, row.name]))
      const qualifiedCoverageShifts: Array<{ employeeId: string; areaId: string; start: number; end: number }> = []
      for (const shift of shifts) {
        if (absent.has(shift.employee_id) || !activeMembers.has(shift.employee_id)
          || currentUnavailable.has(shift.employee_id)) continue
        const mappedAreas = employeeAreas.get(shift.employee_id) ?? new Set<string>()
        if (mappedAreas.size !== 1) continue
        const start = Number(String(shift.start_time).slice(0, 2)) * 60 + Number(String(shift.start_time).slice(3, 5))
        let end = Number(String(shift.end_time).slice(0, 2)) * 60 + Number(String(shift.end_time).slice(3, 5))
        if (end <= start) end += 1440
        qualifiedCoverageShifts.push({ employeeId: shift.employee_id, areaId: [...mappedAreas][0], start, end })
      }
      const areaHeadcount = new Map<string, number>()
      for (const shift of shifts) {
        if (absent.has(shift.employee_id) || !activeMembers.has(shift.employee_id)) continue
        const areas = employeeAreas.get(shift.employee_id) ?? new Set<string>()
        if (areas.size === 1) {
          const areaId = [...areas][0]
          areaHeadcount.set(areaId, (areaHeadcount.get(areaId) ?? 0) + 1)
        }
      }
      for (const [areaId, required] of Object.entries(minimums)) {
        if (!Number.isInteger(required) || Number(required) < 0 || !areaNames.has(areaId)) fail(409, "INVALID_AREA_COVERAGE", "Corrige la configuración de cobertura por área antes de generar la propuesta.")
        if (Number(required) > 0 && (areaHeadcount.get(areaId) ?? 0) < Number(required) + 1) {
          fail(409, "MEAL_COVERAGE_INFEASIBLE", `No se puede garantizar el mínimo de cobertura de ${String(areaNames.get(areaId))} durante una comida. Ajusta los turnos, puestos o mínimos.`)
        }
      }
      const shiftsById = new Map(shifts.map((shift: { id: string }) => [shift.id, shift]))
      const breaksByShift = new Map<string, Array<{ start_time: string; end_time: string }>>()
      for (const item of assertNoError(breaksResult) ?? []) {
        const bucket = breaksByShift.get(item.shift_id) ?? []
        bucket.push(item); breaksByShift.set(item.shift_id, bucket)
      }
      const workers: Array<Record<string, unknown>> = []
      const skippedEmployees: Array<{ employee_id: string; reason: string }> = []
      for (const shift of shifts) {
        const employeeId = String(shift.employee_id)
        const reason = absent.has(employeeId) ? "approved_absence"
          : !activeMembers.has(employeeId) ? "inactive_membership"
          : currentUnavailable.has(employeeId) ? "currently_unavailable"
          : alreadyAte.has(employeeId) ? "meal_already_taken"
          : inProgress.has(employeeId) ? "task_in_progress" : null
        if (reason) { skippedEmployees.push({ employee_id: employeeId, reason }); continue }
        const start = Number(String(shift.start_time).slice(0, 2)) * 60 + Number(String(shift.start_time).slice(3, 5))
        let end = Number(String(shift.end_time).slice(0, 2)) * 60 + Number(String(shift.end_time).slice(3, 5))
        if (end <= start) end += 1440
        if (end - start < duration) { skippedEmployees.push({ employee_id: employeeId, reason: "shift_shorter_than_meal" }); continue }
        const blockedStartMinutes: number[] = []
        const workerAreas = employeeAreas.get(employeeId) ?? new Set<string>()
        const workerArea = workerAreas.size === 1 ? [...workerAreas][0] : null
        for (let slot = 0; slot < 2880; slot += 15) {
          if (slot < start || slot + duration > end) { blockedStartMinutes.push(slot); continue }
          const overlapsBreak = (breaksByShift.get(shift.id) ?? []).some((item) => {
            const breakStartClock = Number(String(item.start_time).slice(0, 2)) * 60 + Number(String(item.start_time).slice(3, 5))
            let breakEndClock = Number(String(item.end_time).slice(0, 2)) * 60 + Number(String(item.end_time).slice(3, 5))
            let breakStart = breakStartClock
            if (breakEndClock <= breakStartClock) breakEndClock += 1440
            if (breakStart < start) breakStart += 1440
            const breakEnd = breakEndClock + (breakStart >= 1440 && breakStartClock < start ? 1440 : 0)
            return slot < breakEnd && breakStart < slot + duration
          })
          let violatesCoverage = false
          if (!overlapsBreak && workerArea) {
            for (const [areaId, required] of Object.entries(minimums)) {
              const minimum = Number(required)
              if (minimum <= 0) continue
              const areaShifts = qualifiedCoverageShifts.filter((row) => row.areaId === areaId)
              const boundaries = new Set<number>([slot])
              for (const row of areaShifts) {
                if (row.start > slot && row.start < slot + duration) boundaries.add(row.start)
                if (row.end > slot && row.end < slot + duration) boundaries.add(row.end)
              }
              for (const minute of boundaries) {
                const scheduled = areaShifts.filter((row) => row.start <= minute && row.end > minute).length
                const unavailableForMeal = workerArea === areaId && start <= minute && end > minute ? 1 : 0
                if (scheduled - unavailableForMeal < minimum) { violatesCoverage = true; break }
              }
              if (violatesCoverage) break
            }
          }
          if (overlapsBreak || violatesCoverage) blockedStartMinutes.push(slot)
        }
        workers.push({ employeeId, shiftStartMinute: start, shiftEndMinute: end, mealDurationMinutes: duration,
          preferredMealStartMinute: Math.round(((start + end - duration) / 2) / 15) * 15, blockedStartMinutes })
      }
      if (!workers.length) fail(409, "NO_MEAL_CANDIDATES", "No hay trabajadores con turno publicado y elegible para incluir en la propuesta.")
      const rangeStart = Math.max(0, Math.floor(Math.min(...workers.map((worker) => Number(worker.shiftStartMinute))) / 15) * 15)
      const rangeEnd = Math.ceil(Math.max(...workers.map((worker) => Number(worker.shiftEndMinute))) / 15) * 15
      const mealStartRange = Array.from({ length: Math.max(0, Math.floor((rangeEnd - rangeStart) / 15)) }, (_, index) => rangeStart + index * 15)
      const serviceUrl = Deno.env.get("TIMEFOLD_SERVICE_URL")?.trim()
      const token = Deno.env.get("TIMEFOLD_SERVICE_TOKEN")?.trim()
      if (!serviceUrl || !token) fail(503, "TIMEFOLD_MEAL_PLANNER_UNAVAILABLE", "Timefold no está configurado para planificar comidas; no se generó una propuesta alternativa silenciosamente.")
      let solveUrl: string
      try {
        const configured = new URL(serviceUrl)
        solveUrl = configured.pathname.endsWith("/api/assignments/solve")
          ? `${configured.origin}${configured.pathname.replace(/\/api\/assignments\/solve$/, "/api/meal-plans/solve")}`
          : new URL("/api/meal-plans/solve", configured.origin).toString()
      } catch { fail(503, "TIMEFOLD_MEAL_PLANNER_UNAVAILABLE", "La URL configurada para Timefold no es válida.") }
      const controller = new AbortController()
      const timeout = setTimeout(() => controller.abort(), 8000)
      let response: Response
      try {
        response = await fetch(solveUrl, { method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
          body: JSON.stringify({ workers, mealStartRange }), signal: controller.signal })
      } catch (error) {
        console.warn("meal_plan_timefold_request_failed", { request_id: requestId, branch_id: branchId, reason: error instanceof Error && error.name === "AbortError" ? "timeout" : "request_failed" })
        fail(503, "TIMEFOLD_MEAL_PLANNER_UNAVAILABLE", "Timefold no respondió; no se guardó una propuesta.")
      } finally { clearTimeout(timeout) }
      if (!response.ok) fail(response.status === 422 ? 409 : 503, response.status === 422 ? "MEAL_PLAN_INFEASIBLE" : "TIMEFOLD_MEAL_PLANNER_UNAVAILABLE", "Timefold no pudo producir un horario factible; no se guardó ninguna propuesta.")
      const solved = await response.json() as { planner?: string; feasible?: boolean; score?: string; assignments?: Array<{ employee_id: string; start_minute: number; end_minute: number }> }
      if (solved.planner !== "timefold" || solved.feasible !== true || !Array.isArray(solved.assignments) || solved.assignments.length !== workers.length) fail(502, "INVALID_TIMEFOLD_MEAL_PLAN", "La respuesta de Timefold no coincide con los trabajadores elegibles.")
      const workerById = new Map(workers.map((worker) => [String(worker.employeeId), worker]))
      const seenEmployees = new Set<string>()
      const slots: Array<{ employee_id: string; starts_at: string; scheduled_end_at: string }> = []
      for (const assignment of solved.assignments) {
        const employeeId = String(assignment.employee_id)
        const worker = workerById.get(employeeId)
        const startMinute = Number(assignment.start_minute)
        const endMinute = Number(assignment.end_minute)
        if (!worker || seenEmployees.has(employeeId) || !Number.isInteger(startMinute) || startMinute % 15 !== 0
          || endMinute - startMinute !== duration || startMinute < Number(worker.shiftStartMinute) || endMinute > Number(worker.shiftEndMinute)
          || (worker.blockedStartMinutes as number[]).includes(startMinute)) fail(502, "INVALID_TIMEFOLD_MEAL_PLAN", "La propuesta de Timefold no respeta turno o descanso configurado.")
        seenEmployees.add(employeeId)
        const startDate = startMinute >= 1440 ? addDays(shiftDate, Math.floor(startMinute / 1440)) : shiftDate
        const endDate = endMinute >= 1440 ? addDays(shiftDate, Math.floor(endMinute / 1440)) : shiftDate
        const startClock = startMinute % 1440; const endClock = endMinute % 1440
        const startText = `${startDate}T${String(Math.floor(startClock / 60)).padStart(2, "0")}:${String(startClock % 60).padStart(2, "0")}`
        const endText = `${endDate}T${String(Math.floor(endClock / 60)).padStart(2, "0")}:${String(endClock % 60).padStart(2, "0")}`
        slots.push({ employee_id: employeeId, starts_at_local: startText, scheduled_end_at_local: endText,
          starts_at: localDateTimeToUtc(startText, branch.timezone),
          scheduled_end_at: localDateTimeToUtc(endText, branch.timezone) })
      }
      const sortedSlots = [...solved.assignments].sort((a, b) => a.start_minute - b.start_minute)
      for (let index = 1; index < sortedSlots.length; index++) {
        if (sortedSlots[index].start_minute < sortedSlots[index - 1].end_minute) fail(502, "INVALID_TIMEFOLD_MEAL_PLAN", "La respuesta de Timefold contiene comidas simultáneas.")
      }
      const insertedPlan = assertNoError(await admin.from("restaurant_meal_plan_proposals").insert({
        branch_id: branchId, shift_date: shiftDate, planner: "timefold",
        proposed_schedule: slots.map((slot) => ({ ...slot, duration_minutes: duration })),
        planning_inputs: { shift_date: shiftDate, timezone: branch.timezone, meal_duration_minutes: duration,
          workers, minimum_area_coverage: minimums },
      }).select("id, shift_date, planner, proposed_schedule, status").single())
      return jsonResponse({ ...insertedPlan, score: solved.score, skipped_employees: skippedEmployees,
        limitations: ["Meals are staggered one at a time to preserve configured qualified headcount conservatively.", "Only published shifts, approved absences, configured breaks, prior or active meals, operational status and in-progress tasks or parts are considered.", "Task time windows and demand forecasts are not modeled because the current task schema has no approved time window or trusted demand feed."] }, 201, requestId)
    }

    if (action === "decide_meal_plan") {
      const planId = requiredUuid(payload.plan_id, "plan_id")
      const decision = requiredString(payload.decision, "decision", 16)
      const pendingPlan = assertNoError(await admin.from("restaurant_meal_plan_proposals")
        .select("id, status, shift_date, proposed_schedule, planning_inputs")
        .eq("branch_id", branchId).eq("id", planId).single())
      if (pendingPlan.status !== "proposed") fail(409, "MEAL_PLAN_NOT_PENDING", "Esta propuesta ya fue resuelta.")
      const planTimezone = String((pendingPlan.planning_inputs as Record<string, unknown>)?.timezone ?? "UTC")
      if (String(pendingPlan.shift_date) < dateInZone(planTimezone)) fail(409, "MEAL_PLAN_EXPIRED", "No se puede aprobar una propuesta de comida para una fecha pasada.")
      let approvedSchedule: unknown[] | null = null
      if (decision !== "rejected") {
        const requested = Array.isArray(payload.schedule) ? payload.schedule : pendingPlan.proposed_schedule
        if (!Array.isArray(requested)) fail(400, "INVALID_MEAL_SCHEDULE", "El horario aprobado debe ser una lista de intervalos.")
        const planningInputs = pendingPlan.planning_inputs as { timezone?: string; shift_date?: string; meal_duration_minutes?: number; workers?: Array<Record<string, unknown>> }
        const workerById = new Map((planningInputs.workers ?? []).map((worker) => [String(worker.employeeId), worker]))
        if (!workerById.size || requested.length !== workerById.size) fail(409, "INVALID_MEAL_SCHEDULE", "El horario debe conservar todas las personas elegibles de la propuesta.")
        const rows: Array<{ employeeId: string; start: number; end: number; original: Record<string, unknown> }> = []
        for (const item of requested) {
          if (typeof item !== "object" || item === null) fail(400, "INVALID_MEAL_SCHEDULE", "Cada comida debe tener responsable e intervalo.")
          const slot = item as Record<string, unknown>
          const employeeId = requiredUuid(slot.employee_id, "employee_id")
          const worker = workerById.get(employeeId)
          if (!worker || rows.some((row) => row.employeeId === employeeId)) fail(400, "INVALID_MEAL_SCHEDULE", "La propuesta contiene personas duplicadas o ajenas al conjunto original.")
          const startFromLocal = typeof slot.starts_at_local === "string"
            ? localDateTimeToUtc(slot.starts_at_local, String(planningInputs.timezone)) : null
          const endFromLocal = typeof slot.scheduled_end_at_local === "string"
            ? localDateTimeToUtc(slot.scheduled_end_at_local, String(planningInputs.timezone)) : null
          const startDate = new Date(startFromLocal ?? String(slot.starts_at ?? "")); const endDate = new Date(endFromLocal ?? String(slot.scheduled_end_at ?? ""))
          if (!Number.isFinite(startDate.getTime()) || !Number.isFinite(endDate.getTime())) fail(400, "INVALID_MEAL_SCHEDULE", "Cada intervalo requiere fechas válidas.")
          const shiftDate = String(planningInputs.shift_date)
          const localStartDate = dateInZone(String(planningInputs.timezone), startDate)
          const localEndDate = dateInZone(String(planningInputs.timezone), endDate)
          const startClock = timeInZone(String(planningInputs.timezone), startDate.toISOString()) ?? ""
          const endClock = timeInZone(String(planningInputs.timezone), endDate.toISOString()) ?? ""
          const dayOffset = (date: string) => Math.round((Date.parse(`${date}T00:00:00Z`) - Date.parse(`${shiftDate}T00:00:00Z`)) / 86400000)
          const toMinute = (date: string, clock: string) => dayOffset(date) * 1440 + Number(clock.slice(0, 2)) * 60 + Number(clock.slice(3, 5))
          const start = toMinute(localStartDate, startClock); const end = toMinute(localEndDate, endClock)
          const duration = Number(planningInputs.meal_duration_minutes)
          const blocked = Array.isArray(worker.blockedStartMinutes) ? worker.blockedStartMinutes as number[] : []
          if (end <= start || end - start !== duration || start < Number(worker.shiftStartMinute)
            || end > Number(worker.shiftEndMinute) || blocked.includes(start)) {
            fail(409, "INVALID_MEAL_SCHEDULE", "El horario modificado no respeta el turno, duración o descanso configurado.")
          }
          rows.push({ employeeId, start, end, original: {
            employee_id: employeeId, starts_at: startDate.toISOString(), scheduled_end_at: endDate.toISOString(), duration_minutes: duration,
          } })
        }
        const ordered = [...rows].sort((a, b) => a.start - b.start)
        for (let index = 1; index < ordered.length; index++) {
          if (ordered[index].start < ordered[index - 1].end) fail(409, "INVALID_MEAL_SCHEDULE", "La política actual exige comidas escalonadas sin traslape.")
        }
        approvedSchedule = rows.map((row) => row.original)
      }
      const result = assertNoError(await admin.rpc("restaurant_decide_meal_plan", {
        p_branch_id: branchId, p_plan_id: planId,
        p_actor_id: user.id, p_decision: decision,
        p_schedule: approvedSchedule,
        p_note: typeof payload.note === "string" ? payload.note.slice(0, 1000) : null,
      }))
      return jsonResponse(result, 200, requestId)
    }

    if (action === "decide_recommendation") {
      const result = assertNoError(await admin.rpc("restaurant_decide_recommendation", {
        p_branch_id: branchId, p_recommendation_id: requiredUuid(payload.recommendation_id, "recommendation_id"),
        p_actor_id: user.id, p_decision: requiredString(payload.decision, "decision", 16),
        p_note: typeof payload.note === "string" ? payload.note.slice(0, 1000) : null,
      }))
      return jsonResponse(result, 200, requestId)
    }

    if (action === "analyze_operational_coverage") {
      const shiftDate = requiredString(payload.shift_date, "shift_date", 10)
      if (!isCalendarDate(shiftDate)) fail(400, "INVALID_SHIFT_DATE", "shift_date must be YYYY-MM-DD.")
      const branch = assertNoError(await admin.from("restaurant_branches")
        .select("timezone, minimum_area_coverage").eq("id", branchId).single())
      const policy = branch.minimum_area_coverage as Record<string, unknown>
      const minimums = Object.entries(policy).filter(([, value]) => Number.isInteger(value) && Number(value) >= 0)
      if (minimums.length === 0) fail(409, "COVERAGE_POLICY_NOT_CONFIGURED", "Configure minimum coverage by area before analyzing the schedule.")
      if (minimums.length !== Object.keys(policy).length || minimums.some(([areaId, value]) => Number(value) > 100 || !UUID.test(areaId))) {
        fail(409, "INVALID_AREA_COVERAGE", "La política de cobertura contiene áreas o cantidades inválidas; corrígela antes de analizar.")
      }
      const [shiftsResult, absencesResult, positionsResult, memberPositionsResult, statesResult, mealsResult, areasResult] = await Promise.all([
        admin.from("restaurant_shifts").select("id, employee_id, start_time, end_time").eq("branch_id", branchId).eq("shift_date", shiftDate).eq("status", "published"),
        admin.from("restaurant_absences").select("employee_id").eq("branch_id", branchId).eq("status", "approved").lte("start_date", shiftDate).gte("end_date", shiftDate),
        admin.from("restaurant_positions").select("id, area_id").eq("branch_id", branchId).eq("is_active", true),
        admin.from("restaurant_member_positions").select("user_id, position_id").eq("branch_id", branchId),
        admin.from("restaurant_member_operational_states").select("employee_id, state").eq("branch_id", branchId),
        admin.from("restaurant_meal_sessions").select("employee_id").eq("branch_id", branchId).is("return_confirmed_at", null),
        admin.from("restaurant_areas").select("id, name").eq("branch_id", branchId).eq("is_active", true),
      ])
      const shifts = assertNoError(shiftsResult) ?? []
      if (!shifts.length) fail(409, "PUBLISHED_SHIFTS_REQUIRED", "No hay turnos publicados para la fecha seleccionada.")
      const absent = new Set((assertNoError(absencesResult) ?? []).map((row: { employee_id: string }) => row.employee_id))
      const positionArea = new Map((assertNoError(positionsResult) ?? []).filter((row: { area_id: string | null }) => row.area_id).map((row: { id: string; area_id: string }) => [row.id, row.area_id]))
      const areas = new Map((assertNoError(areasResult) ?? []).map((row: { id: string; name: string }) => [row.id, row.name]))
      if (minimums.some(([areaId]) => !areas.has(areaId))) {
        fail(409, "AREA_COVERAGE_AREA_INACTIVE", "La política de cobertura refiere un área inexistente o inactiva; actualiza la configuración de la sucursal.")
      }
      const memberAreaSets = new Map<string, Set<string>>()
      for (const row of assertNoError(memberPositionsResult) ?? []) {
        const areaId = positionArea.get(row.position_id)
        if (!areaId) continue
        const set = memberAreaSets.get(row.user_id) ?? new Set<string>()
        set.add(areaId); memberAreaSets.set(row.user_id, set)
      }
      const unavailable = new Set<string>(shiftDate === dateInZone(branch.timezone) ? [
        ...(assertNoError(statesResult) ?? []).filter((row: { state: string }) => ["meal", "rest", "off_shift"].includes(row.state)).map((row: { employee_id: string }) => row.employee_id),
        ...(assertNoError(mealsResult) ?? []).map((row: { employee_id: string }) => row.employee_id),
      ] : [])
      const qualified = new Map<string, Array<{ employee_id: string; start: number; end: number }>>()
      const ambiguousEmployees: string[] = []
      for (const shift of shifts) {
        if (absent.has(shift.employee_id) || unavailable.has(shift.employee_id)) continue
        const mappedAreas = memberAreaSets.get(shift.employee_id) ?? new Set<string>()
        if (mappedAreas.size !== 1) { if (mappedAreas.size > 1) ambiguousEmployees.push(shift.employee_id); continue }
        const areaId = [...mappedAreas][0]
        const start = Number(String(shift.start_time).slice(0, 2)) * 60 + Number(String(shift.start_time).slice(3, 5))
        let end = Number(String(shift.end_time).slice(0, 2)) * 60 + Number(String(shift.end_time).slice(3, 5))
        if (end <= start) end += 1440
        const bucket = qualified.get(areaId) ?? []
        bucket.push({ employee_id: shift.employee_id, start, end }); qualified.set(areaId, bucket)
      }
      const recommendations: Record<string, unknown>[] = []
      for (const [areaId, minimumValue] of minimums) {
        if (!areas.has(areaId)) continue
        const minimum = Number(minimumValue)
        const staff = qualified.get(areaId) ?? []
        const shiftMinutes = shifts.map((shift: { start_time: string; end_time: string }) => {
          const start = Number(String(shift.start_time).slice(0, 2)) * 60 + Number(String(shift.start_time).slice(3, 5))
          let end = Number(String(shift.end_time).slice(0, 2)) * 60 + Number(String(shift.end_time).slice(3, 5))
          if (end <= start) end += 1440
          return { start, end }
        })
        const analysisStart = Math.max(0, Math.floor(Math.min(...shiftMinutes.map((row) => row.start)) / 15) * 15)
        const analysisEnd = Math.ceil(Math.max(...shiftMinutes.map((row) => row.end)) / 15) * 15
        for (let minute = analysisStart; minute < analysisEnd; minute += 15) {
          const count = staff.filter((person) => person.start <= minute && person.end > minute).length
          if (count >= minimum) continue
          const slotDate = minute >= 1440 ? addDays(shiftDate, Math.floor(minute / 1440)) : shiftDate
          const slotMinute = minute % 1440
          const sourcePeriodStart = localClockToUtc(slotDate, `${String(Math.floor(slotMinute / 60)).padStart(2, "0")}:${String(slotMinute % 60).padStart(2, "0")}`, branch.timezone)
          const endMinute = minute + 15
          const endDate = endMinute >= 1440 ? addDays(shiftDate, Math.floor(endMinute / 1440)) : shiftDate
          const endClockMinute = endMinute % 1440
          const sourcePeriodEnd = localClockToUtc(endDate, `${String(Math.floor(endClockMinute / 60)).padStart(2, "0")}:${String(endClockMinute % 60).padStart(2, "0")}`, branch.timezone)
          const areaName = areas.get(areaId) ?? areaId
          const sourceData = { analysis: "published_shift_qualified_coverage", shift_date: shiftDate, area_id: areaId, observed_qualified_staff: count, configured_minimum: minimum, ambiguous_multi_area_employees: [...new Set(ambiguousEmployees)], coverage_semantics: "scheduled_qualification_not_physical_location", operational_state_snapshot_applied: shiftDate === dateInZone(branch.timezone) }
          const explanation = `El horario publicado muestra ${count} persona(s) con puesto explícitamente vinculado a ${areaName}; el mínimo configurado es ${minimum}. Esto mide personal programado y calificado, no ubicación física en tiempo real.`
          const savedId = assertNoError(await admin.rpc("restaurant_record_coverage_recommendation", {
            p_branch_id: branchId, p_actor_id: user.id, p_period_start: sourcePeriodStart, p_period_end: sourcePeriodEnd,
            p_source_data: sourceData, p_explanation: explanation,
            p_suggested_action: "Revisa el horario, los puestos vinculados y la cobertura; cualquier ajuste requiere decisión del gerente.",
          }))
          if (savedId) recommendations.push({ id: savedId, area_id: areaId, start: sourcePeriodStart, end: sourcePeriodEnd, observed: count, minimum })
        }
      }
      return jsonResponse({ shift_date: shiftDate, analyzed_shifts: shifts.length, generated_recommendations: recommendations.length, recommendations, skipped_ambiguous_employee_count: [...new Set(ambiguousEmployees)].length }, 200, requestId)
    }

    if (action === "analyze_operational_history") {
      const startDate = requiredString(payload.start_date, "start_date", 10)
      const endDate = requiredString(payload.end_date, "end_date", 10)
      const branch = assertNoError(await admin.from("restaurant_branches").select("timezone").eq("id", branchId).single())
      if (!isCalendarDate(startDate) || !isCalendarDate(endDate) || endDate < startDate
        || endDate > dateInZone(branch.timezone)
        || Date.parse(`${endDate}T00:00:00Z`) - Date.parse(`${startDate}T00:00:00Z`) > 90 * 86400000) {
        fail(400, "INVALID_ANALYSIS_PERIOD", "Selecciona un periodo válido de hasta 90 días.")
      }
      const endExclusive = addDays(endDate, 1)
      const periodStart = localClockToUtc(startDate, "00:00", branch.timezone)
      const periodEnd = localClockToUtc(endExclusive, "00:00", branch.timezone)
      const [tasksResult, inspectionsResult] = await Promise.all([
        admin.from("restaurant_tasks")
          .select("id, scheduled_for, status, assigned_to, estimated_minutes, completed_at", { count: "exact" })
          .eq("branch_id", branchId).gte("scheduled_for", startDate).lt("scheduled_for", endExclusive)
          .limit(5000),
        admin.from("restaurant_inspections")
          .select("id, inspected_at, needs_attention_count", { count: "exact" })
          .eq("branch_id", branchId).gte("inspected_at", periodStart).lt("inspected_at", periodEnd)
          .limit(5000),
      ])
      const tasks = assertNoError(tasksResult) ?? []
      const inspections = assertNoError(inspectionsResult) ?? []
      if ((tasksResult.count ?? tasks.length) > tasks.length || (inspectionsResult.count ?? inspections.length) > inspections.length) {
        fail(413, "ANALYSIS_PERIOD_TOO_LARGE", "El periodo contiene más registros de los que el análisis procesa de forma completa; reduce el rango.")
      }
      const assignmentEventsResult = await admin.from("restaurant_task_receipt_events")
        .select("receipt_id, occurred_at, details", { count: "exact" })
        .eq("branch_id", branchId).eq("event_type", "assigned")
        .gte("occurred_at", periodStart).lt("occurred_at", periodEnd).limit(5000)
      const assignmentEvents = assertNoError(assignmentEventsResult) ?? []
      if ((assignmentEventsResult.count ?? assignmentEvents.length) > assignmentEvents.length) {
        fail(413, "ANALYSIS_PERIOD_TOO_LARGE", "El periodo contiene demasiados eventos de asignación; reduce el rango.")
      }
      const receiptIds = [...new Set(assignmentEvents.map((event: Record<string, unknown>) => String(event.receipt_id)))]
      const receipts = receiptIds.length ? assertNoError(await admin.from("restaurant_task_receipts")
        .select("id, task_id").eq("branch_id", branchId).in("id", receiptIds)) ?? [] : []
      const receiptTaskIds = [...new Set(receipts.map((receipt: Record<string, unknown>) => String(receipt.task_id)))]
      const assignmentTasks = receiptTaskIds.length ? assertNoError(await admin.from("restaurant_tasks")
        .select("id, estimated_minutes").eq("branch_id", branchId).in("id", receiptTaskIds)) ?? [] : []
      const taskById = new Map(assignmentTasks.map((task: Record<string, unknown>) => [String(task.id), Number(task.estimated_minutes) || 0]))
      const taskIdByReceipt = new Map(receipts.map((receipt: Record<string, unknown>) => [String(receipt.id), String(receipt.task_id)]))
      const assignedWorkload = new Map<string, { assignmentEvents: number; estimatedMinutes: number }>()
      for (const event of assignmentEvents as Array<Record<string, unknown>>) {
        const details = event.details as Record<string, unknown> | null
        const employeeId = typeof details?.employee_id === "string" ? details.employee_id : null
        const taskId = taskIdByReceipt.get(String(event.receipt_id))
        if (!employeeId || !taskId) continue
        const current = assignedWorkload.get(employeeId) ?? { assignmentEvents: 0, estimatedMinutes: 0 }
        current.assignmentEvents += 1
        current.estimatedMinutes += taskById.get(taskId) ?? 0
        assignedWorkload.set(employeeId, current)
      }
      const workloadRows = [...assignedWorkload.values()]
      const estimatedMinutes = workloadRows.map((row) => row.estimatedMinutes)
      const assignmentEventCounts = workloadRows.map((row) => row.assignmentEvents)
      const overdueTasks = tasks.filter((task: Record<string, unknown>) => {
        if (task.status === "completed" && typeof task.completed_at === "string") {
          return dateInZone(branch.timezone, new Date(task.completed_at)) > String(task.scheduled_for)
        }
        return task.status !== "completed" && String(task.scheduled_for) < dateInZone(branch.timezone)
      }).length
      const inspectionsWithAttention = inspections.filter((row: Record<string, unknown>) => Number(row.needs_attention_count) > 0).length
      const attentionResults = inspections.reduce((sum: number, row: Record<string, unknown>) => sum + (Number(row.needs_attention_count) || 0), 0)
      const generated: Array<{ category: string; id: string | null }> = []
      const stableSource = async (category: string, details: Record<string, unknown>) => ({
        ...details, analysis: `actual_operational_history_${category}`,
        period_start_local: startDate, period_end_local: endDate,
        fingerprint: await stableFingerprint({ category, startDate, endDate }),
      })
      const persist = async (category: string, source: Record<string, unknown>, explanation: string, suggestedAction: string) => {
        const id = assertNoError(await admin.rpc("restaurant_record_operational_recommendation", {
          p_branch_id: branchId, p_actor_id: user.id, p_category: category,
          p_period_start: periodStart, p_period_end: periodEnd, p_source_data: source,
          p_explanation: explanation, p_suggested_action: suggestedAction,
        }))
        generated.push({ category, id: typeof id === "string" ? id : null })
      }
      if (workloadRows.length >= 2 && Math.max(...estimatedMinutes) > Math.min(...estimatedMinutes)) {
        const source = await stableSource("workload", {
          assigned_staff_count: workloadRows.length, assignment_event_count: assignmentEventCounts.reduce((sum, count) => sum + count, 0),
          estimated_minutes_min: Math.min(...estimatedMinutes), estimated_minutes_max: Math.max(...estimatedMinutes),
          assignment_events_min: Math.min(...assignmentEventCounts), assignment_events_max: Math.max(...assignmentEventCounts),
          measure: "append_only_assignment_events_weighted_by_task_estimate_not_actual_labor_time",
          excludes: ["divided task parts without assignment receipt events"],
        })
        await persist("workload", source,
          "Los eventos append-only de asignación del periodo, ponderados por minutos estimados de las tareas, muestran variación agregada. Se excluyen partes de tareas divididas sin historial equivalente. Es una señal de revisión, no una medición de productividad ni una evaluación individual.",
          "Revisa dificultad, disponibilidad, puesto y distribución antes de ajustar futuras asignaciones.")
      }
      if (overdueTasks > 0) {
        const source = await stableSource("delay", {
          scheduled_task_count: tasks.length, observed_past_day_tasks: overdueTasks,
          definition: "completed_after_scheduled_local_date_or_still_open_after_that_date",
        })
        await persist("delay", source,
          `${overdueTasks} tarea(s) del periodo se completaron después de su fecha local programada o siguen abiertas después de esa fecha. El esquema no define una hora límite intradía; este análisis no infiere retrasos por hora ni la causa.`,
          "Revisa programación, restricciones y pendientes de cambio de turno; confirma los motivos con el equipo.")
      }
      if (attentionResults > 0) {
        const source = await stableSource("inspection", {
          inspection_count: inspections.length, inspections_with_attention: inspectionsWithAttention,
          attention_item_count: attentionResults,
        })
        await persist("inspection", source,
          `${attentionResults} resultado(s) de inspección requirieron atención en ${inspectionsWithAttention} inspección(es) del periodo.`,
          "Revisa las áreas e ítems con atención registrada y define si hace falta una tarea correctiva o ajustar la frecuencia.")
      }
      return jsonResponse({ period: { start_date: startDate, end_date: endDate, timezone: branch.timezone },
        source: "persisted task assignment events, scheduled tasks, and inspections", task_count: tasks.length,
        inspection_count: inspections.length, assigned_staff_count: workloadRows.length,
        overdue_by_scheduled_day_count: overdueTasks, inspection_attention_count: attentionResults,
        recommendations: generated,
        limitations: ["Estimated task minutes are not measured labor time.", "Divided task parts do not yet have equivalent append-only assignment history.", "Task schema has no intraday due time; only scheduled-day rollover is counted.", "No demand or POS data is used.", "Recommendations require a manager decision and do not trigger assignments automatically."],
      }, 200, requestId)
    }

    if (action === "request_shift_cover") {
      const shiftId = requiredUuid(payload.shift_id, "shift_id")
      const clientEventId = requiredUuid(payload.client_event_id, "client_event_id")
      const note = typeof payload.note === "string" ? payload.note.trim() : ""
      if (note.length > 1000) fail(400, "INVALID_SHIFT_COVER_NOTE", "The request note cannot exceed 1,000 characters.")
      const coverRequestId = assertNoError(await admin.rpc("create_restaurant_shift_cover_request", {
        p_branch_id: branchId, p_actor_id: user.id, p_shift_id: shiftId,
        p_client_event_id: clientEventId, p_note: note || null,
      }))
      return jsonResponse({ request_id: coverRequestId }, 201, requestId)
    }

    if (action === "cancel_shift_cover_request") {
      const requestIdentifier = requiredUuid(payload.request_id, "request_id")
      const requestQuery = () => admin.from("restaurant_shift_cover_requests")
        .select("id, status")
        .eq("branch_id", branchId)
        .eq("requester_id", user.id)
      let coverRequest = assertNoError(await requestQuery().eq("id", requestIdentifier).maybeSingle())
      if (!coverRequest) {
        coverRequest = assertNoError(await requestQuery().eq("client_event_id", requestIdentifier).maybeSingle())
      }
      if (!coverRequest) fail(409, "SHIFT_COVER_REQUEST_NOT_PENDING", "This request is no longer pending or does not belong to you.")
      const requestRow = coverRequest
      const notifyBranchManagers = async () => {
        const [managerResult, notificationResult] = await Promise.all([
          admin.from("restaurant_memberships").select("user_id")
            .eq("branch_id", branchId).eq("is_active", true)
            .in("access_role", ["admin", "supervisor"]).neq("user_id", user.id),
          admin.from("restaurant_notifications").select("recipient_id")
            .eq("branch_id", branchId).eq("notification_type", "shift_cover_reviewed")
            .eq("entity_type", "shift_cover_request").eq("entity_id", requestRow.id),
        ])
        const managers = assertNoError(managerResult) ?? []
        const existing = assertNoError(notificationResult) ?? []
        const alreadyNotified = new Set(existing.map((item: { recipient_id: string }) => item.recipient_id))
        const notifications = managers
          .filter((manager: { user_id: string }) => !alreadyNotified.has(manager.user_id))
          .map((manager: { user_id: string }) => ({
            branch_id: branchId,
            recipient_id: manager.user_id,
            notification_type: "shift_cover_reviewed",
            title: "Solicitud de cobertura cancelada",
            body: "Un integrante canceló una solicitud pendiente.",
            entity_type: "shift_cover_request",
            entity_id: requestRow.id,
            data: { request_id: requestRow.id, status: "cancelled" },
          }))
        if (notifications.length > 0) {
          assertNoError(await admin.from("restaurant_notifications").insert(notifications))
        }
      }
      if (requestRow.status === "cancelled") {
        await notifyBranchManagers()
        return jsonResponse({ cancelled: true, request_id: requestRow.id }, 200, requestId)
      }
      if (requestRow.status !== "pending") {
        fail(409, "SHIFT_COVER_REQUEST_NOT_PENDING", "This request is no longer pending or does not belong to you.")
      }
      const saved = assertNoError(await admin.from("restaurant_shift_cover_requests")
        .update({ status: "cancelled" }).eq("branch_id", branchId).eq("id", requestRow.id)
        .eq("requester_id", user.id).eq("status", "pending").select("id").maybeSingle())
      if (!saved) {
        const latest = assertNoError(await requestQuery().eq("id", requestRow.id).maybeSingle())
        if (latest?.status !== "cancelled") {
          fail(409, "SHIFT_COVER_REQUEST_NOT_PENDING", "This request is no longer pending or does not belong to you.")
        }
      }
      await notifyBranchManagers()
      return jsonResponse({ cancelled: true, request_id: requestRow.id }, 200, requestId)
    }

    if (action === "review_shift_cover_request") {
      const coverRequestId = requiredUuid(payload.request_id, "request_id")
      const decision = requiredString(payload.decision, "decision", 16)
      if (!["approved", "denied"].includes(decision)) fail(400, "INVALID_SHIFT_COVER_DECISION", "Choose approve or deny.")
      const replacementEmployeeId = decision === "approved"
        ? requiredUuid(payload.replacement_employee_id, "replacement_employee_id") : null
      const decisionNote = typeof payload.decision_note === "string" ? payload.decision_note.trim() : ""
      if (decisionNote.length > 500) fail(400, "INVALID_SHIFT_COVER_NOTE", "The decision note cannot exceed 500 characters.")
      const result = assertNoError(await admin.rpc("review_restaurant_shift_cover_request", {
        p_branch_id: branchId, p_actor_id: user.id, p_request_id: coverRequestId,
        p_decision: decision, p_replacement_employee_id: replacementEmployeeId,
        p_decision_note: decisionNote || null,
      }))
      return jsonResponse(result, 200, requestId)
    }

    if (action === "assign_task_part") {
      const taskId = requiredUuid(payload.task_id, "task_id")
      const partId = requiredUuid(payload.part_id, "part_id")
      const assignedTo = payload.assigned_to == null || payload.assigned_to === ""
        ? null : requiredUuid(payload.assigned_to, "assigned_to")
      const [task, part] = await Promise.all([
        admin.from("restaurant_tasks")
          .select("id, activity_template_id, scheduled_for, status")
          .eq("id", taskId).eq("branch_id", branchId).maybeSingle(),
        admin.from("restaurant_task_parts")
          .select("id, task_id, assigned_to, status, estimated_minutes")
          .eq("id", partId).eq("task_id", taskId).eq("branch_id", branchId).maybeSingle(),
      ])
      const taskRow = assertNoError(task)
      const partRow = assertNoError(part)
      if (!taskRow || !partRow) fail(404, "TASK_PART_NOT_FOUND", "This activity part does not belong to the selected branch.")
      if (!(taskRow.status === "pending" || taskRow.status === "in_progress") || partRow.status !== "pending") {
        fail(409, "TASK_PART_NOT_ASSIGNABLE", "Only pending parts of open activities can be reassigned.")
      }
      if (partRow.assigned_to === assignedTo) return jsonResponse({ part_id: partId, assigned_to: assignedTo }, 200, requestId)
      if (!taskRow.activity_template_id) fail(409, "TASK_PART_TEMPLATE_REQUIRED", "Configure the activity before assigning its parts.")
      const template = assertNoError(await admin.from("restaurant_activity_templates")
        .select("is_divisible, interruptible").eq("id", taskRow.activity_template_id).eq("branch_id", branchId).maybeSingle())
      if (!template?.is_divisible) fail(409, "TASK_NOT_DIVISIBLE", "Only parts of a divisible activity can be assigned individually.")

      const branchTimezone = assertNoError(await admin.from("restaurant_branches")
        .select("timezone").eq("id", branchId).single()).timezone
      const localDate = dateInZone(branchTimezone)
      if (taskRow.scheduled_for < localDate) fail(409, "TASK_DATE_PASSED", "Past activity parts cannot be reassigned.")

      if (assignedTo) {
        await ensureEmployeeAvailableForNewAssignment(admin, branchId, assignedTo, taskRow.scheduled_for, localDate)
        const requiredPositionIds = (assertNoError(await admin.from("restaurant_activity_positions")
          .select("position_id").eq("branch_id", branchId).eq("activity_template_id", taskRow.activity_template_id)) ?? [])
          .map((item: Record<string, string>) => item.position_id)
        if (!requiredPositionIds.length) fail(409, "TASK_HAS_NO_ELIGIBLE_POSITION", "Configure an eligible position before assigning this part.")

        const member = assertNoError(await admin.from("restaurant_memberships")
          .select("user_id, customer_service_active").eq("branch_id", branchId).eq("user_id", assignedTo).eq("is_active", true).maybeSingle())
        if (!member) fail(409, "EMPLOYEE_NOT_ACTIVE", "Choose an active employee in this branch.")
        const employeeAccount = assertNoError(await admin.from("users").select("is_active").eq("id", assignedTo).maybeSingle())
        if (!employeeAccount?.is_active) fail(409, "EMPLOYEE_NOT_ACTIVE", "Choose an active employee account.")
        const positions = assertNoError(await admin.from("restaurant_member_positions")
          .select("position_id").eq("branch_id", branchId).eq("user_id", assignedTo)) ?? []
        if (!positions.some((item: Record<string, string>) => requiredPositionIds.includes(item.position_id))) {
          fail(409, "EMPLOYEE_NOT_ELIGIBLE", "This employee does not have a position required for the activity.")
        }
        if (template.interruptible && member.customer_service_active && taskRow.scheduled_for === localDate) {
          fail(409, "EMPLOYEE_SERVING_CUSTOMERS", "Choose someone who is not currently serving customers.")
        }

        const absence = assertNoError(await admin.from("restaurant_absences").select("id")
          .eq("branch_id", branchId).eq("employee_id", assignedTo).eq("status", "approved")
          .lte("start_date", taskRow.scheduled_for).gte("end_date", taskRow.scheduled_for).limit(1)) ?? []
        if (absence.length) fail(409, "EMPLOYEE_ABSENT", "This employee has an approved absence on the activity date.")

        const shifts = assertNoError(await admin.from("restaurant_shifts")
          .select("id, shift_date, start_time, end_time").eq("branch_id", branchId).eq("employee_id", assignedTo)
          .in("shift_date", [taskRow.scheduled_for, addDays(taskRow.scheduled_for, -1)]).eq("status", "published")) ?? []
        const relevantShifts = shifts.filter((shift: Record<string, string>) =>
          shift.shift_date === taskRow.scheduled_for || minutesOfDay(shift.end_time) <= minutesOfDay(shift.start_time))
        if (!relevantShifts.length) fail(409, "EMPLOYEE_NOT_SCHEDULED", "This employee has no published shift on the activity date.")
        const shiftIds = relevantShifts.map((shift: { id: string }) => shift.id)
        const breaks = assertNoError(await admin.from("restaurant_shift_breaks")
          .select("shift_id, start_time, end_time").eq("branch_id", branchId).in("shift_id", shiftIds)) ?? []
        const isToday = taskRow.scheduled_for === localDate
        let currentMinute = 0
        if (isToday) {
          const localClock = new Intl.DateTimeFormat("en-GB", {
            timeZone: branchTimezone, hour: "2-digit", minute: "2-digit", hourCycle: "h23",
          }).format(new Date())
          currentMinute = minutesOfDay(localClock)
        }
        const shiftWindows = new Map<string, { availableStart: number; end: number }>()
        let shiftMinutes = 0
        for (const shift of relevantShifts as Record<string, string>[]) {
          const start = minutesOfDay(shift.start_time)
          const end = minutesOfDay(shift.end_time)
          const previousDay = shift.shift_date !== taskRow.scheduled_for
          const dayOffset = previousDay ? -1440 : 0
          const startAbsolute = start + dayOffset
          const endAbsolute = (end <= start ? end + 1440 : end) + dayOffset
          const availableStart = Math.max(startAbsolute, isToday ? currentMinute : 0)
          shiftWindows.set(shift.id, { availableStart, end: endAbsolute })
          shiftMinutes += Math.max(0, endAbsolute - availableStart)
        }
        let breakMinutes = 0
        for (const item of breaks as Record<string, string>[]) {
          const window = shiftWindows.get(item.shift_id)
          const shift = (relevantShifts as Record<string, string>[]).find((candidate) => candidate.id === item.shift_id)
          if (!window || !shift) continue
          const dayOffset = shift.shift_date !== taskRow.scheduled_for ? -1440 : 0
          const shiftStart = minutesOfDay(shift.start_time)
          const start = minutesOfDay(item.start_time)
          const end = minutesOfDay(item.end_time)
          const breakOffset = start < shiftStart ? 1440 : 0
          const startAbsolute = start + breakOffset + dayOffset
          const endAbsolute = (end <= start ? end + 1440 : end) + breakOffset + dayOffset
          breakMinutes += Math.max(0, Math.min(window.end, endAbsolute) - Math.max(window.availableStart, startAbsolute))
        }

        const dailyTasks = assertNoError(await admin.from("restaurant_tasks")
          .select("id, assigned_to, estimated_minutes").eq("branch_id", branchId)
          .eq("scheduled_for", taskRow.scheduled_for).neq("status", "completed")) ?? []
        const dailyTaskIds = dailyTasks.map((item: { id: string }) => item.id)
        const currentParts = dailyTaskIds.length
          ? assertNoError(await admin.from("restaurant_task_parts")
            .select("id, estimated_minutes").eq("branch_id", branchId).eq("assigned_to", assignedTo)
            .neq("status", "completed").in("task_id", dailyTaskIds)) ?? []
          : []
        const occupiedMinutes = dailyTasks
          .filter((item: Record<string, unknown>) => item.id !== taskId && item.assigned_to === assignedTo)
          .reduce((total: number, item: Record<string, unknown>) => total + Number(item.estimated_minutes ?? 0), 0)
          + currentParts
            .filter((item: Record<string, unknown>) => item.id !== partId)
            .reduce((total: number, item: Record<string, unknown>) => total + Number(item.estimated_minutes ?? 0), 0)
        if (shiftMinutes - breakMinutes - occupiedMinutes < Number(partRow.estimated_minutes)) {
          fail(409, "EMPLOYEE_CAPACITY_EXCEEDED", "This activity part does not fit in the employee's remaining published shift capacity.")
        }
      }

      const update = partRow.assigned_to == null
        ? await admin.from("restaurant_task_parts").update({ assigned_to: assignedTo })
          .eq("id", partId).eq("branch_id", branchId).eq("task_id", taskId).eq("status", "pending")
          .is("assigned_to", null).select("id").maybeSingle()
        : await admin.from("restaurant_task_parts").update({ assigned_to: assignedTo })
          .eq("id", partId).eq("branch_id", branchId).eq("task_id", taskId).eq("status", "pending")
          .eq("assigned_to", partRow.assigned_to).select("id").maybeSingle()
      if (!assertNoError(update)) fail(409, "TASK_PART_ASSIGNMENT_CHANGED", "This activity part changed before assignment. Refresh the calendar and try again.")
      return jsonResponse({ task_id: taskId, part_id: partId, assigned_to: assignedTo }, 200, requestId)
    }

    if (action === "mark_notification_read") {
      const notificationId = requiredUuid(payload.notification_id, "notification_id")
      const updated = assertNoError(await admin.from("restaurant_notifications")
        .update({ read_at: new Date().toISOString() })
        .eq("id", notificationId).eq("branch_id", branchId).eq("recipient_id", user.id)
        .is("read_at", null).select("id")) ?? []
      return jsonResponse({ updated_count: updated.length }, 200, requestId)
    }

    if (action === "mark_all_notifications_read") {
      const updated = assertNoError(await admin.from("restaurant_notifications")
        .update({ read_at: new Date().toISOString() })
        .eq("branch_id", branchId).eq("recipient_id", user.id)
        .is("read_at", null).select("id")) ?? []
      return jsonResponse({ updated_count: updated.length }, 200, requestId)
    }

    if (action === "deliver_handoff") {
      const clientEventId = requiredUuid(payload.client_event_id, "client_event_id")
      const recipientId = payload.recipient_id == null || payload.recipient_id === ""
        ? null : requiredUuid(payload.recipient_id, "recipient_id")
      if (recipientId === user.id) fail(400, "INVALID_RECIPIENT", "Choose another active branch member to receive the handoff.")
      if (recipientId) await memberForBranch(admin, branchId, recipientId)
      const handoffNote = typeof payload.handoff_note === "string" ? payload.handoff_note.trim() : ""
      if (handoffNote.length > 1000) fail(400, "INVALID_PAYLOAD", "handoff_note cannot exceed 1,000 characters.")
      const existing = assertNoError(await admin.from("restaurant_shift_handoffs")
        .select("id, created_by, recipient_id, handoff_note")
        .eq("branch_id", branchId).eq("client_event_id", clientEventId).maybeSingle())
      if (existing) {
        if (existing.created_by !== user.id || existing.recipient_id !== recipientId || existing.handoff_note !== handoffNote) {
          fail(409, "IDEMPOTENCY_KEY_REUSED", "This handoff event id was already used for different content.")
        }
        return jsonResponse({ handoff_id: existing.id, duplicate: true }, 200, requestId)
      }

      const dashboard = await getDashboard(admin, branchId, user.id)
      const openTasks = (dashboard.tasks as Record<string, unknown>[])
        .filter((task) => task.status !== "completed")
      const openIncidents = dashboard.incidents as Record<string, unknown>[]
      const snapshot = {
        captured_at: new Date().toISOString(),
        task_items: openTasks.map((task) => ({
          id: task.id, name: task.name, status: task.status, area_name: task.area_name,
          latest_pause_note: task.latest_pause_note ?? null,
          parts: Array.isArray(task.parts) ? task.parts.map((part: Record<string, unknown>) => ({
            id: part.id, zone_name: part.zone_name, status: part.status,
            latest_pause_note: part.latest_pause_note ?? null,
          })) : [],
        })),
        incident_items: openIncidents.map((incident) => ({
          id: incident.id, description: incident.description, status: incident.status,
          urgency: incident.urgency, area_name: incident.area_name,
        })),
      }
      const saved = await admin.from("restaurant_shift_handoffs").upsert({
        branch_id: branchId, shift_date: dashboard.local_date, created_by: user.id,
        recipient_id: recipientId, client_event_id: clientEventId,
        handoff_note: handoffNote, snapshot,
      }, { onConflict: "branch_id,client_event_id", ignoreDuplicates: true }).select("id").maybeSingle()
      if (saved.error) throw saved.error
      if (saved.data) return jsonResponse({ handoff_id: saved.data.id, duplicate: false }, 201, requestId)
      const raced = assertNoError(await admin.from("restaurant_shift_handoffs")
        .select("id, created_by, recipient_id, handoff_note")
        .eq("branch_id", branchId).eq("client_event_id", clientEventId).single())
      if (raced.created_by !== user.id || raced.recipient_id !== recipientId || raced.handoff_note !== handoffNote) {
        fail(409, "IDEMPOTENCY_KEY_REUSED", "This handoff event id was already used for different content.")
      }
      return jsonResponse({ handoff_id: raced.id, duplicate: true }, 200, requestId)
    }

    if (action === "acknowledge_handoff") {
      const handoffId = requiredUuid(payload.handoff_id, "handoff_id")
      const handoff = assertNoError(await admin.from("restaurant_shift_handoffs")
        .select("id, created_by, recipient_id, acknowledged_by, acknowledged_at")
        .eq("branch_id", branchId).eq("id", handoffId).maybeSingle())
      if (!handoff) fail(404, "HANDOFF_NOT_FOUND", "This handoff is no longer available.")
      if (handoff.recipient_id) {
        if (handoff.recipient_id !== user.id) fail(403, "HANDOFF_RECIPIENT_REQUIRED", "Only the assigned recipient can acknowledge this handoff.")
      } else if (handoff.created_by === user.id) {
        fail(403, "HANDOFF_RECEIVER_REQUIRED", "Another active branch member must acknowledge this handoff.")
      }
      if (handoff.acknowledged_at) {
        if (handoff.acknowledged_by === user.id) return jsonResponse({ acknowledged: true, duplicate: true }, 200, requestId)
        fail(409, "HANDOFF_ALREADY_ACKNOWLEDGED", "Another team member already received this handoff.")
      }
      const updated = assertNoError(await admin.from("restaurant_shift_handoffs")
        .update({ acknowledged_by: user.id, acknowledged_at: new Date().toISOString() })
        .eq("branch_id", branchId).eq("id", handoffId).is("acknowledged_at", null)
        .select("id").maybeSingle())
      if (updated) return jsonResponse({ acknowledged: true, duplicate: false }, 200, requestId)
      const latest = assertNoError(await admin.from("restaurant_shift_handoffs")
        .select("acknowledged_by").eq("branch_id", branchId).eq("id", handoffId).single())
      if (latest.acknowledged_by === user.id) return jsonResponse({ acknowledged: true, duplicate: true }, 200, requestId)
      fail(409, "HANDOFF_ALREADY_ACKNOWLEDGED", "Another team member already received this handoff.")
    }

    if (action === "save_inspection_template") {
      const name = requiredString(payload.name, "name", 120)
      const templateId = payload.id ? requiredUuid(payload.id, "id") : null
      const areaId = payload.area_id ? requiredUuid(payload.area_id, "area_id") : null
      const interval = payload.inspection_interval_minutes == null || payload.inspection_interval_minutes === ""
        ? null : Number(payload.inspection_interval_minutes)
      if (interval !== null && (!Number.isInteger(interval) || interval < 1 || interval > 10080)) {
        fail(400, "INVALID_INSPECTION_INTERVAL", "Inspection interval must be between 1 and 10,080 minutes.")
      }
      if (!Array.isArray(payload.items) || payload.items.length === 0 || payload.items.length > 100) {
        fail(400, "INVALID_INSPECTION_ITEMS", "Add between 1 and 100 checklist items configured by the branch.")
      }
      const items = payload.items.map((item: Record<string, unknown>) => ({
        label: requiredString(item?.label, "item.label", 180),
      }))
      const savedId = assertNoError(await admin.rpc("save_restaurant_inspection_template", {
        p_branch_id: branchId, p_actor_id: user.id, p_template_id: templateId,
        p_area_id: areaId, p_name: name, p_interval_minutes: interval,
        p_is_active: payload.is_active !== false, p_items: items,
      }))
      return jsonResponse({ id: savedId }, 200, requestId)
    }

    if (action === "record_area_inspection") {
      const templateId = requiredUuid(payload.template_id, "template_id")
      const clientEventId = requiredUuid(payload.client_event_id, "client_event_id")
      if (!Array.isArray(payload.results)) fail(400, "INVALID_INSPECTION", "results must list every configured inspection item.")
      let occurredAt: string | null = null
      if (payload.offline_replay === true) {
        if (typeof payload.occurred_at !== "string") {
          fail(400, "INVALID_INSPECTION_TIME", "Offline inspections must include their saved occurrence time.")
        }
        const parsedTime = new Date(payload.occurred_at)
        if (Number.isNaN(parsedTime.getTime())) fail(400, "INVALID_INSPECTION_TIME", "The saved inspection time is invalid.")
        occurredAt = parsedTime.toISOString()
      }
      const results = payload.results.map((item: Record<string, unknown>) => ({
        item_id: requiredUuid(item?.item_id, "item_id"),
        result_state: requiredString(item?.result_state, "result_state", 24),
        note: typeof item?.note === "string" ? item.note.slice(0, 500) : "",
      }))
      const result = assertNoError(await admin.rpc("record_restaurant_area_inspection", {
        p_branch_id: branchId, p_actor_id: user.id, p_template_id: templateId,
        p_client_event_id: clientEventId, p_results: results,
        p_note: typeof payload.note === "string" ? payload.note.slice(0, 1000) : "",
        p_occurred_at: occurredAt,
      }))
      return jsonResponse(result, 201, requestId)
    }

    if (action === "save_assignment_policy") {
      const loadBalanceWeight = Number(payload.assignment_load_balance_weight)
      const heavyRotationWeight = Number(payload.assignment_heavy_rotation_weight)
      const priorityWeight = Number(payload.assignment_priority_weight)
      const weights = [loadBalanceWeight, heavyRotationWeight, priorityWeight]
      if (weights.some((value) => !Number.isInteger(value) || value < 0 || value > 1000)) {
        fail(400, "INVALID_ASSIGNMENT_POLICY", "Assignment weights must be whole numbers between 0 and 1000.")
      }
      const saved = assertNoError(await admin.from("restaurant_branches").update({
        assignment_load_balance_weight: loadBalanceWeight,
        assignment_heavy_rotation_weight: heavyRotationWeight,
        assignment_priority_weight: priorityWeight,
      }).eq("id", branchId).select("assignment_load_balance_weight, assignment_heavy_rotation_weight, assignment_priority_weight").single())
      return jsonResponse({ assignment_policy: saved }, 200, requestId)
    }

    if (action === "save_branch_features") {
      const currentBranch = assertNoError(await admin.from("restaurant_branches")
        .select("name, timezone, enable_time_clock, require_gps_for_time_clock, receipt_escalation_seconds_by_priority, collaboration_manager_escalation_seconds").eq("id", branchId).single())
      const enableTimeClock = payload.enable_time_clock === undefined
        ? currentBranch.enable_time_clock === true : payload.enable_time_clock === true
      const requireGps = enableTimeClock && (payload.require_gps_for_time_clock === undefined
        ? currentBranch.require_gps_for_time_clock === true : payload.require_gps_for_time_clock === true)
      const mealDuration = payload.meal_duration_minutes == null || payload.meal_duration_minutes === ""
        ? null : Number(payload.meal_duration_minutes)
      if (mealDuration !== null && (!Number.isInteger(mealDuration) || mealDuration < 1 || mealDuration > 240)) {
        fail(400, "INVALID_MEAL_DURATION", "La duración de comida debe estar entre 1 y 240 minutos o dejarse sin configurar.")
      }
      const reservationSeconds = payload.collaboration_reservation_seconds == null || payload.collaboration_reservation_seconds === ""
        ? null : Number(payload.collaboration_reservation_seconds)
      if (reservationSeconds !== null && (!Number.isInteger(reservationSeconds) || reservationSeconds < 30 || reservationSeconds > 3600)) {
        fail(400, "INVALID_RESERVATION", "El tiempo de reserva debe configurarse entre 30 y 3600 segundos o dejarse vacío.")
      }
      const receiptEscalation = payload.receipt_escalation_seconds_by_priority == null
        ? undefined : payload.receipt_escalation_seconds_by_priority
      if (receiptEscalation !== undefined && (!receiptEscalation || typeof receiptEscalation !== "object" || Array.isArray(receiptEscalation))) {
        fail(400, "INVALID_RECEIPT_ESCALATION_POLICY", "La política de recepción debe ser un mapa de prioridad a segundos.")
      }
      if (receiptEscalation !== undefined && Object.entries(receiptEscalation as Record<string, unknown>)
        .some(([priority, seconds]) => !/^[1-5]$/.test(priority) || !Number.isInteger(seconds) || Number(seconds) < 30 || Number(seconds) > 86400)) {
        fail(400, "INVALID_RECEIPT_ESCALATION_POLICY", "Configura prioridades 1–5 con plazos enteros de 30 a 86400 segundos.")
      }
      const managerEscalationSeconds = payload.collaboration_manager_escalation_seconds == null
        || payload.collaboration_manager_escalation_seconds === ""
        ? null : Number(payload.collaboration_manager_escalation_seconds)
      if (managerEscalationSeconds !== null
          && (!Number.isInteger(managerEscalationSeconds) || managerEscalationSeconds < 30 || managerEscalationSeconds > 604800)) {
        fail(400, "INVALID_MANAGER_ESCALATION_POLICY", "El plazo para escalar a gerencia debe estar entre 30 y 604800 segundos o dejarse vacío.")
      }
      const minimumAreaCoverage = payload.minimum_area_coverage == null ? undefined : payload.minimum_area_coverage
      if (minimumAreaCoverage !== undefined && (!minimumAreaCoverage || typeof minimumAreaCoverage !== "object" || Array.isArray(minimumAreaCoverage))) {
        fail(400, "INVALID_AREA_COVERAGE", "La cobertura mínima por área debe ser un objeto de configuración.")
      }
      if (minimumAreaCoverage !== undefined && Object.entries(minimumAreaCoverage as Record<string, unknown>)
        .some(([areaId, value]) => !UUID.test(areaId) || !Number.isInteger(value) || Number(value) < 0 || Number(value) > 100)) {
        fail(400, "INVALID_AREA_COVERAGE", "Cada mínimo debe ser un entero de 0 a 100 asociado a un área válida.")
      }
      if (minimumAreaCoverage !== undefined) {
        const areaIds = Object.keys(minimumAreaCoverage as Record<string, unknown>)
        const activeAreas = areaIds.length ? assertNoError(await admin.from("restaurant_areas").select("id")
          .eq("branch_id", branchId).eq("is_active", true).in("id", areaIds)) ?? [] : []
        if (activeAreas.length !== areaIds.length) fail(400, "INVALID_AREA_COVERAGE", "La cobertura debe referir únicamente áreas activas de esta sucursal.")
      }
      const branchName = payload.name == null
        ? currentBranch.name : requiredString(payload.name, "name", 120)
      if (branchName.trim().length < 2) fail(400, "INVALID_BRANCH_NAME", "Branch name must contain at least two characters.")
      const timezone = payload.timezone == null
        ? currentBranch.timezone : requiredString(payload.timezone, "timezone", 64)
      try {
        new Intl.DateTimeFormat("en-US", { timeZone: timezone }).format(new Date())
      } catch {
        fail(400, "INVALID_TIMEZONE", "Choose a valid time zone for the branch.")
      }
      if (payload.enable_time_clock === false) {
        const activeSessions = assertNoError(await admin.from("restaurant_time_sessions")
          .select("id").eq("branch_id", branchId).is("clock_out_at", null).limit(1)) ?? []
        if (activeSessions.length) fail(409, "TIME_CLOCK_HAS_ACTIVE_SESSIONS", "Registra la salida de las sesiones activas antes de apagar el checador.")
      }
      const branchUpdate: Record<string, unknown> = {
        name: branchName.trim(), timezone, enable_time_clock: enableTimeClock, require_gps_for_time_clock: requireGps,
      }
      if (payload.meal_duration_minutes !== undefined) branchUpdate.meal_duration_minutes = mealDuration
      if (payload.collaboration_reservation_seconds !== undefined) branchUpdate.collaboration_reservation_seconds = reservationSeconds
      if (receiptEscalation !== undefined) branchUpdate.receipt_escalation_seconds_by_priority = receiptEscalation
      if (payload.collaboration_manager_escalation_seconds !== undefined) branchUpdate.collaboration_manager_escalation_seconds = managerEscalationSeconds
      if (minimumAreaCoverage !== undefined) branchUpdate.minimum_area_coverage = minimumAreaCoverage
      assertNoError(await admin.from("restaurant_branches").update(branchUpdate).eq("id", branchId).select("id").single())
      return jsonResponse({ name: branchName.trim(), timezone, enable_time_clock: enableTimeClock,
        require_gps_for_time_clock: requireGps, ...(payload.meal_duration_minutes !== undefined ? { meal_duration_minutes: mealDuration } : {}),
        ...(payload.collaboration_reservation_seconds !== undefined ? { collaboration_reservation_seconds: reservationSeconds } : {}),
        ...(receiptEscalation !== undefined ? { receipt_escalation_seconds_by_priority: receiptEscalation } : {}),
        ...(payload.collaboration_manager_escalation_seconds !== undefined ? { collaboration_manager_escalation_seconds: managerEscalationSeconds } : {}),
        ...(minimumAreaCoverage !== undefined ? { minimum_area_coverage: minimumAreaCoverage } : {}) }, 200, requestId)
    }

    if (action === "record_time_event") {
      const eventType = requiredString(payload.event_type, "event_type", 16)
      if (!(["clock_in", "clock_out"] as string[]).includes(eventType)) fail(400, "INVALID_TIME_EVENT", "event_type must be clock_in or clock_out.")
      const occurredAt = typeof payload.occurred_at === "string" ? new Date(payload.occurred_at) : new Date()
      if (Number.isNaN(occurredAt.getTime())) fail(400, "INVALID_TIME_EVENT", "occurred_at must be a valid timestamp.")
      const numberOrNull = (value: unknown) => value == null ? null : Number(value)
      const latitude = numberOrNull(payload.latitude)
      const longitude = numberOrNull(payload.longitude)
      const accuracy = numberOrNull(payload.accuracy_m)
      if ([latitude, longitude, accuracy].some((value) => value !== null && !Number.isFinite(value))) fail(400, "INVALID_GPS", "GPS values must be finite numbers.")
      const result = assertNoError(await admin.rpc("record_restaurant_time_event", {
        p_branch_id: branchId, p_actor_id: user.id,
        p_client_event_id: requiredUuid(payload.client_event_id, "client_event_id"),
        p_event_type: eventType, p_occurred_at: occurredAt.toISOString(),
        p_latitude: latitude, p_longitude: longitude, p_accuracy_m: accuracy,
      }))
      return jsonResponse(result, 200, requestId)
    }

    if (action === "schedule_tasks") {
      const branch = assertNoError(await admin.from("restaurant_branches").select("timezone").eq("id", branchId).single())
      const forDate = typeof payload.for_date === "string" ? payload.for_date : dateInZone(branch.timezone)
      if (!isCalendarDate(forDate)) fail(400, "INVALID_PAYLOAD", "for_date must be a valid calendar date in YYYY-MM-DD format.")
      if (forDate < dateInZone(branch.timezone)) fail(409, "PAST_TASK_DATE", "Configured activities cannot be materialized retroactively.")
      const count = assertNoError(await admin.rpc("materialize_restaurant_tasks", { p_branch_id: branchId, p_for_date: forDate }))
      return jsonResponse({ created_count: count }, 200, requestId)
    }
    if (action === "create_task") {
      const templateId = requiredUuid(payload.template_id, "template_id")
      const eventId = requiredUuid(payload.client_event_id, "client_event_id")
      const branch = assertNoError(await admin.from("restaurant_branches").select("timezone").eq("id", branchId).single())
      const scheduledFor = typeof payload.scheduled_for === "string" ? payload.scheduled_for : dateInZone(branch.timezone)
      if (!isCalendarDate(scheduledFor)) fail(400, "INVALID_SCHEDULE", "scheduled_for must be a valid calendar date in YYYY-MM-DD format.")
      if (scheduledFor < dateInZone(branch.timezone)) fail(409, "PAST_TASK_DATE", "Tasks cannot be created retroactively from the agenda.")
      const taskId = assertNoError(await admin.rpc("create_restaurant_task_instance", {
        p_branch_id: branchId, p_actor_id: user.id, p_template_id: templateId,
        p_scheduled_for: scheduledFor, p_source_event_id: eventId,
      }))
      return jsonResponse({ task_id: taskId }, 201, requestId)
    }
    if (action === "reschedule_task") {
      const taskId = requiredUuid(payload.task_id, "task_id")
      const scheduledFor = requiredString(payload.scheduled_for, "scheduled_for", 10)
      if (!isCalendarDate(scheduledFor)) {
        fail(400, "INVALID_SCHEDULE", "scheduled_for must be a valid calendar date in YYYY-MM-DD format.")
      }
      const branch = assertNoError(await admin.from("restaurant_branches")
        .select("timezone").eq("id", branchId).single())
      const localDate = dateInZone(branch.timezone)
      if (scheduledFor < localDate) {
        fail(409, "PAST_TASK_DATE", "Activities cannot be moved to a past date.")
      }
      const task = assertNoError(await admin.from("restaurant_tasks")
        .select("id, activity_template_id, scheduled_for, task_source, status, assigned_to")
        .eq("branch_id", branchId).eq("id", taskId).maybeSingle())
      if (!task) fail(404, "TASK_NOT_FOUND", "This activity does not belong to the selected branch.")
      if (task.status !== "pending" || task.task_source !== "scheduled" || !task.activity_template_id) {
        fail(409, "TASK_NOT_RESCHEDULABLE", "Only pending activities generated from a configured template can be moved.")
      }
      if (task.assigned_to) {
        fail(409, "TASK_MUST_BE_UNASSIGNED", "Remove the activity assignment before moving it to another date.")
      }
      const assignedParts = assertNoError(await admin.from("restaurant_task_parts")
        .select("id").eq("branch_id", branchId).eq("task_id", taskId)
        .not("assigned_to", "is", null).limit(1)) ?? []
      if (assignedParts.length) {
        fail(409, "TASK_PARTS_MUST_BE_UNASSIGNED", "Remove the activity-part assignments before moving the activity.")
      }
      if (task.scheduled_for === scheduledFor) {
        return jsonResponse({ task_id: taskId, scheduled_for: scheduledFor, unchanged: true }, 200, requestId)
      }
      const duplicate = assertNoError(await admin.from("restaurant_tasks")
        .select("id").eq("branch_id", branchId).eq("activity_template_id", task.activity_template_id)
        .eq("scheduled_for", scheduledFor).eq("task_source", "scheduled").neq("id", taskId).maybeSingle())
      if (duplicate) {
        fail(409, "SCHEDULED_ACTIVITY_ALREADY_EXISTS", "This configured activity is already scheduled for that date.")
      }
      const update = await admin.from("restaurant_tasks")
        .update({ scheduled_for: scheduledFor })
        .eq("branch_id", branchId).eq("id", taskId).eq("status", "pending")
        .eq("task_source", "scheduled").eq("scheduled_for", task.scheduled_for)
        .is("assigned_to", null).select("id, scheduled_for").maybeSingle()
      if (update.error?.code === "23505") {
        fail(409, "SCHEDULED_ACTIVITY_ALREADY_EXISTS", "This configured activity is already scheduled for that date.")
      }
      const saved = assertNoError(update)
      if (!saved) {
        fail(409, "TASK_SCHEDULE_CHANGED", "The activity changed while you were moving it. Refresh the calendar and try again.")
      }
      return jsonResponse({ task_id: taskId, scheduled_for: saved.scheduled_for, unchanged: false }, 200, requestId)
    }
    if (action === "assign_task") {
      const taskId = requiredUuid(payload.task_id, "task_id")
      const assignedTo = payload.assigned_to == null || payload.assigned_to === ""
        ? null : requiredUuid(payload.assigned_to, "assigned_to")
      const task = assertNoError(await admin.from("restaurant_tasks")
        .select("id, activity_template_id, scheduled_for, status, assigned_to, task_source, estimated_minutes")
        .eq("id", taskId).eq("branch_id", branchId).maybeSingle())
      if (!task) fail(404, "TASK_NOT_FOUND", "This task does not belong to the selected branch.")
      if (task.status !== "pending") fail(409, "TASK_NOT_ASSIGNABLE", "Only pending activities can be reassigned from the calendar.")
      if (task.assigned_to === assignedTo) return jsonResponse({ assigned_to: assignedTo }, 200, requestId)
      const branchTimezone = assertNoError(await admin.from("restaurant_branches")
        .select("timezone").eq("id", branchId).single()).timezone
      const localDate = dateInZone(branchTimezone)
      if (task.scheduled_for < localDate) fail(409, "TASK_DATE_PASSED", "Past activities cannot be assigned from the calendar.")

      let requiredPositionIds: string[] = []
      let interruptible = true
      if (task.activity_template_id) {
        const template = assertNoError(await admin.from("restaurant_activity_templates")
          .select("is_divisible, interruptible").eq("id", task.activity_template_id).eq("branch_id", branchId).single())
        if (template.is_divisible) fail(409, "DIVIDED_TASK_REQUIRES_PART_ASSIGNMENT", "Assign divided activities by individual part.")
        interruptible = Boolean(template.interruptible)
      }
      if (task.task_source === "waste") {
        requiredPositionIds = (assertNoError(await admin.from("restaurant_waste_positions")
          .select("position_id").eq("branch_id", branchId)) ?? [])
          .map((item: Record<string, string>) => item.position_id)
      } else if (task.activity_template_id) {
        requiredPositionIds = (assertNoError(await admin.from("restaurant_activity_positions")
          .select("position_id").eq("branch_id", branchId).eq("activity_template_id", task.activity_template_id)) ?? [])
          .map((item: Record<string, string>) => item.position_id)
      }

      if (assignedTo) {
        await ensureEmployeeAvailableForNewAssignment(admin, branchId, assignedTo, task.scheduled_for, localDate)
        if (requiredPositionIds.length === 0) fail(409, "TASK_HAS_NO_ELIGIBLE_POSITION", "Configure an eligible position before assigning this activity.")
        const member = assertNoError(await admin.from("restaurant_memberships")
          .select("user_id, customer_service_active").eq("branch_id", branchId).eq("user_id", assignedTo).eq("is_active", true).maybeSingle())
        if (!member) fail(409, "EMPLOYEE_NOT_ACTIVE", "Choose an active employee in this branch.")
        const employeeAccount = assertNoError(await admin.from("users").select("is_active").eq("id", assignedTo).maybeSingle())
        if (!employeeAccount?.is_active) fail(409, "EMPLOYEE_NOT_ACTIVE", "Choose an active employee account.")
        const positions = assertNoError(await admin.from("restaurant_member_positions")
          .select("position_id").eq("branch_id", branchId).eq("user_id", assignedTo)) ?? []
        if (!positions.some((item: Record<string, string>) => requiredPositionIds.includes(item.position_id))) {
          fail(409, "EMPLOYEE_NOT_ELIGIBLE", "This employee does not have a position required for the activity.")
        }
        if (interruptible && member.customer_service_active && task.scheduled_for === localDate) {
          fail(409, "EMPLOYEE_SERVING_CUSTOMERS", "Choose someone who is not currently serving customers.")
        }

        const absence = assertNoError(await admin.from("restaurant_absences").select("id")
          .eq("branch_id", branchId).eq("employee_id", assignedTo).eq("status", "approved")
          .lte("start_date", task.scheduled_for).gte("end_date", task.scheduled_for).limit(1)) ?? []
        if (absence.length) fail(409, "EMPLOYEE_ABSENT", "This employee has an approved absence on the activity date.")
        const shifts = assertNoError(await admin.from("restaurant_shifts")
          .select("id, shift_date, start_time, end_time").eq("branch_id", branchId).eq("employee_id", assignedTo)
          .in("shift_date", [task.scheduled_for, addDays(task.scheduled_for, -1)]).eq("status", "published")) ?? []
        const relevantShifts = shifts.filter((shift: Record<string, string>) => {
          if (shift.shift_date === task.scheduled_for) return true
          return minutesOfDay(shift.end_time) <= minutesOfDay(shift.start_time)
        })
        if (!relevantShifts.length) fail(409, "EMPLOYEE_NOT_SCHEDULED", "This employee has no published shift on the activity date.")
        const shiftIds = relevantShifts.map((shift: { id: string }) => shift.id)
        const breaks = assertNoError(await admin.from("restaurant_shift_breaks")
          .select("shift_id, start_time, end_time").eq("branch_id", branchId).in("shift_id", shiftIds)) ?? []
        let currentMinute = 0
        if (task.scheduled_for === localDate) {
          const localClock = new Intl.DateTimeFormat("en-GB", {
            timeZone: branchTimezone, hour: "2-digit", minute: "2-digit", hourCycle: "h23",
          }).format(new Date())
          currentMinute = minutesOfDay(localClock)
        }
        const isToday = task.scheduled_for === localDate
        const shiftWindows = new Map<string, { availableStart: number; end: number }>()
        const shiftMinutes = relevantShifts.reduce((total: number, shift: Record<string, string>) => {
          const start = minutesOfDay(shift.start_time)
          const end = minutesOfDay(shift.end_time)
          const previousDay = shift.shift_date !== task.scheduled_for
          const dayOffset = previousDay ? -1440 : 0
          const startAbsolute = start + dayOffset
          const endAbsolute = (end <= start ? end + 1440 : end) + dayOffset
          const availableStart = Math.max(startAbsolute, isToday ? currentMinute : 0)
          shiftWindows.set(shift.id, { availableStart, end: endAbsolute })
          return total + Math.max(0, endAbsolute - availableStart)
        }, 0)
        const breakMinutes = breaks.reduce((total: number, item: Record<string, string>) => {
          const window = shiftWindows.get(item.shift_id)
          const shift = relevantShifts.find((candidate: Record<string, string>) => candidate.id === item.shift_id)
          if (!window || !shift) return total
          const previousDay = shift.shift_date !== task.scheduled_for
          const dayOffset = previousDay ? -1440 : 0
          const shiftStart = minutesOfDay(shift.start_time)
          const start = minutesOfDay(item.start_time)
          const end = minutesOfDay(item.end_time)
          const endAbsolute = (end <= start ? end + 1440 : end) +
            (start < shiftStart ? 1440 : 0) + dayOffset
          const startAbsolute = start + (start < shiftStart ? 1440 : 0) + dayOffset
          return total + Math.max(0,
            Math.min(window.end, endAbsolute) - Math.max(window.availableStart, startAbsolute),
          )
        }, 0)
        const currentTasks = assertNoError(await admin.from("restaurant_tasks")
          .select("id, estimated_minutes").eq("branch_id", branchId).eq("scheduled_for", task.scheduled_for)
          .eq("assigned_to", assignedTo).neq("status", "completed")) ?? []
        const otherTaskIds = currentTasks.filter((item: Record<string, unknown>) => item.id !== taskId)
          .map((item: { id: string }) => item.id)
        const currentParts = otherTaskIds.length
          ? assertNoError(await admin.from("restaurant_task_parts").select("estimated_minutes")
            .eq("branch_id", branchId).eq("assigned_to", assignedTo).neq("status", "completed").in("task_id", otherTaskIds)) ?? []
          : []
        const occupiedMinutes = currentTasks
          .filter((item: Record<string, unknown>) => item.id !== taskId)
          .reduce((total: number, item: Record<string, number>) => total + Number(item.estimated_minutes), 0) +
          currentParts.reduce((total: number, item: Record<string, number>) => total + Number(item.estimated_minutes), 0)
        if (shiftMinutes - breakMinutes - occupiedMinutes < Number(task.estimated_minutes)) {
          fail(409, "EMPLOYEE_CAPACITY_EXCEEDED", "This activity does not fit in the employee's remaining published shift capacity.")
        }
      }

      const update = task.assigned_to == null
        ? await admin.from("restaurant_tasks").update({ assigned_to: assignedTo })
          .eq("id", taskId).eq("branch_id", branchId).eq("status", "pending").is("assigned_to", null)
          .select("id").maybeSingle()
        : await admin.from("restaurant_tasks").update({ assigned_to: assignedTo })
          .eq("id", taskId).eq("branch_id", branchId).eq("status", "pending").eq("assigned_to", task.assigned_to)
          .select("id").maybeSingle()
      const updated = assertNoError(update)
      if (!updated) fail(409, "TASK_ASSIGNMENT_CHANGED", "This activity changed before the assignment was saved. Refresh the calendar and try again.")
      return jsonResponse({ assigned_to: assignedTo }, 200, requestId)
    }
    if (action === "auto_assign") {
      const forDate = payload.for_date == null ? undefined : requiredString(payload.for_date, "for_date", 10)
      return jsonResponse(await autoAssign(admin, branchId, requestId, forDate), 200, requestId)
    }

    if (action === "task_action") {
      const taskId = requiredUuid(payload.task_id, "task_id")
      const clientEventId = requiredUuid(payload.client_event_id, "client_event_id")
      const taskAction = requiredString(payload.task_action, "task_action", 24)
      const partId = payload.part_id == null ? null : requiredUuid(payload.part_id, "part_id")
      const evidencePath = typeof payload.evidence_path === "string" ? payload.evidence_path : null
      if (taskAction === "complete") {
        const taskPolicy = assertNoError(await admin.from("restaurant_tasks").select("evidence_policy")
          .eq("branch_id", branchId).eq("id", taskId).maybeSingle())
        if (taskPolicy?.evidence_policy === "independent_review") {
          fail(409, "INDEPENDENT_REVIEW_REQUIRED", "Reporta la actividad para que otra persona autorizada la valide; no se puede cerrar directamente.")
        }
      }
      let occurredAt: string | null = null
      if (payload.offline_replay === true) {
        if (typeof payload.occurred_at !== "string") {
          fail(400, "INVALID_TASK_EVENT_TIME", "Offline task actions must include their saved occurrence time.")
        }
        const parsedTime = new Date(payload.occurred_at)
        if (Number.isNaN(parsedTime.getTime())) {
          fail(400, "INVALID_TASK_EVENT_TIME", "The saved task action time is invalid.")
        }
        occurredAt = parsedTime.toISOString()
      }
      if (evidencePath) {
        const evidence = assertNoError(await admin.from("restaurant_evidence").select("id")
          .eq("branch_id", branchId).eq("task_id", taskId).eq("uploaded_by", user.id).eq("object_path", evidencePath).maybeSingle())
        if (!evidence) fail(400, "INVALID_EVIDENCE", "The uploaded evidence does not belong to this task.")
      }
      const result = assertNoError(await admin.rpc("apply_restaurant_task_action", {
        p_branch_id: branchId, p_task_id: taskId, p_part_id: partId, p_actor_id: user.id,
        p_action: taskAction, p_client_event_id: clientEventId,
        p_note: typeof payload.note === "string" ? payload.note.slice(0, 500) : null,
        p_evidence_path: evidencePath, p_occurred_at: occurredAt,
      }))
      return jsonResponse(result, 200, requestId)
    }

    if (action === "inspect_waste") {
      const eventId = requiredUuid(payload.client_event_id, "client_event_id")
      if (!Array.isArray(payload.results)) fail(400, "INVALID_PAYLOAD", "results must list the declared state of every active bin.")
      let occurredAt: string | null = null
      if (payload.offline_replay === true) {
        if (typeof payload.occurred_at !== "string") {
          fail(400, "INVALID_INSPECTION_TIME", "Offline inspections must include their saved occurrence time.")
        }
        const parsedTime = new Date(payload.occurred_at)
        if (Number.isNaN(parsedTime.getTime())) fail(400, "INVALID_INSPECTION_TIME", "The saved inspection time is invalid.")
        occurredAt = parsedTime.toISOString()
      }
      const results = payload.results.map((item: Record<string, unknown>) => ({
        bin_id: requiredUuid(item?.bin_id, "bin_id"),
        state: requiredString(item?.state, "state", 12),
      }))
      const result = assertNoError(await admin.rpc("record_restaurant_waste_inspection", {
        p_branch_id: branchId, p_inspector_id: user.id, p_client_event_id: eventId,
        p_results: results, p_occurred_at: occurredAt,
      }))
      return jsonResponse(result, 201, requestId)
    }

    if (action === "create_incident") {
      const description = requiredString(payload.description, "description", 1000)
      if (description.length < 3) fail(400, "INVALID_PAYLOAD", "Describe the issue in at least three characters.")
      const areaId = payload.area_id == null ? null : requiredUuid(payload.area_id, "area_id")
      const urgency = ["low", "normal", "high", "urgent"].includes(String(payload.urgency)) ? String(payload.urgency) : "normal"
      const assignedTo = membership.access_role !== "employee" && payload.assigned_to
        ? requiredUuid(payload.assigned_to, "assigned_to") : null
      const clientEventId = requiredUuid(payload.client_event_id, "client_event_id")
      let occurredAt: string | null = null
      if (payload.offline_replay === true) {
        if (typeof payload.occurred_at !== "string") {
          fail(400, "INVALID_INCIDENT_TIME", "Offline incidents must include their saved occurrence time.")
        }
        const parsedTime = new Date(payload.occurred_at)
        if (Number.isNaN(parsedTime.getTime())) fail(400, "INVALID_INCIDENT_TIME", "The saved incident time is invalid.")
        occurredAt = parsedTime.toISOString()
      }
      if (assignedTo) await memberForBranch(admin, branchId, assignedTo)
      const incidentId = assertNoError(await admin.rpc("create_restaurant_incident", {
        p_branch_id: branchId, p_actor_id: user.id, p_area_id: areaId, p_description: description,
        p_urgency: urgency, p_is_blocking: Boolean(payload.is_blocking), p_assigned_to: assignedTo,
        p_client_event_id: clientEventId, p_occurred_at: occurredAt,
      }))
      return jsonResponse({ incident_id: incidentId }, 201, requestId)
    }

    if (action === "update_incident") {
      const incidentId = requiredUuid(payload.incident_id, "incident_id")
      const assignedTo = payload.assigned_to ? requiredUuid(payload.assigned_to, "assigned_to") : null
      if (assignedTo) await memberForBranch(admin, branchId, assignedTo)
      const result = assertNoError(await admin.rpc("update_restaurant_incident", {
        p_branch_id: branchId, p_incident_id: incidentId, p_actor_id: user.id,
        p_status: requiredString(payload.status, "status", 24), p_assigned_to: assignedTo,
        p_is_blocking: Boolean(payload.is_blocking), p_note: typeof payload.note === "string" ? payload.note.slice(0, 500) : null,
        p_client_event_id: requiredUuid(payload.client_event_id, "client_event_id"),
      }))
      return jsonResponse(result, 200, requestId)
    }

    if (action === "set_customer_service") {
      assertNoError(await admin.from("restaurant_memberships").update({ customer_service_active: Boolean(payload.active) })
        .eq("branch_id", branchId).eq("user_id", user.id).eq("is_active", true))
      return jsonResponse({ active: Boolean(payload.active) }, 200, requestId)
    }

    if (action === "save_area" || action === "save_position") {
      const table = action === "save_area" ? "restaurant_areas" : "restaurant_positions"
      const name = requiredString(payload.name, "name", 100)
      const row = action === "save_position"
        ? { branch_id: branchId, name, is_active: payload.is_active !== false,
          area_id: payload.area_id ? requiredUuid(payload.area_id, "area_id") : null }
        : { branch_id: branchId, name, is_active: payload.is_active !== false }
      const id = payload.id ? requiredUuid(payload.id, "id") : null
      const query = id ? admin.from(table).update(row).eq("id", id).eq("branch_id", branchId)
        : admin.from(table).insert(row)
      const saved = assertNoError(await query.select("id").single())
      return jsonResponse({ id: saved.id }, 200, requestId)
    }

    if (action === "invite_member") {
      const email = requiredString(payload.email, "email", 254).trim().toLowerCase()
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) fail(400, "INVALID_EMAIL", "Escribe un correo electrónico válido.")
      const fullName = requiredString(payload.full_name, "full_name", 120).trim()
      if (fullName.length < 2) fail(400, "INVALID_PAYLOAD", "Escribe el nombre completo de la persona.")
      const webBaseUrl = Deno.env.get("POLLO_MOVIL_WEB_URL")?.trim().replace(/\/+$/, "")
      const redirectTo = webBaseUrl ? `${webBaseUrl}/reset-password` : undefined
      const existingUser = assertNoError(await admin.from("users")
        .select("id, company_id, is_active, full_name").eq("email", email).maybeSingle())
      if (existingUser) {
        if (existingUser.company_id !== membership.company_id) {
          fail(409, "EMAIL_ALREADY_REGISTERED", "No se puede invitar este correo a la sucursal. Verifica que la cuenta pertenezca a la empresa.")
        }
        if (!existingUser.is_active) fail(409, "ACCOUNT_INACTIVE", "Reactiva esta cuenta de la empresa antes de agregarla a una sucursal.")
        const currentMembership = assertNoError(await admin.from("restaurant_memberships")
          .select("access_role, is_active").eq("branch_id", branchId).eq("user_id", existingUser.id).maybeSingle())
        if (currentMembership?.is_active) {
          const authAccount = assertNoError(await admin.auth.admin.getUserById(existingUser.id))
          if (authAccount.user && !authAccount.user.email_confirmed_at) {
            const metadata = {
              company_id: membership.company_id,
              full_name: String(existingUser.full_name ?? fullName),
              role: "worker",
              invited_by: user.id,
            }
            const resent = await admin.auth.admin.generateLink({
              type: "invite", email, options: { data: metadata, ...(redirectTo ? { redirectTo } : {}) },
            })
            const renewedLink = resent.data?.properties?.action_link
            if (resent.data?.user?.id !== existingUser.id || !renewedLink) {
              fail(502, "INVITATION_FAILED", "No se pudo crear un nuevo enlace de invitación.")
            }
            return jsonResponse({
              user_id: existingUser.id, email_sent: false,
              invite_link: renewedLink, invitation_renewed: true,
            }, 200, requestId)
          }
          return jsonResponse({ user_id: existingUser.id, already_member: true }, 200, requestId)
        }
        const saved = assertNoError(await admin.rpc("save_restaurant_member", {
          p_branch_id: branchId, p_actor_id: user.id, p_employee_id: existingUser.id,
          p_access_role: currentMembership?.access_role ?? "employee",
        }))
        return jsonResponse({ ...(saved as Record<string, unknown>), user_id: existingUser.id, existing_account: true }, 200, requestId)
      }

      const metadata = {
        company_id: membership.company_id,
        full_name: fullName,
        role: "worker",
        invited_by: user.id,
      }
      const invitation = await admin.auth.admin.inviteUserByEmail(email, {
        data: metadata, ...(redirectTo ? { redirectTo } : {}),
      })
      let invitedUserId = invitation.data?.user?.id ?? null
      let emailSent = !invitation.error
      let inviteLink: string | null = null
      if (invitation.error) {
        const generated = await admin.auth.admin.generateLink({
          type: "invite", email, options: { data: metadata, ...(redirectTo ? { redirectTo } : {}) },
        })
        const generatedUser = generated.data?.user
        if (!invitedUserId) invitedUserId = generatedUser?.id ?? null
        inviteLink = generated.data?.properties?.action_link ?? null
        const generatedUserMetadata = generatedUser?.user_metadata as Record<string, unknown> | undefined
        if (generatedUser && (generatedUserMetadata?.company_id !== membership.company_id ||
            generatedUserMetadata?.invited_by !== user.id)) {
          fail(409, "EMAIL_ALREADY_REGISTERED", "No se puede invitar este correo a la sucursal. Verifica que la cuenta pertenezca a la empresa.")
        }
      }
      if (!invitedUserId || (invitation.error && !inviteLink)) {
        fail(502, "INVITATION_FAILED", "No se pudo crear la invitación. Revisa el correo e inténtalo de nuevo.")
      }

      assertNoError(await admin.from("users").upsert({
        id: invitedUserId, company_id: membership.company_id, role: "worker",
        full_name: fullName, email, is_active: true,
      }, { onConflict: "id", ignoreDuplicates: true }))
      const saved = assertNoError(await admin.rpc("save_restaurant_member", {
        p_branch_id: branchId, p_actor_id: user.id, p_employee_id: invitedUserId,
        p_access_role: "employee",
      }))
      return jsonResponse({
        ...(saved as Record<string, unknown>), user_id: invitedUserId,
        email_sent: emailSent, invite_link: inviteLink,
      }, 201, requestId)
    }

    if (action === "save_member") {
      const employeeId = requiredUuid(payload.user_id, "user_id")
      const role = requiredString(payload.access_role, "access_role", 24)
      if (!["admin", "supervisor", "employee"].includes(role)) fail(400, "INVALID_MEMBER_ROLE", "Choose a valid branch role.")
      const result = assertNoError(await admin.rpc("save_restaurant_member", {
        p_branch_id: branchId, p_actor_id: user.id,
        p_employee_id: employeeId, p_access_role: role,
      }))
      return jsonResponse(result as Record<string, unknown>, 200, requestId)
    }

    if (action === "set_member_active") {
      const employeeId = requiredUuid(payload.user_id, "user_id")
      if (typeof payload.is_active !== "boolean") fail(400, "INVALID_PAYLOAD", "is_active must be true or false.")
      const saved = assertNoError(await admin.rpc("set_restaurant_member_active", {
        p_branch_id: branchId, p_actor_id: user.id,
        p_employee_id: employeeId, p_is_active: payload.is_active,
      }))
      return jsonResponse({ saved: saved === true, is_active: payload.is_active }, 200, requestId)
    }

    if (action === "save_member_positions") {
      const employeeId = requiredUuid(payload.user_id, "user_id")
      const positionIds = Array.isArray(payload.position_ids) ? payload.position_ids.map((id) => requiredUuid(id, "position_id")) : []
      await memberForBranch(admin, branchId, employeeId)
      assertNoError(await admin.rpc("save_restaurant_member_positions", {
        p_branch_id: branchId, p_actor_id: user.id, p_employee_id: employeeId, p_position_ids: positionIds,
      }))
      return jsonResponse({ saved: true }, 200, requestId)
    }

    if (action === "save_waste_positions") {
      const positionIds = Array.isArray(payload.position_ids) ? payload.position_ids.map((id) => requiredUuid(id, "position_id")) : []
      assertNoError(await admin.rpc("save_restaurant_waste_positions", {
        p_branch_id: branchId, p_actor_id: user.id, p_position_ids: positionIds,
      }))
      return jsonResponse({ saved: true }, 200, requestId)
    }

    if (action === "save_bin") {
      const binId = payload.bin_id ? requiredUuid(payload.bin_id, "bin_id") : null
      const name = typeof payload.name === "string" ? payload.name.trim() : ""
      if (name.length > 120 || (!binId && name.length < 2)) {
        fail(400, "INVALID_BIN_NAME", "Enter a bin name between 2 and 120 characters.")
      }
      const interval = payload.inspection_interval_minutes == null || payload.inspection_interval_minutes === ""
        ? null : Number(payload.inspection_interval_minutes)
      if (interval !== null && (!Number.isInteger(interval) || interval < 1 || interval > 10080)) {
        fail(400, "INVALID_INTERVAL", "Choose an inspection interval from 1 to 10,080 minutes.")
      }
      const policyFields = ["bag_change_activity_name", "bag_change_minutes", "bag_change_difficulty", "bag_change_priority"]
      const policyProvided = policyFields.some((field) => Object.prototype.hasOwnProperty.call(payload, field))
      let wasteTaskPolicy: Record<string, unknown> = {}
      if (!binId || policyProvided) {
        const activityName = typeof payload.bag_change_activity_name === "string"
          ? payload.bag_change_activity_name.trim() : ""
        const minutes = Number(payload.bag_change_minutes)
        const difficulty = Number(payload.bag_change_difficulty)
        const priority = Number(payload.bag_change_priority)
        if (activityName.length < 2 || activityName.length > 120
          || !Number.isInteger(minutes) || minutes < 1 || minutes > 1440
          || !Number.isInteger(difficulty) || difficulty < 1 || difficulty > 5
          || !Number.isInteger(priority) || priority < 1 || priority > 5) {
          fail(400, "INVALID_WASTE_TASK_POLICY", "Define the real task name, duration, difficulty and priority for this container.")
        }
        wasteTaskPolicy = {
          bag_change_activity_name: activityName,
          bag_change_minutes: minutes,
          bag_change_difficulty: difficulty,
          bag_change_priority: priority,
        }
      }
      if (binId) {
        const values: Record<string, unknown> = { inspection_interval_minutes: interval, ...wasteTaskPolicy }
        if (name) values.name = name
        if (typeof payload.is_active === "boolean") values.is_active = payload.is_active
        const update = assertNoError(await admin.from("restaurant_waste_bins")
          .update(values).eq("branch_id", branchId).eq("id", binId).select("id").maybeSingle())
        if (!update) fail(404, "BIN_NOT_FOUND", "The selected bin does not belong to this branch.")
        return jsonResponse({ saved: true, bin_id: binId }, 200, requestId)
      }
      const lastBin = assertNoError(await admin.from("restaurant_waste_bins")
        .select("sort_order").eq("branch_id", branchId)
        .order("sort_order", { ascending: false }).limit(1).maybeSingle())
      const created = assertNoError(await admin.from("restaurant_waste_bins").insert({
        branch_id: branchId, name, inspection_interval_minutes: interval,
        sort_order: Number(lastBin?.sort_order ?? -1) + 1, ...wasteTaskPolicy,
      }).select("id").single())
      return jsonResponse({ saved: true, bin_id: created.id }, 201, requestId)
    }

    if (action === "save_template") {
      const name = requiredString(payload.name, "name", 120)
      const activityType = String(payload.activity_type ?? "")
      if (!["scheduled", "conditional", "corrective"].includes(activityType)) {
        fail(400, "INVALID_ACTIVITY_TYPE", "Choose a valid activity type.")
      }
      const days = Array.isArray(payload.schedule_days) ? payload.schedule_days.map(Number) : []
      if (activityType === "scheduled" && (days.length === 0 || new Set(days).size !== days.length || days.some((day) => !Number.isInteger(day) || day < 1 || day > 7))) {
        fail(400, "INVALID_SCHEDULE", "Choose at least one scheduled day from Monday through Sunday.")
      }
      const estimatedMinutes = Number(payload.estimated_minutes)
      const difficulty = Number(payload.difficulty)
      const priority = Number(payload.priority)
      const evidencePolicy = payload.evidence_policy == null
        ? (payload.requires_evidence === true ? "required" : "none")
        : requiredString(payload.evidence_policy, "evidence_policy", 24)
      if (!["none", "optional", "required", "independent_review"].includes(evidencePolicy)) {
        fail(400, "INVALID_EVIDENCE_POLICY", "Elige una política de evidencia válida.")
      }
      if (!Number.isInteger(estimatedMinutes) || estimatedMinutes < 1 || estimatedMinutes > 1440) {
        fail(400, "INVALID_ESTIMATE", "Set an estimated duration between 1 and 1,440 minutes.")
      }
      if (!Number.isInteger(difficulty) || difficulty < 1 || difficulty > 5
        || !Number.isInteger(priority) || priority < 1 || priority > 5) {
        fail(400, "INVALID_ACTIVITY_POLICY", "Set difficulty and priority from 1 through 5.")
      }
      const areaId = payload.area_id ? requiredUuid(payload.area_id, "area_id") : null
      const positionIds = Array.isArray(payload.position_ids) ? payload.position_ids.map((id) => requiredUuid(id, "position_id")) : []
      const zoneRows = Array.isArray(payload.zones) ? payload.zones : []
      const templatePayload = {
        branch_id: branchId, area_id: areaId, name, description: typeof payload.description === "string" ? payload.description.slice(0, 1000) : null,
        activity_type: activityType, schedule_days: days, estimated_minutes: estimatedMinutes,
        difficulty, priority,
        is_divisible: Boolean(payload.is_divisible), interruptible: payload.interruptible !== false,
        requires_evidence: evidencePolicy === "required", is_active: payload.is_active !== false,
      }
      const id = payload.id ? requiredUuid(payload.id, "id") : null
      const cleanZones = zoneRows.map((zone: Record<string, unknown>, index: number) => {
        const zoneMinutes = Number(zone.estimated_minutes)
        const zoneDifficulty = Number(zone.difficulty)
        if (!Number.isInteger(zoneMinutes) || zoneMinutes < 1 || zoneMinutes > 1440
          || !Number.isInteger(zoneDifficulty) || zoneDifficulty < 1 || zoneDifficulty > 5) {
          fail(400, "INVALID_ACTIVITY_ZONE", "Every activity zone needs a duration and difficulty defined by the branch.")
        }
        return {
          name: requiredString(zone.name, "zone.name", 100),
          estimated_minutes: zoneMinutes,
          difficulty: zoneDifficulty,
          sort_order: index,
        }
      })
      const templateId = assertNoError(await admin.rpc("save_restaurant_activity_template", {
        p_branch_id: branchId, p_actor_id: user.id, p_template_id: id, p_area_id: areaId,
        p_name: name, p_description: templatePayload.description, p_activity_type: activityType,
        p_schedule_days: days, p_estimated_minutes: templatePayload.estimated_minutes,
        p_difficulty: templatePayload.difficulty, p_priority: templatePayload.priority,
        p_is_divisible: templatePayload.is_divisible, p_interruptible: templatePayload.interruptible,
        p_requires_evidence: templatePayload.requires_evidence, p_is_active: templatePayload.is_active,
        p_position_ids: positionIds, p_zones: cleanZones,
      }))
      assertNoError(await admin.from("restaurant_activity_templates").update({
        evidence_policy: evidencePolicy, requires_evidence: evidencePolicy === "required",
      }).eq("branch_id", branchId).eq("id", templateId).select("id").single())
      return jsonResponse({ id: templateId }, 200, requestId)
    }

    if (action === "save_shift") {
      const shiftId = payload.shift_id ? requiredUuid(payload.shift_id, "shift_id") : null
      const employeeId = requiredUuid(payload.employee_id, "employee_id")
      const shiftDate = requiredString(payload.shift_date, "shift_date", 10)
      if (!isCalendarDate(shiftDate)) fail(400, "INVALID_SHIFT", "shift_date must be a valid calendar date in YYYY-MM-DD format.")
      const startTime = requiredString(payload.start_time, "start_time", 8)
      const endTime = requiredString(payload.end_time, "end_time", 8)
      if (![startTime, endTime].every((value) => /^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$/.test(value))) {
        fail(400, "INVALID_SHIFT", "Shift times must use 24-hour HH:mm format.")
      }
      await memberForBranch(admin, branchId, employeeId)
      if (Array.isArray(payload.breaks) && payload.breaks.length > 8) fail(400, "INVALID_SHIFT_BREAK", "A shift can include at most eight breaks.")
      const breaks = Array.isArray(payload.breaks) ? payload.breaks.map((item: Record<string, unknown>) => ({
        start_time: requiredString(item?.start_time, "break.start_time", 8),
        end_time: requiredString(item?.end_time, "break.end_time", 8),
      })) : []
      if (breaks.some((item) => ![item.start_time, item.end_time].every((value) => /^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$/.test(value)))) {
        fail(400, "INVALID_SHIFT_BREAK", "Break times must use 24-hour HH:mm format.")
      }
      const savedShiftId = assertNoError(await admin.rpc(
        shiftId ? "replace_restaurant_shift" : "save_restaurant_shift",
        {
          p_branch_id: branchId, p_actor_id: user.id,
          ...(shiftId ? { p_shift_id: shiftId } : {}),
          p_employee_id: employeeId, p_shift_date: shiftDate,
          p_start_time: startTime, p_end_time: endTime,
          p_status: payload.status === "published" ? "published" : "draft", p_breaks: breaks,
        },
      ))
      return jsonResponse({ shift_id: savedShiftId }, 200, requestId)
    }

    if (action === "cancel_shift") {
      const shiftId = requiredUuid(payload.shift_id, "shift_id")
      const shift = assertNoError(await admin.from("restaurant_shifts")
        .select("id, status").eq("branch_id", branchId).eq("id", shiftId).maybeSingle())
      if (!shift) fail(404, "SHIFT_NOT_FOUND", "The selected shift does not belong to this branch.")
      if (shift.status !== "cancelled") {
        assertNoError(await admin.from("restaurant_shifts")
          .update({ status: "cancelled" }).eq("branch_id", branchId).eq("id", shiftId))
      }
      return jsonResponse({ cancelled: true, shift_id: shiftId }, 200, requestId)
    }

    if (action === "request_absence") {
      const clientEventId = requiredUuid(payload.client_event_id, "client_event_id")
      const startDate = requiredString(payload.start_date, "start_date", 10)
      const endDate = requiredString(payload.end_date, "end_date", 10)
      if (!isCalendarDate(startDate) || !isCalendarDate(endDate) || endDate < startDate) {
        fail(400, "INVALID_ABSENCE", "Choose a valid absence date range.")
      }
      const note = typeof payload.note === "string" ? payload.note.trim() : ""
      if (note.length > 300) fail(400, "INVALID_ABSENCE", "The note cannot exceed 300 characters.")
      const existing = assertNoError(await admin.from("restaurant_absences")
        .select("id, employee_id, start_date, end_date, note, status")
        .eq("branch_id", branchId).eq("client_event_id", clientEventId).maybeSingle())
      if (existing) {
        if (existing.employee_id !== user.id || existing.start_date !== startDate ||
          existing.end_date !== endDate || existing.note !== (note || null)) {
          fail(409, "IDEMPOTENCY_KEY_REUSED", "This absence request id was already used for different content.")
        }
        return jsonResponse({ id: existing.id, status: existing.status, duplicate: true }, 200, requestId)
      }
      const saved = await admin.from("restaurant_absences").upsert({
        branch_id: branchId, employee_id: user.id, start_date: startDate,
        end_date: endDate, status: "pending", note: note || null,
        created_by: user.id, client_event_id: clientEventId,
      }, { onConflict: "branch_id,client_event_id", ignoreDuplicates: true }).select("id").maybeSingle()
      if (saved.error) throw saved.error
      if (saved.data) return jsonResponse({ id: saved.data.id, status: "pending", duplicate: false }, 201, requestId)
      const raced = assertNoError(await admin.from("restaurant_absences")
        .select("id, employee_id, start_date, end_date, note, status")
        .eq("branch_id", branchId).eq("client_event_id", clientEventId).single())
      if (raced.employee_id !== user.id || raced.start_date !== startDate ||
        raced.end_date !== endDate || raced.note !== (note || null)) {
        fail(409, "IDEMPOTENCY_KEY_REUSED", "This absence request id was already used for different content.")
      }
      return jsonResponse({ id: raced.id, status: raced.status, duplicate: true }, 200, requestId)
    }

    if (action === "review_absence") {
      const absenceId = requiredUuid(payload.absence_id, "absence_id")
      const status = payload.status === "approved" || payload.status === "denied" ? payload.status : null
      if (!status) fail(400, "INVALID_ABSENCE_STATUS", "Choose approved or denied.")
      const saved = assertNoError(await admin.from("restaurant_absences")
        .update({ status }).eq("branch_id", branchId).eq("id", absenceId).eq("status", "pending")
        .select("id, status").maybeSingle())
      if (!saved) fail(409, "ABSENCE_ALREADY_REVIEWED", "This request is no longer pending.")
      return jsonResponse(saved, 200, requestId)
    }

    if (action === "save_absence") {
      const employeeId = requiredUuid(payload.employee_id, "employee_id")
      const startDate = requiredString(payload.start_date, "start_date", 10)
      const endDate = requiredString(payload.end_date, "end_date", 10)
      if (!/^\d{4}-\d{2}-\d{2}$/.test(startDate) || !/^\d{4}-\d{2}-\d{2}$/.test(endDate) || endDate < startDate) {
        fail(400, "INVALID_ABSENCE", "Choose a valid absence date range.")
      }
      const status = ["pending", "approved", "denied"].includes(String(payload.status)) ? String(payload.status) : "approved"
      await memberForBranch(admin, branchId, employeeId)
      const saved = assertNoError(await admin.from("restaurant_absences").insert({
        branch_id: branchId, employee_id: employeeId, start_date: startDate, end_date: endDate,
        status, note: typeof payload.note === "string" ? payload.note.slice(0, 300) : null,
        created_by: user.id,
      }).select("id").single())
      return jsonResponse({ id: saved.id }, 201, requestId)
    }

    if (action === "sign_evidence_upload") {
      const taskId = requiredUuid(payload.task_id, "task_id")
      const partId = payload.part_id ? requiredUuid(payload.part_id, "part_id") : null
      const mimeType = requiredString(payload.mime_type, "mime_type", 40)
      const size = Number(payload.file_size_bytes)
      if (!["image/jpeg", "image/png", "image/webp"].includes(mimeType) || size <= 0 || size > 10 * 1024 * 1024) {
        fail(400, "INVALID_EVIDENCE", "Use a JPEG, PNG, or WebP image up to 10 MB.")
      }
      const task = assertNoError(await admin.from("restaurant_tasks").select("id, requires_evidence, evidence_policy, assigned_to")
        .eq("id", taskId).eq("branch_id", branchId).maybeSingle())
      if (!task || task.evidence_policy === "none") fail(400, "EVIDENCE_NOT_ALLOWED", "Esta actividad no admite evidencia fotográfica.")
      const part = partId ? assertNoError(await admin.from("restaurant_task_parts").select("id, assigned_to")
        .eq("id", partId).eq("task_id", taskId).eq("branch_id", branchId).maybeSingle()) : null
      const objectPath = `${branchId}/${taskId}/${crypto.randomUUID()}`
      const signed = assertNoError(await admin.storage.from("restaurant-evidence").createSignedUploadUrl(objectPath))
      return jsonResponse({ object_path: objectPath, token: signed.token, signed_url: signed.signedUrl, mime_type: mimeType, file_size_bytes: size, part_id: partId }, 201, requestId)
    }

    if (action === "register_evidence") {
      const taskId = requiredUuid(payload.task_id, "task_id")
      const partId = payload.part_id ? requiredUuid(payload.part_id, "part_id") : null
      const objectPath = requiredString(payload.object_path, "object_path", 500)
      if (!objectPath.startsWith(`${branchId}/${taskId}/`)) fail(400, "INVALID_EVIDENCE", "Evidence path does not match this branch and task.")
      const task = assertNoError(await admin.from("restaurant_tasks").select("id, assigned_to, evidence_policy")
        .eq("id", taskId).eq("branch_id", branchId).maybeSingle())
      const part = partId ? assertNoError(await admin.from("restaurant_task_parts").select("id, assigned_to")
        .eq("id", partId).eq("task_id", taskId).eq("branch_id", branchId).maybeSingle()) : null
      if (!task || task.evidence_policy === "none") fail(400, "EVIDENCE_NOT_ALLOWED", "Esta actividad no admite evidencia fotográfica.")
      if (partId && !part) fail(404, "TASK_PART_NOT_FOUND", "La parte de la actividad no pertenece a esta sucursal.")
      const signed = assertNoError(await admin.storage.from("restaurant-evidence").list(`${branchId}/${taskId}`)) ?? []
      const objectName = objectPath.split("/").at(-1)
      const storedObject = signed.find((object: Record<string, unknown>) => object.name === objectName) as Record<string, unknown> | undefined
      if (!storedObject) fail(400, "EVIDENCE_NOT_FOUND", "Upload the image before attaching it to the task.")
      const metadata = storedObject.metadata as Record<string, unknown> | null
      const mimeType = String(metadata?.mimetype ?? metadata?.contentType ?? "")
      const size = Number(metadata?.size)
      if (!["image/jpeg", "image/png", "image/webp"].includes(mimeType) || !Number.isFinite(size) || size <= 0 || size > 10 * 1024 * 1024) {
        fail(400, "INVALID_EVIDENCE", "Evidence must be an allowed image up to 10 MB.")
      }
      const requestedMime = requiredString(payload.mime_type, "mime_type", 40)
      const requestedSize = Number(payload.file_size_bytes)
      if (requestedMime !== mimeType || requestedSize !== size) fail(400, "INVALID_EVIDENCE", "Image metadata does not match the uploaded object.")
      const existing = assertNoError(await admin.from("restaurant_evidence").select("id, uploaded_by, task_id, part_id")
        .eq("object_path", objectPath).maybeSingle())
      if (existing && (existing.uploaded_by !== user.id || existing.task_id !== taskId || existing.part_id !== partId)) {
        fail(403, "INVALID_EVIDENCE", "This image is already linked to another operation.")
      }
      if (existing) return jsonResponse({ id: existing.id, object_path: objectPath }, 200, requestId)
      const evidence = assertNoError(await admin.from("restaurant_evidence").insert({
        branch_id: branchId, task_id: taskId, part_id: partId, uploaded_by: user.id,
        object_path: objectPath, mime_type: mimeType, file_size_bytes: size,
      }).select("id, object_path").single())
      return jsonResponse(evidence, 201, requestId)
    }

    fail(400, "INVALID_ACTION", "Unknown operation.")
  } catch (error) {
    logRequestError(ENDPOINT, requestId, error)
    if (error instanceof OpsError) return errorResponse(requestId, error.status, error.code, error.message)
    const message = error instanceof Error ? error.message : "Unexpected server error."
    const mapped = message.match(/TASK_NOT_FOUND|TASK_PART_NOT_FOUND|INCIDENT_NOT_FOUND|BIN_NOT_FOUND|SHIFT_COVER_REQUEST_NOT_FOUND|COLLABORATION_REQUEST_NOT_FOUND|TASK_RECEIPT_NOT_FOUND|INVALID_TASK_TRANSITION|NOT_ON_SHIFT_OR_ON_BREAK|TASK_NOT_ASSIGNED_TO_USER|NO_ELIGIBLE_POSITION|EVIDENCE_REQUIRED|TASK_EVIDENCE_REQUIRED|TASK_EVIDENCE_NOT_REGISTERED|EVIDENCE_NOT_ALLOWED|EVIDENCE_NOT_FOUND|TASK_REPORT_EVIDENCE_NOT_FOUND|RESPONSIBLE_EMPLOYEE_MISMATCH|RESPONSIBLE_EMPLOYEE_NOT_IN_BRANCH|EMPLOYEE_NOT_ON_SHIFT|ACTIVE_TASK_REQUIRES_HANDOFF|MEAL_ALREADY_ACTIVE|MEAL_NOT_ACTIVE|MEAL_ALREADY_TAKEN|MEAL_PLAN_EXPIRED|MEAL_PLAN_NOT_PENDING|MEAL_COVERAGE_INFEASIBLE|NO_MEAL_CANDIDATES|INVALID_MEAL_SCHEDULE|TIMEFOLD_MEAL_PLANNER_UNAVAILABLE|INVALID_TIMEFOLD_MEAL_PLAN|TASK_REPORT_NOT_FOUND|TASK_REPORT_ALREADY_REVIEWED|TASK_NOT_REPORTABLE|TASK_PART_NOT_REPORTABLE|TASK_PART_ALREADY_COMPLETED|INDEPENDENT_REVIEW_REQUIRED|INVALID_REPORT_DECISION|INVALID_DECLARED_COMPLETION_TIME|OPERATIONAL_EVENTS_APPEND_ONLY|CUSTOMER_SERVICE_PRIORITY|INSPECTION_MUST_INCLUDE_EVERY_ACTIVE_BIN|INVALID_BIN_OR_STATE|INVALID_INSPECTION_RESULTS|INVALID_ACTIVITY_CONFIGURATION|INVALID_MEMBER_ROLE|INVALID_EMPLOYEE|INVALID_AREA|INVALID_POSITION|INVALID_ZONES|INVALID_URGENCY|INVALID_ASSIGNEE|BRANCH_ADMIN_REQUIRED|LAST_BRANCH_ADMIN|BRANCH_ACCESS_REQUIRED|INVALID_TIMEZONE|EMPLOYEE_NOT_IN_BRANCH|EMPLOYEE_HAS_ACTIVE_TIME_SESSION|EMPLOYEE_NOT_ACTIVE|EMPLOYEE_ABSENT|TEMPLATE_NOT_FOUND|INVALID_ACTIVITY_TEMPLATE|MANAGER_REQUIRED|TIME_CLOCK_DISABLED|TIME_CLOCK_HAS_ACTIVE_SESSIONS|NO_ACTIVE_TIME_SESSION|ACTIVE_TIME_SESSION|GPS_REQUIRED|INVALID_TIME_EVENT|IDEMPOTENCY_KEY_REUSED|INVALID_SHIFT_BREAK|INVALID_SHIFT|SHIFT_OVERLAP|SHIFT_NOT_AVAILABLE|SHIFT_NOT_OWNED_BY_REQUESTER|SHIFT_ALREADY_STARTED|SHIFT_COVER_ALREADY_PENDING|SHIFT_COVER_REQUEST_NOT_PENDING|INVALID_SHIFT_COVER_DECISION|INVALID_SHIFT_COVER_REPLACEMENT|INVALID_SHIFT_COVER_NOTE|INVALID_ABSENCE|TASK_NOT_ASSIGNED|TASK_ALREADY_COMPLETED|TASK_RECEIPT_NOT_AWAITING|INVALID_RESERVATION|COLLABORATION_REQUEST_NOT_OPEN|TARGET_CANNOT_CLAIM_NOTICE|COLLABORATION_CLAIM_EXPIRED|INVALID_COLLABORATION_RESOLUTION|COLLABORATOR_NOT_AVAILABLE|INVALID_MEAL_DURATION|MEAL_DURATION_NOT_CONFIGURED|INVALID_ANALYSIS_PERIOD|ANALYSIS_PERIOD_TOO_LARGE|INVALID_OPERATIONAL_RECOMMENDATION/)
    if (mapped) {
      const code = mapped[0]
      const status = code.endsWith("_NOT_FOUND") ? 404
        : code === "ANALYSIS_PERIOD_TOO_LARGE" ? 413
        : code.startsWith("INVALID_") || code.startsWith("TASK_EVIDENCE_") || code === "EVIDENCE_REQUIRED" || code === "EVIDENCE_NOT_ALLOWED" || code === "EVIDENCE_NOT_FOUND" || code === "GPS_REQUIRED" || code === "NO_ELIGIBLE_POSITION" ? 400
        : code === "TIME_CLOCK_DISABLED" || code === "TIME_CLOCK_HAS_ACTIVE_SESSIONS" || code === "NO_ACTIVE_TIME_SESSION" || code === "ACTIVE_TIME_SESSION" || code === "IDEMPOTENCY_KEY_REUSED" || code === "LAST_BRANCH_ADMIN" || code === "EMPLOYEE_HAS_ACTIVE_TIME_SESSION" || code.startsWith("SHIFT_COVER_") || (code.startsWith("SHIFT_") && code !== "SHIFT_NOT_OWNED_BY_REQUESTER") || code === "EMPLOYEE_ABSENT" || code === "EMPLOYEE_NOT_ACTIVE" ? 409
        : code.endsWith("_REQUIRED") || code === "TASK_NOT_ASSIGNED_TO_USER" || code === "RESPONSIBLE_EMPLOYEE_MISMATCH" || code === "SHIFT_NOT_OWNED_BY_REQUESTER" ? 403
        : code === "SHIFT_OVERLAP" ? 409
        : 409
      const friendlyMessage = code === "LAST_BRANCH_ADMIN"
        ? "No se puede desactivar al último administrador activo de la sucursal."
        : code === "EMPLOYEE_HAS_ACTIVE_TIME_SESSION"
          ? "La persona debe registrar su salida antes de desactivar su acceso a la sucursal."
          : code === "BRANCH_ADMIN_REQUIRED"
            ? "Solo un administrador de la sucursal puede asignar permisos de administrador o modificar a otro administrador."
          : code === "INVALID_EMPLOYEE"
            ? "Elige una cuenta activa de la empresa para agregarla a esta sucursal."
          : code === "SHIFT_COVER_ALREADY_PENDING"
            ? "Este turno ya tiene una solicitud de cobertura pendiente."
          : code === "SHIFT_ALREADY_STARTED"
            ? "No se puede solicitar cobertura para un turno que ya comenzó."
          : code === "SHIFT_NOT_AVAILABLE"
            ? "Este turno ya no está publicado o fue modificado. Actualiza la pantalla."
          : code === "EMPLOYEE_ABSENT"
            ? "La persona elegida tiene una ausencia aprobada en esa fecha."
          : code === "SHIFT_OVERLAP"
            ? "La persona elegida ya tiene otro turno que se traslapa."
          : code.replaceAll("_", " ").toLowerCase()
      return errorResponse(requestId, status, code, friendlyMessage)
    }
    console.error("restaurant_ops error", { request_id: requestId, message })
    return errorResponse(requestId, 500, "INTERNAL_ERROR", "The operation could not be saved. Try again.")
  }
})

function urlFrom(request: Request): URL {
  return new URL(request.url)
}
