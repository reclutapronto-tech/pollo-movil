"use client";

import { useCallback, useEffect, useState } from "react";
import { useI18n } from "@/lib/i18n";
import { callFunctionJson } from "@/lib/function-client";
import { getSupabase } from "@/lib/supabase";

interface Job {
  id: string;
  name: string;
  code: string;
}

interface CostCodeBreakdown {
  cost_code: string;
  total_hours: number;
  worker_count: number;
}

interface CostCodesResponse {
  cost_codes?: string[];
}

interface CostCodeReportResponse {
  breakdown?: CostCodeBreakdown[];
  total_hours?: number;
}

export default function CostCodesPage() {
  const { t } = useI18n();
  const [jobs, setJobs] = useState<Job[]>([]);
  const [selectedJobId, setSelectedJobId] = useState<string>("");
  const [codes, setCodes] = useState<string[]>([]);
  const [breakdown, setBreakdown] = useState<CostCodeBreakdown[]>([]);
  const [totalHours, setTotalHours] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loadPage = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const supabase = getSupabase();
      const { data: jobData, error: jobsError } = await supabase
        .from("jobs")
        .select("id, name, code")
        .in("status", ["active", "in_progress", "completed"])
        .order("name");

      if (jobsError) throw jobsError;

      const activeJobs = (jobData as Job[]) ?? [];
      setJobs(activeJobs);

      const codesPayload = await callFunctionJson<CostCodesResponse>("cost_codes");
      setCodes(codesPayload.cost_codes ?? []);

      const jobId = selectedJobId || activeJobs[0]?.id || "";
      if (!jobId) {
        setBreakdown([]);
        setTotalHours(0);
        return;
      }

      if (!selectedJobId) {
        setSelectedJobId(jobId);
      }

      const reportPayload = await callFunctionJson<CostCodeReportResponse>("cost_codes", {
        query: {
          job_id: jobId,
          report: "profitability",
        },
      });
      setBreakdown(reportPayload.breakdown ?? []);
      setTotalHours(
        typeof reportPayload.total_hours === "number" ? reportPayload.total_hours : 0,
      );
    } catch (err) {
      setError(err instanceof Error ? err.message : t("costCodesPage.failedToLoad"));
    } finally {
      setLoading(false);
    }
  }, [selectedJobId, t]);

  useEffect(() => {
    loadPage();
  }, [loadPage]);

  return (
    <div>
      <div className="mb-8">
        <a
          href="/"
          className="mb-4 inline-flex items-center gap-1 text-sm font-medium text-slate-500 hover:text-slate-900"
        >
          <span>&larr;</span> {t("common.backToDashboard")}
        </a>
        <h1 className="text-2xl font-bold tracking-tight text-slate-900 dark:text-slate-100">{t("costCodesPage.title")}</h1>
        <p className="mt-1 text-sm text-slate-600 dark:text-slate-400">{t("costCodesPage.subtitle")}</p>
      </div>

      <div className="mb-6 grid gap-4 lg:grid-cols-[320px,1fr]">
        <div className="rounded-2xl border border-stone-200 bg-card p-5 shadow-sm">
          <div className="mb-3 text-xs font-semibold uppercase tracking-widest text-slate-500">
            {t("costCodesPage.jobFilter")}
          </div>
          <select
            value={selectedJobId}
            onChange={(event) => setSelectedJobId(event.target.value)}
            className="w-full rounded-xl border border-stone-300 px-4 py-2.5 text-sm"
          >
            {jobs.map((job) => (
              <option key={job.id} value={job.id}>
                {job.name} ({job.code})
              </option>
            ))}
          </select>
          <button
            onClick={loadPage}
            className="mt-3 w-full rounded-xl bg-slate-900 px-4 py-2 text-sm font-semibold text-white hover:bg-slate-800"
          >
            {t("costCodesPage.refreshReport")}
          </button>
        </div>

        <div className="rounded-2xl border border-stone-200 bg-card p-5 shadow-sm">
          <div className="mb-2 text-xs font-semibold uppercase tracking-widest text-slate-500">
            {t("costCodesPage.knownCostCodes")}
          </div>
          <div className="flex flex-wrap gap-2">
            {codes.length === 0 && (
              <span className="text-sm text-slate-500">{t("costCodesPage.noCodes")}</span>
            )}
            {codes.map((code) => (
              <span
                key={code}
                className="rounded-full border border-stone-200 bg-stone-50 px-3 py-1 text-xs font-semibold text-slate-600"
              >
                {code}
              </span>
            ))}
          </div>
        </div>
      </div>

      {loading && (
        <div className="flex items-center gap-2 text-slate-500">
          <div className="h-4 w-4 animate-spin rounded-full border-2 border-slate-300 border-t-amber-500" />
          {t("costCodesPage.loading")}
        </div>
      )}

      {error && (
        <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          {error}
        </div>
      )}

      {!loading && !error && (
        <div className="rounded-2xl border border-stone-200 bg-card shadow-sm">
          <div className="flex items-center justify-between border-b border-stone-100 px-5 py-4">
            <div>
              <div className="text-xs font-semibold uppercase tracking-widest text-slate-500">
                {t("costCodesPage.profitabilityView")}
              </div>
              <div className="text-lg font-bold text-slate-900">
                {jobs.find((job) => job.id === selectedJobId)?.name ?? t("costCodesPage.noJobSelected")}
              </div>
            </div>
            <div className="rounded-full bg-amber-50 px-4 py-2 text-sm font-semibold text-amber-700">
              {t("costCodesPage.totalHours", { hours: totalHours.toFixed(2) })}
            </div>
          </div>

          {breakdown.length === 0 ? (
            <div className="p-8 text-sm text-slate-500">
              {t("costCodesPage.noClassifiedLabor")}
            </div>
          ) : (
            <table className="min-w-full text-left text-sm">
              <thead className="bg-stone-50 text-slate-500">
                <tr>
                  <th className="px-5 py-3 font-semibold">{t("costCodesPage.costCode")}</th>
                  <th className="px-5 py-3 font-semibold">{t("costCodesPage.hours")}</th>
                  <th className="px-5 py-3 font-semibold">{t("costCodesPage.workers")}</th>
                </tr>
              </thead>
              <tbody>
                {breakdown.map((row) => (
                  <tr key={row.cost_code} className="border-t border-stone-100">
                    <td className="px-5 py-4 font-semibold text-slate-900">{row.cost_code}</td>
                    <td className="px-5 py-4 text-slate-600">{row.total_hours.toFixed(2)}h</td>
                    <td className="px-5 py-4 text-slate-600">{row.worker_count}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}
    </div>
  );
}
