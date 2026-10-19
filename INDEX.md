---
title: FieldOps AI — Vault Index
tags:
  - index
  - moc
aliases:
  - Home
  - MOC
---

# FieldOps AI — Vault Index

> [!abstract] This is the central hub for all FieldOps project documentation.
> Open any linked doc to navigate deeper. All docs use `[[wikilinks]]` for cross-referencing.

---

## Product

| Doc | Purpose |
|-----|---------|
| [[PRD]] | Product requirements, pillars, and MVP scope |
| [[ROADMAP]] | Master plan from Step 0 to Step 10 |
| [[architecture]] | Tech stack, system design, and infrastructure |
| [[DATA_MODEL]] | Database schema, events, and RLS model |
| [[OPENAPI]] | API contract documentation |
| [[FieldOps_AI_Complete_Plan_2026_v5]] | Complete product plan with competitor analysis |

---

## Execution

| Doc | Purpose |
|-----|---------|
| [[SPRINT_TRACKER]] | Current sprint status — mirrors Notion board |
| [[LESSONS_LEARNED]] | What we learned each sprint |
| [[TESTING_GUIDE]] | How to run backend, mobile, and web locally |

---

## Guides & References

| Doc | Purpose |
|-----|---------|
| [[README_GUIDE]] | GitHub README best practices — structure, badges, tech stack visuals |

---

## Sprint Status at a Glance

| Sprint | Goal | Status |
|--------|------|--------|
| Sprint 1 | Core backend endpoints | ✅ Done |
| Sprint 2 | MVP worker loop + supervisor view | ✅ Done |
| Sprint 3 | Structured tasks with photo enforcement | ✅ Done |
| Sprint 4 | Overtime verification | ✅ Done |
| Sprint 5 | Reporting engine | ✅ Done |
| Sprint 6 | Competitive parity + admin system + pilot readiness | 🔄 ~90% (signatures + state OT remaining) |
| Sprint 7 | Field intelligence + scalability foundations | ⬜ Backlog |
| Sprint 8 | Billing + integrations + SOC 2 | ⬜ Backlog |
| Sprint 9 | AI + production hardening | ⬜ Backlog |
| Sprint 10 | Scale + client portal | ⬜ Backlog |

---

## Codebase

| Component | Path | Stack |
|-----------|------|-------|
| Mobile app | `apps/fieldops_mobile/` | Flutter + Riverpod + Drift |
| Web dashboard | `apps/fieldops_web/` | Next.js 15 + React + Tailwind |
| Super-admin panel | `apps/fieldops_admin/` | Next.js 15 (port 3001) |
| Edge functions | `infra/supabase/functions/` | Deno + TypeScript (16 functions) |
| Shared helpers | `infra/supabase/functions/_shared/` | api.ts + settings.ts |
| Backend tests | `execution/` | Python |
| CI/CD | `.github/workflows/` | GitHub Actions (Gitleaks + lint) |

---

## Quick Commands

```bash
# Backend
cd infra && supabase start
python3 execution/run_backend_regression_suite.py

# Mobile
cd apps/fieldops_mobile
flutter analyze && flutter test
flutter run -d macos --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=<key>

# Web dashboard
cd apps/fieldops_web
npm run dev        # port 3000

# Super-admin panel
cd apps/fieldops_admin
npm run dev        # port 3001
```

---

## Key Session Log (2026-04-05)

- Code review: 47 P0/P1/P2 issues fixed across 2 rounds
- CI pipeline: fixed (Gitleaks + lint; Docker tests deferred Sprint 7)
- Completed: logging, RLS isolation test, PTO system, admin system (4 phases)
- Notion synced: Sprint groups 6-10 added, 35 new tasks, 24 tasks marked Done
- Competitive research: ClockShark, Busybusy, Connecteam, Jobber, ServiceTitan, Procore
- Dev review feedback: integrated into Sprints 7-10
- Lessons 36-39 added to [[LESSONS_LEARNED]]
