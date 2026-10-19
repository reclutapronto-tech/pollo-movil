type BranchOption = { id: string };

const BRANCH_STORAGE_KEY = "pollo-movil:selected-branch:v1";

export function preferredRestaurantBranchId(
  branches: readonly BranchOption[],
): string {
  if (typeof window !== "undefined") {
    try {
      const saved = window.localStorage.getItem(BRANCH_STORAGE_KEY);
      if (saved && branches.some((branch) => branch.id === saved)) return saved;
    } catch {
      // Storage may be unavailable in private browsing; use the first branch.
    }
  }
  return branches[0]?.id ?? "";
}

export function rememberRestaurantBranchId(branchId: string): void {
  if (!branchId || typeof window === "undefined") return;
  try {
    window.localStorage.setItem(BRANCH_STORAGE_KEY, branchId);
  } catch {
    // Branch selection remains usable for this page even if storage is blocked.
  }
}
