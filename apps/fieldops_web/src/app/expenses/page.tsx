"use client";

import { Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useSearchParams } from "next/navigation";
import { useI18n } from "@/lib/i18n";
import { callFunctionJson } from "@/lib/function-client";
import { getSupabase } from "@/lib/supabase";
import { SkeletonCard } from "@/components/ui/skeleton";
import { useToast } from "@/components/ui/toast";

interface ExpenseEntry {
  id: string;
  job_id: string;
  submitted_by: string;
  category: string;
  amount: number | string;
  vendor: string | null;
  notes: string | null;
  media_asset_id: string | null;
  status: string;
  submitted_at: string;
  decision_reason: string | null;
  reimbursed_at: string | null;
  reimbursement_reference: string | null;
  reimbursement_notes: string | null;
}

interface MediaAsset {
  id: string;
  bucket_name: string;
  storage_path: string;
}

type ExpenseCardData = ExpenseEntry & {
  workerName: string;
  jobName: string;
  jobCode: string;
};

interface ExpensesResponse {
  expenses?: ExpenseEntry[];
}

export default function ExpensesPage() {
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
      <ExpensesContent />
    </Suspense>
  );
}

function ExpensesContent() {
  const { t } = useI18n();
  const searchParams = useSearchParams();
  const filterStatus = searchParams.get("status") || "pending";

  const [expenses, setExpenses] = useState<ExpenseCardData[]>([]);
  const [signedUrls, setSignedUrls] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const { toast, showToast } = useToast();
  const [decidingId, setDecidingId] = useState<string | null>(null);
  const [reimbursingId, setReimbursingId] = useState<string | null>(null);
  const urlCacheRef = useRef<Record<string, string>>({});

  const loadExpenses = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const supabase = getSupabase();
      // No status param → all statuses. Tabs filter client-side so the KPI
      // cards (pending total, reimbursed, …) always see the full dataset —
      // previously they computed over the visible tab and showed $0.00
      // pending while on the Approved tab.
      const payload = await callFunctionJson<ExpensesResponse>("expenses", {});
      const expenseRows = payload.expenses ?? [];
      const workerIds = Array.from(new Set(expenseRows.map((entry) => entry.submitted_by)));
      const jobIds = Array.from(new Set(expenseRows.map((entry) => entry.job_id)));
      const mediaIds = Array.from(
        new Set(expenseRows.map((entry) => entry.media_asset_id).filter((id): id is string => Boolean(id))),
      );

      const [{ data: workers }, { data: jobs }, { data: mediaAssets }] = await Promise.all([
        workerIds.length > 0
          ? supabase.from("users").select("id, full_name").in("id", workerIds)
          : Promise.resolve({ data: [] }),
        jobIds.length > 0
          ? supabase.from("jobs").select("id, name, code").in("id", jobIds)
          : Promise.resolve({ data: [] }),
        mediaIds.length > 0
          ? supabase.from("media_assets").select("id, bucket_name, storage_path").in("id", mediaIds)
          : Promise.resolve({ data: [] }),
      ]);

      const workerById = new Map(
        ((workers as { id: string; full_name: string | null }[] | null) ?? []).map((worker) => [
          worker.id,
          worker.full_name ?? t("expensesPage.unknownWorker"),
        ]),
      );
      const jobsById = new Map(
        ((jobs as { id: string; name: string; code: string | null }[] | null) ?? []).map((job) => [
          job.id,
          { name: job.name, code: job.code ?? "" },
        ]),
      );
      const assets = (mediaAssets as MediaAsset[] | null) ?? [];

      const nextSignedUrls: Record<string, string> = {};
      await Promise.allSettled(
        assets.map(async (asset) => {
          const cacheKey = `${asset.id}:${asset.bucket_name}:${asset.storage_path}`;
          if (!urlCacheRef.current[cacheKey]) {
            const { data: urlData } = await supabase.storage
              .from(asset.bucket_name)
              .createSignedUrl(asset.storage_path, 3600);
            if (urlData?.signedUrl) {
              urlCacheRef.current[cacheKey] = urlData.signedUrl;
            }
          }
          if (urlCacheRef.current[cacheKey]) {
            nextSignedUrls[asset.id] = urlCacheRef.current[cacheKey];
          }
        }),
      );

      setSignedUrls(nextSignedUrls);
      setExpenses(
        expenseRows.map((entry) => ({
          ...entry,
          workerName: workerById.get(entry.submitted_by) ?? t("expensesPage.unknownWorker"),
          jobName: jobsById.get(entry.job_id)?.name ?? t("expensesPage.unknownJob"),
          jobCode: jobsById.get(entry.job_id)?.code ?? "",
        })),
      );
    } catch (err) {
      setError(err instanceof Error ? err.message : t("expensesPage.failedToLoad"));
    } finally {
      setLoading(false);
    }
  }, [t]);

  useEffect(() => {
    loadExpenses();
  }, [loadExpenses]);

  async function handleDecision(
    expenseId: string,
    decision: "approved" | "denied",
    reason: string,
  ) {
    setDecidingId(expenseId);
    try {
      await callFunctionJson("expenses", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Idempotency-Key": crypto.randomUUID(),
        },
        body: JSON.stringify({
          action: "decide",
          expense_id: expenseId,
          decision,
          reason,
        }),
      });

      showToast(decision === "approved" ? "Expense approved" : "Expense denied");
      await loadExpenses();
    } catch (err) {
      setError(err instanceof Error ? err.message : t("expensesPage.failedToLoad"));
    } finally {
      setDecidingId(null);
    }
  }

  async function handleReimbursement(
    expenseId: string,
    reference: string,
    notes: string,
  ) {
    setReimbursingId(expenseId);
    try {
      await callFunctionJson("expenses", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Idempotency-Key": crypto.randomUUID(),
        },
        body: JSON.stringify({
          action: "reimburse",
          expense_id: expenseId,
          reference,
          notes,
        }),
      });

      showToast("Marked reimbursed");
      await loadExpenses();
    } catch (err) {
      setError(err instanceof Error ? err.message : t("expensesPage.failedToLoad"));
    } finally {
      setReimbursingId(null);
    }
  }

  function downloadCsv() {
    const headers = [
      "expense_id",
      "status",
      "worker",
      "job",
      "job_code",
      "category",
      "amount",
      "vendor",
      "submitted_at",
      "decision_reason",
      "reimbursed_at",
      "reimbursement_reference",
      "reimbursement_notes",
    ];
    const rows = visibleExpenses.map((expense) => [
      expense.id,
      expense.status,
      expense.workerName,
      expense.jobName,
      expense.jobCode,
      expense.category,
      String(expense.amount),
      expense.vendor ?? "",
      expense.submitted_at,
      expense.decision_reason ?? "",
      expense.reimbursed_at ?? "",
      expense.reimbursement_reference ?? "",
      expense.reimbursement_notes ?? "",
    ]);
    const csv = [headers, ...rows]
      .map((row) => row.map((value) => `"${String(value).replaceAll('"', '""')}"`).join(","))
      .join("\n");
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `expenses-${filterStatus}.csv`;
    link.click();
    URL.revokeObjectURL(url);
  }

  function formatTime(iso: string) {
    return new Date(iso).toLocaleString(undefined, {
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  }

  const visibleExpenses = useMemo(
    () => expenses.filter((e) => e.status === filterStatus),
    [expenses, filterStatus],
  );

  const kpiStats = useMemo(() => {
    const now = new Date();
    const currentMonth = now.getMonth();
    const currentYear = now.getFullYear();

    const pendingItems = expenses.filter((e) => e.status === "pending");
    const pendingTotal = pendingItems.reduce(
      (sum, e) => sum + (typeof e.amount === "number" ? e.amount : Number(e.amount)),
      0,
    );
    const pendingCount = pendingItems.length;

    const approvedThisMonth = expenses.filter((e) => {
      if (e.status !== "approved") return false;
      const d = new Date(e.submitted_at);
      return d.getMonth() === currentMonth && d.getFullYear() === currentYear;
    }).length;

    const totalReimbursed = expenses
      .filter((e) => Boolean(e.reimbursed_at))
      .reduce(
        (sum, e) => sum + (typeof e.amount === "number" ? e.amount : Number(e.amount)),
        0,
      );

    return { pendingTotal, pendingCount, approvedThisMonth, totalReimbursed };
  }, [expenses]);

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
        <h1 className="text-2xl font-bold tracking-tight text-slate-900 dark:text-slate-100">{t("expensesPage.title")}</h1>
        <p className="mt-1 text-slate-600">{t("expensesPage.subtitle")}</p>

        {/* KPI Summary Row */}
        <div className="mt-4 grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
          <div className="rounded-xl border border-stone-200 bg-card p-4 shadow-sm">
            <div className="text-xs font-medium text-slate-500">{t("expensesPage.pendingTotal")}</div>
            <div className="mt-1 text-2xl font-bold text-slate-900">
              ${kpiStats.pendingTotal.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
            </div>
          </div>
          <div className="rounded-xl border border-stone-200 bg-card p-4 shadow-sm">
            <div className="text-xs font-medium text-slate-500">{t("expensesPage.pendingCount")}</div>
            <div className="mt-1 text-2xl font-bold text-slate-900">{kpiStats.pendingCount}</div>
          </div>
          <div className="rounded-xl border border-stone-200 bg-card p-4 shadow-sm">
            <div className="text-xs font-medium text-slate-500">{t("expensesPage.approvedThisMonth")}</div>
            <div className="mt-1 text-2xl font-bold text-slate-900">{kpiStats.approvedThisMonth}</div>
          </div>
          <div className="rounded-xl border border-stone-200 bg-card p-4 shadow-sm">
            <div className="text-xs font-medium text-slate-500">{t("expensesPage.totalReimbursed")}</div>
            <div className="mt-1 text-2xl font-bold text-slate-900">
              ${kpiStats.totalReimbursed.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
            </div>
          </div>
        </div>

        <div className="mt-4 flex flex-wrap items-center gap-2">
          {["pending", "approved", "denied"].map((status) => (
            <a
              key={status}
              href={`/expenses?status=${status}`}
              className={`rounded-full px-4 py-1.5 text-sm font-semibold transition-colors ${
                filterStatus === status
                  ? "bg-amber-500 text-white"
                  : "bg-stone-100 text-slate-600 hover:bg-stone-200"
              }`}
            >
              {t(`expensesPage.${status}`)}
            </a>
          ))}
          <button
            onClick={downloadCsv}
            className="rounded-full bg-slate-900 px-4 py-1.5 text-sm font-semibold text-white hover:bg-slate-800"
          >
            {t("expensesPage.downloadCsv")}
          </button>
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
          <button onClick={loadExpenses} className="ml-3 font-semibold underline">
            {t("common.retry")}
          </button>
        </div>
      )}

      {!loading && !error && visibleExpenses.length === 0 && (
        <div className="rounded-xl border border-stone-200 bg-card p-8 text-center text-slate-500">
          {t("expensesPage.noExpenses", { status: t(`expensesPage.${filterStatus}`) })}
        </div>
      )}

      <div className="space-y-4">
        {visibleExpenses.map((expense) => (
          <ExpenseCard
            key={expense.id}
            expense={expense}
            receiptUrl={expense.media_asset_id ? signedUrls[expense.media_asset_id] : undefined}
            isPending={filterStatus === "pending"}
            isApproved={filterStatus === "approved"}
            isDeciding={decidingId === expense.id}
            isReimbursing={reimbursingId === expense.id}
            onDecision={handleDecision}
            onReimbursement={handleReimbursement}
            formatTime={formatTime}
          />
        ))}
      </div>
    </div>
  );
}

