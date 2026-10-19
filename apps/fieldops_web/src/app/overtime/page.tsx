"use client";

import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";
import { useI18n } from "@/lib/i18n";
import { callFunctionJson } from "@/lib/function-client";
import { SkeletonCard } from "@/components/ui/skeleton";
import { BulkActionBar } from "@/components/bulk-action-bar";
import { useToast } from "@/components/ui/toast";

interface OTRequest {
  id: string;
  job_id: string;
  worker_id: string;
  requested_at: string;
  total_hours_at_request: number | null;
  notes: string | null;
  status: string;
  users: { full_name: string } | null;
  jobs: { name: string; code: string } | null;
}

interface OTListResponse {
  ot_requests?: OTRequest[];
}

export default function OvertimePage() {
  return (
    <Suspense
      fallback={
        <div className="space-y-4">
          <SkeletonCard />
          <SkeletonCard />
          <SkeletonCard />
        </div>
      }
    >
      <OvertimeContent />
    </Suspense>
  );
}

function OvertimeContent() {
  const { t } = useI18n();
  const searchParams = useSearchParams();
  const filterStatus = searchParams.get("status") || "pending";

  const OT_PAGE_SIZE = 30;

  const [requests, setRequests] = useState<OTRequest[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [decidingId, setDecidingId] = useState<string | null>(null);
  const [hasMoreRequests, setHasMoreRequests] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const { toast, showToast } = useToast();
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [bulkInFlight, setBulkInFlight] = useState(false);
  const [bulkProgress, setBulkProgress] = useState<{ done: number; total: number } | null>(null);
  const [bulkReason, setBulkReason] = useState<"" | "approved" | "denied">("");
  const [reasonInput, setReasonInput] = useState("");

  const [kpiCounts, setKpiCounts] = useState<{
    pending: number;
    approvedToday: number;
    denied: number;
  }>({ pending: 0, approvedToday: 0, denied: 0 });

  const loadKpis = useCallback(async () => {
    // The ot endpoint filters server-side per status, so the KPI row needs
    // its own per-status counts — computing them from the visible tab
    // rendered "0 pending" whenever you looked at Approved/Denied.
    try {
      const todayStr = new Date().toISOString().slice(0, 10);
      const [pending, approved, denied] = await Promise.all(
        (["pending", "approved", "denied"] as const).map((s) =>
          callFunctionJson<OTListResponse>("ot", {
            query: { status: s, offset: 0, limit: 100 },
          }),
        ),
      );
      setKpiCounts({
        pending: (pending.ot_requests ?? []).length,
        approvedToday: (approved.ot_requests ?? []).filter(
          (r) => r.requested_at.slice(0, 10) === todayStr,
        ).length,
        denied: (denied.ot_requests ?? []).length,
      });
    } catch {
      // KPI row is best-effort; the list itself surfaces real errors.
    }
  }, []);

  const loadRequests = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const payload = await callFunctionJson<OTListResponse>("ot", {
        query: {
          status: filterStatus,
          offset: 0,
          limit: OT_PAGE_SIZE,
        },
      });
      const result = payload.ot_requests ?? [];
      setRequests(result);
      setHasMoreRequests(result.length === OT_PAGE_SIZE);
    } catch (e) {
      setError(e instanceof Error ? e.message : t("overtimePage.failedToLoad"));
    } finally {
      setLoading(false);
    }
  }, [filterStatus, t]);

  const loadMoreRequests = useCallback(async () => {
    setLoadingMore(true);
    try {
      const payload = await callFunctionJson<OTListResponse>("ot", {
        query: {
          status: filterStatus,
          offset: requests.length,
          limit: OT_PAGE_SIZE,
        },
      });
      const newItems = payload.ot_requests ?? [];
      setRequests((prev) => [...prev, ...newItems]);
      setHasMoreRequests(newItems.length === OT_PAGE_SIZE);
    } catch (e) {
      setError(e instanceof Error ? e.message : t("overtimePage.failedToLoad"));
    } finally {
      setLoadingMore(false);
    }
  }, [filterStatus, requests.length, t]);

  useEffect(() => {
    loadRequests();
    // Clear selection when the filter changes — those rows are no longer visible.
    setSelectedIds(new Set());
    setBulkReason("");
    setReasonInput("");
  }, [loadRequests]);

  useEffect(() => {
    loadKpis();
  }, [loadKpis]);

  const toggleSelect = useCallback((id: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);

  const toggleSelectAll = useCallback(() => {
    setSelectedIds((prev) =>
      prev.size === requests.length
        ? new Set()
        : new Set(requests.map((r) => r.id)),
    );
  }, [requests]);

  const runBulkDecision = useCallback(
    async (decision: "approved" | "denied", reason: string) => {
      const ids = Array.from(selectedIds);
      if (ids.length === 0) return;
      setBulkInFlight(true);
      setBulkProgress({ done: 0, total: ids.length });
      setError(null);
      try {
        // Serial loop so we don't overload the edge function; each decision uses its own Idempotency-Key.
        for (let i = 0; i < ids.length; i++) {
          await callFunctionJson("ot", {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "Idempotency-Key": crypto.randomUUID(),
            },
            body: JSON.stringify({
              action: "decide",
              ot_request_id: ids[i],
              decision,
              reason,
            }),
          });
          setBulkProgress({ done: i + 1, total: ids.length });
        }
        setSelectedIds(new Set());
        setBulkReason("");
        setReasonInput("");
        showToast(`${ids.length} OT request${ids.length === 1 ? "" : "s"} ${decision}`);
        await loadRequests();
        loadKpis();
      } catch (e) {
        setError(e instanceof Error ? e.message : t("overtimePage.decisionFailed"));
      } finally {
        setBulkInFlight(false);
        setBulkProgress(null);
      }
    },
    [selectedIds, loadRequests, loadKpis, showToast, t],
  );

  async function handleDecision(
    requestId: string,
    decision: "approved" | "denied",
    reason: string,
  ) {
    setDecidingId(requestId);
    try {
      await callFunctionJson("ot", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Idempotency-Key": crypto.randomUUID(),
        },
        body: JSON.stringify({
          action: "decide",
          ot_request_id: requestId,
          decision,
          reason,
        }),
      });

      showToast(decision === "approved" ? "OT approved" : "OT denied");
      await loadRequests();
      loadKpis();
    } catch (e) {
      setError(e instanceof Error ? e.message : t("overtimePage.decisionFailed"));
    } finally {
      setDecidingId(null);
    }
  }

  function formatTime(iso: string) {
    return new Date(iso).toLocaleString(undefined, {
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  }

  const kpiStats = useMemo(
    () => ({
      pendingCount: kpiCounts.pending,
      approvedTodayCount: kpiCounts.approvedToday,
      deniedCount: kpiCounts.denied,
    }),
    [kpiCounts],
  );

  return (
    <div>
      {toast}
      <div className="mb-8">
        <a
          href="/"
          className="mb-4 inline-flex items-center gap-1 text-sm font-medium text-slate-500 hover:text-slate-900"
        >
          <span>&larr;</span> {t("common.backToDashboard")}
        </a>
        <h1 className="text-2xl font-bold tracking-tight text-slate-900 dark:text-slate-100">
          {t("overtimePage.title")}
        </h1>
        <p className="mt-1 text-slate-600">{t("overtimePage.subtitle")}</p>

        {/* KPI Summary Row */}
        <div className="mt-4 grid grid-cols-3 gap-4 mb-6">
          <div className="rounded-xl border border-stone-200 bg-card p-4 shadow-sm">
            <div className="text-xs font-medium text-slate-500">{t("overtimePage.pendingRequests")}</div>
            <div className="mt-1 text-2xl font-bold text-slate-900">{kpiStats.pendingCount}</div>
          </div>
          <div className="rounded-xl border border-stone-200 bg-card p-4 shadow-sm">
            <div className="text-xs font-medium text-slate-500">{t("overtimePage.approvedToday")}</div>
            <div className="mt-1 text-2xl font-bold text-slate-900">{kpiStats.approvedTodayCount}</div>
          </div>
          <div className="rounded-xl border border-stone-200 bg-card p-4 shadow-sm">
            <div className="text-xs font-medium text-slate-500">{t("overtimePage.deniedStat")}</div>
            <div className="mt-1 text-2xl font-bold text-slate-900">{kpiStats.deniedCount}</div>
          </div>
        </div>

        {/* Status filter tabs */}
        <div className="mt-4 flex gap-2">
          {["pending", "approved", "denied"].map((s) => (
            <a
              key={s}
              href={`/overtime?status=${s}`}
              className={`rounded-full px-4 py-1.5 text-sm font-semibold transition-colors ${
                filterStatus === s
                  ? "bg-amber-500 text-white"
                  : "bg-stone-100 text-slate-600 hover:bg-stone-200"
              }`}
            >
              {t(`overtimePage.${s}`)}
            </a>
          ))}
        </div>
      </div>

      {loading && (
        <div className="space-y-4">
          <SkeletonCard />
          <SkeletonCard />
          <SkeletonCard />
        </div>
      )}

      {error && (
        <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700 dark:border-red-900/50 dark:bg-red-950/30 dark:text-red-300">
          {error}
          <button
            onClick={loadRequests}
            className="ml-3 font-semibold underline"
          >
            {t("common.retry")}
          </button>
        </div>
      )}

      {!loading && !error && requests.length === 0 && (
        <div className="rounded-xl border border-stone-200 bg-card p-8 text-center text-slate-500">
          {t("overtimePage.noRequests", { status: t(`overtimePage.${filterStatus}`) })}
        </div>
      )}

      {/* Bulk selection bar — pending tab only */}
      {filterStatus === "pending" && (
        <>
          <BulkActionBar
            count={selectedIds.size}
            onClear={() => {
              setSelectedIds(new Set());
              setBulkReason("");
              setReasonInput("");
            }}
            selectedLabel={
              bulkProgress
                ? t("overtimePage.bulkProgress", {
                    done: bulkProgress.done,
                    total: bulkProgress.total,
                  })
                : t("overtimePage.bulkSelected", { count: selectedIds.size })
            }
            actions={[
              {
                label: t("overtimePage.bulkApprove"),
                tone: "primary",
                disabled: bulkInFlight,
                onClick: () => {
                  setBulkReason("approved");
                  setReasonInput("");
                },
              },
              {
                label: t("overtimePage.bulkReject"),
                tone: "danger",
                disabled: bulkInFlight,
                onClick: () => {
                  setBulkReason("denied");
                  setReasonInput("");
                },
              },
            ]}
          />

          {bulkReason !== "" && (
            <div className="mb-4 rounded-xl border border-stone-200 bg-card p-4 dark:border-slate-800 dark:bg-slate-900">
              <label className="block text-sm font-medium text-slate-700 dark:text-slate-400">
                {bulkReason === "approved"
                  ? t("overtimePage.reasonForApproval")
                  : t("overtimePage.reasonForDenial")}
              </label>
              <textarea
                value={reasonInput}
                onChange={(e) => setReasonInput(e.target.value)}
                className="mt-2 w-full rounded-xl border border-stone-300 px-4 py-2.5 text-sm focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 dark:border-slate-700 dark:bg-slate-950 dark:text-slate-100"
                rows={2}
                placeholder={t("overtimePage.decisionPlaceholder")}
              />
              <div className="mt-3 flex gap-2">
                <button
                  onClick={() => runBulkDecision(bulkReason, reasonInput)}
                  disabled={!reasonInput.trim() || bulkInFlight}
                  className={`rounded-lg px-4 py-1.5 text-sm font-semibold text-white disabled:bg-stone-100 disabled:text-slate-400 ${
                    bulkReason === "approved"
                      ? "bg-green-600 hover:bg-green-700"
                      : "bg-red-600 hover:bg-red-700"
                  }`}
                >
                  {bulkInFlight
                    ? t("overtimePage.submitting")
                    : t("overtimePage.confirmBulk", {
                        count: selectedIds.size,
                      })}
                </button>
                <button
                  onClick={() => {
                    setBulkReason("");
                    setReasonInput("");
                  }}
                  disabled={bulkInFlight}
                  className="rounded-lg bg-stone-100 px-4 py-1.5 text-sm font-semibold text-slate-600 hover:bg-stone-200 dark:bg-slate-800 dark:text-slate-400 dark:hover:bg-slate-700"
                >
                  {t("common.cancel")}
                </button>
              </div>
            </div>
          )}

          {requests.length > 0 && (
            <label className="mb-2 flex cursor-pointer items-center gap-2 text-xs font-semibold text-slate-500 dark:text-slate-400">
              <input
                type="checkbox"
                checked={
                  selectedIds.size === requests.length && requests.length > 0
                }
                onChange={toggleSelectAll}
                className="h-3.5 w-3.5 rounded border-stone-300"
              />
              {selectedIds.size === requests.length
                ? t("overtimePage.deselectAll")
                : t("overtimePage.selectAll")}
            </label>
          )}
        </>
      )}

      <div className="space-y-4">
        {requests.map((req) => (
          <OTRequestCard
            key={req.id}
            request={req}
            isPending={filterStatus === "pending"}
            isDeciding={decidingId === req.id}
            onDecision={handleDecision}
            isSelectable={filterStatus === "pending"}
            isSelected={selectedIds.has(req.id)}
            onToggleSelect={() => toggleSelect(req.id)}
            formatTime={formatTime}
            t={t}
          />
        ))}
      </div>

      {hasMoreRequests && (
        <div className="mt-6 flex justify-center">
          <button
            onClick={loadMoreRequests}
            disabled={loadingMore}
            className="mx-auto flex items-center gap-2 rounded-xl border border-stone-200 bg-card px-6 py-2.5 text-sm font-semibold text-slate-600 shadow-sm hover:bg-stone-50 disabled:bg-stone-100 disabled:text-slate-400"
          >
            {loadingMore ? t("common.loadingMore") : t("common.loadMore")}
          </button>
        </div>
      )}
    </div>
  );
}

function OTRequestCard({
  request,
  isPending,
  isDeciding,
  onDecision,
  isSelectable,
  isSelected,
  onToggleSelect,
  formatTime,
  t,
}: {
  request: OTRequest;
  isPending: boolean;
  isDeciding: boolean;
  onDecision: (
    id: string,
    decision: "approved" | "denied",
    reason: string,
  ) => void;
  isSelectable?: boolean;
  isSelected?: boolean;
  onToggleSelect?: () => void;
  formatTime: (iso: string) => string;
  t: (key: string, vars?: Record<string, string | number>) => string;
}) {
  const [reason, setReason] = useState("");
  const [showReasonFor, setShowReasonFor] = useState<
    "approved" | "denied" | null
  >(null);

  const workerName =
    (request.users as { full_name: string } | null)?.full_name ?? t("overtimePage.unknownWorker");
  const jobName =
    (request.jobs as { name: string; code: string } | null)?.name ?? t("overtimePage.unknownJob");
  const jobCode =
    (request.jobs as { name: string; code: string } | null)?.code ?? "";

  return (
    <div
      className={`rounded-2xl border bg-card p-5 shadow-sm transition-colors dark:bg-slate-900 ${
        isSelected
          ? "border-amber-400 ring-2 ring-amber-200 dark:border-amber-500 dark:ring-amber-900/40"
          : "border-stone-200 dark:border-slate-800"
      }`}
    >
      <div className="flex items-start justify-between gap-3">
        {isSelectable && (
          <label className="flex-shrink-0 cursor-pointer pt-0.5">
            <input
              type="checkbox"
              checked={!!isSelected}
              onChange={onToggleSelect}
              className="h-4 w-4 rounded border-stone-300"
              aria-label="Select request"
            />
          </label>
        )}
        <div className="flex-1">
          <h3 className="font-bold text-slate-900">{workerName}</h3>
          <p className="text-sm text-slate-500">
            {jobName} ({jobCode})
          </p>
        </div>
        <span
          className={`rounded-full px-2.5 py-0.5 text-xs font-semibold ${
            request.status === "pending"
              ? "bg-amber-100 text-amber-700"
              : request.status === "approved"
                ? "bg-green-100 text-green-700"
                : "bg-red-100 text-red-700"
          }`}
        >
          {t(`overtimePage.${request.status}`)}
        </span>
      </div>

      <div className="mt-3 flex gap-4 text-sm text-slate-600">
        <span>{t("overtimePage.requested", { time: formatTime(request.requested_at) })}</span>
        {request.total_hours_at_request != null && (
          <span>{t("overtimePage.hours", { hours: request.total_hours_at_request })}</span>
        )}
      </div>

      {request.notes && (
        <p className="mt-2 text-sm text-slate-600 italic">
          &ldquo;{request.notes}&rdquo;
        </p>
      )}

      {isPending && (
        <div className="mt-4">
          {showReasonFor ? (
            <div className="space-y-3">
              <label className="block text-sm font-medium text-slate-700">
                {showReasonFor === "approved"
                  ? t("overtimePage.reasonForApproval")
                  : t("overtimePage.reasonForDenial")}
              </label>
              <textarea
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                className="w-full rounded-xl border border-stone-300 px-4 py-2.5 text-sm focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30"
                rows={2}
                placeholder={t("overtimePage.decisionPlaceholder")}
              />
              <div className="flex gap-2">
                <button
                  onClick={() => {
                    if (reason.trim()) {
                      onDecision(request.id, showReasonFor!, reason);
                    }
                  }}
                  disabled={!reason.trim() || isDeciding}
                  className={`rounded-xl px-5 py-2 text-sm font-semibold text-white disabled:bg-stone-100 disabled:text-slate-400 ${
                    showReasonFor === "approved"
                      ? "bg-green-600 hover:bg-green-700"
                      : "bg-red-600 hover:bg-red-700"
                  }`}
                >
                  {isDeciding
                    ? t("overtimePage.submitting")
                    : showReasonFor === "approved"
                      ? t("overtimePage.confirmApproval")
                      : t("overtimePage.confirmDenial")}
                </button>
                <button
                  onClick={() => {
                    setShowReasonFor(null);
                    setReason("");
                  }}
                  className="rounded-xl px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-stone-100"
                >
                  {t("overtimePage.cancel")}
                </button>
              </div>
            </div>
          ) : (
            <div className="flex gap-2">
              <button
                onClick={() => setShowReasonFor("approved")}
                className="rounded-xl bg-green-600 px-5 py-2 text-sm font-semibold text-white hover:bg-green-700"
              >
                {t("overtimePage.approve")}
              </button>
              <button
                onClick={() => setShowReasonFor("denied")}
                className="rounded-xl bg-red-50 px-5 py-2 text-sm font-semibold text-red-700 hover:bg-red-100"
              >
                {t("overtimePage.deny")}
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
