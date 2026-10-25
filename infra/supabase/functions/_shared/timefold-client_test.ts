import { tryTimefoldAssignmentPlan } from "./timefold-client.ts"

Deno.test("reports an explicit fallback reason when Timefold is not configured", async () => {
  const attempt = await tryTimefoldAssignmentPlan(
    [{
      id: "ci-task",
      groupId: "ci-task",
      requiredPositionIds: ["cook"],
      estimatedMinutes: 10,
      difficulty: 2,
      priority: 3,
      interruptible: true,
    }],
    [],
    { loadBalanceWeight: 100, heavyRotationWeight: 60, priorityWeight: 100 },
    undefined,
    undefined,
  )

  if (attempt.plan !== null) throw new Error("An unconfigured remote solver must not return a plan.")
  if (attempt.fallbackReason !== "service_not_configured") {
    throw new Error("The fallback reason must be visible to the caller.")
  }
})
