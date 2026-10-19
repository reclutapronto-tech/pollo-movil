"use client";

import { useCallback, useEffect, useState } from "react";
import { getSupabase } from "@/lib/supabase";
import { isManagementRole } from "@/lib/roles";
import { useCurrentUser } from "@/lib/use-role";
import { LogoUpload } from "@/components/logo-upload";

/* ── Constants ─────────────────────────────────────────────── */

const TABS = ["General", "Branding", "Time & Attendance", "Notifications"] as const;
type Tab = (typeof TABS)[number];

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

const INDUSTRY_LABELS: Record<string, string> = {
  electrical: "Electrical",
  construction: "General Construction",
  plumbing: "Plumbing",
  hvac: "HVAC",
  telecom: "Telecom / Infrastructure",
  solar: "Solar / Renewable",
  landscaping: "Landscaping",
  other: "Other",
};

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

const TIMEZONE_LABELS: Record<string, string> = {
  "America/New_York": "Eastern Time (ET)",
  "America/Chicago": "Central Time (CT)",
  "America/Denver": "Mountain Time (MT)",
  "America/Los_Angeles": "Pacific Time (PT)",
  "America/Anchorage": "Alaska (AKT)",
  "Pacific/Honolulu": "Hawaii (HST)",
  "Europe/London": "London (GMT)",
  "Europe/Paris": "Paris (CET)",
  "Africa/Abidjan": "West Africa (WAT)",
  "Asia/Bangkok": "Bangkok (ICT)",
  "Asia/Shanghai": "Shanghai (CST)",
  "Asia/Dubai": "Dubai (GST)",
};

const PAY_PERIOD_OPTIONS = [
  { value: "weekly", label: "Weekly" },
  { value: "biweekly", label: "Biweekly" },
  { value: "semimonthly", label: "Semi-monthly" },
  { value: "monthly", label: "Monthly" },
];

const ROUNDING_OPTIONS = [
  { value: "off", label: "Off" },
  { value: "5min", label: "5 minutes" },
  { value: "15min", label: "15 minutes" },
];

/* ── Settings shape ────────────────────────────────────────── */

interface CompanySettings {
  pay_period: string;
  ot_threshold_weekly: number;
  ot_jurisdiction: string;
  time_rounding: string;
  gps_required: boolean;
  geofence_radius: number;
  break_alerts: boolean;
  break_duration: number;
  photo_on_clockin: boolean;
  stamp_mode: "logo" | "name";
  ot_approach_alert: boolean;
  missed_clockin_alert: boolean;
  shift_reminder: boolean;
  onboarding_steps?: {
    upload_logo: boolean;
    set_pay_period: boolean;
    invite_first_staff: boolean;
  };
}

const JURISDICTION_OPTIONS = [
  { value: "federal", label: "Federal (40h/week)" },
  { value: "california", label: "California (8h/day + 40h/week)" },
];

const DEFAULT_SETTINGS: CompanySettings = {
  pay_period: "weekly",
  ot_threshold_weekly: 40,
  ot_jurisdiction: "federal",
  time_rounding: "off",
  gps_required: false,
  geofence_radius: 150,
  break_alerts: false,
  break_duration: 30,
  photo_on_clockin: false,
  stamp_mode: "logo",
  ot_approach_alert: true,
  missed_clockin_alert: true,
  shift_reminder: true,
  onboarding_steps: {
    upload_logo: false,
    set_pay_period: false,
    invite_first_staff: false,
  },
};

/* ── Page ──────────────────────────────────────────────────── */