function ExpenseCard({
  expense,
  receiptUrl,
  isPending,
  isApproved,
  isDeciding,
  isReimbursing,
  onDecision,
  onReimbursement,
  formatTime,
}: {
  expense: ExpenseCardData;
  receiptUrl?: string;
  isPending: boolean;
  isApproved: boolean;
  isDeciding: boolean;
  isReimbursing: boolean;
  onDecision: (id: string, decision: "approved" | "denied", reason: string) => void;
  onReimbursement: (id: string, reference: string, notes: string) => void;
  formatTime: (iso: string) => string;
}) {
  const { t } = useI18n();
  const [reason, setReason] = useState("");
  const [showReasonFor, setShowReasonFor] = useState<"approved" | "denied" | null>(null);
  const [showReimbursementForm, setShowReimbursementForm] = useState(false);
  const [reimbursementReference, setReimbursementReference] = useState("");
  const [reimbursementNotes, setReimbursementNotes] = useState("");
  const amount = typeof expense.amount === "number" ? expense.amount : Number(expense.amount);
  const isReimbursed = Boolean(expense.reimbursed_at);

  return (
    <div className="rounded-2xl border border-stone-200 bg-card p-5 shadow-sm">
      <div className="flex flex-col gap-4 md:flex-row">
        <div className="md:w-52">
          {receiptUrl ? (
            <img
              src={receiptUrl}
              alt={t("expensesPage.receiptAttached")}
              className="h-36 w-full rounded-xl object-cover"
              loading="lazy"
            />
          ) : (
            <div className="flex h-36 items-center justify-center rounded-xl bg-stone-100 text-sm text-slate-500">
              {t("expensesPage.receiptMissing")}
            </div>
          )}
        </div>

        <div className="flex-1">
          <div className="flex items-start justify-between gap-4">
            <div>
              <h3 className="font-bold text-slate-900">{expense.workerName}</h3>
              <p className="text-sm text-slate-500">
                {expense.jobName} {expense.jobCode ? `(${expense.jobCode})` : ""}
              </p>
            </div>
            <span
              className={`rounded-full px-2.5 py-0.5 text-xs font-semibold ${
                expense.status === "pending"
                  ? "bg-amber-100 text-amber-700"
                  : expense.status === "approved"
                    ? "bg-green-100 text-green-700"
                    : "bg-red-100 text-red-700"
              }`}
            >
              {t(`expensesPage.${expense.status}`)}
            </span>
          </div>

          {isReimbursed && (
            <div className="mt-2 inline-flex rounded-full bg-emerald-50 px-2.5 py-0.5 text-xs font-semibold text-emerald-700">
              {t("expensesPage.reimbursed")}
            </div>
          )}

          <div className="mt-3 grid gap-2 text-sm text-slate-600 md:grid-cols-2">
            <div>
              <span className="font-semibold text-slate-900">{t("expensesPage.amount")}:</span>{" "}
              ${amount.toFixed(2)}
            </div>
            <div>
              <span className="font-semibold text-slate-900">{t("expensesPage.category")}:</span>{" "}
              {expense.category}
            </div>
            {expense.vendor && (
              <div>
                <span className="font-semibold text-slate-900">{t("expensesPage.vendor")}:</span>{" "}
                {expense.vendor}
              </div>
            )}
            <div>{t("expensesPage.submitted", { time: formatTime(expense.submitted_at) })}</div>
          </div>

          {expense.notes && (
            <p className="mt-3 text-sm italic text-slate-600">
              <span className="font-semibold not-italic text-slate-900">{t("expensesPage.notes")}:</span>{" "}
              {expense.notes}
            </p>
          )}

          {isPending && (
            <div className="mt-4">
              {showReasonFor ? (
                <div className="space-y-3">
                  <textarea
                    value={reason}
                    onChange={(event) => setReason(event.target.value)}
                    className="w-full rounded-xl border border-stone-300 px-4 py-2.5 text-sm focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30"
                    rows={2}
                    placeholder={t("expensesPage.decisionPlaceholder")}
                  />
                  <div className="flex gap-2">
                    <button
                      onClick={() => {
                        if (reason.trim()) {
                          onDecision(expense.id, showReasonFor, reason);
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
                        ? t("expensesPage.submitting")
                        : showReasonFor === "approved"
                          ? t("expensesPage.confirmApproval")
                          : t("expensesPage.confirmDenial")}
                    </button>
                    <button
                      onClick={() => {
                        setShowReasonFor(null);
                        setReason("");
                      }}
                      className="rounded-xl px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-stone-100"
                    >
                      {t("common.cancel")}
                    </button>
                  </div>
                </div>
              ) : (
                <div className="flex gap-2">
                  <button
                    onClick={() => setShowReasonFor("approved")}
                    className="rounded-xl bg-green-600 px-5 py-2 text-sm font-semibold text-white hover:bg-green-700"
                  >
                    {t("expensesPage.approve")}
                  </button>
                  <button
                    onClick={() => setShowReasonFor("denied")}
                    className="rounded-xl bg-red-50 px-5 py-2 text-sm font-semibold text-red-700 hover:bg-red-100"
                  >
                    {t("expensesPage.deny")}
                  </button>
                </div>
              )}
            </div>
          )}

          {!isPending && expense.decision_reason && (
            <p className="mt-4 text-sm text-slate-600">
              <span className="font-semibold text-slate-900">{t("expensesPage.notes")}:</span>{" "}
              {expense.decision_reason}
            </p>
          )}

          {isApproved && !isReimbursed && (
            <div className="mt-4">
              {showReimbursementForm ? (
                <div className="space-y-3">
                  <input
                    value={reimbursementReference}
                    onChange={(event) => setReimbursementReference(event.target.value)}
                    className="w-full rounded-xl border border-stone-300 px-4 py-2.5 text-sm focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30"
                    placeholder={t("expensesPage.reimbursementReferencePlaceholder")}
                  />
                  <textarea
                    value={reimbursementNotes}
                    onChange={(event) => setReimbursementNotes(event.target.value)}
                    className="w-full rounded-xl border border-stone-300 px-4 py-2.5 text-sm focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30"
                    rows={2}
                    placeholder={t("expensesPage.reimbursementNotesPlaceholder")}
                  />
                  <div className="flex gap-2">
                    <button
                      onClick={() => {
                        if (reimbursementReference.trim()) {
                          onReimbursement(expense.id, reimbursementReference, reimbursementNotes);
                        }
                      }}
                      disabled={!reimbursementReference.trim() || isReimbursing}
                      className="rounded-xl bg-slate-900 px-5 py-2 text-sm font-semibold text-white hover:bg-slate-800 disabled:bg-stone-100 disabled:text-slate-400"
                    >
                      {isReimbursing
                        ? t("expensesPage.submitting")
                        : t("expensesPage.confirmReimbursement")}
                    </button>
                    <button
                      onClick={() => {
                        setShowReimbursementForm(false);
                        setReimbursementReference("");
                        setReimbursementNotes("");
                      }}
                      className="rounded-xl px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-stone-100"
                    >
                      {t("common.cancel")}
                    </button>
                  </div>
                </div>
              ) : (
                <button
                  onClick={() => setShowReimbursementForm(true)}
                  className="rounded-xl bg-slate-900 px-5 py-2 text-sm font-semibold text-white hover:bg-slate-800"
                >
                  {t("expensesPage.markReimbursed")}
                </button>
              )}
            </div>
          )}

          {isReimbursed && (
            <div className="mt-4 space-y-1 text-sm text-slate-600">
              <div>
                <span className="font-semibold text-slate-900">{t("expensesPage.reimbursed")}:</span>{" "}
                {formatTime(expense.reimbursed_at!)}
              </div>
              {expense.reimbursement_reference && (
                <div>
                  <span className="font-semibold text-slate-900">{t("expensesPage.reimbursementReference")}:</span>{" "}
                  {expense.reimbursement_reference}
                </div>
              )}
              {expense.reimbursement_notes && (
                <div>
                  <span className="font-semibold text-slate-900">{t("expensesPage.reimbursementNotes")}:</span>{" "}
                  {expense.reimbursement_notes}
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
