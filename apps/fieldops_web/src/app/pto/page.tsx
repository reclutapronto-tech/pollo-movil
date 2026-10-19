"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useI18n } from "@/lib/i18n";
import { callFunctionJson } from "@/lib/function-client";
import { SkeletonCard } from "@/components/ui/skeleton";
import { BulkActionBar } from "@/components/bulk-action-bar";
import { useToast } from "@/components/ui/toast";

interface PTORequest {
  id: string;
  user_id: string;
  pto_type: string;
  start_date: string;
  end_date: string;
  day_count: number;
  status: string;
  notes: string | null;
  decided_by: string | null;
  decided_at: string | null;
  decision_reason: string | null;
  created_at: string;
  users: { full_name: string } | null;
}

interface PTOListResponse {
  requests?: PTORequest[];
}

const STATUS_COLORS: Record<string, { bg: string; text: string }> = {
  pending: { bg: "bg-amber-100", text: "text-amber-700" },
  approved: { bg: "bg-green-100", text: "text-green-700" },
  denied: { bg: "bg-red-100", text: "text-red-700" },
  cancelled: { bg: "bg-stone-100", text: "text-stone-500" },
};

const TYPE_LABELS: Record<string, string> = {
  vacation: "Vacation",
  sick: "Sick Leave",
  personal: "Personal",
};

