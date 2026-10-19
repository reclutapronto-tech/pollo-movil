"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useI18n } from "@/lib/i18n";
import { getSupabase } from "@/lib/supabase";

interface WorkerEntry {
  id: string;
  firstName: string;
  lastName: string;
  email: string;
  phone: string;
  address: string;
  notes: string;
}

const STEP_KEYS = [
  { titleKey: "onboardingPage.steps.company.title", descriptionKey: "onboardingPage.steps.company.description" },
  { titleKey: "onboardingPage.steps.team.title", descriptionKey: "onboardingPage.steps.team.description" },
  { titleKey: "onboardingPage.steps.firstJob.title", descriptionKey: "onboardingPage.steps.firstJob.description" },
  { titleKey: "onboardingPage.steps.goLive.title", descriptionKey: "onboardingPage.steps.goLive.description" },
] as const;

const INDUSTRY_VALUES = [
  "electrical",
  "construction",
  "plumbing",
  "hvac",
  "telecom",
  "solar",
  "landscaping",
  "other",
] as const;

const TIMEZONE_VALUES = [
  "America/New_York",
  "America/Chicago",
  "America/Denver",
  "America/Los_Angeles",
  "America/Anchorage",
  "Pacific/Honolulu",
  "Europe/London",
  "Europe/Paris",
  "Africa/Abidjan",
  "Asia/Bangkok",
  "Asia/Shanghai",
  "Asia/Dubai",
] as const;

const STORAGE_KEY = "onboarding_progress";

/** Convert a display name to a simple job code: "Downtown Reno" → "DOWNTOWN-RENO" */
function toJobCode(name: string): string {
  return name
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(0, 20);
}

