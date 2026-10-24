# Pollo Móvil assignment optimizer

This private Quarkus sidecar applies Timefold Solver to the assignment plan assembled by the `restaurant_ops` Edge Function. The Edge Function remains authoritative: it sends only task/candidate IDs, position IDs, and scheduling attributes, then validates every returned assignment before writing it to Supabase. If the service is absent, times out, or returns an invalid result, the existing in-process planner is used.

The service is local-development infrastructure, not a production deployment. Its host port is bound to `127.0.0.1:8088`; the Edge Function reaches it over the existing `pollo-movil-local` Docker network at `http://timefold:8080`.

## Local wiring

1. Start the Supabase local stack on the `pollo-movil-local` Docker network.
2. Run `scripts/configure-timefold-local.ps1` from the repository root. It creates a cryptographically random shared token when needed and writes it to the two ignored local environment files without displaying it. It refuses to change a non-local service URL or reconcile mismatched existing tokens.
3. Restart the local Supabase stack after changing Edge Function environment values so the function runtime receives them.
4. From this directory, start the sidecar with `docker compose up -d --build`.

Do not commit either `.env` file or put the token in source control. The setup script preserves unrelated settings and never prints secret values.

The `/api/assignments/solve` endpoint enforces task eligibility, remaining shift capacity, and one employee per divided-task group. It prioritizes assignment coverage, balances weighted workload, and rotates heavy tasks using per-branch weights. Task assignment has an explicit TypeScript fallback in the Edge Function and logs its reason.

The `/api/meal-plans/solve` endpoint uses a separate named Timefold solver. It enforces published shift boundaries, configured break windows, and non-overlapping meals, with a soft preference for each worker's shift midpoint. The Edge Function also blocks starts that violate configured per-area minimum headcount at any point in a meal, then validates the returned worker set and windows again before persisting a proposal. A missing/unavailable meal solver produces an error; it does not silently substitute the task planner or create a fabricated proposal. Managers must approve a proposal; approval does not start a meal.

The meal planner is deliberately conservative: meals run one at a time, and task time windows/customer demand are not yet modeled because the versioned schema has no approved time-window field or trusted demand feed. It must not be described as a demand-optimized meal schedule. GPS and time-clock settings are not part of either solver input. Both endpoints reject unauthenticated solve requests.

The domain follows the official [Timefold task-assignment quickstart](https://github.com/TimefoldAI/timefold-quickstarts/tree/stable/use-cases/task-assigning) and the [Quarkus integration guide](https://docs.timefold.ai/timefold-solver/latest/quickstart/quarkus/quarkus-quickstart). Keep this service on an internal network and use a randomly generated shared token whenever enabling the sidecar.
