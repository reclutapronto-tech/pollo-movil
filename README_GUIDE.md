---
title: GitHub README Best Practices
tags:
  - documentation
  - github
  - best-practices
  - reference
aliases:
  - README Guide
related:
  - "[[INDEX]]"
  - "[[LESSONS_LEARNED]]"
---

# GitHub README Best Practices

> [!info] Context
> Researched and applied when creating the first public README for FieldOps AI on 2026-04-04.
> Sources: othneildrew/Best-README-Template, matiassingers/awesome-readme, PostHog, gofiber/fiber, Hatica, daily.dev.

---

## Core Rule

> The README answers three questions in under 30 seconds:
> **What is it? Why does it exist? How do I run it?**

If a visitor has to scroll past the fold to understand the product, the README has failed.

---

## Section Order (canonical)

| # | Section | Why |
|---|---------|-----|
| 1 | Logo + name + tagline | First impression — brand identity in one line |
| 2 | Badges row | Trust signals at a glance (CI, license, last commit) |
| 3 | Short description / elevator pitch | 1–3 sentences: what, why, who |
| 4 | Screenshot / demo GIF | Show don't tell — highest-impact element |
| 5 | Table of contents | Required once README exceeds ~500 words |
| 6 | Features | Bullet list, scannable |
| 7 | Tech stack | Logos/badges grouped by layer |
| 8 | Getting started | Prerequisites + step-by-step |
| 9 | Usage / examples | Code snippets, common tasks |
| 10 | Architecture | Folder tree + how it connects (critical for monorepos) |
| 11 | Deployment | One-click deploy buttons if applicable |
| 12 | Roadmap | Shows active development, builds trust |
| 13 | Contributing | How to submit PRs |
| 14 | License | Always required |
| 15 | Contact / community | Discord, Twitter, email |

---

## Badges

**Always include:**
```markdown
![CI](https://img.shields.io/github/actions/workflow/status/{owner}/{repo}/ci.yml?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)
![Last Commit](https://img.shields.io/github/last-commit/{owner}/{repo}?style=flat-square)
```

**Rules:**
- Cap at 5–10 badges max
- One row, consistent style — use `flat-square` or `for-the-badge`, never mix
- Broken badges (red CI) are worse than no badge — only add what you can keep green

---

## Tech Stack Presentation

**Pattern A — Shields.io inline (most common):**
```markdown
![Next.js](https://img.shields.io/badge/Next.js-000?logo=nextdotjs&logoColor=white&style=flat-square)
![TypeScript](https://img.shields.io/badge/TypeScript-3178C6?logo=typescript&logoColor=white&style=flat-square)
```
Uses `simple-icons` slugs for logos. Brand colors in hex.

**Pattern B — Skill icon grid (cleaner visually):**
```markdown
<p align="left">
  <img src="https://skillicons.dev/icons?i=nextjs,ts,postgres,docker" />
</p>
```

**Structure:** Always group by layer — Frontend / Backend / Database / Infrastructure / DevOps.

---

## Architecture Section

For a multi-service product, include:
- An annotated folder tree (monorepo structure)
- A short ASCII or Mermaid flow diagram showing how the services connect
- 3–5 bullet design principles that explain *why* it's built this way

This is the section that separates "good" from "great" READMEs for developer audiences.

---

## Roadmap Table

Use a simple status table — not a verbose bullet list:

```markdown
| Sprint | What ships | Status |
|--------|-----------|--------|
| 1 | Core backend | ✅ Done |
| 2 | MVP loop | ✅ Done |
| 3 | Tasks | 🔄 Next |
| 4 | OT | ⬜ Backlog |
```

**Critical rule:** Status must reflect reality, not aspiration.
Always cross-check against `SPRINT_TRACKER.md` and Notion before publishing.
See [[LESSONS_LEARNED]] — Lesson 27.

---

## Monorepo READMEs

The root README is a **navigation hub**, not a deep-dive:

- What the monorepo contains (1 paragraph)
- Repo structure diagram with descriptions
- How to run the full stack locally (each app)
- Links to per-package READMEs (when they exist)

Each `apps/` subdirectory can have its own README covering app-specific setup.

---

## What Separates Good from Great

From studying top-cited repos (PostHog, gofiber/fiber, iterative/dvc):

- **Demo GIF or screenshot above the fold** — single highest-impact addition
- **ASCII architecture diagram** — makes the system immediately understandable
- **One-click deploy buttons** — `[![Deploy on Railway](...)` as image links
- **Environment variables in a collapsible section** — use `<details><summary>` for long configs
- **Contributor grid** via `contrib.rocks`
- **Back to top links** in long sections: `[↑ Back to top](#top)`

---

## What to Avoid

- No logo or hero image (biggest miss for first impressions)
- Wall of text with no visual break in the first 100 lines
- Stale status badges (broken CI badge = red flag to contributors)
- Generic section titles ("About") instead of descriptive ones
- Missing license (blocks enterprise adoption)
- No demo or screenshot (forces reader to install before understanding value)
- Single monolithic README trying to document every app (breaks for monorepos)
- Roadmap that doesn't match actual sprint status (see [[LESSONS_LEARNED]] — Lesson 27)

---

## FieldOps README Location

- File: `README.md` (repo root)
- Rendered at: https://github.com/seancheick/FieldOpsAi
- Update the roadmap table whenever a sprint closes — keep it honest.

---

## Reference Links

- [Best-README-Template](https://github.com/othneildrew/Best-README-Template) — canonical structure
- [awesome-readme](https://github.com/matiassingers/awesome-readme) — curated examples
- [shields.io](https://shields.io) — badge generator
- [skillicons.dev](https://skillicons.dev) — tech stack icon grid
- [contrib.rocks](https://contrib.rocks) — contributor image grid
- [simple-icons](https://simpleicons.org) — brand icon slugs for badges
