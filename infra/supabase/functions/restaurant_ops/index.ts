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

async function getBranches(admin: SupabaseClient, userId: string) {
  const memberships = assertNoError(await admin.from("restaurant_memberships")
    .select("branch_id, access_role").eq("user_id", userId).eq("is_active", true)) ?? []
  const ids = memberships.map((row: { branch_id: string }) => row.branch_id)
  if (ids.length === 0) return []
  const branches = assertNoError(await admin.from("restaurant_branches")
    .select("id, company_id, name, timezone, is_active, enable_time_clock, require_gps_for_time_clock").in("id", ids).eq("is_active", true)) ?? []
  return branches.map((branch: Record<string, unknown>) => ({
    ...branch,
    access_role: memberships.find((item: { branch_id: string }) => item.branch_id === branch.id)?.access_role,
  }))
}

async function getSettings(admin: SupabaseClient, branchId: string, companyId: string, requestedShiftStart?: string | null) {
  const branch = assertNoError(await admin.from("restaurant_branches")
    .select("id, name, timezone, company_id, enable_time_clock, require_gps_for_time_clock, assignment_load_balance_weight, assignment_heavy_rotation_weight, assignment_priority_weight").eq("id", branchId).single())
  const localDate = dateInZone(branch.timezone)
  const requestedDate = requestedShiftStart && /^\d{4}-\d{2}-\d{2}$/.test(requestedShiftStart)
    ? new Date(`${requestedShiftStart}T00:00:00.000Z`) : null
  const shiftStart = typeof requestedShiftStart === "string" && requestedDate && Number.isFinite(requestedDate.getTime())
    && requestedDate.toISOString().slice(0, 10) === requestedShiftStart ? requestedShiftStart : localDate
  const shiftEnd = addDays(shiftStart, 6)
  const [areas, positions, templates, templatePositions, zones, memberships, users, shifts, breaks, absences, bins, memberPositions, wastePositions, inspectionTemplates, inspectionItems, scheduledTasks] = await Promise.all([
    admin.from("restaurant_areas").select("id, name, sort_order, is_active").eq("branch_id", branchId).order("sort_order"),
    admin.from("restaurant_positions").select("id, name, is_active").eq("branch_id", branchId).order("name"),
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
    .select("id, name, timezone, enable_time_clock, require_gps_for_time_clock").eq("id", branchId).single())
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
  const tasksForClient = data.tasks.map((task: Record<string, unknown>) => {
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
    incidents: data.incidents.map((incident: Record<string, unknown>) => ({
      ...incident,
      assignee_name: userById.get(incident.assigned_to) ?? null,
      area_name: data.areas.find((area: Record<string, unknown>) => area.id === incident.area_id)?.name ?? null,
    })),
    members: data.members.map((member: Record<string, unknown>) => ({
      ...member, user_name: userById.get(member.user_id) ?? null,
    })),
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
    return {
      id: String(membership.user_id),
      positionIds: data.memberPositions.filter((row: Record<string, string>) => row.user_id === membership.user_id).map((row: Record<string, string>) => row.position_id),
      onShift: isToday ? Boolean(activeShift) : futureShiftCapacity > 0,
      onBreak: isToday && onBreak,
      absent,
      servingCustomers: isToday && Boolean(membership.customer_service_active),
      capacityMinutes: isToday
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
          admin.from("restaurant_positions").select("id, name").eq("branch_id", branchId)
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
          admin.from("restaurant_positions").select("id, name, is_active")
            .eq("branch_id", branchId).order("name"),
          admin.from("restaurant_branches").select("enable_time_clock, require_gps_for_time_clock")
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
    const managerOnly = ["auto_assign", "assign_task", "assign_task_part", "reschedule_task", "save_area", "save_position", "save_member", "invite_member", "set_member_active", "save_member_positions", "save_waste_positions", "save_bin", "save_template", "save_inspection_template", "save_shift", "cancel_shift", "save_absence", "review_absence", "review_shift_cover_request", "save_branch_features", "save_assignment_policy", "update_incident", "schedule_tasks", "create_task"].includes(action)
    const membership = await memberForBranch(admin, branchId, user.id, managerOnly)

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
      const enableTimeClock = payload.enable_time_clock === true
      const requireGps = enableTimeClock && payload.require_gps_for_time_clock === true
      const currentBranch = assertNoError(await admin.from("restaurant_branches")
        .select("name, timezone").eq("id", branchId).single())
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
      if (!enableTimeClock) {
        const activeSessions = assertNoError(await admin.from("restaurant_time_sessions")
          .select("id").eq("branch_id", branchId).is("clock_out_at", null).limit(1)) ?? []
        if (activeSessions.length) fail(409, "TIME_CLOCK_HAS_ACTIVE_SESSIONS", "Registra la salida de las sesiones activas antes de apagar el checador.")
      }
      assertNoError(await admin.from("restaurant_branches").update({
        name: branchName.trim(), timezone, enable_time_clock: enableTimeClock, require_gps_for_time_clock: requireGps,
      }).eq("id", branchId).select("id").single())
      return jsonResponse({ name: branchName.trim(), timezone, enable_time_clock: enableTimeClock, require_gps_for_time_clock: requireGps }, 200, requestId)
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
      const row = { branch_id: branchId, name, is_active: payload.is_active !== false }
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
        requires_evidence: Boolean(payload.requires_evidence), is_active: payload.is_active !== false,
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
      const task = assertNoError(await admin.from("restaurant_tasks").select("id, requires_evidence, assigned_to")
        .eq("id", taskId).eq("branch_id", branchId).maybeSingle())
      if (!task?.requires_evidence) fail(400, "EVIDENCE_NOT_REQUIRED", "This task does not request evidence.")
      const part = partId ? assertNoError(await admin.from("restaurant_task_parts").select("id, assigned_to")
        .eq("id", partId).eq("task_id", taskId).eq("branch_id", branchId).maybeSingle()) : null
      if (task.assigned_to !== user.id && part?.assigned_to !== user.id && !["admin", "supervisor"].includes(membership.access_role)) {
        fail(403, "TASK_NOT_ASSIGNED_TO_USER", "Evidence can only be attached by the assigned worker or a supervisor.")
      }
      const objectPath = `${branchId}/${taskId}/${crypto.randomUUID()}`
      const signed = assertNoError(await admin.storage.from("restaurant-evidence").createSignedUploadUrl(objectPath))
      return jsonResponse({ object_path: objectPath, token: signed.token, signed_url: signed.signedUrl, mime_type: mimeType, file_size_bytes: size, part_id: partId }, 201, requestId)
    }

    if (action === "register_evidence") {
      const taskId = requiredUuid(payload.task_id, "task_id")
      const partId = payload.part_id ? requiredUuid(payload.part_id, "part_id") : null
      const objectPath = requiredString(payload.object_path, "object_path", 500)
      if (!objectPath.startsWith(`${branchId}/${taskId}/`)) fail(400, "INVALID_EVIDENCE", "Evidence path does not match this branch and task.")
      const task = assertNoError(await admin.from("restaurant_tasks").select("id, assigned_to")
        .eq("id", taskId).eq("branch_id", branchId).maybeSingle())
      const part = partId ? assertNoError(await admin.from("restaurant_task_parts").select("id, assigned_to")
        .eq("id", partId).eq("task_id", taskId).eq("branch_id", branchId).maybeSingle()) : null
      if (!task || (task.assigned_to !== user.id && part?.assigned_to !== user.id && !["admin", "supervisor"].includes(membership.access_role))) {
        fail(403, "TASK_NOT_ASSIGNED_TO_USER", "Evidence can only be attached by the assigned worker or a supervisor.")
      }
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
    const mapped = message.match(/TASK_NOT_FOUND|TASK_PART_NOT_FOUND|INCIDENT_NOT_FOUND|BIN_NOT_FOUND|SHIFT_COVER_REQUEST_NOT_FOUND|INVALID_TASK_TRANSITION|NOT_ON_SHIFT_OR_ON_BREAK|TASK_NOT_ASSIGNED_TO_USER|NO_ELIGIBLE_POSITION|EVIDENCE_REQUIRED|CUSTOMER_SERVICE_PRIORITY|INSPECTION_MUST_INCLUDE_EVERY_ACTIVE_BIN|INVALID_BIN_OR_STATE|INVALID_INSPECTION_RESULTS|INVALID_ACTIVITY_CONFIGURATION|INVALID_MEMBER_ROLE|INVALID_EMPLOYEE|INVALID_AREA|INVALID_POSITION|INVALID_ZONES|INVALID_URGENCY|INVALID_ASSIGNEE|BRANCH_ADMIN_REQUIRED|LAST_BRANCH_ADMIN|BRANCH_ACCESS_REQUIRED|INVALID_TIMEZONE|EMPLOYEE_NOT_IN_BRANCH|EMPLOYEE_HAS_ACTIVE_TIME_SESSION|EMPLOYEE_NOT_ACTIVE|EMPLOYEE_ABSENT|TEMPLATE_NOT_FOUND|INVALID_ACTIVITY_TEMPLATE|MANAGER_REQUIRED|TIME_CLOCK_DISABLED|TIME_CLOCK_HAS_ACTIVE_SESSIONS|NO_ACTIVE_TIME_SESSION|ACTIVE_TIME_SESSION|GPS_REQUIRED|INVALID_TIME_EVENT|IDEMPOTENCY_KEY_REUSED|INVALID_SHIFT_BREAK|INVALID_SHIFT|SHIFT_OVERLAP|SHIFT_NOT_AVAILABLE|SHIFT_NOT_OWNED_BY_REQUESTER|SHIFT_ALREADY_STARTED|SHIFT_COVER_ALREADY_PENDING|SHIFT_COVER_REQUEST_NOT_PENDING|INVALID_SHIFT_COVER_DECISION|INVALID_SHIFT_COVER_REPLACEMENT|INVALID_SHIFT_COVER_NOTE|INVALID_ABSENCE/)
    if (mapped) {
      const code = mapped[0]
      const status = code.endsWith("_NOT_FOUND") ? 404
        : code.startsWith("INVALID_") || code === "GPS_REQUIRED" || code === "NO_ELIGIBLE_POSITION" ? 400
        : code === "TIME_CLOCK_DISABLED" || code === "TIME_CLOCK_HAS_ACTIVE_SESSIONS" || code === "NO_ACTIVE_TIME_SESSION" || code === "ACTIVE_TIME_SESSION" || code === "IDEMPOTENCY_KEY_REUSED" || code === "LAST_BRANCH_ADMIN" || code === "EMPLOYEE_HAS_ACTIVE_TIME_SESSION" || code.startsWith("SHIFT_COVER_") || (code.startsWith("SHIFT_") && code !== "SHIFT_NOT_OWNED_BY_REQUESTER") || code === "EMPLOYEE_ABSENT" || code === "EMPLOYEE_NOT_ACTIVE" ? 409
        : code.endsWith("_REQUIRED") || code === "TASK_NOT_ASSIGNED_TO_USER" || code === "SHIFT_NOT_OWNED_BY_REQUESTER" ? 403
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