export default function PTOPage() {
  const { t } = useI18n();
  const [allRequests, setAllRequests] = useState<PTORequest[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<string>("pending");
  const { toast, showToast } = useToast();
  const [decidingId, setDecidingId] = useState<string | null>(null);
  const [decisionReason, setDecisionReason] = useState("");
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [bulkDecision, setBulkDecision] = useState<"" | "approved" | "denied">("");
  const [bulkReasonInput, setBulkReasonInput] = useState("");
  const [bulkInFlight, setBulkInFlight] = useState(false);
  const [bulkProgress, setBulkProgress] = useState<{ done: number; total: number } | null>(null);

  const loadRequests = useCallback(async () => {
    setError(null);
    try {
      // No status param → server returns all (limit 100). Tabs filter
      // client-side so KPI cards always see the full picture and tab
      // switches are instant with no request race.
      const payload = await callFunctionJson<PTOListResponse>("pto", {});
      setAllRequests(payload.requests ?? []);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load PTO requests");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    setLoading(true);
    loadRequests();
  }, [loadRequests]);

  // Clear bulk selection when switching tabs so the select-all checkbox and
  // count always describe the visible rows.
  useEffect(() => {
    setSelectedIds(new Set());
    setBulkDecision("");
    setBulkReasonInput("");
  }, [filter]);

  async function handleDecision(requestId: string, decision: "approved" | "denied") {
    // Denials must carry an explanation — the worker sees it. (The bulk
    // path already enforces this; single-row now matches.)
    if (decision === "denied" && !decisionReason.trim()) {
      setError("Please give a reason for the denial — the worker will see it.");
      return;
    }
    try {
      await callFunctionJson("pto", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          action: "decide",
          pto_request_id: requestId,
          decision,
          reason: decisionReason || undefined,
        }),
      });

      setDecidingId(null);
      setDecisionReason("");
      showToast(decision === "approved" ? "PTO approved" : "PTO denied");
      loadRequests();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Decision failed");
    }
  }

  const runBulkDecision = useCallback(
    async (decision: "approved" | "denied", reason: string) => {
      const ids = Array.from(selectedIds);
      if (ids.length === 0) return;
      setBulkInFlight(true);
      setBulkProgress({ done: 0, total: ids.length });
      setError(null);
      try {
        // Serial loop through the existing single-row endpoint — mirrors the
        // /overtime bulk flow. Each call gets its own Idempotency-Key.
        for (let i = 0; i < ids.length; i++) {
          await callFunctionJson("pto", {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "Idempotency-Key": crypto.randomUUID(),
            },
            body: JSON.stringify({
              action: "decide",
              pto_request_id: ids[i],
              decision,
              reason: reason.trim() || undefined,
            }),
          });
          setBulkProgress({ done: i + 1, total: ids.length });
        }
        setSelectedIds(new Set());
        setBulkDecision("");
        setBulkReasonInput("");
        showToast(`${ids.length} request${ids.length === 1 ? "" : "s"} ${decision}`);
        await loadRequests();
      } catch (e) {
        setError(e instanceof Error ? e.message : t("ptoPage.decisionFailed"));
      } finally {
        setBulkInFlight(false);
        setBulkProgress(null);
      }
    },
    [selectedIds, loadRequests, showToast, t],
  );

  function toggleSelected(id: string) {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  const requests = useMemo(
    () => allRequests.filter((r) => r.status === filter),
    [allRequests, filter],
  );

  const kpiStats = useMemo(() => {
    const now = new Date();
    const todayStr = now.toISOString().slice(0, 10);
    const currentMonth = now.getMonth();
    const currentYear = now.getFullYear();

    const pendingCount = allRequests.filter((r) => r.status === "pending").length;
    const upcomingApproved = allRequests.filter(
      (r) => r.status === "approved" && r.start_date >= todayStr,
    ).length;
    const daysOffThisMonth = allRequests
      .filter((r) => {
        if (r.status !== "approved") return false;
        const start = new Date(r.start_date);
        return start.getMonth() === currentMonth && start.getFullYear() === currentYear;
      })
      .reduce((sum, r) => sum + r.day_count, 0);

    return { pendingCount, upcomingApproved, daysOffThisMonth };
  }, [allRequests]);

  return (
    <div>
      {toast}
      <div className="mb-6">
        <a href="/" className="mb-2 inline-flex items-center gap-1 text-sm font-medium text-slate-500 hover:text-slate-900">
          <span>&larr;</span> {t("common.backToDashboard")}
        </a>
        <h1 className="text-2xl font-bold tracking-tight text-slate-900 dark:text-slate-100">Time Off Requests</h1>
        <p className="mt-1 text-slate-600">Review and manage worker PTO requests.</p>
      </div>

      {/* KPI Summary Row */}
      <div className="grid grid-cols-3 gap-4 mb-6">
        <div className="rounded-xl border border-stone-200 bg-card p-4 shadow-sm">
          <div className="text-xs font-medium text-slate-500">{t("ptoPage.pendingRequests")}</div>
          <div className="mt-1 text-2xl font-bold text-slate-900">{kpiStats.pendingCount}</div>
        </div>
        <div className="rounded-xl border border-stone-200 bg-card p-4 shadow-sm">
          <div className="text-xs font-medium text-slate-500">{t("ptoPage.upcomingApproved")}</div>
          <div className="mt-1 text-2xl font-bold text-slate-900">{kpiStats.upcomingApproved}</div>
        </div>
        <div className="rounded-xl border border-stone-200 bg-card p-4 shadow-sm">
          <div className="text-xs font-medium text-slate-500">{t("ptoPage.daysOffThisMonth")}</div>
          <div className="mt-1 text-2xl font-bold text-slate-900">{kpiStats.daysOffThisMonth}</div>
        </div>
      </div>

      {error && (
        <div className="mb-4 rounded-lg bg-red-50 p-3 text-sm text-red-700 dark:bg-red-950/30 dark:text-red-300">{error}</div>
      )}

      {/* Filter tabs */}
      <div className="mb-6 flex flex-wrap gap-2">
        {["pending", "approved", "denied", "cancelled"].map((s) => (
          <button
            key={s}
            onClick={() => setFilter(s)}
            className={`rounded-full px-4 py-1.5 text-sm font-semibold transition-colors ${
              filter === s
                ? "bg-amber-500 text-white"
                : "bg-stone-100 text-slate-600 hover:bg-stone-200"
            }`}
          >
            {s.charAt(0).toUpperCase() + s.slice(1)}
          </button>
        ))}
      </div>

      {loading && (
        <div className="space-y-4">
          <SkeletonCard />
          <SkeletonCard />
          <SkeletonCard />
        </div>
      )}

      {!loading && requests.length === 0 && (
        <div className="rounded-2xl border border-dashed border-stone-200 p-12 text-center text-sm text-slate-500">
          No {filter} PTO requests.
        </div>
      )}

      {/* Bulk selection — pending tab only */}
      {filter === "pending" && requests.length > 0 && (
        <>
          <BulkActionBar
            count={selectedIds.size}
            onClear={() => {
              setSelectedIds(new Set());
              setBulkDecision("");
              setBulkReasonInput("");
            }}
            selectedLabel={
              bulkProgress
                ? t("ptoPage.bulkProgress", {
                    done: bulkProgress.done,
                    total: bulkProgress.total,
                  })
                : t("ptoPage.bulkSelected", { count: selectedIds.size })
            }
            actions={[
              {
                label: t("ptoPage.bulkApprove"),
                tone: "primary",
                disabled: bulkInFlight,
                onClick: () => setBulkDecision("approved"),
              },
              {
                label: t("ptoPage.bulkDeny"),
                tone: "danger",
                disabled: bulkInFlight,
                onClick: () => setBulkDecision("denied"),
              },
            ]}
          />

          {bulkDecision !== "" && selectedIds.size > 0 && (
            <div className="mb-4 rounded-xl border border-stone-200 bg-card p-4 dark:border-slate-800 dark:bg-slate-900">
              <label className="block text-sm font-medium text-slate-700 dark:text-slate-400">
                {bulkDecision === "approved"
                  ? t("ptoPage.reasonForApproval")
                  : t("ptoPage.reasonForDenial")}
              </label>
              <textarea
                value={bulkReasonInput}
                onChange={(e) => setBulkReasonInput(e.target.value)}
                className="mt-2 w-full rounded-xl border border-stone-300 px-4 py-2.5 text-sm focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 dark:border-slate-700 dark:bg-slate-950 dark:text-slate-100"
                rows={2}
              />
              <div className="mt-3 flex gap-2">
                <button
                  onClick={() => runBulkDecision(bulkDecision, bulkReasonInput)}
                  disabled={
                    bulkInFlight ||
                    (bulkDecision === "denied" && !bulkReasonInput.trim())
                  }
                  className={`rounded-lg px-4 py-1.5 text-sm font-semibold text-white disabled:bg-stone-100 disabled:text-slate-400 ${
                    bulkDecision === "approved"
                      ? "bg-green-600 hover:bg-green-700"
                      : "bg-red-600 hover:bg-red-700"
                  }`}
                >
                  {bulkInFlight
                    ? t("ptoPage.submitting")
                    : t("ptoPage.confirmBulk", { count: selectedIds.size })}
                </button>
                <button
                  onClick={() => {
                    setBulkDecision("");
                    setBulkReasonInput("");
                  }}
                  disabled={bulkInFlight}
                  className="rounded-lg bg-stone-100 px-4 py-1.5 text-sm font-semibold text-slate-600 hover:bg-stone-200 dark:bg-slate-800 dark:text-slate-400 dark:hover:bg-slate-700"
                >
                  {t("common.cancel")}
                </button>
              </div>
            </div>
          )}

          <label className="mb-2 flex items-center gap-2 text-sm text-slate-600 dark:text-slate-400">
            <input
              type="checkbox"
              checked={selectedIds.size === requests.length && requests.length > 0}
              onChange={(e) =>
                setSelectedIds(
                  e.target.checked ? new Set(requests.map((r) => r.id)) : new Set(),
                )
              }
              className="h-4 w-4 rounded border-stone-300 text-amber-500 focus:ring-amber-500"
            />
            {t("ptoPage.selectAll")}
          </label>
        </>
      )}

      <div className="space-y-3">
        {requests.map((req) => {
          const colors = STATUS_COLORS[req.status] ?? STATUS_COLORS.pending;
          return (
            <div key={req.id} className="rounded-2xl border border-stone-200 bg-card p-5 shadow-sm">
              <div className="flex items-start justify-between">
                <div className="flex items-start gap-3">
                  {filter === "pending" && req.status === "pending" && (
                    <input
                      type="checkbox"
                      checked={selectedIds.has(req.id)}
                      onChange={() => toggleSelected(req.id)}
                      aria-label={`Select PTO request from ${req.users?.full_name ?? "worker"}`}
                      className="mt-1 h-4 w-4 rounded border-stone-300 text-amber-500 focus:ring-amber-500"
                    />
                  )}
                <div>
                  <div className="font-semibold text-slate-900">
                    {req.users?.full_name ?? "Unknown"}
                  </div>
                  <div className="mt-1 text-sm text-slate-500">
                    {TYPE_LABELS[req.pto_type] ?? req.pto_type} &middot; {req.start_date} to {req.end_date} ({req.day_count} day{req.day_count !== 1 ? "s" : ""})
                  </div>
                  {req.notes && (
                    <div className="mt-2 text-sm text-slate-600">{req.notes}</div>
                  )}
                  {req.decision_reason && (
                    <div className="mt-2 text-xs text-slate-500">
                      Decision: {req.decision_reason}
                    </div>
                  )}
                </div>
                </div>
                <span className={`rounded-full px-3 py-1 text-xs font-bold ${colors.bg} ${colors.text}`}>
                  {req.status.toUpperCase()}
                </span>
              </div>

              {/* Decision UI for pending requests */}
              {req.status === "pending" && (
                <div className="mt-4 border-t border-stone-100 pt-4">
                  {decidingId === req.id ? (
                    <div className="space-y-3">
                      <textarea
                        value={decisionReason}
                        onChange={(e) => setDecisionReason(e.target.value)}
                        placeholder="Reason (optional)..."
                        className="w-full rounded-xl border border-stone-200 px-4 py-2.5 text-sm focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30"
                        rows={2}
                      />
                      <div className="flex gap-2">
                        <button
                          onClick={() => handleDecision(req.id, "approved")}
                          className="rounded-xl bg-green-600 px-4 py-2 text-sm font-semibold text-white hover:bg-green-700"
                        >
                          Approve
                        </button>
                        <button
                          onClick={() => handleDecision(req.id, "denied")}
                          className="rounded-xl bg-red-600 px-4 py-2 text-sm font-semibold text-white hover:bg-red-700"
                        >
                          Deny
                        </button>
                        <button
                          onClick={() => { setDecidingId(null); setDecisionReason(""); }}
                          className="rounded-xl px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-stone-100"
                        >
                          {t("common.cancel")}
                        </button>
                      </div>
                    </div>
                  ) : (
                    <button
                      onClick={() => setDecidingId(req.id)}
                      className="text-sm font-semibold text-amber-600 hover:text-amber-700"
                    >
                      Review &rarr;
                    </button>
                  )}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
