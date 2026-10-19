export type AssignmentUnit = {
  id: string
  groupId: string
  requiredPositionIds: string[]
  estimatedMinutes: number
  difficulty: number
  priority: number
  interruptible: boolean
}

export type AssignmentCandidate = {
  id: string
  positionIds: string[]
  onShift: boolean
  onBreak: boolean
  absent: boolean
  servingCustomers: boolean
  capacityMinutes: number
  assignedWeightedMinutes: number
  recentHeavyTasks: number
  rotationRank?: number
}

export type AssignmentPlan = {
  assignments: Array<{ unitId: string; candidateId: string }>
  unassignedUnitIds: string[]
}

export type AssignmentPolicy = {
  loadBalanceWeight: number
  heavyRotationWeight: number
  priorityWeight: number
}

export const DEFAULT_ASSIGNMENT_POLICY: AssignmentPolicy = {
  loadBalanceWeight: 100,
  heavyRotationWeight: 60,
  priorityWeight: 100,
}

export function eligibleForUnit(
  unit: AssignmentUnit,
  candidate: AssignmentCandidate,
): boolean {
  if (!candidate.onShift || candidate.onBreak || candidate.absent) return false
  if (unit.requiredPositionIds.length === 0) return false
  if (!unit.requiredPositionIds.some((positionId) => candidate.positionIds.includes(positionId))) {
    return false
  }
  if (unit.interruptible && candidate.servingCustomers) return false
  return candidate.capacityMinutes >= unit.estimatedMinutes
}

/**
 * A conservative greedy assignment pass. Hard eligibility is checked before
 * scoring. The soft score uses branch-configured workload and rotation weights.
 * Missing eligibility data produces an unassigned task rather than a guess.
 */
export function planRestaurantAssignments(
  units: AssignmentUnit[],
  candidates: AssignmentCandidate[],
  policy: AssignmentPolicy = DEFAULT_ASSIGNMENT_POLICY,
): AssignmentPlan {
  const workload = new Map(candidates.map((candidate) => [candidate.id, {
    weightedMinutes: candidate.assignedWeightedMinutes,
    capacityMinutes: candidate.capacityMinutes,
    recentHeavyTasks: candidate.recentHeavyTasks,
  }]));
  const assignedByGroup = new Map<string, Set<string>>();
  const assignments: AssignmentPlan["assignments"] = [];
  const unassignedUnitIds: string[] = [];

  // Mix branch urgency with estimated effort so the fallback still honors a
  // zero priority weight instead of treating every priority as identical.
  const assignmentOrderScore = (unit: AssignmentUnit) =>
    unit.priority * policy.priorityWeight +
    (unit.estimatedMinutes * unit.difficulty) / 60
  const orderedUnits = [...units].sort((left, right) =>
    assignmentOrderScore(right) - assignmentOrderScore(left) ||
    left.id.localeCompare(right.id)
  );

  for (const unit of orderedUnits) {
    const alreadyAssigned = assignedByGroup.get(unit.groupId) ?? new Set<string>();
    const options = candidates
      .filter((candidate) => {
        const load = workload.get(candidate.id)!;
        return !alreadyAssigned.has(candidate.id) &&
          load.capacityMinutes >= unit.estimatedMinutes &&
          eligibleForUnit(unit, { ...candidate, capacityMinutes: load.capacityMinutes });
      })
      .map((candidate) => {
        const load = workload.get(candidate.id)!;
        const addedWeight = unit.estimatedMinutes * unit.difficulty;
        const capacity = Math.max(load.capacityMinutes, 1);
        // A recent heavy assignment adds one bounded rotation penalty; extra
        // heavy tasks do not compound it.
        const rotationPenalty = load.recentHeavyTasks > 0
          ? policy.heavyRotationWeight
          : 0
        const score = ((load.weightedMinutes + addedWeight) / capacity) * policy.loadBalanceWeight / 100 +
          rotationPenalty / capacity +
          (candidate.servingCustomers ? 0.05 : 0);
        return { candidate, score };
      })
      .sort((left, right) => left.score - right.score ||
        (left.candidate.rotationRank ?? 0) - (right.candidate.rotationRank ?? 0) ||
        left.candidate.id.localeCompare(right.candidate.id));

    const selected = options[0]?.candidate;
    if (!selected) {
      unassignedUnitIds.push(unit.id);
      continue;
    }

    assignments.push({ unitId: unit.id, candidateId: selected.id });
    alreadyAssigned.add(selected.id);
    assignedByGroup.set(unit.groupId, alreadyAssigned);
    const load = workload.get(selected.id)!;
    load.weightedMinutes += unit.estimatedMinutes * unit.difficulty;
    load.capacityMinutes -= unit.estimatedMinutes;
    if (unit.difficulty >= 4) load.recentHeavyTasks += 1;
  }

  return { assignments, unassignedUnitIds };
}
