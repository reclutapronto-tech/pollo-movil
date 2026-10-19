"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  DndContext,
  PointerSensor,
  TouchSensor,
  useSensor,
  useSensors,
  type DragEndEvent,
} from "@dnd-kit/core";
import { useI18n } from "@/lib/i18n";
import { getSupabase } from "@/lib/supabase";
import { callFunctionJson } from "@/lib/function-client";
import { ScheduleToolbar } from "@/components/schedule/Toolbar";
import { WorkerGrid } from "@/components/schedule/WorkerGrid";
import { MobileDayList } from "@/components/schedule/MobileDayList";
import { ShiftFormModal } from "@/components/schedule/ShiftFormModal";
import {
  asDateKey,
  buildVisibleDates,
  formatRangeLabel,
  shiftAnchor,
} from "@/lib/schedule/dates";
import type {
  Job,
  PtoRequest,
  ScheduleEntry,
  ViewMode,
  Worker,
} from "@/lib/schedule/types";

interface SchedulePayload {
  shifts?: ScheduleEntry[];
  pto_requests?: PtoRequest[];
}

export default function SchedulePage() {
  const { t } = useI18n();

  const [anchorDate, setAnchorDate] = useState<string>(() =>
    asDateKey(new Date()),
  );
  const [viewMode, setViewMode] = useState<ViewMode>("week");
  const [workers, setWorkers] = useState<Worker[]>([]);
  const [jobs, setJobs] = useState<Job[]>([]);
  const [entries, setEntries] = useState<ScheduleEntry[]>([]);
  const [ptoRequests, setPtoRequests] = useState<PtoRequest[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  const [workerSearch, setWorkerSearch] = useState("");
  const [selectedJobIds, setSelectedJobIds] = useState<Set<string>>(new Set());

  const [modalOpen, setModalOpen] = useState(false);
  const [modalInitial, setModalInitial] = useState<Partial<ScheduleEntry> | null>(
    null,
  );

  const [isMobile, setIsMobile] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia("(max-width: 767px)");
    const handler = () => setIsMobile(mq.matches);
    handler();
    mq.addEventListener("change", handler);
    return () => mq.removeEventListener("change", handler);
  }, []);

  const dates = useMemo(
    () => buildVisibleDates(anchorDate, viewMode),
    [anchorDate, viewMode],
  );
  const rangeStart = useMemo(() => asDateKey(dates[0]), [dates]);
  const rangeEnd = useMemo(() => asDateKey(dates[dates.length - 1]), [dates]);
  const rangeLabel = useMemo(
    () => formatRangeLabel(anchorDate, viewMode, dates),
    [anchorDate, viewMode, dates],
  );

  const filteredWorkers = useMemo(() => {
    const q = workerSearch.trim().toLowerCase();
    if (!q) return workers;
    return workers.filter(
      (w) =>
        w.full_name.toLowerCase().includes(q) ||
        w.role.toLowerCase().includes(q),
    );
  }, [workers, workerSearch]);

  const loadReferenceData = useCallback(async () => {
    const supabase = getSupabase();
    const [{ data: workersData }, { data: jobsData }] = await Promise.all([
      supabase
        .from("users")
        .select("id, full_name, role")
        .eq("is_active", true)
        .in("role", ["worker", "foreman"])
        .order("full_name"),
      supabase
        .from("jobs")
        .select("id, name, code")
        .in("status", ["active", "in_progress"])
        .order("name"),
    ]);
    setWorkers((workersData as Worker[]) ?? []);
    setJobs((jobsData as Job[]) ?? []);
  }, []);

  const loadVersionRef = useRef(0);

  const loadSchedule = useCallback(async () => {
    const payload = await callFunctionJson<SchedulePayload>("schedule", {
      query: { date_from: rangeStart, date_to: rangeEnd },
    });
    setEntries(payload.shifts ?? []);
    setPtoRequests(payload.pto_requests ?? []);
  }, [rangeStart, rangeEnd]);

  useEffect(() => {
    const version = ++loadVersionRef.current;
    (async () => {
      setLoading(true);
      setError(null);
      try {
        await Promise.all([loadReferenceData(), loadSchedule()]);
      } catch (err) {
        if (loadVersionRef.current === version) {
          setError(err instanceof Error ? err.message : t("schedulePage.failedToLoad"));
        }
      } finally {
        if (loadVersionRef.current === version) setLoading(false);
      }
    })();
  }, [loadReferenceData, loadSchedule, t]);

  async function postSchedule(body: Record<string, unknown>) {
    return callFunctionJson<unknown>("schedule", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Idempotency-Key": crypto.randomUUID(),
      },
      body: JSON.stringify(body),
    });
  }

  function openCreate(workerId?: string, date?: string) {
    setModalInitial({
      worker_id: workerId,
      date: date ?? anchorDate,
    } as Partial<ScheduleEntry>);
    setModalOpen(true);
  }

  function openEdit(entry: ScheduleEntry) {
    setModalInitial(entry);
    setModalOpen(true);
  }

  async function handleSubmit(values: {
    shift_id?: string;
    worker_id: string;
    job_id: string;
    shift_date: string;
    start_time: string;
    end_time: string;
    notes: string | null;
    publish?: boolean;
  }) {
    setBusy("save");
    setError(null);
    setSuccess(null);
    try {
      await postSchedule({
        action: values.shift_id ? "update" : "create",
        ...values,
        publish: values.publish ?? false,
      });
      await loadSchedule();
      if (!values.shift_id) {
        setAnchorDate(values.shift_date);
      }
      setModalOpen(false);
      setSuccess(
        values.publish
          ? t("schedulePage.shiftPublished") || "Shift published"
          : values.shift_id
            ? t("schedulePage.draftUpdated")
            : t("schedulePage.draftSaved"),
      );
    } catch (err) {
      setError(err instanceof Error ? err.message : t("schedulePage.failedToAdd"));
    } finally {
      setBusy(null);
    }
  }

  async function handleDelete(id: string) {
    setBusy("save");
    setError(null);
    setSuccess(null);
    try {
      await postSchedule({ action: "delete", shift_id: id });
      await loadSchedule();
      setModalOpen(false);
      setSuccess(t("schedulePage.draftRemoved"));
    } catch (err) {
      setError(err instanceof Error ? err.message : t("schedulePage.failedToRemove"));
    } finally {
      setBusy(null);
    }
  }

  async function handlePublish() {
    const draftIds = entries.filter((e) => e.status === "draft").map((e) => e.id);
    if (draftIds.length === 0) return;
    setBusy("publish");
    setError(null);
    setSuccess(null);
    try {
      await postSchedule({ action: "publish", shift_ids: draftIds });
      await loadSchedule();
      setSuccess(t("schedulePage.published"));
    } catch (err) {
      setError(err instanceof Error ? err.message : t("schedulePage.failedToPublish"));
    } finally {
      setBusy(null);
    }
  }

  async function handleCopyPrev() {
    setBusy("copy");
    setError(null);
    setSuccess(null);
    try {
      const prevAnchor = shiftAnchor(anchorDate, viewMode, -1);
      const prevDates = buildVisibleDates(prevAnchor, viewMode);
      await postSchedule({
        action: "copy_week",
        source_start: asDateKey(prevDates[0]),
        source_end: asDateKey(prevDates[prevDates.length - 1]),
        target_start: rangeStart,
      });
      await loadSchedule();
      setSuccess(t("schedulePage.weekCopied"));
    } catch (err) {
      setError(err instanceof Error ? err.message : t("schedulePage.failedToCopy"));
    } finally {
      setBusy(null);
    }
  }

  async function handleDragEnd(event: DragEndEvent) {
    const dragData = event.active.data.current as
      | { kind: string; entryId?: string }
      | undefined;
    const overData = event.over?.data.current as
      | { kind: string; workerId?: string; date?: string }
      | undefined;
    if (
      !dragData ||
      dragData.kind !== "shift" ||
      !dragData.entryId ||
      !overData ||
      overData.kind !== "cell" ||
      !overData.workerId ||
      !overData.date
    ) {
      return;
    }
    const entry = entries.find((e) => e.id === dragData.entryId);
    if (!entry) return;
    if (entry.worker_id === overData.workerId && entry.date === overData.date) return;

    setBusy("save");
    setError(null);
    try {
      await postSchedule({
        action: "update",
        shift_id: entry.id,
        worker_id: overData.workerId,
        job_id: entry.job_id,
        shift_date: overData.date,
        start_time: entry.start_time,
        end_time: entry.end_time,
        notes: entry.notes ?? null,
      });
      await loadSchedule();
      setSuccess(t("schedulePage.draftUpdated"));
    } catch (err) {
      setError(err instanceof Error ? err.message : t("schedulePage.failedToUpdate"));
    } finally {
      setBusy(null);
    }
  }

  function toggleJob(id: string) {
    setSelectedJobIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 150, tolerance: 5 } }),
  );

  const draftCount = useMemo(
    () => entries.filter((e) => e.status === "draft").length,
    [entries],
  );

  return (
    <div className="space-y-4 p-4 sm:p-6">
      <header className="flex flex-col gap-1">
        <a
          href="/"
          className="inline-flex items-center gap-1 text-xs font-medium text-stone-500 hover:text-stone-900"
        >
          ← {t("nav.home") || "Home"}
        </a>
        <h1 className="text-2xl font-bold tracking-tight text-slate-900 dark:text-slate-100">
          {t("schedulePage.title")}
        </h1>
        <p className="text-sm text-slate-600 dark:text-slate-400">{t("schedulePage.subtitle")}</p>
      </header>

      <ScheduleToolbar
        rangeLabel={rangeLabel}
        viewMode={viewMode}
        onViewModeChange={setViewMode}
        onPrev={() => setAnchorDate((a) => shiftAnchor(a, viewMode, -1))}
        onNext={() => setAnchorDate((a) => shiftAnchor(a, viewMode, 1))}
        onToday={() => setAnchorDate(asDateKey(new Date()))}
        jobs={jobs}
        selectedJobIds={selectedJobIds}
        onToggleJob={toggleJob}
        onClearJobs={() => setSelectedJobIds(new Set())}
        workerSearch={workerSearch}
        onWorkerSearchChange={setWorkerSearch}
        onAddShift={() => openCreate()}
        onPublish={handlePublish}
        onCopyPrev={handleCopyPrev}
        draftCount={draftCount}
        busyAction={busy}
        labels={{
          addShift: t("schedulePage.addShift"),
          publish: t("schedulePage.publishSchedule"),
          publishing: t("schedulePage.publishing"),
          copyPrev: t("schedulePage.prevWeek"),
          today: "Today",
          prev: t("schedulePage.prevRange"),
          next: t("schedulePage.nextRange"),
          searchWorkers: t("schedulePage.searchWorkersPlaceholder"),
          jobs: t("schedulePage.jobs"),
          clear: "Clear",
          viewModes: {
            day: t("schedulePage.viewModes.day"),
            week: t("schedulePage.viewModes.week"),
            twoWeek: t("schedulePage.viewModes.twoWeek"),
            month: t("schedulePage.viewModes.month"),
          },
          drafts: (n) =>
            t("schedulePage.draftShifts", { count: n, suffix: n === 1 ? "" : "s" }),
        }}
      />

      {error && (
        <div className="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700 dark:border-red-900/50 dark:bg-red-950/30 dark:text-red-300">
          {error}
        </div>
      )}
      {success && (
        <div className="rounded-lg border border-emerald-200 bg-emerald-50 px-3 py-2 text-sm text-emerald-700">
          {success}
        </div>
      )}

      {loading ? (
        <div className="rounded-2xl border border-stone-200 bg-card p-8 text-center text-sm text-stone-500">
          Loading schedule…
        </div>
      ) : isMobile ? (
        <MobileDayList
          workers={filteredWorkers}
          dates={dates}
          entries={entries}
          selectedJobIds={selectedJobIds}
          onShiftClick={openEdit}
          onAddForDate={(date) => openCreate(undefined, date)}
        />
      ) : (
        <DndContext sensors={sensors} onDragEnd={handleDragEnd}>
          <WorkerGrid
            workers={filteredWorkers}
            dates={dates}
            entries={entries}
            ptoRequests={ptoRequests}
            rangeStart={rangeStart}
            rangeEnd={rangeEnd}
            selectedJobIds={selectedJobIds}
            onShiftClick={openEdit}
            onEmptyCellClick={openCreate}
            labels={{
              hours: (h) => `${h}h`,
              pto: t("schedulePage.onPto"),
              today: "Today",
            }}
          />
        </DndContext>
      )}

      <ShiftFormModal
        open={modalOpen}
        initial={modalInitial}
        workers={workers}
        jobs={jobs}
        onClose={() => setModalOpen(false)}
        onSubmit={handleSubmit}
        onDelete={handleDelete}
        busy={busy === "save"}
        labels={{
          addTitle: t("schedulePage.addShiftTitle"),
          editTitle: t("schedulePage.editShiftTitle"),
          worker: t("schedulePage.worker"),
          job: t("schedulePage.job"),
          day: t("schedulePage.day"),
          startTime: t("schedulePage.startTime"),
          endTime: t("schedulePage.endTime"),
          notes: t("schedulePage.notes"),
          notesPlaceholder: t("schedulePage.notesPlaceholder"),
          selectWorker: t("schedulePage.selectWorker"),
          selectJob: t("schedulePage.selectJob"),
          cancel: t("schedulePage.cancel"),
          save: t("schedulePage.saveDraft"),
          saving: t("schedulePage.saving"),
          remove: t("schedulePage.remove"),
          removing: t("schedulePage.removing"),
        }}
      />
    </div>
  );
}
