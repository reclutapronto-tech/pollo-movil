import {
  eligibleForUnit,
  type AssignmentCandidate,
  type AssignmentPolicy,
  type AssignmentPlan,
  type AssignmentUnit,
} from "./restaurant-optimizer.ts"

type TimefoldAssignmentResponse = {
  assignments?: unknown
}

export type TimefoldAssignmentAttempt = {
  plan: AssignmentPlan | null
  fallbackReason: string | null
  httpStatus?: number
}

const SOLVER_REQUEST_TIMEOUT_MS = 5_000

/** Calls the private Timefold service and rejects any unsafe plan. */
export async function tryTimefoldAssignmentPlan(
  units: AssignmentUnit[],
  candidates: AssignmentCandidate[],
  policy: AssignmentPolicy,
  endpoint: string | undefined,
  token: string | undefined,
): Promise<TimefoldAssignmentAttempt> {
  if (units.length === 0) return { plan: null, fallbackReason: null }
  if (!endpoint || !token) {
    return { plan: null, fallbackReason: "service_not_configured" }
  }
  if (units.length > 500 || candidates.length > 200) {
    return { plan: null, fallbackReason: "request_limit_exceeded" }
  }

  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), SOLVER_REQUEST_TIMEOUT_MS)
  try {
    const headers: Record<string, string> = { "Content-Type": "application/json" }
    headers.Authorization = `Bearer ${token}`
    const response = await fetch(endpoint, {
      method: "POST",
      headers,
      body: JSON.stringify({ candidates, units, weights: policy }),
      signal: controller.signal,
    })
    if (!response.ok) {
      return {
        plan: null,
        fallbackReason: "http_error",
        httpStatus: response.status,
      }
    }

    const result = await response.json() as TimefoldAssignmentResponse
    const assignments = parseAndValidateAssignments(result.assignments, units, candidates)
    if (!assignments) {
      return { plan: null, fallbackReason: "invalid_plan" }
    }

    const assignedUnitIds = new Set(assignments.map((assignment) => assignment.unitId))
    return {
      plan: {
        assignments,
        unassignedUnitIds: units.filter((unit) => !assignedUnitIds.has(unit.id)).map((unit) => unit.id),
      },
      fallbackReason: null,
    }
  } catch (error) {
    return {
      plan: null,
      fallbackReason: error instanceof Error && error.name === "AbortError"
        ? "timeout"
        : "request_failed",
    }
  } finally {
    clearTimeout(timeout)
  }
}

function parseAndValidateAssignments(
  value: unknown,
  units: AssignmentUnit[],
  candidates: AssignmentCandidate[],
): AssignmentPlan["assignments"] | null {
  if (!Array.isArray(value)) return null

  const unitById = new Map(units.map((unit) => [unit.id, unit]))
  const candidateById = new Map(candidates.map((candidate) => [candidate.id, candidate]))
  const remainingCapacity = new Map(candidates.map((candidate) => [candidate.id, candidate.capacityMinutes]))
  const assignedByGroup = new Map<string, Set<string>>()
  const seenUnits = new Set<string>()
  const assignments: AssignmentPlan["assignments"] = []

  for (const raw of value) {
    if (typeof raw !== "object" || raw === null) return null
    const unitId = "unitId" in raw ? raw.unitId : undefined
    const candidateId = "candidateId" in raw ? raw.candidateId : undefined
    if (typeof unitId !== "string" || typeof candidateId !== "string" || seenUnits.has(unitId)) return null

    const unit = unitById.get(unitId)
    const candidate = candidateById.get(candidateId)
    const capacityMinutes = remainingCapacity.get(candidateId)
    if (!unit || !candidate || capacityMinutes === undefined) return null

    const assignedForGroup = assignedByGroup.get(unit.groupId) ?? new Set<string>()
    const capacityAdjustedCandidate = { ...candidate, capacityMinutes }
    if (assignedForGroup.has(candidate.id) || !eligibleForUnit(unit, capacityAdjustedCandidate)) return null

    assignedForGroup.add(candidate.id)
    assignedByGroup.set(unit.groupId, assignedForGroup)
    remainingCapacity.set(candidate.id, capacityMinutes - unit.estimatedMinutes)
    seenUnits.add(unitId)
    assignments.push({ unitId, candidateId })
  }

  return assignments
}