export default function CompanySettingsPage() {
  const currentUser = useCurrentUser();

  const [activeTab, setActiveTab] = useState<Tab>("General");

  // Company fields
  const [companyName, setCompanyName] = useState("");
  const [industry, setIndustry] = useState("electrical");
  const [address, setAddress] = useState("");
  const [phone, setPhone] = useState("");
  const [email, setEmail] = useState("");
  const [timezone, setTimezone] = useState("America/New_York");
  const [defaultLocale, setDefaultLocale] = useState("en");
  const [logoUrl, setLogoUrl] = useState<string | null>(null);

  // Settings fields
  const [settings, setSettings] = useState<CompanySettings>(DEFAULT_SETTINGS);
  const [settingsVersion, setSettingsVersion] = useState(0);

  // UI state
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [toast, setToast] = useState<{ type: "success" | "error"; message: string } | null>(null);
  const [dirty, setDirty] = useState(false);

  /* ── Load company data ───────────────────────────────────── */

  const loadCompany = useCallback(async (companyId: string) => {
    try {
      const supabase = getSupabase();
      const { data, error } = await supabase
        .from("companies")
        .select("*")
        .eq("id", companyId)
        .single();

      if (error || !data) return;

      setCompanyName(data.name ?? "");
      setIndustry(data.industry ?? "electrical");
      setAddress(data.address ?? "");
      setPhone(data.phone ?? "");
      setEmail(data.email ?? "");
      setTimezone(data.timezone ?? "America/New_York");
      setDefaultLocale(data.default_locale ?? "en");
      setLogoUrl(data.logo_url ?? null);
      setSettingsVersion(data.settings_version ?? 0);

      // Normalize DB settings format → page format
      const raw = data.settings ?? {};
      const notifications = raw.notifications ?? {};
      const otRules = raw.ot_rules ?? {};
      const onboard = raw.onboarding_steps ?? {};

      setSettings({
        ...DEFAULT_SETTINGS,
        // Direct-mapped keys
        pay_period: raw.pay_period ?? DEFAULT_SETTINGS.pay_period,
        time_rounding: raw.time_rounding ?? DEFAULT_SETTINGS.time_rounding,
        gps_required: raw.gps_required ?? DEFAULT_SETTINGS.gps_required,
        break_alerts: raw.break_alerts ?? DEFAULT_SETTINGS.break_alerts,
        photo_on_clockin: raw.photo_on_clockin ?? DEFAULT_SETTINGS.photo_on_clockin,
        // Renamed keys (DB → page)
        stamp_mode: raw.stamp_branding === "name_only" ? "name" : raw.stamp_mode ?? DEFAULT_SETTINGS.stamp_mode,
        geofence_radius: raw.geofence_radius_default_m ?? raw.geofence_radius ?? DEFAULT_SETTINGS.geofence_radius,
        break_duration: raw.break_duration_min ?? raw.break_duration ?? DEFAULT_SETTINGS.break_duration,
        ot_threshold_weekly: otRules.weekly_threshold ?? raw.ot_threshold_weekly ?? DEFAULT_SETTINGS.ot_threshold_weekly,
        ot_jurisdiction: otRules.daily_threshold != null ? "california" : raw.ot_jurisdiction ?? DEFAULT_SETTINGS.ot_jurisdiction,
        // Nested notifications → flat keys
        ot_approach_alert: notifications.ot_approach ?? raw.ot_approach_alert ?? DEFAULT_SETTINGS.ot_approach_alert,
        missed_clockin_alert: notifications.missed_clockin ?? raw.missed_clockin_alert ?? DEFAULT_SETTINGS.missed_clockin_alert,
        shift_reminder: notifications.shift_reminder ?? raw.shift_reminder ?? DEFAULT_SETTINGS.shift_reminder,
        // Onboarding key remap
        onboarding_steps: {
          upload_logo: onboard.logo_uploaded ?? onboard.upload_logo ?? false,
          set_pay_period: onboard.pay_period_set ?? onboard.set_pay_period ?? false,
          invite_first_staff: onboard.first_staff_invited ?? onboard.invite_first_staff ?? false,
        },
      });
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (currentUser.companyId && !currentUser.loading) {
      loadCompany(currentUser.companyId);
    } else if (!currentUser.loading) {
      setLoading(false);
    }
  }, [currentUser.companyId, currentUser.loading, loadCompany]);

  /* ── Save ────────────────────────────────────────────────── */

  async function handleSave() {
    if (!currentUser.companyId) return;

    // Basic validation
    if (!companyName.trim()) {
      setToast({ type: "error", message: "Company name is required." });
      return;
    }

    setSaving(true);
    setToast(null);

    try {
      const supabase = getSupabase();
      const { error } = await supabase
        .from("companies")
        .update({
          name: companyName.trim(),
          industry,
          address: address.trim(),
          phone: phone.trim(),
          email: email.trim(),
          timezone,
          default_locale: defaultLocale,
          settings: { ...settings },
          settings_version: settingsVersion + 1,
        })
        .eq("id", currentUser.companyId);

      if (error) throw error;

      setSettingsVersion((prev) => prev + 1);
      setDirty(false);
      setToast({ type: "success", message: "Settings saved" });
    } catch {
      setToast({ type: "error", message: "Failed to save settings" });
    } finally {
      setSaving(false);
      setTimeout(() => setToast(null), 4000);
    }
  }

  /* ── Helpers ─────────────────────────────────────────────── */

  function updateSetting<K extends keyof CompanySettings>(key: K, value: CompanySettings[K]) {
    setSettings((prev) => ({ ...prev, [key]: value }));
    setDirty(true);
  }

  /* ── Access denied ───────────────────────────────────────── */

  if (!currentUser.loading && !isManagementRole(currentUser.role)) {
    return (
      <div className="mt-20 text-center">
        <h2 className="text-xl font-bold text-slate-900">Access Denied</h2>
        <p className="mt-2 text-sm text-slate-500">
          Only owners and administrators can access company settings.
        </p>
        <a
          href="/"
          className="mt-4 inline-block text-sm font-medium text-amber-600 hover:text-amber-700"
        >
          &larr; Back to dashboard
        </a>
      </div>
    );
  }

  /* ── Loading ─────────────────────────────────────────────── */

  if (loading || currentUser.loading) {
    return (
      <div className="flex items-center gap-2 pt-20 text-sm text-slate-500">
        <div className="h-4 w-4 animate-spin rounded-full border-2 border-stone-200 border-t-slate-900" />
        Loading...
      </div>
    );
  }

  /* ── Onboarding checklist ────────────────────────────────── */

  const onboarding = settings.onboarding_steps;
  const completedSteps = onboarding
    ? [onboarding.upload_logo, onboarding.set_pay_period, onboarding.invite_first_staff].filter(Boolean).length
    : 0;
  const hasIncompleteOnboarding = onboarding && completedSteps < 3;
  const setupProgress = Math.round((completedSteps / 3) * 100);

  /* ── Render ──────────────────────────────────────────────── */

  return (
    <div className="mx-auto max-w-2xl">
      <h1 className="text-2xl font-bold tracking-tight text-slate-900">Company Settings</h1>
      <p className="mt-1 text-sm text-slate-500">Manage your company configuration and preferences</p>

      {/* First-run checklist with progress ring */}
      {hasIncompleteOnboarding && (
        <div className="mt-6 rounded-2xl border border-stone-200 bg-card p-6 shadow-sm">
          <div className="flex items-center gap-5">
            <ProgressRing progress={setupProgress} />
            <div>
              <h3 className="text-sm font-bold text-slate-900">Setup Progress</h3>
              <p className="text-xs text-slate-500">{completedSteps} of 3 complete</p>
            </div>
          </div>
          <div className="mt-5 grid gap-3 sm:grid-cols-3">
            <SetupCard
              done={onboarding?.upload_logo ?? false}
              icon="🎨"
              title="Upload Logo"
              description="Add your company branding"
              onClick={() => setActiveTab("Branding")}
            />
            <SetupCard
              done={onboarding?.set_pay_period ?? false}
              icon="📅"
              title="Configure Pay Period"
              description="Set weekly, biweekly, or monthly"
              onClick={() => setActiveTab("Time & Attendance")}
            />
            <SetupCard
              done={onboarding?.invite_first_staff ?? false}
              icon="👤"
              title="Add First Staff"
              description="Invite your team members"
              href="/settings/staff"
            />
          </div>
        </div>
      )}

      {/* Tabs */}
      <div className="mt-6 flex gap-1 rounded-xl bg-stone-100 p-1">
        {TABS.map((tab) => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            className={`flex-1 rounded-lg px-3 py-2 text-xs font-semibold transition-all ${
              activeTab === tab
                ? "bg-card text-slate-900 shadow-sm"
                : "text-slate-500 hover:text-slate-600"
            }`}
          >
            {tab}
          </button>
        ))}
      </div>

      {/* Tab content */}
      <div className="mt-6">
        {activeTab === "General" && (
          <Card title="Company Information">
            <div className="space-y-4">
              <Field
                label="Company Name"
                value={companyName}
                onChange={(v) => { setCompanyName(v); setDirty(true); }}
                required
              />
              <div className="grid gap-4 sm:grid-cols-2">
                <SelectField
                  label="Industry"
                  value={industry}
                  onChange={(v) => { setIndustry(v); setDirty(true); }}
                  options={INDUSTRY_VALUES.map((v) => ({ value: v, label: INDUSTRY_LABELS[v] ?? v }))}
                />
                <SelectField
                  label="Timezone"
                  value={timezone}
                  onChange={(v) => { setTimezone(v); setDirty(true); }}
                  options={TIMEZONE_VALUES.map((v) => ({ value: v, label: TIMEZONE_LABELS[v] ?? v }))}
                />
              </div>
              <Field label="Address" value={address} onChange={(v) => { setAddress(v); setDirty(true); }} placeholder="123 Main St, City, State" />
              <div className="grid gap-4 sm:grid-cols-2">
                <Field label="Phone" value={phone} onChange={(v) => { setPhone(v); setDirty(true); }} placeholder="(555) 123-4567" type="tel" />
                <Field label="Email" value={email} onChange={(v) => { setEmail(v); setDirty(true); }} placeholder="office@company.com" type="email" />
              </div>
              <SelectField
                label="Default Locale"
                value={defaultLocale}
                onChange={(v) => { setDefaultLocale(v); setDirty(true); }}
                options={[
                  { value: "en", label: "English" },
                  { value: "es", label: "Spanish" },
                  { value: "th", label: "Thai" },
                ]}
              />
            </div>
          </Card>
        )}

        {activeTab === "Branding" && (
          <Card title="Branding">
            <div className="space-y-5">
              <div>
                <label className="mb-2 block text-xs font-semibold text-slate-600">
                  Company Logo
                </label>
                <LogoUpload
                  currentLogoUrl={logoUrl}
                  onLogoChanged={(url) => setLogoUrl(url)}
                />
              </div>

              <div>
                <label className="mb-2 block text-xs font-semibold text-slate-600">
                  Photo stamp includes:
                </label>
                <div className="flex gap-3">
                  <label
                    className={`flex cursor-pointer items-center gap-2 rounded-lg border px-4 py-2.5 text-sm font-medium transition-all ${
                      settings.stamp_mode === "logo"
                        ? "border-slate-900 bg-slate-50 text-slate-900"
                        : "border-stone-200 text-slate-500 hover:border-stone-300"
                    }`}
                  >
                    <input
                      type="radio"
                      name="stamp_mode"
                      value="logo"
                      checked={settings.stamp_mode === "logo"}
                      onChange={() => updateSetting("stamp_mode", "logo")}
                      className="sr-only"
                    />
                    Company Logo
                  </label>
                  <label
                    className={`flex cursor-pointer items-center gap-2 rounded-lg border px-4 py-2.5 text-sm font-medium transition-all ${
                      settings.stamp_mode === "name"
                        ? "border-slate-900 bg-slate-50 text-slate-900"
                        : "border-stone-200 text-slate-500 hover:border-stone-300"
                    }`}
                  >
                    <input
                      type="radio"
                      name="stamp_mode"
                      value="name"
                      checked={settings.stamp_mode === "name"}
                      onChange={() => updateSetting("stamp_mode", "name")}
                      className="sr-only"
                    />
                    Company Name Only
                  </label>
                </div>
                <p className="mt-2 text-xs text-slate-500">
                  Preview: {settings.stamp_mode === "logo" && logoUrl
                    ? "Photos will include your logo watermark"
                    : `Photos will show "${companyName || "Company Name"}"`}
                </p>
              </div>
            </div>
          </Card>
        )}

        {activeTab === "Time & Attendance" && (
          <Card title="Time & Attendance">
            <div className="space-y-5">
              <SelectField
                label="Pay Period"
                value={settings.pay_period}
                onChange={(v) => updateSetting("pay_period", v)}
                options={PAY_PERIOD_OPTIONS}
              />
              <NumberField
                label="OT Threshold (weekly hours)"
                value={settings.ot_threshold_weekly}
                onChange={(v) => updateSetting("ot_threshold_weekly", v)}
                min={0}
                max={168}
              />
              <SelectField
                label="OT Jurisdiction"
                value={settings.ot_jurisdiction}
                onChange={(v) => updateSetting("ot_jurisdiction", v)}
                options={JURISDICTION_OPTIONS}
              />
              <SelectField
                label="Time Rounding"
                value={settings.time_rounding}
                onChange={(v) => updateSetting("time_rounding", v)}
                options={ROUNDING_OPTIONS}
              />
              <ToggleField
                label="GPS Required on Clock-in"
                description="Workers must enable GPS when clocking in"
                checked={settings.gps_required}
                onChange={(v) => updateSetting("gps_required", v)}
              />

              {settings.gps_required && (
                <div>
                  <label className="mb-1.5 block text-xs font-semibold text-slate-600">
                    Default Geofence Radius: {settings.geofence_radius}m
                  </label>
                  <input
                    type="range"
                    min={50}
                    max={500}
                    step={10}
                    value={settings.geofence_radius}
                    onChange={(e) => updateSetting("geofence_radius", Number(e.target.value))}
                    className="w-full accent-amber-500"
                  />
                  <div className="mt-1 flex justify-between text-xs text-slate-500">
                    <span>50m</span>
                    <span>500m</span>
                  </div>
                </div>
              )}

              <ToggleField
                label="Break Alerts"
                description="Remind workers to take mandatory breaks"
                checked={settings.break_alerts}
                onChange={(v) => updateSetting("break_alerts", v)}
              />

              {settings.break_alerts && (
                <NumberField
                  label="Break Duration (minutes)"
                  value={settings.break_duration}
                  onChange={(v) => updateSetting("break_duration", v)}
                  min={5}
                  max={120}
                />
              )}

              <ToggleField
                label="Photo on Clock-in"
                description="Require a photo when clocking in"
                checked={settings.photo_on_clockin}
                onChange={(v) => updateSetting("photo_on_clockin", v)}
              />
            </div>
          </Card>
        )}

        {activeTab === "Notifications" && (
          <Card title="Notifications">
            <div className="space-y-4">
              <ToggleField
                label="OT Approach Alert"
                description="Notify when workers near overtime threshold"
                checked={settings.ot_approach_alert}
                onChange={(v) => updateSetting("ot_approach_alert", v)}
              />
              <ToggleField
                label="Missed Clock-in Alert"
                description="Alert when scheduled workers haven't clocked in"
                checked={settings.missed_clockin_alert}
                onChange={(v) => updateSetting("missed_clockin_alert", v)}
              />
              <ToggleField
                label="Shift Reminder"
                description="Remind workers before their shift starts"
                checked={settings.shift_reminder}
                onChange={(v) => updateSetting("shift_reminder", v)}
              />
            </div>
          </Card>
        )}
      </div>

      {/* Save button + toast + unsaved indicator */}
      <div className="mt-6 flex items-center justify-between pb-8">
        <div className="flex items-center gap-3">
          {dirty && !toast && (
            <span className="flex items-center gap-1.5 text-xs font-medium text-amber-600">
              <span className="h-1.5 w-1.5 rounded-full bg-amber-500" />
              Unsaved changes
            </span>
          )}
          {toast && (
            <span
              className={`text-sm font-medium ${
                toast.type === "success" ? "text-green-600" : "text-red-500"
              }`}
            >
              {toast.message}
            </span>
          )}
        </div>
        <button
          onClick={handleSave}
          disabled={saving}
          className={`rounded-xl px-8 py-3 text-sm font-semibold shadow-sm transition-all ${
            dirty
              ? "bg-amber-500 text-white hover:bg-amber-600"
              : "bg-slate-900 text-white hover:bg-slate-800"
          } disabled:bg-stone-100 disabled:text-slate-400`}
        >
          {saving ? "Saving..." : "Save Changes"}
        </button>
      </div>
    </div>
  );
}

