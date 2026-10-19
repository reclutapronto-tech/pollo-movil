"use client";

import { useEffect, useState } from "react";
import type { Job, ScheduleEntry, Worker } from "@/lib/schedule/types";

interface Props {
  open: boolean;
  initial: Partial<ScheduleEntry> | null;
  workers: Worker[];
  jobs: Job[];
  onClose: () => void;
  onSubmit: (values: {
    shift_id?: string;
    worker_id: string;
    job_id: string;
    shift_date: string;
    start_time: string;
    end_time: string;
    notes: string | null;
    publish?: boolean;
  }) => Promise<void>;
  onDelete?: (id: string) => Promise<void>;
  busy: boolean;
  labels: {
    addTitle: string;
    editTitle: string;
    worker: string;
    job: string;
    day: string;
    startTime: string;
    endTime: string;
    notes: string;
    notesPlaceholder: string;
    selectWorker: string;
    selectJob: string;
    cancel: string;
    save: string;
    saving: string;
    remove: string;
    removing: string;
  };
}

export function ShiftFormModal({
  open,
  initial,
  workers,
  jobs,
  onClose,
  onSubmit,
  onDelete,
  busy,
  labels,
}: Props) {
  const [workerId, setWorkerId] = useState("");
  const [jobId, setJobId] = useState("");
  const [date, setDate] = useState("");
  const [startTime, setStartTime] = useState("08:00");
  const [endTime, setEndTime] = useState("16:00");
  const [notes, setNotes] = useState("");

  useEffect(() => {
    if (!open) return;
    setWorkerId(initial?.worker_id ?? "");
    setJobId(initial?.job_id ?? "");
    setDate(initial?.date ?? new Date().toISOString().slice(0, 10));
    setStartTime(initial?.start_time?.slice(0, 5) ?? "08:00");
    setEndTime(initial?.end_time?.slice(0, 5) ?? "16:00");
    setNotes(initial?.notes ?? "");
  }, [open, initial]);

  if (!open) return null;
  const editingId = initial?.id;
  const canSave = workerId && jobId && date && startTime && endTime;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
      onClick={onClose}
    >
      <div
        className="w-full max-w-md rounded-2xl bg-white p-5 shadow-xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-4 flex items-center justify-between">
          <h2 className="text-lg font-semibold text-stone-900">
            {editingId ? labels.editTitle : labels.addTitle}
          </h2>
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg p-1 text-stone-500 hover:bg-stone-100"
            aria-label={labels.cancel}
          >
            ×
          </button>
        </div>

        <div className="space-y-3">
          <Field label={labels.worker}>
            <select
              value={workerId}
              onChange={(e) => setWorkerId(e.target.value)}
              className="w-full rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30"
            >
              <option value="">{labels.selectWorker}</option>
              {workers.map((w) => (
                <option key={w.id} value={w.id}>
                  {w.full_name}
                </option>
              ))}
            </select>
          </Field>

          <Field label={labels.job}>
            <select
              value={jobId}
              onChange={(e) => setJobId(e.target.value)}
              className="w-full rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30"
            >
              <option value="">{labels.selectJob}</option>
              {jobs.map((j) => (
                <option key={j.id} value={j.id}>
                  {j.code ? `${j.code} — ` : ""}{j.name}
                </option>
              ))}
            </select>
          </Field>

          <Field label={labels.day}>
            <input
              type="date"
              value={date}
              onChange={(e) => setDate(e.target.value)}
              className="w-full rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30"
            />
          </Field>

          <div className="grid grid-cols-2 gap-3">
            <Field label={labels.startTime}>
              <input
                type="time"
                value={startTime}
                onChange={(e) => setStartTime(e.target.value)}
                className="w-full rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30"
              />
            </Field>
            <Field label={labels.endTime}>
              <input
                type="time"
                value={endTime}
                onChange={(e) => setEndTime(e.target.value)}
                className="w-full rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30"
              />
            </Field>
          </div>

          <Field label={labels.notes}>
            <textarea
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              placeholder={labels.notesPlaceholder}
              rows={2}
              className="w-full resize-none rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30"
            />
          </Field>
        </div>

        <div className="mt-5 flex items-center justify-between gap-2">
          <div>
            {editingId && onDelete && (
              <button
                type="button"
                onClick={() => onDelete(editingId)}
                disabled={busy}
                className="rounded-lg border border-red-200 px-3 py-1.5 text-sm font-medium text-red-600 hover:bg-red-50 disabled:bg-stone-100 disabled:text-slate-400"
              >
                {busy ? labels.removing : labels.remove}
              </button>
            )}
          </div>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={onClose}
              disabled={busy}
              className="rounded-lg border border-stone-200 px-3 py-1.5 text-sm font-medium text-stone-700 hover:bg-stone-50"
            >
              {labels.cancel}
            </button>
            <button
              type="button"
              onClick={() =>
                canSave &&
                onSubmit({
                  shift_id: editingId,
                  worker_id: workerId,
                  job_id: jobId,
                  shift_date: date,
                  start_time: `${startTime}:00`,
                  end_time: `${endTime}:00`,
                  notes: notes.trim() || null,
                  publish: false,
                })
              }
              disabled={!canSave || busy}
              className="rounded-lg inline-flex min-h-11 items-center rounded-lg bg-slate-900 px-4 text-sm font-semibold text-white transition-colors hover:bg-slate-800 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-white disabled:cursor-not-allowed disabled:bg-stone-100 disabled:text-slate-400"
            >
              {busy ? labels.saving : labels.save}
            </button>
            <button
              type="button"
              onClick={() =>
                canSave &&
                onSubmit({
                  shift_id: editingId,
                  worker_id: workerId,
                  job_id: jobId,
                  shift_date: date,
                  start_time: `${startTime}:00`,
                  end_time: `${endTime}:00`,
                  notes: notes.trim() || null,
                  publish: true,
                })
              }
              disabled={!canSave || busy}
              className="rounded-lg bg-emerald-600 px-4 py-1.5 text-sm font-semibold text-white shadow-sm hover:bg-emerald-700 disabled:cursor-not-allowed disabled:bg-stone-100 disabled:text-slate-400"
            >
              {busy ? labels.saving : "Publish Now"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="mb-1 block text-xs font-semibold uppercase tracking-wide text-stone-500">
        {label}
      </span>
      {children}
    </label>
  );
}
