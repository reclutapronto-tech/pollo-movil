# Photos And Ops Stabilization Design

## Goal

Stabilize the supervisor-facing operations pages that are intermittently failing to load, and redesign the photo experience so `/photos` works as a project browser with in-page `Feed`, `Timeline`, and `Map` views instead of routing to unrelated pages.

## Observed Context

- [`/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/app/photos/page.tsx`](/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/app/photos/page.tsx) currently requires a `job_id` query param and shows a dropdown-based project picker.
- The same page links `Timeline` to [`/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/app/timeline/page.tsx`](/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/app/timeline/page.tsx) and `Map` to [`/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/app/map/page.tsx`](/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/app/map/page.tsx), which breaks the intended photo workflow.
- [`/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/app/overtime/page.tsx`](/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/app/overtime/page.tsx) lists records by querying `ot_requests` directly, while decisions go through the [`/Users/seancheick/FieldsOps_ai/infra/supabase/functions/ot/index.ts`](/Users/seancheick/FieldsOps_ai/infra/supabase/functions/ot/index.ts) edge function.
- [`/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/app/expenses/page.tsx`](/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/app/expenses/page.tsx), [`/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/app/pto/page.tsx`](/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/app/pto/page.tsx), and [`/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/app/cost-codes/page.tsx`](/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/app/cost-codes/page.tsx) each implement their own session/token/fetch/error pattern.
- [`/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/lib/i18n.tsx`](/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/lib/i18n.tsx) only supports `en` and `es`.

## Decision Summary

Use a focused two-part change:

1. Standardize the operational data pages on a single function-backed fetch pattern with clearer failure states.
2. Rebuild `/photos` into a two-stage experience:
   - stage 1: project browser with folder-like list/icon views
   - stage 2: project workspace with in-page `Feed`, `Timeline`, and `Map` tabs

This avoids a larger navigation rewrite while fixing the specific product and UX issues that were reported.

## Architecture

### 1. Operations Page Stabilization

Introduce a small client utility for authenticated edge-function requests in the web app. The helper will:

- get the current session token
- make the request with the correct authorization headers
- parse JSON safely
- throw normalized errors with backend messages when present

Apply this to:

- `/expenses`
- `/cost-codes`
- `/pto`
- `/overtime`

For overtime specifically, switch list loading from direct table access to the existing `GET /functions/v1/ot` endpoint so listing and mutation both use the same authorization and company-scoping path.

### 2. Photo Information Architecture

`/photos` without a selected project becomes a browser page rather than an error state.

The page will show:

- header and subtitle
- project search
- list/icon view toggle
- project cards/rows styled like folders rather than a plain form select

Each project item will display:

- project name
- project code
- status
- last photo activity if available
- photo count if available

Selecting a project keeps the user on `/photos?job_id=<id>`.

### 3. Photo Workspace Tabs

Inside a selected project, `/photos` stays the single route and switches views with a local tab state:

- `Feed`: existing grid/table, filters, proof export, lightbox
- `Timeline`: chronological grouping of photo-related events for the selected project, rendered in-page
- `Map`: map of photo locations for the selected project, rendered in-page and scoped to photo data rather than live worker positions

The existing `/timeline` and `/map` routes remain for broader app navigation, but the photo workflow no longer routes to them from the photo page tabs.

## Component Boundaries

To avoid keeping all of this logic in one oversized page file, the photo experience should be split into focused pieces:

- project browser section
- project workspace header and tab state
- feed panel
- timeline panel
- map panel
- shared photo/project data helpers

The split should follow the existing app structure and only extract pieces that materially reduce complexity in [`/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/app/photos/page.tsx`](/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/app/photos/page.tsx).

## Error Handling

Operations pages should distinguish:

- missing session
- backend validation/authorization errors
- empty result sets
- network/runtime failures

Photo page states should distinguish:

- no project selected
- no projects available
- selected project with no photos
- project data failed to load

Retry actions should call the same normalized loader instead of duplicating fetch logic per page.

## Localization

Add `th` to the locale union and language picker.

First-pass Thai coverage must include:

- shell navigation
- common actions and errors
- the new photo-browser labels

Existing deep page strings that are not touched by this feature may remain in English for now if needed, but the language option itself must be functional and safe.

## Testing

Add focused regression coverage for:

- authenticated function fetch helper behavior
- OT page consuming the function response shape
- photo page project-browser empty and selected states
- locale union including Thai

Verification should also include targeted app builds/linting for the touched web app files.

## Out Of Scope

- Stripe billing setup
- company ownership/permissions redesign
- replacing the standalone live map or timeline routes globally
- a full navigation IA overhaul across the whole product
