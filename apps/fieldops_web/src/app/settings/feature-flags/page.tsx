"use client";

import { useCallback, useEffect, useState } from "react";
import { useCurrentUser } from "@/lib/use-role";
import { isManagementRole } from "@/lib/roles";
import { callFunctionJson } from "@/lib/function-client";
import { SkeletonTable } from "@/components/ui/skeleton";

interface Flag {
  flag_key: string;
  description: string | null;
  enabled: boolean;
  source: "default" | "company_override";
}

interface ListResponse {
  status: string;
  flags?: Flag[];
}

type RowState = "idle" | "saving" | "saved" | "error";

export default function FeatureFlagsPage() {
  const currentUser = useCurrentUser();
  const authorized = isManagementRole(currentUser.role);

  const [flags, setFlags] = useState<Flag[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [rowState, setRowState] = useState<Record<string, RowState>>({});
  const [rowError, setRowError] = useState<Record<string, string>>({});

  const load = useCallback(async () => {
    setError(null);
    try {
      const res = await callFunctionJson<ListResponse>("feature_flags", {
        method: "GET",
      });
      setFlags(res.flags ?? []);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load flags");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (currentUser.loading) return;
    if (!authorized) {
      setLoading(false);
      return;
    }
    setLoading(true);
    load();
  }, [authorized, currentUser.loading, load]);

  async function setOverride(flagKey: string, enabled: boolean) {
    const previous = flags.find((f) => f.flag_key === flagKey);
    if (!previous) return;
    setRowState((m) => ({ ...m, [flagKey]: "saving" }));
    setRowError((m) => {
      const n = { ...m };
      delete n[flagKey];
      return n;
    });
    // Optimistic update
    setFlags((list) =>
      list.map((f) =>
        f.flag_key === flagKey
          ? { ...f, enabled, source: "company_override" }
          : f,
      ),
    );
    try {
      await callFunctionJson("feature_flags", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ flag_key: flagKey, enabled }),
      });
      setRowState((m) => ({ ...m, [flagKey]: "saved" }));
      setTimeout(() => {
        setRowState((m) => {
          if (m[flagKey] !== "saved") return m;
          const { [flagKey]: _, ...rest } = m;
          return rest;
        });
      }, 1500);
    } catch (err) {
      // Roll back
      setFlags((list) =>
        list.map((f) => (f.flag_key === flagKey ? previous : f)),
      );
      setRowState((m) => ({ ...m, [flagKey]: "error" }));
      setRowError((m) => ({
        ...m,
        [flagKey]: err instanceof Error ? err.message : "Save failed",
      }));
    }
  }

  async function clearOverride(flagKey: string) {
    const previous = flags.find((f) => f.flag_key === flagKey);
    if (!previous) return;
    setRowState((m) => ({ ...m, [flagKey]: "saving" }));
    setRowError((m) => {
      const n = { ...m };
      delete n[flagKey];
      return n;
    });
    try {
      await callFunctionJson("feature_flags", {
        method: "DELETE",
        query: { flag_key: flagKey },
      });
      await load();
      setRowState((m) => ({ ...m, [flagKey]: "saved" }));
      setTimeout(() => {
        setRowState((m) => {
          if (m[flagKey] !== "saved") return m;
          const { [flagKey]: _, ...rest } = m;
          return rest;
        });
      }, 1500);
    } catch (err) {
      setRowState((m) => ({ ...m, [flagKey]: "error" }));
      setRowError((m) => ({
        ...m,
        [flagKey]: err instanceof Error ? err.message : "Reset failed",
      }));
    }
  }

  if (currentUser.loading || loading) {
    return (
      <div className="p-6">
        <SkeletonTable rows={4} cols={3} />
      </div>
    );
  }

  if (!authorized) {
    return (
      <div className="p-6">
        <div className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800">
          Only owners or admins can manage feature flags.
        </div>
      </div>
    );
  }

  return (
    <div>
      <div className="mb-6">
        <a
          href="/settings"
          className="mb-2 inline-flex items-center gap-1 text-sm font-medium text-slate-500 hover:text-slate-900"
        >
          <span>&larr;</span> Back to Settings
        </a>
        <h1 className="text-2xl font-bold tracking-tight text-slate-900 dark:text-slate-100">Feature Flags</h1>
        <p className="mt-1 text-sm text-slate-600 dark:text-slate-400">
          Toggle features on or off for your company. Overrides win over the
          global default until you reset them.
        </p>
      </div>

      {error && (
        <div className="mb-4 rounded-lg bg-red-50 p-3 text-sm text-red-700">
          {error}
        </div>
      )}

      {flags.length === 0 && !error && (
        <div className="rounded-xl border border-stone-200 bg-card p-8 text-center text-slate-500">
          No feature flags defined yet.
        </div>
      )}

      {flags.length > 0 && (
        <div className="overflow-hidden rounded-2xl border border-stone-200 bg-card shadow-sm">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b bg-stone-50 text-left text-slate-500">
                <th className="px-5 py-3">Flag</th>
                <th className="px-5 py-3">Status</th>
                <th className="px-5 py-3">Source</th>
                <th className="px-5 py-3 text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              {flags.map((f) => {
                const s = rowState[f.flag_key] ?? "idle";
                const err = rowError[f.flag_key];
                const isOverride = f.source === "company_override";
                return (
                  <tr
                    key={f.flag_key}
                    className="border-b border-stone-100 last:border-0"
                  >
                    <td className="px-5 py-4">
                      <div className="font-mono text-xs font-semibold text-slate-900">
                        {f.flag_key}
                      </div>
                      {f.description && (
                        <div className="mt-1 text-xs text-slate-500">
                          {f.description}
                        </div>
                      )}
                    </td>
                    <td className="px-5 py-4">
                      <label className="inline-flex cursor-pointer items-center gap-2">
                        <input
                          type="checkbox"
                          checked={f.enabled}
                          disabled={s === "saving"}
                          onChange={(e) =>
                            setOverride(f.flag_key, e.target.checked)
                          }
                          className="h-4 w-4 rounded border-stone-300 text-amber-500 focus:ring-ring"
                        />
                        <span
                          className={`text-xs font-semibold ${
                            f.enabled ? "text-green-700" : "text-stone-500"
                          }`}
                        >
                          {f.enabled ? "Enabled" : "Disabled"}
                        </span>
                      </label>
                    </td>
                    <td className="px-5 py-4">
                      <span
                        className={`inline-block rounded-full px-2 py-0.5 text-xs font-semibold ${
                          isOverride
                            ? "bg-amber-100 text-amber-700"
                            : "bg-stone-100 text-stone-500"
                        }`}
                      >
                        {isOverride ? "Company override" : "Default"}
                      </span>
                    </td>
                    <td className="px-5 py-4 text-right">
                      {isOverride ? (
                        <button
                          onClick={() => clearOverride(f.flag_key)}
                          disabled={s === "saving"}
                          className="rounded-lg border border-stone-300 bg-card px-3 py-1.5 text-xs font-semibold text-slate-700 shadow-sm hover:bg-stone-50 disabled:bg-stone-100 disabled:text-slate-400"
                        >
                          Reset to default
                        </button>
                      ) : (
                        <span className="text-xs text-stone-400">—</span>
                      )}
                      {s === "saving" && (
                        <span className="ml-2 text-xs text-slate-500">
                          Saving…
                        </span>
                      )}
                      {s === "saved" && (
                        <span className="ml-2 text-xs text-green-600">
                          Saved
                        </span>
                      )}
                      {err && (
                        <div className="mt-1 text-xs text-red-600">{err}</div>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
