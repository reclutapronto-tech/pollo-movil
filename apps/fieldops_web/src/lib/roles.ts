export const OWNER_ROLE = "owner";
export const ADMIN_ROLE = "admin";
export const SUPERVISOR_ROLE = "supervisor";
export const FOREMAN_ROLE = "foreman";
export const WORKER_ROLE = "worker";

export const MANAGEMENT_ROLES = [OWNER_ROLE, ADMIN_ROLE] as const;
export const SUPERVISOR_AND_ABOVE_ROLES = [OWNER_ROLE, ADMIN_ROLE, SUPERVISOR_ROLE] as const;

export function isManagementRole(role: string | null | undefined): boolean {
  return !!role && MANAGEMENT_ROLES.includes(role as (typeof MANAGEMENT_ROLES)[number]);
}

export function isOwnerRole(role: string | null | undefined): boolean {
  return role === OWNER_ROLE;
}

export function isSupervisorOrAbove(role: string | null | undefined): boolean {
  return (
    !!role &&
    SUPERVISOR_AND_ABOVE_ROLES.includes(
      role as (typeof SUPERVISOR_AND_ABOVE_ROLES)[number],
    )
  );
}