/* ── Shared sub-components ─────────────────────────────────── */

function Card({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-2xl border border-stone-200 bg-card p-6 shadow-sm">
      <h2 className="mb-5 text-sm font-bold uppercase tracking-wider text-slate-500">{title}</h2>
      {children}
    </div>
  );
}

function ProgressRing({ progress }: { progress: number }) {
  const r = 36;
  const c = 2 * Math.PI * r;
  const offset = c - (progress / 100) * c;
  return (
    <svg width="88" height="88" className="rotate-[-90deg]">
      <circle cx="44" cy="44" r={r} fill="none" stroke="#e7e5e4" strokeWidth="6" />
      <circle cx="44" cy="44" r={r} fill="none" stroke="#10b981" strokeWidth="6"
        strokeDasharray={c} strokeDashoffset={offset} strokeLinecap="round"
        className="transition-all duration-500" />
    </svg>
  );
}

function SetupCard({
  done,
  icon,
  title,
  description,
  onClick,
  href,
}: {
  done: boolean;
  icon: string;
  title: string;
  description: string;
  onClick?: () => void;
  href?: string;
}) {
  const content = (
    <div
      className={`flex flex-col items-center gap-2 rounded-xl border p-4 text-center transition-all ${
        done
          ? "border-green-200 bg-green-50"
          : "border-stone-200 bg-stone-50 hover:border-stone-300 hover:shadow-sm"
      }`}
    >
      <span className="text-2xl">{icon}</span>
      <div>
        <p className={`text-sm font-semibold ${done ? "text-green-700" : "text-slate-900"}`}>
          {done ? `${title} \u2713` : title}
        </p>
        <p className="mt-0.5 text-xs text-slate-500">{description}</p>
      </div>
      {!done && (
        <span className="text-xs font-semibold text-amber-600 hover:text-amber-700">
          Set up &rarr;
        </span>
      )}
    </div>
  );

  if (href && !done) {
    return <a href={href}>{content}</a>;
  }
  if (onClick && !done) {
    return <button onClick={onClick} className="text-left">{content}</button>;
  }
  return content;
}