export default function OnboardingPage() {
  const { t } = useI18n();
  const [step, setStep] = useState(0);
  const [companyName, setCompanyName] = useState("");
  const [companyLogo, setCompanyLogo] = useState("");
  const [timezone, setTimezone] = useState<string>("America/New_York");
  const [industry, setIndustry] = useState<string>("electrical");
  const [workers, setWorkers] = useState<WorkerEntry[]>([]);
  const [jobName, setJobName] = useState("");
  const [jobAddress, setJobAddress] = useState("");
  const [jobCode, setJobCode] = useState("");
  const [resumed, setResumed] = useState(false);

  // Saving state for async DB writes
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  // Track which steps have already been written to avoid duplicate Supabase calls
  const savedSteps = useRef<Set<number>>(new Set());

  // Restore progress from localStorage on mount
  useEffect(() => {
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (saved) {
        const data = JSON.parse(saved);
        if (data.step != null) setStep(data.step);
        if (data.companyName) setCompanyName(data.companyName);
        if (data.companyLogo) setCompanyLogo(data.companyLogo);
        if (data.timezone) setTimezone(data.timezone);
        if (data.industry) setIndustry(data.industry);
        if (data.workers) setWorkers(data.workers);
        if (data.jobName) setJobName(data.jobName);
        if (data.jobAddress) setJobAddress(data.jobAddress);
        if (data.jobCode) setJobCode(data.jobCode);
        if (data.savedSteps) {
          savedSteps.current = new Set(data.savedSteps);
        }
        if (data.step > 0) {
          setResumed(true);
          setTimeout(() => setResumed(false), 3000);
        }
      }
    } catch {
      // ignore corrupt localStorage
    }
  }, []);

  // Auto-save progress on every state change
  useEffect(() => {
    try {
      localStorage.setItem(
        STORAGE_KEY,
        JSON.stringify({
          step,
          companyName,
          companyLogo,
          timezone,
          industry,
          workers,
          jobName,
          jobAddress,
          jobCode,
          savedSteps: Array.from(savedSteps.current),
        }),
      );
    } catch {
      // ignore quota errors
    }
  }, [step, companyName, companyLogo, timezone, industry, workers, jobName, jobAddress, jobCode]);

  const steps = useMemo(
    () =>
      STEP_KEYS.map((entry) => ({
        title: t(entry.titleKey),
        description: t(entry.descriptionKey),
      })),
    [t],
  );

  function addWorker() {
    setWorkers((prev) => [
      ...prev,
      { id: crypto.randomUUID(), firstName: "", lastName: "", email: "", phone: "", address: "", notes: "" },
    ]);
  }

  function updateWorker(id: string, field: keyof WorkerEntry, value: string) {
    setWorkers((prev) =>
      prev.map((worker) => (worker.id === id ? { ...worker, [field]: value } : worker)),
    );
  }

  function removeWorker(id: string) {
    setWorkers((prev) => prev.filter((worker) => worker.id !== id));
  }

  // ── Step 0: Save company details ──────────────────────────
  async function saveCompanyStep() {
    if (savedSteps.current.has(0)) {
      setStep(1);
      return;
    }
    setSaving(true);
    setSaveError(null);
    try {
      const supabase = getSupabase();
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) throw new Error("Not authenticated");

      // Get the user's company_id from the users table
      const { data: userRecord, error: userErr } = await supabase
        .from("users")
        .select("company_id")
        .eq("id", session.user.id)
        .single();
      if (userErr || !userRecord) throw new Error("Could not load your account");

      // Update the company record with the details filled in the wizard
      const { error: updateErr } = await supabase
        .from("companies")
        .update({
          name: companyName.trim(),
          timezone,
          logo_url: companyLogo.trim() || null,
          settings: { industry },
        })
        .eq("id", userRecord.company_id);

      if (updateErr) throw updateErr;

      savedSteps.current.add(0);
      setStep(1);
    } catch (e) {
      setSaveError(e instanceof Error ? e.message : "Failed to save company details");
    } finally {
      setSaving(false);
    }
  }

  // ── Step 1: Send invites for workers with an email ────────
  async function saveTeamStep() {
    if (savedSteps.current.has(1)) {
      setStep(2);
      return;
    }
    setSaving(true);
    setSaveError(null);
    try {
      const supabase = getSupabase();
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) throw new Error("Not authenticated");

      const workersWithEmail = workers.filter((w) => w.email.trim());
      const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || "";

      // Fire-and-forget invites — don't block on any individual failure
      const inviteResults = await Promise.allSettled(
        workersWithEmail.map(async (worker) => {
          const res = await fetch(`${supabaseUrl}/functions/v1/invites`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${session.access_token}`,
            },
            body: JSON.stringify({
              email: worker.email.trim(),
              full_name: `${worker.firstName} ${worker.lastName}`.trim(),
              role: "worker",
            }),
          });
          if (!res.ok) {
            const body = await res.json().catch(() => ({}));
            throw new Error(body.message || `Failed to invite ${worker.email}`);
          }
        }),
      );

      // Surface the first invite error as a warning but still proceed
      const failed = inviteResults.filter((r) => r.status === "rejected") as PromiseRejectedResult[];
      if (failed.length > 0 && workersWithEmail.length > 0) {
        setSaveError(`${failed.length} invite(s) failed: ${(failed[0].reason as Error).message}. You can re-invite later from Settings.`);
      }

      savedSteps.current.add(1);
      setStep(2);
    } catch (e) {
      setSaveError(e instanceof Error ? e.message : "Failed to send invites");
    } finally {
      setSaving(false);
    }
  }

  // ── Step 2: Create the first job ──────────────────────────
  async function saveJobStep() {
    if (savedSteps.current.has(2)) {
      setStep(3);
      return;
    }
    setSaving(true);
    setSaveError(null);
    try {
      const supabase = getSupabase();
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) throw new Error("Not authenticated");

      const { data: userRecord, error: userErr } = await supabase
        .from("users")
        .select("id, company_id")
        .eq("id", session.user.id)
        .single();
      if (userErr || !userRecord) throw new Error("Could not load your account");

      const code = (jobCode.trim() || toJobCode(jobName)).slice(0, 20) || "JOB-001";

      const { error: jobErr } = await supabase.from("jobs").insert({
        company_id: userRecord.company_id,
        name: jobName.trim(),
        code,
        status: "active",
        address_line_1: jobAddress.trim() || null,
        created_by: userRecord.id,
      });

      if (jobErr) throw jobErr;

      savedSteps.current.add(2);
      setStep(3);
    } catch (e) {
      setSaveError(e instanceof Error ? e.message : "Failed to create job");
    } finally {
      setSaving(false);
    }
  }

  const canProceedStep0 = companyName.trim().length > 0;
  const canProceedStep1 = workers.length > 0 && workers.every((worker) => worker.firstName.trim());
  const canProceedStep2 = jobName.trim().length > 0;
  const workerNoun =
    workers.length === 1 ? t("onboardingPage.workerSingular") : t("onboardingPage.workerPlural");

  return (
    <div className="mx-auto max-w-3xl">
      {resumed && (
        <div className="mb-4 rounded-xl border border-green-200 bg-green-50 px-4 py-2.5 text-sm text-green-700">
          {t("onboardingPage.resuming")}
        </div>
      )}

      {saveError && (
        <div className="mb-4 rounded-xl border border-amber-200 bg-amber-50 px-4 py-2.5 text-sm text-amber-700">
          {saveError}
        </div>
      )}

      <div className="mb-8">
        <div className="flex items-center justify-between">
          {steps.map((entry, index) => (
            <div key={entry.title} className="flex items-center">
              <button
                onClick={() => index < step && setStep(index)}
                className={`flex h-9 w-9 items-center justify-center rounded-full text-sm font-bold transition-all ${
                  index === step
                    ? "bg-slate-900 text-white shadow-md ring-4 ring-slate-900/10"
                    : index < step
                      ? "bg-green-500 text-white"
                      : "bg-stone-200 text-stone-400"
                }`}
              >
                {index < step ? "✓" : index + 1}
              </button>
              {index < steps.length - 1 && (
                <div
                  className={`mx-2 h-0.5 w-12 sm:w-20 ${
                    index < step ? "bg-green-500" : "bg-stone-200"
                  }`}
                />
              )}
            </div>
          ))}
        </div>
        <div className="mt-4">
          <h2 className="text-xl font-bold text-slate-900">{steps[step].title}</h2>
          <p className="text-sm text-slate-500">{steps[step].description}</p>
        </div>
      </div>

      {step === 0 && (
        <div className="rounded-2xl border border-stone-200 bg-card p-8 shadow-sm">
          <div className="space-y-5">
            <div>
              <label className="mb-1.5 block text-sm font-semibold text-slate-700">
                {t("onboardingPage.companyName")} <span className="text-red-400">*</span>
              </label>
              <input
                type="text"
                value={companyName}
                onChange={(event) => setCompanyName(event.target.value)}
                placeholder={t("onboardingPage.placeholders.companyName")}
                className="w-full rounded-xl border border-stone-200 bg-stone-50 px-4 py-3 text-sm transition-colors focus:border-slate-900 focus:bg-card focus:outline-none focus:ring-2 focus:ring-slate-900/5"
              />
            </div>

            <div className="grid gap-5 sm:grid-cols-2">
              <div>
                <label className="mb-1.5 block text-sm font-semibold text-slate-700">
                  {t("onboardingPage.industry")}
                </label>
                <select
                  value={industry}
                  onChange={(event) => setIndustry(event.target.value)}
                  className="w-full rounded-xl border border-stone-200 bg-stone-50 px-4 py-3 text-sm focus:border-slate-900 focus:bg-card focus:outline-none focus:ring-2 focus:ring-slate-900/5"
                >
                  {INDUSTRY_VALUES.map((value) => (
                    <option key={value} value={value}>
                      {t(`commonOptions.industries.${value}`)}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label className="mb-1.5 block text-sm font-semibold text-slate-700">
                  {t("onboardingPage.timezone")}
                </label>
                <select
                  value={timezone}
                  onChange={(event) => setTimezone(event.target.value)}
                  className="w-full rounded-xl border border-stone-200 bg-stone-50 px-4 py-3 text-sm focus:border-slate-900 focus:bg-card focus:outline-none focus:ring-2 focus:ring-slate-900/5"
                >
                  {TIMEZONE_VALUES.map((value) => (
                    <option key={value} value={value}>
                      {t(`commonOptions.timezones.${value}`)}
                    </option>
                  ))}
                </select>
              </div>
            </div>

            <div>
              <label className="mb-1.5 block text-sm font-semibold text-slate-700">
                {t("onboardingPage.logoUrl")}{" "}
                <span className="text-slate-500">({t("onboardingPage.optional")})</span>
              </label>
              <input
                type="url"
                value={companyLogo}
                onChange={(event) => setCompanyLogo(event.target.value)}
                placeholder={t("onboardingPage.placeholders.logoUrl")}
                className="w-full rounded-xl border border-stone-200 bg-stone-50 px-4 py-3 text-sm focus:border-slate-900 focus:bg-card focus:outline-none focus:ring-2 focus:ring-slate-900/5"
              />
            </div>
          </div>

          <div className="mt-8 flex items-center justify-between">
            <button
              onClick={() => { setSaveError(null); setStep(1); }}
              className="text-sm font-medium text-slate-500 hover:text-slate-600"
            >
              {t("onboardingPage.skipForNow")} &rarr;
            </button>
            <button
              onClick={saveCompanyStep}
              disabled={!canProceedStep0 || saving}
              className="rounded-xl bg-slate-900 px-8 py-3 text-sm font-semibold text-white shadow-sm transition-all hover:bg-slate-800 disabled:bg-stone-100 disabled:text-slate-400"
            >
              {saving ? "Saving…" : t("onboardingPage.continue")}
            </button>
          </div>
        </div>
      )}

      {step === 1 && (
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <span className="text-sm text-slate-500">
              {t("onboardingPage.workerCountAdded", { count: workers.length, noun: workerNoun })}
            </span>
            <button
              onClick={addWorker}
              className="rounded-xl bg-slate-900 px-5 py-2.5 text-sm font-semibold text-white shadow-sm transition-all hover:bg-slate-800"
            >
              + {t("onboardingPage.addWorker")}
            </button>
          </div>

          {workers.length === 0 && (
            <div className="rounded-2xl border-2 border-dashed border-stone-200 bg-card p-12 text-center">
              <div className="text-3xl text-stone-300">👷</div>
              <p className="mt-3 text-sm font-medium text-slate-500">{t("onboardingPage.noWorkersYet")}</p>
              <p className="mt-1 text-xs text-slate-500">{t("onboardingPage.noWorkersHint")}</p>
              <button
                onClick={addWorker}
                className="mt-5 rounded-xl bg-slate-900 px-6 py-2.5 text-sm font-semibold text-white shadow-sm hover:bg-slate-800"
              >
                + {t("onboardingPage.addFirstWorker")}
              </button>
            </div>
          )}

          {workers.map((worker, index) => (
            <div key={worker.id} className="rounded-2xl border border-stone-200 bg-card p-5 shadow-sm">
              <div className="mb-4 flex items-center justify-between">
                <span className="text-xs font-semibold text-slate-500">
                  {t("onboardingPage.workerLabel", { index: index + 1 })}
                </span>
                <button
                  onClick={() => removeWorker(worker.id)}
                  className="rounded-lg px-2 py-1 text-xs font-medium text-red-400 transition-colors hover:bg-red-50 hover:text-red-600"
                >
                  {t("onboardingPage.remove")}
                </button>
              </div>

              <div className="grid gap-4 sm:grid-cols-2">
                <div>
                  <label className="mb-1 block text-xs font-semibold text-slate-600">
                    {t("onboardingPage.firstName")} <span className="text-red-400">*</span>
                  </label>
                  <input
                    type="text"
                    value={worker.firstName}
                    onChange={(event) => updateWorker(worker.id, "firstName", event.target.value)}
                    placeholder={t("onboardingPage.placeholders.firstName")}
                    className="w-full rounded-lg border border-stone-200 bg-stone-50 px-3 py-2.5 text-sm focus:border-slate-900 focus:bg-card focus:outline-none"
                  />
                </div>
                <div>
                  <label className="mb-1 block text-xs font-semibold text-slate-600">
                    {t("onboardingPage.lastName")}
                  </label>
                  <input
                    type="text"
                    value={worker.lastName}
                    onChange={(event) => updateWorker(worker.id, "lastName", event.target.value)}
                    placeholder={t("onboardingPage.placeholders.lastName")}
                    className="w-full rounded-lg border border-stone-200 bg-stone-50 px-3 py-2.5 text-sm focus:border-slate-900 focus:bg-card focus:outline-none"
                  />
                </div>
                <div>
                  <label className="mb-1 block text-xs font-semibold text-slate-600">
                    {t("onboardingPage.email")}
                    <span className="ml-1 font-normal text-slate-500">(required to send invite)</span>
                  </label>
                  <input
                    type="email"
                    value={worker.email}
                    onChange={(event) => updateWorker(worker.id, "email", event.target.value)}
                    placeholder={t("onboardingPage.placeholders.email")}
                    className="w-full rounded-lg border border-stone-200 bg-stone-50 px-3 py-2.5 text-sm focus:border-slate-900 focus:bg-card focus:outline-none"
                  />
                </div>
                <div>
                  <label className="mb-1 block text-xs font-semibold text-slate-600">
                    {t("onboardingPage.phone")}
                  </label>
                  <input
                    type="tel"
                    value={worker.phone}
                    onChange={(event) => updateWorker(worker.id, "phone", event.target.value)}
                    placeholder={t("onboardingPage.placeholders.phone")}
                    className="w-full rounded-lg border border-stone-200 bg-stone-50 px-3 py-2.5 text-sm focus:border-slate-900 focus:bg-card focus:outline-none"
                  />
                </div>
                <div>
                  <label className="mb-1 block text-xs font-semibold text-slate-600">
                    {t("onboardingPage.address")}{" "}
                    <span className="text-slate-500">({t("onboardingPage.optional")})</span>
                  </label>
                  <input
                    type="text"
                    value={worker.address}
                    onChange={(event) => updateWorker(worker.id, "address", event.target.value)}
                    placeholder={t("onboardingPage.placeholders.address")}
                    className="w-full rounded-lg border border-stone-200 bg-stone-50 px-3 py-2.5 text-sm focus:border-slate-900 focus:bg-card focus:outline-none"
                  />
                </div>
                <div>
                  <label className="mb-1 block text-xs font-semibold text-slate-600">
                    {t("onboardingPage.notes")}{" "}
                    <span className="text-slate-500">({t("onboardingPage.optional")})</span>
                  </label>
                  <input
                    type="text"
                    value={worker.notes}
                    onChange={(event) => updateWorker(worker.id, "notes", event.target.value)}
                    placeholder={t("onboardingPage.placeholders.notes")}
                    className="w-full rounded-lg border border-stone-200 bg-stone-50 px-3 py-2.5 text-sm focus:border-slate-900 focus:bg-card focus:outline-none"
                  />
                </div>
              </div>
            </div>
          ))}

          <div className="flex items-center justify-between pt-4">
            <button
              onClick={() => setStep(0)}
              className="rounded-xl px-6 py-3 text-sm font-semibold text-slate-500 hover:bg-stone-100"
            >
              {t("onboardingPage.back")}
            </button>
            <div className="flex items-center gap-4">
              <button
                onClick={() => { setSaveError(null); setStep(2); }}
                className="text-sm font-medium text-slate-500 hover:text-slate-600"
              >
                {t("onboardingPage.skipForNow")} &rarr;
              </button>
              <button
                onClick={saveTeamStep}
                disabled={!canProceedStep1 || saving}
                className="rounded-xl bg-slate-900 px-8 py-3 text-sm font-semibold text-white shadow-sm hover:bg-slate-800 disabled:bg-stone-100 disabled:text-slate-400"
              >
                {saving ? "Sending invites…" : t("onboardingPage.continue")}
              </button>
            </div>
          </div>

          {workers.filter((w) => !w.email.trim()).length > 0 && (
            <p className="text-xs text-slate-500">
              Workers without an email address will not receive an invite — you can add them manually later from Settings → Staff.
            </p>
          )}
        </div>
      )}

      {step === 2 && (
        <div className="rounded-2xl border border-stone-200 bg-card p-8 shadow-sm">
          <div className="space-y-5">
            <div>
              <label className="mb-1.5 block text-sm font-semibold text-slate-700">
                {t("onboardingPage.jobName")} <span className="text-red-400">*</span>
              </label>
              <input
                type="text"
                value={jobName}
                onChange={(event) => setJobName(event.target.value)}
                placeholder={t("onboardingPage.placeholders.jobName")}
                className="w-full rounded-xl border border-stone-200 bg-stone-50 px-4 py-3 text-sm focus:border-slate-900 focus:bg-card focus:outline-none focus:ring-2 focus:ring-slate-900/5"
              />
            </div>
            <div className="grid gap-5 sm:grid-cols-2">
              <div>
                <label className="mb-1.5 block text-sm font-semibold text-slate-700">
                  {t("onboardingPage.jobCode")}
                  <span className="ml-1 font-normal text-slate-500">(auto-generated if blank)</span>
                </label>
                <input
                  type="text"
                  value={jobCode}
                  onChange={(event) => setJobCode(event.target.value)}
                  placeholder={jobName ? toJobCode(jobName) : t("onboardingPage.placeholders.jobCode")}
                  className="w-full rounded-xl border border-stone-200 bg-stone-50 px-4 py-3 text-sm focus:border-slate-900 focus:bg-card focus:outline-none focus:ring-2 focus:ring-slate-900/5"
                />
              </div>
              <div>
                <label className="mb-1.5 block text-sm font-semibold text-slate-700">
                  {t("onboardingPage.siteAddress")}
                </label>
                <input
                  type="text"
                  value={jobAddress}
                  onChange={(event) => setJobAddress(event.target.value)}
                  placeholder={t("onboardingPage.placeholders.jobAddress")}
                  className="w-full rounded-xl border border-stone-200 bg-stone-50 px-4 py-3 text-sm focus:border-slate-900 focus:bg-card focus:outline-none focus:ring-2 focus:ring-slate-900/5"
                />
              </div>
            </div>

            {workers.length > 0 && (
              <div>
                <label className="mb-1.5 block text-sm font-semibold text-slate-700">
                  {t("onboardingPage.assignWorkers")}
                </label>
                <div className="flex flex-wrap gap-2">
                  {workers.map((worker) => (
                    <span
                      key={worker.id}
                      className="rounded-full bg-stone-100 px-3 py-1.5 text-xs font-medium text-slate-600"
                    >
                      {worker.firstName} {worker.lastName}
                    </span>
                  ))}
                </div>
                <p className="mt-1 text-xs text-slate-500">
                  {t("onboardingPage.allWorkersAssigned", { count: workers.length, noun: workerNoun })}
                </p>
              </div>
            )}
          </div>

          <div className="mt-8 flex justify-between">
            <button
              onClick={() => setStep(1)}
              className="rounded-xl px-6 py-3 text-sm font-semibold text-slate-500 hover:bg-stone-100"
            >
              {t("onboardingPage.back")}
            </button>
            <button
              onClick={saveJobStep}
              disabled={!canProceedStep2 || saving}
              className="rounded-xl bg-slate-900 px-8 py-3 text-sm font-semibold text-white shadow-sm hover:bg-slate-800 disabled:bg-stone-100 disabled:text-slate-400"
            >
              {saving ? "Creating job…" : t("onboardingPage.continue")}
            </button>
          </div>
        </div>
      )}

      {step === 3 && (
        <div className="rounded-2xl border border-stone-200 bg-card p-10 text-center shadow-sm">
          <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-2xl bg-green-50">
            <span className="text-3xl">✓</span>
          </div>
          <h3 className="mt-5 text-2xl font-bold text-slate-900">
            {t("onboardingPage.companyReady", { companyName })}
          </h3>
          <p className="mt-2 text-sm text-slate-500">
            {t("onboardingPage.readySummary", { count: workers.length, noun: workerNoun })}
          </p>

          <div className="mx-auto mt-8 max-w-md rounded-xl bg-stone-50 p-5 text-left">
            <p className="text-xs font-semibold uppercase tracking-wider text-slate-500">
              {t("onboardingPage.nextSteps")}
            </p>
            <ol className="mt-3 space-y-2 text-sm text-slate-600">
              {[1, 2, 3, 4].map((index) => (
                <li key={index} className="flex items-start gap-2">
                  <span className="mt-0.5 flex h-5 w-5 flex-shrink-0 items-center justify-center rounded-full bg-slate-900 text-xs font-bold text-white">
                    {index}
                  </span>
                  {t(`onboardingPage.nextStepItems.${index}`)}
                </li>
              ))}
            </ol>
          </div>

          <div className="mt-8 flex justify-center gap-3">
            <a
              href="/map"
              className="rounded-xl bg-slate-900 px-8 py-3 text-sm font-semibold text-white shadow-sm hover:bg-slate-800"
            >
              {t("onboardingPage.openLiveMap")}
            </a>
            <a
              href="/"
              className="rounded-xl bg-stone-100 px-8 py-3 text-sm font-semibold text-slate-600 hover:bg-stone-200"
            >
              {t("onboardingPage.goToDashboard")}
            </a>
          </div>
        </div>
      )}
    </div>
  );
}
