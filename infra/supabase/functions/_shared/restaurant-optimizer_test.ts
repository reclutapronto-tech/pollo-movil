import { planRestaurantAssignments, type AssignmentCandidate, type AssignmentUnit } from "./restaurant-optimizer.ts"

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message)
}

function unit(overrides: Partial<AssignmentUnit> = {}): AssignmentUnit {
  return {
    id: "task-1",
    groupId: "task-1",
    requiredPositionIds: ["floor"],
    estimatedMinutes: 20,
    difficulty: 2,
    priority: 3,
    interruptible: true,
    ...overrides,
  }
}

function candidate(overrides: Partial<AssignmentCandidate> = {}): AssignmentCandidate {
  return {
    id: "worker-1",
    positionIds: ["floor"],
    onShift: true,
    onBreak: false,
    absent: false,
    servingCustomers: false,
    capacityMinutes: 240,
    assignedWeightedMinutes: 0,
    recentHeavyTasks: 0,
    ...overrides,
  }
}

Deno.test("hard eligibility leaves a task unassigned when nobody is qualified and on shift", () => {
  const plan = planRestaurantAssignments(
    [unit()],
    [
      candidate({ id: "wrong-position", positionIds: ["cashier"] }),
      candidate({ id: "on-break", onBreak: true }),
      candidate({ id: "absent", absent: true }),
      candidate({ id: "off-shift", onShift: false }),
    ],
  )

  assert(plan.assignments.length === 0, "ineligible candidates must not receive the task")
  assert(plan.unassignedUnitIds[0] === "task-1", "the task must remain visibly unassigned")
})

Deno.test("load balancing accounts for estimated duration and difficulty, not task count", () => {
  const plan = planRestaurantAssignments(
    [unit()],
    [
      candidate({ id: "more-count-but-lighter", assignedWeightedMinutes: 10 }),
      candidate({ id: "less-count-but-heavier", assignedWeightedMinutes: 190 }),
    ],
  )

  assert(plan.assignments[0]?.candidateId === "more-count-but-lighter", "weighted workload should decide fairness")
})

Deno.test("recent heavy assignments rotate difficult work when weighted load is otherwise close", () => {
  const plan = planRestaurantAssignments(
    [unit({ difficulty: 5, estimatedMinutes: 40 })],
    [
      candidate({ id: "recent-heavy", assignedWeightedMinutes: 100, recentHeavyTasks: 2 }),
      candidate({ id: "rested", assignedWeightedMinutes: 100, recentHeavyTasks: 0 }),
    ],
  )

  assert(plan.assignments[0]?.candidateId === "rested", "heavy work should rotate across eligible staff")
})

Deno.test("branch priority weight controls whether urgency or effort orders assignments", () => {
  const plan = planRestaurantAssignments(
    [
      unit({ id: "urgent-short", groupId: "urgent-short", priority: 5, estimatedMinutes: 10 }),
      unit({ id: "routine-heavy", groupId: "routine-heavy", priority: 1, estimatedMinutes: 240, difficulty: 5 }),
    ],
    [candidate({ capacityMinutes: 600 })],
    { loadBalanceWeight: 0, heavyRotationWeight: 0, priorityWeight: 0 },
  )

  assert(
    plan.assignments[0]?.unitId === "routine-heavy",
    "zero priority weight should let estimated effort determine assignment order",
  )
})

Deno.test("split zones avoid assigning two parts of the same task to one person", () => {
  const plan = planRestaurantAssignments(
    [
      unit({ id: "zone-a", groupId: "split-task", priority: 4 }),
      unit({ id: "zone-b", groupId: "split-task", priority: 4 }),
    ],
    [candidate({ id: "worker-a" }), candidate({ id: "worker-b" })],
  )

  assert(plan.assignments.length === 2, "both qualified zones should be assigned")
  assert(plan.assignments[0]?.candidateId !== plan.assignments[1]?.candidateId, "split zones should have separate owners")
})

Deno.test("customer service takes precedence over interruptible work", () => {
  const plan = planRestaurantAssignments(
    [unit()],
    [candidate({ id: "serving", servingCustomers: true })],
  )

  assert(plan.unassignedUnitIds[0] === "task-1", "interruptible tasks should wait while staff serve customers")
})