function Field({
  label,
  value,
  onChange,
  placeholder,
  type = "text",
  required = false,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  type?: string;
  required?: boolean;
}) {
  return (
    <div>
      <label className="mb-1.5 block text-xs font-semibold text-slate-600">
        {label}
        {required && <span className="text-red-400"> *</span>}
      </label>
      <input
        type={type}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        className="w-full rounded-lg border border-stone-200 bg-stone-50 px-3 py-2.5 text-sm transition-colors focus:border-slate-900 focus:bg-card focus:outline-none"
      />
    </div>
  );
}

function SelectField({
  label,
  value,
  onChange,
  options,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  options: { value: string; label: string }[];
}) {
  return (
    <div>
      <label className="mb-1.5 block text-xs font-semibold text-slate-600">{label}</label>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="w-full rounded-lg border border-stone-200 bg-stone-50 px-3 py-2.5 text-sm focus:border-slate-900 focus:bg-card focus:outline-none"
      >
        {options.map((opt) => (
          <option key={opt.value} value={opt.value}>
            {opt.label}
          </option>
        ))}
      </select>
    </div>
  );
}

function NumberField({
  label,
  value,
  onChange,
  min,
  max,
}: {
  label: string;
  value: number;
  onChange: (value: number) => void;
  min?: number;
  max?: number;
}) {
  return (
    <div>
      <label className="mb-1.5 block text-xs font-semibold text-slate-600">{label}</label>
      <input
        type="number"
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        min={min}
        max={max}
        className="w-full rounded-lg border border-stone-200 bg-stone-50 px-3 py-2.5 text-sm transition-colors focus:border-slate-900 focus:bg-card focus:outline-none"
      />
    </div>
  );
}

function ToggleField({
  label,
  description,
  checked,
  onChange,
}: {
  label: string;
  description: string;
  checked: boolean;
  onChange: (value: boolean) => void;
}) {
  return (
    <div className="flex items-center justify-between rounded-lg border border-stone-200 p-3">
      <div>
        <span className="text-sm font-medium text-slate-700">{label}</span>
        <p className="text-xs text-slate-500">{description}</p>
      </div>
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        aria-label={label}
        onClick={() => onChange(!checked)}
        className={`relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer items-center rounded-full transition-colors duration-200 ease-in-out focus:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 ${
          checked ? "bg-amber-500" : "bg-stone-300"
        }`}
      >
        <span
          aria-hidden="true"
          className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-card shadow ring-0 transition-transform duration-200 ease-in-out ${
            checked ? "translate-x-[22px]" : "translate-x-0.5"
          }`}
        />
      </button>
    </div>
  );
}
