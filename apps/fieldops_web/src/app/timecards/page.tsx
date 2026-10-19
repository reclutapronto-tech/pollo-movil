"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useI18n } from "@/lib/i18n";
import { getSupabase } from "@/lib/supabase";
import { BulkActionBar } from "@/components/bulk-action-bar";

/* ── Types ────────────────────────────────────────────────── */

interface Timecard {
  id: string;
  worker_id: string;
  supervisor_id: string | null;
  week_start: string;
  week_end: string;
  worker_signed_at: string | null;
  supervisor_signed_at: string | null;
  total_regular_hours: number | null;
  total_ot_hours: number | null;
  status: "pending" | "worker_signed" | "approved" | "disputed";
  created_at: string;
  users?: { full_name: string } | null;
}

/* ── Helpers ──────────────────────────────────────────────── */

function getWeekStart(date: Date): string {
  const d = new Date(date);
  const day = d.getUTCDay();
  const offset = day === 0 ? -6 : 1 - day;
  d.setUTCDate(d.getUTCDate() + offset);
  return d.toISOString().split("T")[0];
}

function statusBadge(status: string, t: (key: string) => string) {
  const map: Record<string, { label: string; color: string }> = {
    pending: { label: t("timecards.pending"), color: "bg-stone-100 text-stone-600" },
    worker_signed: { label: t("timecards.workerSigned"), color: "bg-blue-100 text-blue-700" },
    approved: { label: t("timecards.approved"), color: "bg-green-100 text-green-700" },
    disputed: { label: t("timecards.disputed"), color: "bg-red-100 text-red-700" },
  };
  const badge = map[status] ?? map.pending;
  return (
    <span className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold ${badge.color}`}>
      {badge.label}
    </span>
  );
}

/* ── Signature Pad ────────────────────────────────────────── */

function SignaturePad({
  onSave,
  onCancel,
  t,
}: {
  onSave: (dataUrl: string) => void;
  onCancel: () => void;
  t: (key: string) => string;
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const isDrawing = useRef(false);

  const getCoords = (e: React.MouseEvent | React.TouchEvent) => {
    const canvas = canvasRef.current;
    if (!canvas) return { x: 0, y: 0 };
    const rect = canvas.getBoundingClientRect();
    if ("touches" in e) {
      const touch = e.touches[0] || e.changedTouches[0];
      return { x: touch.clientX - rect.left, y: touch.clientY - rect.top };
    }
    return { x: e.clientX - rect.left, y: e.clientY - rect.top };
  };

  const startDraw = (e: React.MouseEvent | React.TouchEvent) => {
    e.preventDefault();
    isDrawing.current = true;
    const ctx = canvasRef.current?.getContext("2d");
    if (!ctx) return;
    const { x, y } = getCoords(e);
    ctx.beginPath();
    ctx.moveTo(x, y);
  };

  const draw = (e: React.MouseEvent | React.TouchEvent) => {
    e.preventDefault();
    if (!isDrawing.current) return;
    const ctx = canvasRef.current?.getContext("2d");
    if (!ctx) return;
    const { x, y } = getCoords(e);
    ctx.lineWidth = 2;
    ctx.lineCap = "round";
    ctx.strokeStyle = "#1e293b";
    ctx.lineTo(x, y);
    ctx.stroke();
  };

  const stopDraw = () => {
    isDrawing.current = false;
  };

  const handleClear = () => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (ctx) ctx.clearRect(0, 0, canvas.width, canvas.height);
  };

  const handleSave = () => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const dataUrl = canvas.toDataURL("image/png");
    onSave(dataUrl);
  };

  return (
    <div className="space-y-3">
      <div className="rounded-xl border-2 border-dashed border-stone-300 bg-card p-1">
        <canvas
          ref={canvasRef}
          width={400}
          height={150}
          className="w-full cursor-crosshair touch-none rounded-lg"
          onMouseDown={startDraw}
          onMouseMove={draw}
          onMouseUp={stopDraw}
          onMouseLeave={stopDraw}
          onTouchStart={startDraw}
          onTouchMove={draw}
          onTouchEnd={stopDraw}
        />
      </div>
      <p className="text-center text-xs text-slate-500">
        {t("timecards.signatureRequired")}
      </p>
      <div className="flex gap-2">
        <button
          onClick={handleClear}
          className="flex-1 rounded-xl border border-stone-200 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-stone-50"
        >
          {t("timecards.clearSignature")}
        </button>
        <button
          onClick={handleSave}
          className="flex-1 rounded-xl bg-slate-900 px-4 py-2 text-sm font-semibold text-white hover:bg-slate-800"
        >
          {t("timecards.saveSignature")}
        </button>
        <button
          onClick={onCancel}
          className="rounded-xl border border-stone-200 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-stone-50"
        >
          {t("common.cancel")}
        </button>
      </div>
    </div>
  );
}

/* ── Page ─────────────────────────────────────────────────── */

export default function TimecardsPage() {
  const { t } = useI18n();
  const [timecards, setTimecards] = useState<Timecard[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);
  const [signingId, setSigningId] = useState<string | null>(null);
  const [approvingId, setApprovingId] = useState<string | null>(null);
  const [busyAction, setBusyAction] = useState<string | null>(null);

  const [weekStart] = useState(() => getWeekStart(new Date()));
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());

  const toggleSelect = useCallback((id: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);

  const selectedTimecards = useMemo(
    () => timecards.filter((tc) => selectedIds.has(tc.id)),
    [timecards, selectedIds],
  );

  const exportCsv = useCallback(() => {
    if (selectedTimecards.length === 0) return;
    const esc = (v: string | number | null | undefined) => {
      const s = v == null ? "" : String(v);
      return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
    };
    const header = [
      "worker",
      "week_start",
      "week_end",
      "regular_hours",
      "ot_hours",
      "status",
      "worker_signed_at",
      "supervisor_signed_at",
    ].join(",");
    const rows = selectedTimecards.map((tc) =>
      [
        esc(tc.users?.full_name ?? ""),
        esc(tc.week_start),
        esc(tc.week_end),
        esc(tc.total_regular_hours ?? 0),
        esc(tc.total_ot_hours ?? 0),
        esc(tc.status),
        esc(tc.worker_signed_at ?? ""),
        esc(tc.supervisor_signed_at ?? ""),
      ].join(","),
    );
    const csv = [header, ...rows].join("\n");
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `timecards-${weekStart}-${new Date()
      .toISOString()
      .slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
    setSuccessMessage(
      t("timecards.bulkExportDone", { count: selectedTimecards.length }),
    );
  }, [selectedTimecards, weekStart, t]);

  const loadTimecards = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const supabase = getSupabase();
      const session = await supabase.auth.getSession();
      const token = session.data.session?.access_token;

      const res = await fetch(
        `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/timecards?week_start=${weekStart}`,
        {
          headers: { Authorization: `Bearer ${token}` },
        },
      );

      const data = await res.json();
      if (!res.ok) throw new Error(data.message || "Failed to load timecards");
      setTimecards(data.timecards || []);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to load timecards");
    } finally {
      setLoading(false);
    }
  }, [weekStart]);

  useEffect(() => {
    loadTimecards();
  }, [loadTimecards]);

  async function postTimecards(body: Record<string, unknown>) {
    const supabase = getSupabase();
    const session = await supabase.auth.getSession();
    const token = session.data.session?.access_token;

    const res = await fetch(
      `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/timecards`,
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
    if (!res.ok) throw new Error(data.message || "Request failed");
    return data;
  }

  async function handleSign(timecardId: string, signature: string) {
    setBusyAction(timecardId);
    setError(null);
    setSuccessMessage(null);
    try {
      await postTimecards({ action: "sign", timecard_id: timecardId, signature });
      setSigningId(null);
      setSuccessMessage(t("timecards.workerSigned"));
      await loadTimecards();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to sign timecard");
    } finally {
      setBusyAction(null);
    }
  }

  async function handleApprove(timecardId: string, signature: string) {
    setBusyAction(timecardId);
    setError(null);
    setSuccessMessage(null);
    try {
      await postTimecards({ action: "countersign", timecard_id: timecardId, signature });
      setApprovingId(null);
      setSuccessMessage(t("timecards.approved"));
      await loadTimecards();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to approve timecard");
    } finally {
      setBusyAction(null);
    }
  }

  return (
    <div>
      <div className="mb-8">
        <a
          href="/"
          className="mb-4 inline-flex items-center gap-1 text-sm font-medium text-slate-500 hover:text-slate-900"
        >
          <span>&larr;</span> {t("common.backToDashboard")}
        </a>
        <h1 className="text-2xl font-bold tracking-tight text-slate-900 dark:text-slate-100">{t("timecards.title")}</h1>
        <p className="mt-1 text-slate-600">
          {t("timecards.weekOf")} {weekStart}
        </p>
      </div>

      {error && (
        <div className="mb-6 rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700 dark:border-red-900/50 dark:bg-red-950/30 dark:text-red-300">
          {error}
        </div>
      )}

      {successMessage && (
        <div className="mb-6 rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-700 dark:border-emerald-900/50 dark:bg-emerald-950/30 dark:text-emerald-300">
          {successMessage}
        </div>
      )}

      {loading ? (
        <div className="flex items-center gap-2 pt-20 text-sm text-slate-500">
          <div className="h-4 w-4 animate-spin rounded-full border-2 border-stone-200 border-t-slate-900" />
          {t("common.loading")}
        </div>
      ) : timecards.length === 0 ? (
        <div className="rounded-2xl border border-stone-200 bg-card p-8 text-center text-sm text-slate-500">
          {t("common.noData")}
        </div>
      ) : (
        <>
          <BulkActionBar
            count={selectedIds.size}
            onClear={() => setSelectedIds(new Set())}
            selectedLabel={t("timecards.bulkSelected", { count: selectedIds.size })}
            actions={[
              {
                label: t("timecards.bulkExportCsv"),
                tone: "primary",
                onClick: exportCsv,
              },
            ]}
          />
          <div className="space-y-4">
          {timecards.map((tc) => (
            <div
              key={tc.id}
              className={`rounded-2xl border bg-card p-6 shadow-sm transition-colors dark:bg-slate-900 ${
                selectedIds.has(tc.id)
                  ? "border-amber-400 ring-2 ring-amber-200 dark:border-amber-500 dark:ring-amber-900/40"
                  : "border-stone-200 dark:border-slate-800"
              }`}
            >
              <div className="flex items-start justify-between gap-3">
                <label className="flex-shrink-0 cursor-pointer pt-1">
                  <input
                    type="checkbox"
                    checked={selectedIds.has(tc.id)}
                    onChange={() => toggleSelect(tc.id)}
                    className="h-4 w-4 rounded border-stone-300"
                    aria-label="Select timecard"
                  />
                </label>
                <div className="flex-1">
                  <h3 className="text-lg font-bold text-slate-900">
                    {tc.users?.full_name || t("common.unknown")}
                  </h3>
                  <p className="mt-1 text-sm text-slate-500">
                    {t("timecards.weekOf")} {tc.week_start} &mdash; {tc.week_end}
                  </p>
                </div>
                {statusBadge(tc.status, t)}
              </div>

              <div className="mt-4 grid grid-cols-2 gap-4 sm:grid-cols-4">
                <div>
                  <div className="text-xs font-semibold uppercase text-slate-500">
                    {t("timecards.regularHours")}
                  </div>
                  <div className="mt-1 text-xl font-bold text-slate-900">
                    {tc.total_regular_hours ?? 0}h
                  </div>
                </div>
                <div>
                  <div className="text-xs font-semibold uppercase text-slate-500">
                    {t("timecards.otHours")}
                  </div>
                  <div className="mt-1 text-xl font-bold text-amber-600">
                    {tc.total_ot_hours ?? 0}h
                  </div>
                </div>
                <div>
                  <div className="text-xs font-semibold uppercase text-slate-500">
                    {t("timecards.workerSigned")}
                  </div>
                  <div className="mt-1 text-sm text-slate-600">
                    {tc.worker_signed_at
                      ? new Date(tc.worker_signed_at).toLocaleDateString()
                      : "--"}
                  </div>
                </div>
                <div>
                  <div className="text-xs font-semibold uppercase text-slate-500">
                    {t("timecards.approved")}
                  </div>
                  <div className="mt-1 text-sm text-slate-600">
                    {tc.supervisor_signed_at
                      ? new Date(tc.supervisor_signed_at).toLocaleDateString()
                      : "--"}
                  </div>
                </div>
              </div>

              {/* Worker sign action */}
              {tc.status === "pending" && signingId !== tc.id && (
                <div className="mt-4">
                  <button
                    onClick={() => setSigningId(tc.id)}
                    disabled={busyAction === tc.id}
                    className="rounded-xl bg-slate-900 px-5 py-2.5 text-sm font-semibold text-white hover:bg-slate-800 disabled:bg-stone-100 disabled:text-slate-400"
                  >
                    {t("timecards.sign")}
                  </button>
                </div>
              )}

              {signingId === tc.id && (
                <div className="mt-4">
                  <SignaturePad
                    onSave={(sig) => handleSign(tc.id, sig)}
                    onCancel={() => setSigningId(null)}
                    t={t}
                  />
                </div>
              )}

              {/* Supervisor approve action */}
              {tc.status === "worker_signed" && approvingId !== tc.id && (
                <div className="mt-4">
                  <button
                    onClick={() => setApprovingId(tc.id)}
                    disabled={busyAction === tc.id}
                    className="rounded-xl bg-green-600 px-5 py-2.5 text-sm font-semibold text-white hover:bg-green-700 disabled:bg-stone-100 disabled:text-slate-400"
                  >
                    {t("timecards.approve")}
                  </button>
                </div>
              )}

              {approvingId === tc.id && (
                <div className="mt-4">
                  <SignaturePad
                    onSave={(sig) => handleApprove(tc.id, sig)}
                    onCancel={() => setApprovingId(null)}
                    t={t}
                  />
                </div>
              )}
            </div>
          ))}
          </div>
        </>
      )}
    </div>
  );
}
