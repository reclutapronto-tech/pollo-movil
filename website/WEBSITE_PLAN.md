---
title: FieldOps AI — Website Plan
tags:
  - website
  - marketing
  - design
related:
  - "[[PRD]]"
  - "[[ROADMAP]]"
---

# FieldOps AI — Website Plan

> **For the developer:** This document is the complete spec for the FieldOps AI marketing website.
> Build it in **Next.js + Tailwind CSS** (same stack as the supervisor dashboard).
> Every section, every word, every CTA is intentional. Follow it exactly.

---

## 1. Competitive Intelligence

### What competitors do well (steal these patterns)

| Competitor | Strength | FieldOps Response |
|-----------|----------|-------------------|
| [ClockShark](https://www.clockshark.com) ($40+$9/user) | Industry-specific landing pages, QuickBooks integration badges, 14-day free trial, video testimonials | We beat on price (per-company, not per-user) and proof layer (they don't burn stamps into photos) |
| [CompanyCam](https://www.companycam.com) ($19-34/user) | Photo-first messaging, clean UI, real customer photos as hero | We match photo proof AND add time tracking + OT verification + tasks — they don't have any of that |
| [Timemark](https://www.timemark.com) ($0-129/mo) | Free tier, "best CompanyCam alternative" positioning, GPS photo stamps | We match stamps AND burn them into pixels (theirs is metadata-only). We add clock, tasks, OT, reports |
| [Fieldwire](https://www.fieldwire.com) | Blueprint management, construction-specific features | We don't compete here — different product. Our strength is proof + workforce, not blueprints |

### Our unique positioning (what no competitor has)
1. **Server-side burned proof stamp** — GPS, time, worker name, job code burned INTO the image pixels. Survives screenshots. No competitor does this.
2. **Per-company pricing** — structurally cheaper than per-user at 15+ workers. ClockShark at 30 workers = $310/mo. FieldOps = $149/mo.
3. **OT Photo Verification** — entirely original feature. No competitor has photo-stamped overtime approval.
4. **Append-only audit trail** — enterprise compliance at SMB pricing.
5. **One-hour setup** — from zero to first clock-in in under 60 minutes, no sales call needed.

---

## 2. Design System

### Colors
| Token | Hex | Usage |
|-------|-----|-------|
| Primary (Signal Orange) | `#F38B2A` | CTAs, buttons, accents |
| Slate | `#0F172A` | Headings, dark backgrounds |
| Steel | `#64748B` | Body text, secondary |
| Canvas | `#FAFAFA` | Page background |
| Surface | `#FFFFFF` | Cards, sections |
| Success | `#16A34A` | Status indicators |
| Danger | `#DC2626` | Alerts, destructive |
| Border | `#E2E8F0` | Dividers, card borders |

### Typography
| Role | Font | Weight | Size |
|------|------|--------|------|
| Display (H1) | Space Grotesk | 700 | 56-72px |
| Heading (H2) | Space Grotesk | 700 | 36-48px |
| Subheading (H3) | Space Grotesk | 600 | 24-32px |
| Body | Inter | 400 | 16-18px |
| Label/CTA | Inter | 600 | 15-16px |
| Code/Data | JetBrains Mono | 400 | 14px |

### Spacing
- 8px grid system
- Section padding: 80-120px vertical
- Container max-width: 1280px
- Card border-radius: 16-24px

### Icons
- Lucide Icons (consistent stroke width)
- NO emojis in production UI

---

## 3. Page Structure

### 3.1 Navigation Bar (sticky)

```
┌─────────────────────────────────────────────────────────────┐
│ [Logo] FieldOps AI    Features  Pricing  About    [Try Free]│
└─────────────────────────────────────────────────────────────┘
```

- Logo: left-aligned, links to home
- Links: Features, Pricing, About (anchor links on same page or separate pages)
- CTA: "Try Free" — orange button, always visible
- Mobile: hamburger menu with full-screen overlay
- Sticky on scroll with subtle shadow

---

### 3.2 Hero Section

> The first thing anyone sees. Must answer: "What is this, who is it for, and why should I care?"

**Layout:** Split — left text, right product screenshot/animation

**Content:**

```
[Badge] For construction & field service teams

# Stop losing money on disputes.
# Prove the work — automatically.

The only platform that combines GPS-verified time tracking,
photo proof with burned-in stamps, task management, and
automated reporting in one mobile-first app.

[Try Free — No Credit Card]     [Watch Demo →]

"Saved us $12,000 in disputed overtime in the first month."
— First pilot customer
```

**Design notes:**
- H1: 56-72px Space Grotesk Bold, slate color, negative letter-spacing
- Subtext: 18px Inter, steel color, max 65 chars per line
- Primary CTA: Orange filled button, 56px height, rounded-16
- Secondary CTA: Text link with arrow icon
- Right side: Actual app screenshot (phone mockup showing the worker home screen with a job card, clocked-in state, and proof photo button)
- Background: Subtle gradient from slate-50 to white
- NO stock photos. Use the real app.

---

### 3.3 Social Proof Bar

```
┌─────────────────────────────────────────────────────────────┐
│  Trusted by field teams  •  500+ workers tracked  •  4.9★  │
└─────────────────────────────────────────────────────────────┘
```

- Grayscale logos of industries served (electrical, construction, infrastructure)
- Metrics: workers tracked, photos captured, hours verified
- Light background, centered, subtle border top/bottom
- Fade-in animation on scroll

---

### 3.4 Problem Section

> Make the pain feel real before showing the solution.

**Headline:** "Your field team's biggest problems, solved."

**3-column grid:**

| 📋 Payroll Disputes | 📸 No Proof of Work | ⏰ OT Chaos |
|---|---|---|
| Workers clock in from their couch. You pay for hours nobody worked. Disputes eat your profit. | Client says the work wasn't done. You have no photo evidence. You eat the cost. | Overtime runs unchecked. By the time you find out, payroll is already submitted. |

**Design notes:**
- Each column: icon (Lucide, not emoji) + title + 2-sentence pain description
- Use red/danger tint for the pain icons
- Followed by a transitional line: "What if you could prove every minute and every photo — automatically?"

---

### 3.5 Solution Section — "How It Works"

> Show the product loop in 4 steps. Visual, not text-heavy.

**Headline:** "From clock-in to client report — in 4 steps."

**Steps (horizontal on desktop, vertical on mobile):**

```
1. Clock In              2. Capture Proof          3. Track Tasks           4. Generate Report
GPS-verified,            In-app camera,            Photo-required           One-click PDF with
geofence-validated       server-stamped,           checklists,              stamped photos,
one-tap clock-in         tamper-proof              before/after mode        hours, and proof

[Phone mockup]           [Stamped photo]           [Task checklist]         [PDF preview]
```

**Design notes:**
- Step numbers in orange circles
- Each step has a mini screenshot/illustration
- Connecting line/arrow between steps
- Light background

---

### 3.6 Feature Grid — "Everything You Need"

> The feature showcase. Use a bento-style grid layout (2026 trend).

**Headline:** "Built for how field teams actually work."

**Feature cards (bento grid):**

| Feature | Description | Visual |
|---------|-------------|--------|
| **GPS Clock In/Out** | One-tap clock with geofence validation. Workers can only clock in at the job site. Break tracking included. | Map pin animation |
| **Burned-In Photo Proof** | Every photo stamped server-side with GPS, time, worker name, and job code. The stamp survives screenshots. | Before/after stamp comparison |
| **Task Checklists** | Structured tasks with photo-required enforcement. Workers can't skip the proof. | Checklist with camera icons |
| **OT Verification** | Automatic overtime prompt at shift threshold. Photo-stamped OT approval. No more disputed hours. | OT prompt screenshot |
| **Offline-First** | Full clock-in and photo capture without internet. Auto-syncs when connection returns. | Offline badge animation |
| **Live Map Dashboard** | See every worker's GPS position in real-time. Job site markers with geofence radius. | Map screenshot |
| **Project Photo Feed** | Real-time evidence wall per job. Every photo from every worker, chronologically. | Photo grid |
| **Timesheet Export** | One-click CSV for payroll. Regular/OT hours split. Rounds to 15 minutes. Ready for QuickBooks. | CSV preview |
| **Job Reports** | PDF reports with stamped photos, worker hours, task status, and OT approvals. Send to clients. Get paid. | PDF mockup |
| **Daily Shift Reports** | Foreman logs: headcount, tasks completed, issues, next steps. Auto-populated from the day's events. | Report card |
| **Supervisor Dashboard** | Active jobs, worker status, photo feed, timeline, overtime approvals, reports — all in one web console. | Dashboard screenshot |
| **Alert System** | Automated alerts for geofence violations, missed checkpoints, unapproved overtime, and late arrivals. | Alert feed |
| **Receipt & Expense Capture** | Workers snap receipts, auto-categorize (materials, fuel, tools), attach to jobs. Supervisors approve. Expenses feed into job cost reports. Never lose a receipt again. | Receipt card with category badge |
| **Job Costing & Cost Codes** | Track labor costs per job code. See real-time profitability. Know which jobs make money and which don't. | Profitability chart |
| **Time Card Signatures** | Digital sign-off by worker and supervisor. Legally defensible. Required for union and certified payroll compliance. | Signature preview |
| **PTO & Time Off** | Workers request vacation, sick days, or personal time. Supervisors approve from the dashboard. Balances tracked automatically. | PTO request card |
| **State-Specific OT Rules** | California daily OT, weekly OT, double-time — all calculated automatically based on your jurisdiction. No more payroll errors. | OT rules selector |
| **Worker Hours Dashboard** | Workers see their hours at a glance: today, this week, this month. Progress bars and totals. No guessing, no confusion. | Hours stat cards |
| **Who's Working Now** | Supervisors see real-time worker status: clocked in, on break, clocked out, late. Sortable by status, name, or job. | Status list |
| **Drag & Drop Scheduling** | Create schedules in draft, edit, then publish. Workers get notified instantly. Day, week, and month views. Or skip the schedule and just clock in. | Calendar screenshot |
| **Crew Clock-In** | Foreman clocks in the whole crew from one device. Every entry tagged with who clocked whom — full audit trail. | Crew list |
| **GPS Route Replay** | Replay an animated trail of each worker's day. See exactly where they were, when. GPS only active while clocked in — never off the clock. | Animated map |
| **Dark Mode** | Full dark theme that follows system preference. Built for early morning and late night shifts. | Dark/light toggle |
| **Multilingual** | English, French, Arabic support. Workers use the app in their own language. | Language selector |

**Design notes:**
- Bento grid: mix of large (2-col) and small (1-col) cards
- Each card: title + 1-2 sentence description + screenshot or illustration
- Hover effect: subtle scale + shadow
- Large cards for the hero features: Burned-In Photo Proof, Live Map Dashboard
- Responsive: 3-col desktop, 2-col tablet, 1-col mobile

---

### 3.7 Proof Stamp Showcase

> This is THE selling feature. Give it its own section.

**Headline:** "Proof you can see. Proof that survives."

**Layout:** Side-by-side comparison

```
┌──────────────────┐    ┌──────────────────┐
│                  │    │ ┌──────────────┐  │
│  Raw Photo       │ →  │ │ Apex Electric│  │
│  (no metadata)   │    │ │ John Smith   │  │
│                  │    │ │ GPS: 42.36°  │  │
│                  │    │ │ Apr 3, 2026  │  │
│                  │    │ │ JOB-1234     │  │
│                  │    │ │ FO-A1B2C3D4  │  │
│                  │    │ └──────────────┘  │
│                  │    │  Stamped Photo    │
└──────────────────┘    └──────────────────┘
```

**Below:** "Other tools store GPS in metadata — invisible, easily stripped. FieldOps burns the stamp into the image itself. Screenshot it, email it, print it — the proof stays."

**CTA:** "See it in action → Try Free"

---

### 3.8 Pricing Section

> Per-company pricing is the wedge. Make the comparison obvious.

**Headline:** "Pricing that makes sense for your crew."
**Subhead:** "Per-company, not per-user. The bigger your team, the more you save."

**3 pricing cards:**

| Starter | Pro | Business |
|---------|-----|----------|
| **$49/mo** | **$149/mo** | **$299/mo** |
| Up to 10 workers | Up to 50 workers | Unlimited workers |
| GPS clock in/out | Everything in Starter | Everything in Pro |
| Photo proof stamps | Task checklists | API access |
| Job timeline | OT verification | Custom reports |
| Timesheet export | Shift reports | White-label option |
| Mobile app (iOS + Android) | Supervisor dashboard | Priority support |
| | PDF reports | Dedicated onboarding |
| [Start Free] | [Start Free] | [Contact Sales] |

**Below the cards:**
```
"Free to start — no credit card required. Upgrade when you're ready."
```

**Competitor comparison table:**

| Feature | FieldOps AI | ClockShark | busybusy | Timemark | CompanyCam |
|---------|------------|------------|----------|----------|------------|
| Price (30 workers) | **$149/mo** | $310/mo | ~$300/mo | $219/mo | $570/mo |
| GPS Clock In/Out | ✓ | ✓ | ✓ | ✗ | ✗ |
| Photo Proof Stamps | **Burned-in** | ✗ | ✗ | Metadata only | ✗ |
| Task Checklists | ✓ | ✓ | ✗ | ✗ | ✗ |
| OT Photo Verification | **✓** | ✗ | ✗ | ✗ | ✗ |
| Receipt/Expense Capture | **✓** | ✗ | ✗ | ✗ | ✗ |
| Job Costing | ✓ | ✓ | ✓ | ✗ | ✗ |
| Time Card Signatures | ✓ | ✗ | ✓ | ✗ | ✗ |
| State-Specific OT | ✓ | ✗ | ✓ (CA) | ✗ | ✗ |
| PTO Requests | ✓ | ✓ | ✓ | ✗ | ✗ |
| Offline Mode | ✓ | ✓ | ✓ | ✓ | ✓ |
| Live Map | ✓ | ✓ | ✓ | ✗ | ✗ |
| Per-Company Pricing | **✓** | ✗ | ✗ | ✗ | ✗ |
| Dark Mode | ✓ | ✗ | ✗ | ✗ | ✗ |
| Multilingual | ✓ | ✗ | ✗ | ✗ | ✗ |

---

### 3.9 Testimonials Section

**Headline:** "Trusted by field teams who need proof."

**3 testimonial cards:**

```
"FieldOps eliminated our overtime disputes overnight.
 The burned-in photo stamp is something no other tool has."
 — [Name], [Title], [Company]
 ★★★★★

"My crew adopted it in one day. Clock in, take photo, done.
 30 seconds. That's it."
 — [Name], [Title], [Company]
 ★★★★★

"The client asked for proof. I generated a PDF report with
 stamped photos in 2 minutes. We got paid the next day."
 — [Name], [Title], [Company]
 ★★★★★
```

**Design notes:**
- Card layout with avatar, name, title, company, star rating
- Subtle background gradient
- Use real testimonials once available; placeholder for now

---

### 3.10 FAQ Section

**Headline:** "Questions? We've got answers."

**Accordion style:**

1. **How long does setup take?** → Under 60 minutes. Create your company, add workers, create a job, and your crew is clocking in.
2. **Do workers need internet to use the app?** → No. FieldOps works fully offline. Clock-ins, photos, and tasks queue locally and sync automatically when connection returns.
3. **How is the photo stamp different from metadata?** → Other tools store GPS in file metadata — invisible and easily stripped. FieldOps burns the stamp into the image pixels. It's visible in every screenshot, email, and printout.
4. **Can I export timesheets to QuickBooks?** → Yes. One-click CSV export with worker name, hours, OT breakdown, and job codes. Ready for QuickBooks, Gusto, or any payroll system.
5. **What devices are supported?** → iOS 13+ and Android 8.0+. The app is optimized for low-end devices with 2GB RAM.
6. **Is there a free tier?** → Free to start with no credit card. Full feature access during your trial. Upgrade to a paid plan when you're ready.
7. **How does per-company pricing work?** → You pay one flat monthly rate based on your team size tier. No per-user fees, no hidden charges. The bigger your team, the more you save vs per-user competitors.
8. **Can supervisors approve overtime remotely?** → Yes. Supervisors receive the OT request with the stamped photo and can approve or deny from the web dashboard or their phone.

---

### 3.11 Final CTA Section

> Last chance to convert. Make it emotional and urgent.

**Layout:** Full-width, dark background (slate), centered text

```
# Stop losing money. Start proving the work.

Your crew is already on the job site.
Give them the tool that proves what they did — automatically.

[Try Free — No Credit Card Required]

Setup takes less than 60 minutes.
No sales call. No contract. Cancel anytime.
```

---

### 3.12 Footer

```
┌─────────────────────────────────────────────────────────────┐
│ FieldOps AI                                                 │
│ The system that proves work happened — automatically.       │
│                                                             │
│ Product           Company          Legal                    │
│ Features          About            Privacy Policy           │
│ Pricing           Careers          Terms of Service         │
│ Changelog         Contact          Cookie Policy            │
│ API Docs          Blog                                      │
│                                                             │
│ [App Store]  [Google Play]  [LinkedIn]  [Twitter/X]         │
│                                                             │
│ © 2026 B&Br Technology, Boston, MA. All rights reserved.    │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. Page List

| Page | Priority | Notes |
|------|----------|-------|
| `/` (Home/Landing) | P0 | Everything above — single scrolling page |
| `/pricing` | P0 | Expanded pricing with comparison table |
| `/features` | P1 | Detailed feature pages with screenshots |
| `/about` | P1 | Company story, team, mission |
| `/contact` | P1 | Contact form + calendar booking |
| `/blog` | P2 | SEO content (future) |
| `/changelog` | P2 | Product updates |
| `/privacy` | P0 | Required for App Store |
| `/terms` | P0 | Required for App Store |

---

## 5. Technical Spec

| Item | Choice |
|------|--------|
| Framework | Next.js 15 (App Router) |
| Styling | Tailwind CSS 4 |
| Hosting | Vercel |
| Analytics | PostHog or Plausible |
| Forms | Formspree or Supabase Edge Function |
| Images | WebP/AVIF with next/image |
| Fonts | Google Fonts (Space Grotesk + Inter) |
| Icons | Lucide React |
| Animation | Framer Motion (subtle, reduced-motion aware) |
| SEO | Next.js metadata API + sitemap.xml + robots.txt |

---

## 6. Conversion Optimization Rules

1. **One primary CTA per viewport** — "Try Free" is always visible (nav + hero + mid-page + bottom)
2. **No credit card required** — say it at least 3 times on the page
3. **Show the real product** — screenshots of the actual app, not illustrations
4. **Social proof near every CTA** — testimonial or metric badge next to each button
5. **Mobile-first** — 83% of SaaS traffic is mobile. Hero must work at 375px.
6. **Load time under 2 seconds** — lazy load below-fold images, inline critical CSS
7. **One conversion goal** — free trial signup. Not newsletter, not demo request, not contact form. Free trial.
8. **Price anchoring** — show competitor pricing to make FieldOps look cheap (because it is)

---

## 7. SEO Keywords

| Primary | Secondary |
|---------|-----------|
| field operations software | construction time tracking app |
| GPS time tracking for crews | photo proof for contractors |
| workforce management construction | overtime verification system |
| field service management app | job site photo documentation |
| proof of work software | mobile workforce tracking |

---

## Sources

- [ClockShark Pricing & Reviews](https://www.clockshark.com/pricing/)
- [CompanyCam Pricing](https://www.capterra.com/p/171143/CompanyCam/pricing/)
- [Timemark - Best CompanyCam Alternative](https://www.timemark.com/compare/best-companycam-alternative)
- [SaaS Landing Page Trends 2026](https://www.saasframe.io/blog/10-saas-landing-page-trends-for-2026-with-real-examples)
- [High-Converting SaaS Landing Pages](https://www.saashero.net/design/enterprise-landing-page-design-2026/)
- [SaaS Landing Page Conversion System](https://unicornplatform.com/blog/saas-landing-page-conversion-system-in-2026/)
