"use client";

import { useCallback, useEffect, useState } from "react";
import { useCurrentUser } from "@/lib/use-role";
import { isSupervisorOrAbove } from "@/lib/roles";
import { callFunctionJson } from "@/lib/function-client";
import { SkeletonTable } from "@/components/ui/skeleton";

interface AlertEvent {
  id: string;
  company_id: string;
  job_id: string | null;
  user_id: string | null;
  alert_type: string;
  severity: string;
  status: "open" | "resolved" | "dismissed";
  message: string;
  triggered_at: string;
  resolved_at: string | null;
  resolved_by: string | null;
}

interface ListResponse {
  status: string;
  alerts?: AlertEvent[];
  count?: number;
}

interface ScanResponse {
  status: string;
  alerts_generated?: number;
}

type StatusFilter = "open" | "resolved" | "dismissed";

const SEVERITY_STYLE: Record<string, string> = {
  high: "bg-red-100 text-red-700",
  medium: "bg-amber-100 text-amber-700",
  low: "bg-stone-100 text-stone-600",
};

export default function AlertsPage() {
  const currentUser = useCurrentUser();
  const authorized = isSupervisorOrAbove(currentUser.role);

  const [alerts, setAlerts] = useState<AlertEvent[]>([]);
  const [status, setStatus] = useState<StatusFilter>("open");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [scanning, setScanning] = useState(false);
  const [rowBusy, setRowBusy] = useState<Record<string, boolean>>({});
  const [toast, setToast] = useState<string | null>(null);

  const load = useCallback(async () => {
    setError(null);
    try {
      const res = await callFunctionJson<ListResponse>("alerts", {
        method: "GET",
        query: { status },
      });
      setAlerts(res.alerts ?? []);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load alerts");
    } finally {
      setLoading(false);
    }
  }, [status]);

  useEffect(() => {
    if (currentUser.loading) return;
    if (!authorized) {
      setLoading(false);
      return;
    }
    setLoading(true);
    load();
  }, [authorized, currentUser.loading, load]);

  async function runScan() {
    setScanning(true);
    setError(null);
    try {
      const res = await callFunctionJson<ScanResponse>("alerts", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "scan" }),
      });
      const n = res.alerts_generated ?? 0;
      setToast(
        n === 0
          ? "Scan complete — no new alerts."
          : `Scan complete — ${n} new alert${n === 1 ? "" : "s"}.`,
      );
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Scan failed");
    } finally {
      setScanning(false);
      setTimeout(() => setToast(null), 3000);
    }
  }

  async function decide(alertId: string, resolution: "resolve" | "dismiss") {
    setRowBusy((m) => ({ ...m, [alertId]: true }));
    try {
      await callFunctionJson("alerts", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "resolve", alert_id: alertId, resolution }),
      });
      // Optimistically drop the row if we're on the open tab
      if (status === "open") {
        setAlerts((list) => list.filter((a) => a.id !== alertId));
      } else {
        await load();
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "Action failed");
    } finally {
      setRowBusy((m) => {
        const n = { ...m };
        delete n[alertId];
        return n;
      });
    }
  }

  if (currentUser.loading || loading) {
    return (
      <div className="p-6">
        <SkeletonTable rows={6} cols={4} />
      </div>
    );
  }

  if (!authorized) {
    return (
      <div className="p-6">
        <div className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800">
          Only supervisors, admins, or owners can view alerts.
        </div>
      </div>
    );
  }

  return (
    <div>
      <div className="mb-6">
        <a
          href="/"
          className="mb-2 inline-flex items-center gap-1 text-sm font-medium text-slate-500 hover:text-slate-900"
        >
          <span>&larr;</span> Back to Dashboard
        </a>
        <div className="flex items-start justify-between">
          <div>
            <h1 className="text-2xl font-bold tracking-tight text-slate-900 dark:text-slate-100">Alerts</h1>
            <p className="mt-1 text-slate-600">
              Operational anomalies detected from clock events, OT, and job
              activity. Run a scan to generate new alerts, then resolve or
              dismiss each one.
            </p>
          </div>
          <button
            onClick={runScan}
            disabled={scanning}
            className="rounded-lg bg-amber-500 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-amber-600 disabled:bg-stone-100 disabled:text-slate-400"
          >
            {scanning ? "Scanning…" : "Run scan"}
          </button>
        </div>
      </div>

      {toast && (
        <div className="mb-4 rounded-lg bg-green-50 p-3 text-sm text-green-700">
          {toast}
        </div>
      )}

      {error && (
        <div className="mb-4 rounded-lg bg-red-50 p-3 text-sm text-red-700 dark:bg-red-950/30 dark:text-red-300">
          {error}
        </div>
      )}

      <div className="mb-6 flex flex-wrap gap-2">
        {(["open", "resolved", "dismissed"] as const).map((s) => (
          <button
            key={s}
            onClick={() => setStatus(s)}
            className={`rounded-full px-4 py-1.5 text-sm font-semibold capitalize transition-colors ${
              status === s
                ? "bg-amber-500 text-white"
                : "bg-stone-100 text-slate-600 hover:bg-stone-200"
            }`}
          >
            {s}
          </button>
        ))}
      </div>

      {alerts.length === 0 && !error && (
        <div className="rounded-xl border border-stone-200 bg-card p-8 text-center text-slate-500">
          No {status} alerts.
        </div>
      )}

      {alerts.length > 0 && (
        <div className="overflow-hidden rounded-2xl border border-stone-200 bg-card shadow-sm">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b bg-stone-50 text-left text-slate-500">
                <th className="px-5 py-3">Triggered</th>
                <th className="px-5 py-3">Type</th>
                <th className="px-5 py-3">Severity</th>
                <th className="px-5 py-3">Message</th>
                <th className="px-5 py-3 text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              {alerts.map((a) => {
                const busy = rowBusy[a.id] ?? false;
                return (
                  <tr
                    key={a.id}
                    className="border-b border-stone-100 last:border-0 align-top"
                  >
                    <td className="whitespace-nowrap px-5 py-4 text-xs text-slate-500">
                      {new Date(a.triggered_at).toLocaleString()}
                    </td>
                    <td className="px-5 py-4">
                      <span className="font-mono text-xs text-slate-900">
                        {a.alert_type}
                      </span>
                    </td>
                    <td className="px-5 py-4">
                      <span
                        className={`inline-block rounded-full px-2 py-0.5 text-xs font-semibold ${
                          SEVERITY_STYLE[a.severity] ??
                          "bg-stone-100 text-stone-600"
                        }`}
                      >
                        {a.severity}
                      </span>
                    </td>
                    <td className="px-5 py-4 text-slate-700">{a.message}</td>
                    <td className="px-5 py-4 text-right">
                      {status === "open" ? (
                        <div className="inline-flex gap-2">
                          <button
                            onClick={() => decide(a.id, "resolve")}
                            disabled={busy}
                            className="rounded-lg bg-green-600 px-3 py-1.5 text-xs font-semibold text-white shadow-sm hover:bg-green-700 disabled:bg-stone-100 disabled:text-slate-400"
                          >
                            Resolve
                          </button>
                          <button
                            onClick={() => decide(a.id, "dismiss")}
                            disabled={busy}
                            className="rounded-lg border border-stone-300 bg-card px-3 py-1.5 text-xs font-semibold text-slate-700 shadow-sm hover:bg-stone-50 disabled:bg-stone-100 disabled:text-slate-400"
                          >
                            Dismiss
                          </button>
                        </div>
                      ) : (
                        <span className="text-xs text-stone-400">
                          {a.resolved_at
                            ? new Date(a.resolved_at).toLocaleString()
                            : "—"}
                        </span>
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
