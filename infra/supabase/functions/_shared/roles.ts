export const OWNER_ROLE = "owner"
export const ADMIN_ROLE = "admin"
export const SUPERVISOR_ROLE = "supervisor"
export const FOREMAN_ROLE = "foreman"
export const WORKER_ROLE = "worker"

export const MANAGEMENT_ROLES = [OWNER_ROLE, ADMIN_ROLE] as const

// True supervisor tier — money / payroll / company-wide actions.
// Deliberately EXCLUDES foreman: budgets, timecards, expenses, reports,
// alerts, galleries, permits are supervisor+ in the web UI and in every
// error message. (Before 2026-07 this array wrongly included foreman,
// which silently granted crew leads payroll + expense approval powers.)
export const SUPERVISOR_AND_ABOVE_ROLES = [
  OWNER_ROLE,
  ADMIN_ROLE,
  SUPERVISOR_ROLE,
] as const

// Crew-lead tier — actions a foreman legitimately performs for their crew:
// OT + PTO approvals, time-correction decisions, crew schedule writes,
// crew attendance reads. Mobile foreman home wires screens to all of these.
export const FOREMAN_AND_ABOVE_ROLES = [
  OWNER_ROLE,
  ADMIN_ROLE,
  SUPERVISOR_ROLE,
  FOREMAN_ROLE,
] as const

export function isManagementRole(role: string | null | undefined): boolean {
  return !!role && MANAGEMENT_ROLES.includes(role as (typeof MANAGEMENT_ROLES)[number])
}

export function isSupervisorOrAbove(role: string | null | undefined): boolean {
  return !!role && SUPERVISOR_AND_ABOVE_ROLES.includes(role as (typeof SUPERVISOR_AND_ABOVE_ROLES)[number])
}

export function isForemanOrAbove(role: string | null | undefined): boolean {
  return !!role && FOREMAN_AND_ABOVE_ROLES.includes(role as (typeof FOREMAN_AND_ABOVE_ROLES)[number])
}
