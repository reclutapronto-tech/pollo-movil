"use client";

import { useEffect, useState, useCallback } from "react";
import { useI18n } from "@/lib/i18n";
import { getSupabase } from "@/lib/supabase";
import { FileDown, Save, ChevronDown } from "lucide-react";
import { JobReportView } from "./JobReportView";

/* ---------- Types ---------- */

interface Job {
  id: string;
  name: string;
  code: string;
}

interface Preset {
  name: string;
  jobId: string;
  dateFrom: string;
  dateTo: string;
  reportType: string;
}

const PRESET_KEY = "report_presets";

function loadPresets(): Preset[] {
  if (typeof window === "undefined") return [];
  try {
    return JSON.parse(localStorage.getItem(PRESET_KEY) || "[]");
  } catch {
    return [];
  }
}

function savePresetsToStorage(presets: Preset[]) {
  localStorage.setItem(PRESET_KEY, JSON.stringify(presets));
}

/* ---------- Page ---------- */

export default function ReportsPage() {
  const { t } = useI18n();
  const [jobs, setJobs] = useState<Job[]>([]);
  const [selectedJob, setSelectedJob] = useState("");
  const [dateFrom, setDateFrom] = useState(() => {
    const d = new Date();
    d.setDate(d.getDate() - 7);
    return d.toISOString().split("T")[0];
  });
  const [dateTo, setDateTo] = useState(() =>
    new Date().toISOString().split("T")[0],
  );
  const [generating, setGenerating] = useState(false);
  const [reportData, setReportData] = useState<Record<string, unknown> | null>(null);
  const [csvData, setCsvData] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [lastReportType, setLastReportType] = useState<string>("");

  // Presets state
  const [presets, setPresets] = useState<Preset[]>([]);
  const [presetName, setPresetName] = useState("");
  const [showPresetInput, setShowPresetInput] = useState(false);
  const [showPresetDropdown, setShowPresetDropdown] = useState(false);

  useEffect(() => {
    loadJobs();
    setPresets(loadPresets());
  }, []);

  async function loadJobs() {
    const supabase = getSupabase();
    const { data } = await supabase
      .from("jobs")
      .select("id, name, code")
      .in("status", ["active", "in_progress"])
      .order("name");
    setJobs(data ?? []);
  }

  async function generateReport(reportType: string) {
    setGenerating(true);
    setError(null);
    setReportData(null);
    setCsvData(null);
    setLastReportType(reportType);

    try {
      const supabase = getSupabase();
      const session = await supabase.auth.getSession();
      const token = session.data.session?.access_token;

      const body: Record<string, string> = { report_type: reportType };
      if (selectedJob) body.job_id = selectedJob;
      if (reportType === "timesheet") {
        body.date_from = dateFrom;
        body.date_to = dateTo;
      }

      const res = await fetch(
        `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/reports`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${token}`,
          },
          body: JSON.stringify(body),
        },
      );

      const data = await res.json();
      if (!res.ok) throw new Error(data.message || t("reports.generationFailed"));

      if (reportType === "job_report") {
        setReportData(data.report);
      } else {
        setCsvData(data.csv);
        setReportData(data);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : t("reports.failedToGenerate"));
    } finally {
      setGenerating(false);
    }
  }

  function downloadCsv() {
    if (!csvData) return;
    const blob = new Blob([csvData], { type: "text/csv" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `timesheet_${dateFrom}_${dateTo}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  function downloadQuickbooksExport() {
    if (!csvData) return;
    const lines = csvData.split("\n").filter(Boolean);
    // Skip header row (index 0)
    const rows = lines.slice(1).map((line) => {
      // Split respecting quoted fields
      const cols: string[] = [];
      let current = "";
      let inQuotes = false;
      for (const ch of line) {
        if (ch === '"') {
          inQuotes = !inQuotes;
        } else if (ch === "," && !inQuotes) {
          cols.push(current.trim());
          current = "";
        } else {
          current += ch;
        }
      }
      cols.push(current.trim());
      // Original columns: Worker,Date,Job Code,Cost Code,Clock In,Clock Out,Regular Hours,OT Hours,Total Hours
      const [worker, date, jobCode, , clockIn, clockOut, , , totalHours] = cols;
      const description = clockIn && clockOut ? `${clockIn} - ${clockOut}` : "";
      return `"${worker}","${date}","${jobCode}","${description}","${totalHours}","No"`;
    });
    const qbHeader = "Name,Date,Item/Service,Description,Hours,Billable";
    const qbCsv = [qbHeader, ...rows].join("\n");
    const blob = new Blob([qbCsv], { type: "text/csv" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    const today = new Date().toISOString().slice(0, 10);
    a.download = `quickbooks_timesheet_${today}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  function handleExportPdf() {
    window.print();
  }

  const handleSavePreset = useCallback(() => {
    const trimmed = presetName.trim();
    if (!trimmed) return;
    const newPreset: Preset = {
      name: trimmed,
      jobId: selectedJob,
      dateFrom,
      dateTo,
      reportType: lastReportType || "job_report",
    };
    const updated = [...presets.filter((p) => p.name !== trimmed), newPreset];
    setPresets(updated);
    savePresetsToStorage(updated);
    setPresetName("");
    setShowPresetInput(false);
  }, [presetName, selectedJob, dateFrom, dateTo, lastReportType, presets]);

  function applyPreset(preset: Preset) {
    setSelectedJob(preset.jobId);
    setDateFrom(preset.dateFrom);
    setDateTo(preset.dateTo);
    setShowPresetDropdown(false);
  }

  return (
    <div>
      <div className="mb-8">
        <a
          href="/"
          className="no-print mb-4 inline-flex items-center gap-1 text-sm font-medium text-slate-600 transition-colors hover:text-slate-900 dark:text-slate-400 dark:hover:text-slate-100"
        >
          <span aria-hidden="true">&larr;</span> {t("common.backToDashboard")}
        </a>
        <h1 className="text-2xl font-bold tracking-tight text-slate-900 dark:text-slate-100">
          {t("reports.title")}
        </h1>
        <p className="mt-1 text-sm text-slate-600 dark:text-slate-400">
          {t("reports.subtitle")}
        </p>
      </div>

      {/* Controls */}
      <div className="no-print mb-8 rounded-2xl border border-stone-200 bg-card p-6 shadow-sm dark:border-slate-800">
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700 dark:text-slate-300">
              {t("reports.job")}
            </label>
            <select
              value={selectedJob}
              onChange={(e) => setSelectedJob(e.target.value)}
              className="w-full rounded-xl border border-stone-200 bg-card px-4 py-2.5 text-sm text-slate-900 focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 dark:border-slate-700 dark:text-slate-100"
            >
              <option value="">{t("reports.allJobs")}</option>
              {jobs.map((j) => (
                <option key={j.id} value={j.id}>
                  {j.name} ({j.code})
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700 dark:text-slate-300">
              {t("reports.from")}
            </label>
            <input
              type="date"
              value={dateFrom}
              onChange={(e) => setDateFrom(e.target.value)}
              className="w-full rounded-xl border border-stone-200 bg-card px-4 py-2.5 text-sm tabular-nums text-slate-900 focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 dark:border-slate-700 dark:text-slate-100"
            />
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700 dark:text-slate-300">
              {t("reports.to")}
            </label>
            <input
              type="date"
              value={dateTo}
              onChange={(e) => setDateTo(e.target.value)}
              className="w-full rounded-xl border border-stone-200 bg-card px-4 py-2.5 text-sm tabular-nums text-slate-900 focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 dark:border-slate-700 dark:text-slate-100"
            />
          </div>
          <div className="flex items-end gap-2">
            <button
              type="button"
              onClick={() => generateReport("job_report")}
              disabled={generating || !selectedJob}
              className="inline-flex min-h-11 items-center rounded-xl bg-slate-900 px-5 text-sm font-semibold text-white transition-colors hover:bg-slate-800 disabled:bg-stone-100 disabled:text-slate-400 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-white dark:disabled:bg-slate-800 dark:disabled:text-slate-500"
            >
              {generating ? t("reports.generating") : t("reports.jobReport")}
            </button>
            <button
              type="button"
              onClick={() => generateReport("timesheet")}
              disabled={generating}
              className="inline-flex min-h-11 items-center rounded-xl border border-stone-200 bg-card px-5 text-sm font-semibold text-slate-700 transition-colors hover:bg-stone-50 disabled:bg-stone-100 disabled:text-slate-400 dark:border-slate-700 dark:text-slate-200 dark:hover:bg-slate-800 dark:disabled:bg-slate-900 dark:disabled:text-slate-500"
            >
              {generating ? "…" : t("reports.timesheet")}
            </button>
          </div>
        </div>

        {/* Action row: Export PDF + Presets */}
        <div className="mt-4 flex flex-wrap items-center gap-2 border-t border-stone-200 pt-4 dark:border-slate-800">
          {/* Export PDF */}
          <button
            type="button"
            onClick={handleExportPdf}
            disabled={!reportData}
            className="inline-flex min-h-11 items-center gap-1.5 rounded-xl border border-stone-200 bg-card px-4 text-sm font-medium text-slate-700 transition-colors hover:bg-stone-50 disabled:bg-stone-100 disabled:text-slate-400 dark:border-slate-700 dark:text-slate-200 dark:hover:bg-slate-800 dark:disabled:bg-slate-900 dark:disabled:text-slate-500"
          >
            <FileDown size={16} aria-hidden="true" />
            {t("reports.exportPdf")}
          </button>

          {/* Export for QuickBooks */}
          <button
            type="button"
            onClick={downloadQuickbooksExport}
            disabled={!csvData}
            className="inline-flex min-h-11 items-center gap-1.5 rounded-xl border border-stone-200 bg-card px-4 text-sm font-medium text-slate-700 transition-colors hover:bg-stone-50 disabled:bg-stone-100 disabled:text-slate-400 dark:border-slate-700 dark:text-slate-200 dark:hover:bg-slate-800 dark:disabled:bg-slate-900 dark:disabled:text-slate-500"
          >
            <FileDown size={16} aria-hidden="true" />
            {t("reports.exportQuickbooks")}
          </button>

          {/* Save Preset */}
          {showPresetInput ? (
            <div className="inline-flex items-center gap-2">
              <input
                type="text"
                value={presetName}
                onChange={(e) => setPresetName(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && handleSavePreset()}
                placeholder={t("reports.presetName")}
                className="min-h-11 rounded-xl border border-stone-200 bg-card px-3 text-sm text-slate-900 focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 dark:border-slate-700 dark:text-slate-100"
                autoFocus
              />
              <button
                type="button"
                onClick={handleSavePreset}
                disabled={!presetName.trim()}
                aria-label={t("reports.savePreset")}
                className="inline-flex h-11 w-11 items-center justify-center rounded-xl bg-emerald-600 text-white transition-colors hover:bg-emerald-700 disabled:bg-stone-100 disabled:text-slate-400 dark:disabled:bg-slate-900 dark:disabled:text-slate-500"
              >
                <Save size={16} aria-hidden="true" />
              </button>
              <button
                type="button"
                onClick={() => {
                  setShowPresetInput(false);
                  setPresetName("");
                }}
                className="inline-flex min-h-11 items-center px-2 text-sm font-medium text-slate-600 transition-colors hover:text-slate-900 dark:text-slate-400 dark:hover:text-slate-100"
              >
                {t("common.cancel")}
              </button>
            </div>
          ) : (
            <button
              type="button"
              onClick={() => setShowPresetInput(true)}
              className="inline-flex min-h-11 items-center gap-1.5 rounded-xl border border-stone-200 bg-card px-4 text-sm font-medium text-slate-700 transition-colors hover:bg-stone-50 dark:border-slate-700 dark:text-slate-200 dark:hover:bg-slate-800"
            >
              <Save size={16} aria-hidden="true" />
              {t("reports.savePreset")}
            </button>
          )}

          {/* Load Preset */}
          {presets.length > 0 && (
            <div className="relative">
              <button
                type="button"
                onClick={() => setShowPresetDropdown(!showPresetDropdown)}
                aria-expanded={showPresetDropdown}
                className="inline-flex min-h-11 items-center gap-1.5 rounded-xl border border-stone-200 bg-card px-4 text-sm font-medium text-slate-700 transition-colors hover:bg-stone-50 dark:border-slate-700 dark:text-slate-200 dark:hover:bg-slate-800"
              >
                <ChevronDown size={16} aria-hidden="true" />
                {t("reports.loadPreset")}
              </button>
              {showPresetDropdown && (
                <div
                  role="menu"
                  className="absolute left-0 top-full z-20 mt-1 w-56 rounded-xl border border-stone-200 bg-popover py-1 shadow-lg dark:border-slate-700"
                >
                  {presets.map((p) => (
                    <button
                      key={p.name}
                      type="button"
                      role="menuitem"
                      onClick={() => applyPreset(p)}
                      className="block w-full px-4 py-2.5 text-left text-sm text-slate-700 transition-colors hover:bg-stone-50 dark:text-slate-200 dark:hover:bg-slate-800"
                    >
                      {p.name}
                    </button>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>
      </div>

      {error && (
        <div
          role="alert"
          className="mb-6 rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700 dark:border-red-900/50 dark:bg-red-950/30 dark:text-red-300"
        >
          {error}
        </div>
      )}

      {/* CSV Download */}
      {csvData && (
        <div className="mb-6 rounded-2xl border border-emerald-200 bg-emerald-50 p-5 dark:border-emerald-900/50 dark:bg-emerald-950/30">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <h3 className="font-bold tracking-tight text-emerald-900 dark:text-emerald-200">
                {t("reports.timesheetReady")}
              </h3>
              <p className="mt-1 text-sm tabular-nums text-emerald-700 dark:text-emerald-300">
                {t("reports.timesheetSummary", {
                  rows:
                    ((reportData as Record<string, unknown>)?.row_count as number) ??
                    0,
                  from: dateFrom,
                  to: dateTo,
                })}
              </p>
            </div>
            <button
              type="button"
              onClick={downloadCsv}
              className="no-print inline-flex min-h-11 items-center rounded-xl bg-emerald-600 px-5 text-sm font-semibold text-white transition-colors hover:bg-emerald-700 dark:bg-emerald-500 dark:hover:bg-emerald-400"
            >
              {t("reports.downloadCsv")}
            </button>
          </div>
        </div>
      )}

      {/* Job Report Display */}
      <div data-print-area>
        {reportData && (reportData as Record<string, unknown>).report_type === "job_report" && (
          <JobReportView report={reportData} t={t} />
        )}
      </div>
    </div>
  );
}
