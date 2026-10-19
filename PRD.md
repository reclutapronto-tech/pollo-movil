---
title: FieldOps AI PRD
tags:
  - product
  - requirements
  - strategy
aliases:
  - PRD
  - Product Requirements
related:
  - "[[ROADMAP]]"
  - "[[architecture]]"
  - "[[DATA_MODEL]]"
  - "[[SPRINT_TRACKER]]"
---

# 🚀 FIELDOPS AI — ELITE PRD (v2.0)

## 1. Product Definition
### 1.1 Product Name
**FieldOps AI**

### 1.2 Product Type
* Mobile-first SaaS platform
* Workforce + Operations + Proof system
* AI-enabled (data-driven, not hype-driven)

### 1.3 Core Value Proposition
> "The system that proves work happened — automatically."

This is not a feature. This is the **product primitive**. Everything else supports it.

### 1.4 Product Pillars (NON-NEGOTIABLE)
| Pillar       | Description                                   |
| ------------ | --------------------------------------------- |
| Proof        | Immutable, timestamped, GPS-linked evidence   |
| Workforce    | Verified time tracking + labor accountability |
| Operations   | Job execution + coordination                  |
| Intelligence | AI built on real event data                   |

---

## 2. Product Vision
### 2.1 Long-Term Vision
> Build the operating system for field work.

Not a time tracker. Not a photo app. Not a project tool.
👉 **The source of truth for everything that happens in the field.**

### 2.2 Strategic Insight
Most tools track **activity**.
FieldOps tracks: 👉 **Proof + context + sequence.** That’s defensibility.

---

## 3. Problem Definition
### 3.1 Core Problem
Field companies cannot **prove what happened**. This creates payment disputes, payroll errors, and operational blind spots.

### 3.2 Root Cause
Fragmentation: WhatsApp (photos) + Excel (hours) + Memory (supervision). No system = no truth.

---

## 4. Target Users
### 4.1 Primary Persona
**Owner / Operator:** Cares about money, disputes, and visibility.

### 4.2 Secondary Personas
**Foreman (Field Leader):** Needs situational awareness across their crew, shift logs, and real-time intervention capabilities at the job site.
**Supervisor (Office Manager):** Needs broad control, OT approvals, and real-time map insights.
**Worker:** Needs speed + simplicity (the 30-Second Rule).

### 4.3 Key Constraint
> Worker adoption = system success. If the worker flow fails → the product fails.

---

## 5. Core System Architecture (CRITICAL)
### 5.1 Event-Sourced Architecture
Everything is an immutable event. This is the **data backbone**.
* `ClockEvent`
* `PhotoEvent`
* `TaskEvent`
* `OTApprovalEvent`
* `CorrectionEvent` (Append-only updates, ensuring audit integrity)

### 5.2 Phase 1 Schema "Tech Debt Guardrail"
**CRITICAL:** `ClockEvent` MUST include a nullable `task_classification` field from Day 1. This prevents massive data migrations in Phase 4 when building Certified Payroll (US Public Works) or Union Prevailing Wages integrations.

### 5.3 Product Engine
`Field Activity → Events → Timeline → Reports → Insights`

---

## 6. Advanced System Integration (ANTIGRAVITY)
FieldOps integrates with the **Antigravity system architecture**, making it a deterministic engine.

### 6.1 Agent System Integration
* **Report Agent:** Automatically generates structured PDF reports for clients.
* **Analysis Agent:** Detects anomalies (e.g., GPS drift, repeated early clock-ins).
* **Sync Agent:** Manages offline data queuing and ensures conflict-free upload.

### 6.2 Task Queue System
Heavy operations run entirely asynchronous for speed: Report generation, AI analysis, and Server-side image stamping.

### 6.3 MCP Layer (Tool Integration)
FieldOps does NOT directly integrate APIs.
`Agent → MCP → Tools`
Enables scalable, future-proof connections to QuickBooks, Trayd, and Google Drive without bespoke rewrites.

---

## 7. Core Product Loops
### 7.1 Daily Worker Loop
1. Clock in
2. Perform task
3. Take photo
4. Continue work
👉 Requires **< 30 seconds total friction**.

### 7.2 Foreman Field Loop
1. Quick crew view overview
2. Log Daily Shift report structure
3. Process rapid "at-the-moment" OT verification approvals.

### 7.3 Supervisor Office Loop
1. Monitor live map dashboard
2. Review project photo feeds
3. Approve OT and exception flags

### 7.4 Owner Loop
1. Open report
2. Verify work
3. Send to client → Get paid

---

## 8. MVP Scope (STRICT: Pilot "30-Day Co-Build")
### 8.1 MVP Definition
> Worker clocks in → takes photo → supervisor sees it live.

### 8.2 MVP Protocol
* **Pilot Lock:** Do not scale to a second customer until the first reference customer uses the app flawlessly in the real world.
* **Device Min-Specs:** Locked at Android 8.0+, iOS 13+, 2GB RAM.

### 8.3 Core Features
* Auth + Roles
* GPS clock-in (server validated)
* In-app photo capture
* Job creation & Timeline
* Supervisor Map Dashboard

---

## 9. Product Requirements (SYSTEM-LEVEL)
### 9.1 Performance & Hardware
* Clock-in **< 2 seconds**.
* Photo flow **< 10 seconds**.
* **50-Photo Offline Cap:** Prevents local storage corruption on low-end 2GB RAM devices in offline environments. 

### 9.2 Reliability & Security (The "Stamp")
* No data loss; append-only system.
* **Server-Side Burned-In Proof Stamp:** The watermark (GPS, Time, Date, Job Reference, User) is *burned into the image pixels* on the backend. It is immune to screenshotting and client-side manipulation.

### 9.3 Usability
* 1–2 taps per action; works with gloves; zero typing for field workers.

---

## 10. AI Layer (STRICT RULES)
### 10.1 AI Principle
> AI only works on structured data.

### 10.2 Allowed AI Use Cases
* Report summarization (from Foreman Shift Logs)
* Anomaly detection
* Voice transcription 

❌ FORBIDDEN: Guessing, free-form generation, or decision-making without data.

---

## 11. Monetization
### 11.1 Pricing Strategy (Per-Company)
* **Starter:** Entry level.
* **Pro:** Growth.
* **Business:** Intelligence.
* **Enterprise:** White-labeled solutions.

*Key Wedge:* Structurally cheaper at scale than per-seat SaaS models.

---

## 12. Go-To-Market
* **Phase 0:** 1 pilot company → real usage → real data (Define top-10 failure modes runbook before going live).
* **Phase 1:** 3–5 companies via founder-led sales.
* **Phase 2:** Referrals, inbound content, outbound.

---

## 13. Success Metrics
* **Product:** DAU / WAU, photos per worker, OT verification completion rate.
* **Business:** MRR, CAC, Churn.
* **System:** Sync failure rate, error rate, task queue latency.

---

## 14. Risks & Mitigation
* **Biggest Risk:** Worker adoption. Mitigated by the 30-second rule.
* **Technical Risk:** Offline sync limits. Mitigated by queue limits (50-photo cap).
* **Compliance Risk:** GPS Spoofing. Mitigate by phrasing as "GPS-verified and metadata-secured visual evidence", rather than "tamper-proof guarantee".

---

## 15. Strategic Moat
* **Data Moat:** You own work history, performance data, and operational patterns.
* **Switching Cost:** Deeply ingrained crew habits and embedded reporting workflows.
* **Product Moat:** Competitors track *activity*. FieldOps proves *reality*.

> **Final Product Principle:** If it doesn’t improve the job timeline, it doesn’t ship.
