/**
 * Company settings helper — deep merge, validation, defaults.
 *
 * Every edge function that reads company settings MUST use
 * getCompanySettings() instead of reading the JSONB directly.
 * This guarantees a complete, validated settings object even
 * if the DB value is null, partial, or malformed.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4"

// ─── Types ─────────────────────────────────────────────────

export interface OTRules {
  weekly_threshold: number
  daily_threshold: number | null
}

export interface NotificationSettings {
  ot_approach: boolean
  missed_clockin: boolean
  shift_reminder: boolean
}

export interface OnboardingSteps {
  logo_uploaded: boolean
  pay_period_set: boolean
  first_staff_invited: boolean
}

export interface CompanySettings {
  stamp_branding: "logo" | "name_only"
  ot_rules: OTRules
  time_rounding: "off" | "5min" | "15min"
  gps_required: boolean
  geofence_radius_default_m: number
  break_alerts: boolean
  break_duration_min: number
  pay_period: "weekly" | "biweekly" | "semimonthly" | "monthly"
  photo_on_clockin: boolean
  notifications: NotificationSettings
  onboarding_steps: OnboardingSteps
  version: number
}

// ─── Defaults ──────────────────────────────────────────────

export const DEFAULT_COMPANY_SETTINGS: CompanySettings = {
  stamp_branding: "name_only",
  ot_rules: { weekly_threshold: 40, daily_threshold: null },
  time_rounding: "off",
  gps_required: true,
  geofence_radius_default_m: 150,
  break_alerts: true,
  break_duration_min: 30,
  pay_period: "weekly",
  photo_on_clockin: false,
  notifications: { ot_approach: true, missed_clockin: true, shift_reminder: true },
  onboarding_steps: { logo_uploaded: false, pay_period_set: false, first_staff_invited: false },
  version: 1,
}

// ─── Deep Merge ────────────────────────────────────────────

/**
 * Recursively merges `source` into `target`. Preserves nested objects
 * instead of overwriting them (unlike Object.assign / spread).
 *
 * Example: deepMerge({ ot_rules: { weekly: 40, daily: null } }, { ot_rules: { weekly: 44 } })
 *       → { ot_rules: { weekly: 44, daily: null } }
 */
function deepMerge<T extends Record<string, unknown>>(target: T, source: Record<string, unknown>): T {
  const result = { ...target } as Record<string, unknown>
  for (const key of Object.keys(source)) {
    const srcVal = source[key]
    const tgtVal = result[key]
    if (
      srcVal !== null &&
      typeof srcVal === "object" &&
      !Array.isArray(srcVal) &&
      tgtVal !== null &&
      typeof tgtVal === "object" &&
      !Array.isArray(tgtVal)
    ) {
      result[key] = deepMerge(tgtVal as Record<string, unknown>, srcVal as Record<string, unknown>)
    } else {
      result[key] = srcVal
    }
  }
  return result as T
}

// ─── Validation ────────────────────────────────────────────

interface ValidationError {
  field: string
  message: string
}

/**
 * Validates a settings object. Returns an array of errors (empty = valid).
 * This is the SERVER-SIDE enforcement — client-side validation is convenience.
 */
export function validateCompanySettings(settings: Record<string, unknown>): ValidationError[] {
  const errors: ValidationError[] = []

  // stamp_branding
  if (settings.stamp_branding !== undefined) {
    if (!["logo", "name_only"].includes(settings.stamp_branding as string)) {
      errors.push({ field: "stamp_branding", message: "must be 'logo' or 'name_only'" })
    }
  }

  // ot_rules
  if (settings.ot_rules !== undefined) {
    const ot = settings.ot_rules as Record<string, unknown>
    if (typeof ot !== "object" || ot === null) {
      errors.push({ field: "ot_rules", message: "must be an object" })
    } else {
      if (ot.weekly_threshold !== undefined && typeof ot.weekly_threshold !== "number") {
        errors.push({ field: "ot_rules.weekly_threshold", message: "must be a number" })
      }
      if (ot.daily_threshold !== undefined && ot.daily_threshold !== null && typeof ot.daily_threshold !== "number") {
        errors.push({ field: "ot_rules.daily_threshold", message: "must be a number or null" })
      }
    }
  }

  // time_rounding
  if (settings.time_rounding !== undefined) {
    if (!["off", "5min", "15min"].includes(settings.time_rounding as string)) {
      errors.push({ field: "time_rounding", message: "must be 'off', '5min', or '15min'" })
    }
  }

  // pay_period
  if (settings.pay_period !== undefined) {
    if (!["weekly", "biweekly", "semimonthly", "monthly"].includes(settings.pay_period as string)) {
      errors.push({ field: "pay_period", message: "must be 'weekly', 'biweekly', 'semimonthly', or 'monthly'" })
    }
  }

  // Boolean fields
  for (const field of ["gps_required", "break_alerts", "photo_on_clockin"]) {
    if (settings[field] !== undefined && typeof settings[field] !== "boolean") {
      errors.push({ field, message: "must be a boolean" })
    }
  }

  // Numeric fields
  for (const field of ["geofence_radius_default_m", "break_duration_min"]) {
    if (settings[field] !== undefined && typeof settings[field] !== "number") {
      errors.push({ field, message: "must be a number" })
    }
  }

  // notifications
  if (settings.notifications !== undefined) {
    const n = settings.notifications as Record<string, unknown>
    if (typeof n !== "object" || n === null) {
      errors.push({ field: "notifications", message: "must be an object" })
    } else {
      for (const key of ["ot_approach", "missed_clockin", "shift_reminder"]) {
        if (n[key] !== undefined && typeof n[key] !== "boolean") {
          errors.push({ field: `notifications.${key}`, message: "must be a boolean" })
        }
      }
    }
  }

  return errors
}

// ─── Main getter ───────────────────────────────────────────

/**
 * Reads company settings from the DB, deep-merges with defaults,
 * and returns a typed, guaranteed-complete CompanySettings object.
 *
 * Use this in every edge function instead of reading settings directly.
 */
export async function getCompanySettings(
  supabaseAdmin: ReturnType<typeof createClient>,
  companyId: string,
): Promise<CompanySettings> {
  const { data } = await supabaseAdmin
    .from("companies")
    .select("settings")
    .eq("id", companyId)
    .single()

  const dbSettings = (data?.settings ?? {}) as Record<string, unknown>

  // Deep merge: DB values override defaults, nested objects are preserved
  return deepMerge(
    structuredClone(DEFAULT_COMPANY_SETTINGS) as Record<string, unknown>,
    dbSettings,
  ) as CompanySettings
}
