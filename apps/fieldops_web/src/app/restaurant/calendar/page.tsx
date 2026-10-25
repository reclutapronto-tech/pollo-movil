"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { ArrowLeft, ArrowRight, CalendarClock, CalendarRange, RefreshCw, Settings2 } from "lucide-react";
import { callFunctionJson } from "@/lib/function-client";
import { preferredRestaurantBranchId, rememberRestaurantBranchId } from "@/lib/restaurant-branch-selection";
import { getSupabase } from "@/lib/supabase";

type Branch = { id: string; name: string; timezone: string; access_role: string };
type TaskPart = {
  id: string;
  assigned_to: string | null;
  assignee_name: string | null;
  estimated_minutes: number;
  status: string;
  zone_name: string | null;
};
type Task = {
  id: string;
  name: string;
  status: string;
  scheduled_for: string;
  assigned_to: string | null;
  assignee_name: string | null;
  area_name: string | null;
  estimated_minutes: number | null;
  priority: number;
  task_source: string;
  is_divisible: boolean;
  configuration_pending?: boolean;
  parts?: TaskPart[];
};
type AssignableMember = { id: string; full_name: string | null };

function isCalendarDate(value: string | null): value is string {
  if (!value || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [year, month, day] = value.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

const inputClass = "rounded-xl border border-stone-200 bg-white px-3 py-2 text-sm dark:border-slate-700 dark:bg-slate-900";
const panelClass = "rounded-2xl border border-stone-200 bg-white p-4 shadow-sm dark:border-slate-800 dark:bg-slate-900";
const secondaryClass = "inline-flex items-center gap-2 rounded-xl border border-stone-200 px-3 py-2 text-sm font-semibold hover:bg-stone-50 disabled:opacity-50 dark:border-slate-700 dark:hover:bg-slate-800";

function addDays(date: string, count: number) {
  const [year, month, day] = date.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day + count)).toISOString().slice(0, 10);
}

function startOfWeek(date: string) {
  const weekday = new Date(`${date}T12:00:00Z`).getUTCDay();
  return addDays(date, -((weekday + 6) % 7));
}

function dateInZone(timeZone: string) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone, year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}

function formatDay(date: string) {
  return new Intl.DateTimeFormat("es-MX", {
    weekday: "long", day: "numeric", month: "short", timeZone: "UTC",
  }).format(new Date(`${date}T12:00:00Z`));
}

function statusLabel(status: string) {
  return ({ pending: "Pendiente", in_progress: "En curso", paused: "Pausada", blocked: "Bloqueada", completed: "Terminada" } as Record<string, string>)[status] ?? status;
}

export default function RestaurantCalendarPage() {
  const [branches, setBranches] = useState<Branch[]>([]);
  const [branchId, setBranchId] = useState("");
  const [weekStart, setWeekStart] = useState("");
  const [tasks, setTasks] = useState<Task[]>([]);
  const [assignableMembers, setAssignableMembers] = useState<AssignableMember[]>([]);
  const [loading, setLoading] = useState(true);
  const [busyDate, setBusyDate] = useState("");
  const [schedulingWeek, setSchedulingWeek] = useState(false);
  const [savingTaskId, setSavingTaskId] = useState("");
  const [savingPartId, setSavingPartId] = useState("");
  const [savingScheduleTaskId, setSavingScheduleTaskId] = useState("");
  const [assigningToday, setAssigningToday] = useState(false);
  const [highlightTaskId, setHighlightTaskId] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const didScrollToHighlightedTask = useRef(false);

  const branch = branches.find((item) => item.id === branchId) ?? null;
  const branchToday = branch ? dateInZone(branch.timezone) : "";
  const canManage = branch ? ["admin", "supervisor"].includes(branch.access_role) : false;
  const days = useMemo(() => weekStart ? Array.from({ length: 7 }, (_, index) => addDays(weekStart, index)) : [], [weekStart]);

  const load = useCallback(async () => {
    if (!branchId || !weekStart) return;
    setLoading(true);
    setError(null);
    try {
      const result = await callFunctionJson<{ tasks: Task[]; assignable_members?: AssignableMember[] }>("restaurant_ops", {
        query: {
          action: "task_calendar",
          branch_id: branchId,
          from_date: weekStart,
          to_date: addDays(weekStart, 6),
        },
      });
      setTasks(result.tasks ?? []);
      setAssignableMembers(result.assignable_members ?? []);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "No se pudo cargar el calendario.");
    } finally {
      setLoading(false);
    }
  }, [branchId, weekStart]);

  useEffect(() => {
    let cancelled = false;
    callFunctionJson<{ branches: Branch[] }>("restaurant_ops", { query: { action: "branches" } })
      .then(({ branches: rows }) => {
        if (cancelled) return;
        const available = rows ?? [];
        setBranches(available);
        const params = new URLSearchParams(window.location.search);
        const requestedBranchId = params.get("branch_id");
        const requestedBranch = available.find((item) => item.id === requestedBranchId);
        const preferredId = requestedBranch?.id ?? preferredRestaurantBranchId(available);
        const requestedTaskId = params.get("task_id");
        if (requestedTaskId && requestedTaskId.length <= 80) setHighlightTaskId(requestedTaskId);
        setBranchId((current) => current && available.some((item) => item.id === current) ? current : preferredId);
        if (requestedBranch) rememberRestaurantBranchId(requestedBranch.id);
        if (!available.length) setLoading(false);
      })
      .catch((cause: unknown) => {
        if (!cancelled) {
          setError(cause instanceof Error ? cause.message : "No se pudieron cargar las sucursales.");
          setLoading(false);
        }
      });
    return () => { cancelled = true; };
  }, []);

  const branchTimezone = branch?.timezone;
  useEffect(() => {
    if (!branchTimezone) return;
    const requestedDate = new URLSearchParams(window.location.search).get("date");
    setWeekStart(startOfWeek(isCalendarDate(requestedDate) ? requestedDate : dateInZone(branchTimezone)));
  }, [branchTimezone]);

  useEffect(() => { void load(); }, [load]);

  useEffect(() => {
    if (didScrollToHighlightedTask.current || !highlightTaskId || !tasks.some((task) => task.id === highlightTaskId)) return;
    const frame = window.requestAnimationFrame(() => {
      const taskElement = document.getElementById(`restaurant-task-${highlightTaskId}`);
      if (!taskElement) return;
      taskElement.scrollIntoView({ behavior: "smooth", block: "center", inline: "nearest" });
      didScrollToHighlightedTask.current = true;
    });
    return () => window.cancelAnimationFrame(frame);
  }, [highlightTaskId, tasks]);

  useEffect(() => {
    if (!branchId) return;
    const supabase = getSupabase();
    let timer: number | undefined;
    const channel = supabase
      .channel(`pollo-calendar-${branchId}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_tasks", filter: `branch_id=eq.${branchId}` }, () => {
        if (timer !== undefined) window.clearTimeout(timer);
        timer = window.setTimeout(() => void load(), 250);
      })
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_task_parts", filter: `branch_id=eq.${branchId}` }, () => {
        if (timer !== undefined) window.clearTimeout(timer);
        timer = window.setTimeout(() => void load(), 250);
      })
      .subscribe();
    return () => {
      if (timer !== undefined) window.clearTimeout(timer);
      void supabase.removeChannel(channel);
    };
  }, [branchId, load]);

  const scheduleDay = async (date: string) => {
    if (!branchId || busyDate || schedulingWeek || assigningToday || savingScheduleTaskId) return;
    if (date < branchToday) {
      setError("No se generan actividades retroactivas desde el calendario.");
      setNotice(null);
      return;
    }
    setBusyDate(date);
    setError(null);
    setNotice(null);
    try {
      const result = await callFunctionJson<{ created_count: number }>("restaurant_ops", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "schedule_tasks", branch_id: branchId, for_date: date }),
      });
      setNotice(`${result.created_count ?? 0} actividades nuevas para ${formatDay(date)} usando las reglas de esta sucursal. Las ya programadas no se duplicaron.`);
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "No se pudieron programar las actividades.");
    } finally {
      setBusyDate("");
    }
  };

  const scheduleVisibleWeek = async () => {
    if (!branchId || !branch || !weekStart || busyDate || schedulingWeek || assigningToday || savingTaskId || savingPartId || savingScheduleTaskId) return;
    const today = dateInZone(branch.timezone);
    const eligibleDays = days.filter((date) => date >= today);
    if (eligibleDays.length === 0) {
      setNotice("Esta semana ya pasó; no se modificó ninguna fecha.");
      setError(null);
      return;
    }

    setSchedulingWeek(true);
    setError(null);
    setNotice(null);
    let createdCount = 0;
    const failedDays: string[] = [];
    try {
      for (const date of eligibleDays) {
        try {
          const result = await callFunctionJson<{ created_count: number }>("restaurant_ops", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ action: "schedule_tasks", branch_id: branchId, for_date: date }),
          });
          createdCount += result.created_count ?? 0;
        } catch {
          failedDays.push(formatDay(date));
        }
      }
      const pastDayCount = days.length - eligibleDays.length;
      const summary = `${createdCount} actividades confirmadas en ${eligibleDays.length - failedDays.length} días; las fechas pasadas se dejaron intactas.`;
      if (failedDays.length) {
        setError(`${summary} No se pudieron programar: ${failedDays.join(", ")}. Puedes volver a intentar; las ya creadas no se duplicarán.`);
      } else {
        setNotice(`${summary} Las fechas ya materializadas no se duplicaron.${pastDayCount ? ` Se omitieron ${pastDayCount} días pasados.` : ""}`);
      }
      await load();
    } finally {
      setSchedulingWeek(false);
    }
  };

  const rescheduleTask = async (task: Task, scheduledFor: string) => {
    if (!branchId || !branch || !scheduledFor || scheduledFor === task.scheduled_for || busyDate || schedulingWeek || assigningToday || savingTaskId || savingPartId || savingScheduleTaskId) return;
    if (scheduledFor < branchToday) {
      setError("No se pueden mover actividades a una fecha pasada.");
      setNotice(null);
      return;
    }
    setSavingScheduleTaskId(task.id);
    setError(null);
    setNotice(null);
    try {
      await callFunctionJson("restaurant_ops", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "reschedule_task",
          branch_id: branchId,
          task_id: task.id,
          scheduled_for: scheduledFor,
        }),
      });
      setNotice(`Actividad reprogramada para ${formatDay(scheduledFor)}.`);
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "No se pudo cambiar la fecha de la actividad.");
      await load();
    } finally {
      setSavingScheduleTaskId("");
    }
  };

  const assignTask = async (task: Task, employeeId: string) => {
    if (!branchId || savingTaskId || savingPartId || savingScheduleTaskId) return;
    setSavingTaskId(task.id);
    setError(null);
    setNotice(null);
    try {
      await callFunctionJson("restaurant_ops", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "assign_task",
          branch_id: branchId,
          task_id: task.id,
          assigned_to: employeeId || null,
        }),
      });
      setNotice("Responsable de la actividad actualizado.");
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "No se pudo actualizar la asignación.");
      await load();
    } finally {
      setSavingTaskId("");
    }
  };

  const assignTaskPart = async (task: Task, part: TaskPart, employeeId: string) => {
    if (!branchId || savingPartId || savingTaskId || savingScheduleTaskId) return;
    setSavingPartId(part.id);
    setError(null);
    setNotice(null);
    try {
      await callFunctionJson("restaurant_ops", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "assign_task_part",
          branch_id: branchId,
          task_id: task.id,
          part_id: part.id,
          assigned_to: employeeId || null,
        }),
      });
      setNotice("Responsable de la parte actualizado.");
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "No se pudo actualizar la asignación de la parte.");
      await load();
    } finally {
      setSavingPartId("");
    }
  };

  const autoAssignToday = async () => {
    if (!branchId || assigningToday || schedulingWeek || busyDate || savingTaskId || savingPartId || savingScheduleTaskId) return;
    setAssigningToday(true);
    setError(null);
    setNotice(null);
    try {
      const result = await callFunctionJson<{ assigned_count: number; unassigned_count: number; planner: string }>("restaurant_ops", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "auto_assign", branch_id: branchId }),
      });
      const planner = result.planner === "timefold" ? "Timefold" : "el planificador local";
      setNotice(`${result.assigned_count ?? 0} actividades asignadas con ${planner}; ${result.unassigned_count ?? 0} sin persona elegible.`);
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "No se pudieron asignar las actividades.");
    } finally {
      setAssigningToday(false);
    }
  };

  const autoAssignVisibleWeek = async () => {
    if (!branchId || !branch || !weekStart || assigningToday || schedulingWeek || busyDate || savingTaskId || savingPartId || savingScheduleTaskId) return;
    const eligibleDays = days.filter((date) => date >= dateInZone(branch.timezone));
    if (!eligibleDays.length) {
      setNotice("Esta semana ya pasó; no se modificó ninguna asignación.");
      setError(null);
      return;
    }

    setAssigningToday(true);
    setError(null);
    setNotice(null);
    let assignedCount = 0;
    let unassignedCount = 0;
    const planners = new Set<string>();
    const failedDays: string[] = [];
    try {
      for (const date of eligibleDays) {
        try {
          const result = await callFunctionJson<{ assigned_count: number; unassigned_count: number; planner: string }>("restaurant_ops", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ action: "auto_assign", branch_id: branchId, for_date: date }),
          });
          assignedCount += result.assigned_count ?? 0;
          unassignedCount += result.unassigned_count ?? 0;
          planners.add(result.planner === "timefold" ? "Timefold" : "planificador local");
        } catch {
          failedDays.push(formatDay(date));
        }
      }

      const plannerLabel = [...planners].join(" y ") || "sin planificador";
      const summary = `${assignedCount} asignaciones en ${eligibleDays.length - failedDays.length} fechas procesadas, usando ${plannerLabel}; ${unassignedCount} actividades sin persona elegible.`;
      if (failedDays.length) {
        setError(`${summary} No se pudieron procesar: ${failedDays.join(", ")}. Puedes volver a intentar; las asignaciones guardadas no se duplican.`);
      } else {
        setNotice(`${summary} Solo se asignaron actividades ya programadas; las fechas pasadas quedaron intactas.`);
      }
      await load();
    } finally {
      setAssigningToday(false);
    }
  };

  return (
    <main className="mx-auto max-w-[1600px] pb-12">
      <header className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <p className="text-sm font-semibold text-amber-700">Pollo Móvil</p>
          <h1 className="mt-1 text-2xl font-bold tracking-tight">Calendario de actividades</h1>
          <p className="mt-1 text-sm text-slate-500">Actividades reales configuradas para cada sucursal; aquí no se inventan horarios ni tareas.</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <select aria-label="Sucursal" className={inputClass} value={branchId} disabled={Boolean(savingScheduleTaskId)} onChange={(event) => { rememberRestaurantBranchId(event.target.value); setBranchId(event.target.value); }}>
            {branches.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}
          </select>
          <Link className={secondaryClass} href="/restaurant"><ArrowLeft size={16} /> Operación</Link>
          {canManage && <Link className={secondaryClass} href="/restaurant/configuration"><Settings2 size={16} /> Configuración</Link>}
          <button aria-label="Actualizar calendario" className={secondaryClass} disabled={loading || Boolean(savingScheduleTaskId)} onClick={() => void load()}><RefreshCw size={16} /> Actualizar</button>
        </div>
      </header>

      {(error || notice) && <div role="status" className={`mt-5 rounded-xl border px-4 py-3 text-sm ${error ? "border-rose-200 bg-rose-50 text-rose-700" : "border-emerald-200 bg-emerald-50 text-emerald-800"}`}>{error ?? notice}</div>}

      <section className="mt-6 flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-stone-200 bg-white p-4 dark:border-slate-800 dark:bg-slate-900">
        <div className="flex items-center gap-3"><CalendarRange className="text-amber-700" size={20} /><div><h2 className="font-semibold">{weekStart ? `${formatDay(weekStart)} – ${formatDay(addDays(weekStart, 6))}` : "Semana"}</h2><p className="text-sm text-slate-500">{branch?.name ?? "Selecciona una sucursal"} · {branch?.timezone ?? ""}</p></div></div>
      <div className="flex flex-wrap gap-2">
          {canManage && <button className={secondaryClass} disabled={schedulingWeek || Boolean(busyDate) || assigningToday || loading || !branch || Boolean(savingScheduleTaskId)} onClick={() => void scheduleVisibleWeek()}><CalendarClock size={16} />{schedulingWeek ? "Programando semana…" : "Programar semana visible"}</button>}
          {canManage && branch && days.includes(dateInZone(branch.timezone)) && <button className={secondaryClass} disabled={assigningToday || schedulingWeek || Boolean(busyDate) || Boolean(savingTaskId) || Boolean(savingPartId) || Boolean(savingScheduleTaskId)} onClick={() => void autoAssignToday()}><CalendarClock size={16} />{assigningToday ? "Asignando…" : "Asignar elegibles hoy"}</button>}
          {canManage && branch && <button className={secondaryClass} disabled={assigningToday || schedulingWeek || Boolean(busyDate) || Boolean(savingTaskId) || Boolean(savingPartId) || Boolean(savingScheduleTaskId) || days.every((date) => date < branchToday)} onClick={() => void autoAssignVisibleWeek()}><CalendarClock size={16} />{assigningToday ? "Asignando semana…" : "Asignar elegibles de la semana"}</button>}
          <button className={secondaryClass} disabled={!weekStart || loading || Boolean(savingScheduleTaskId)} onClick={() => setWeekStart((current) => current ? addDays(current, -7) : current)}><ArrowLeft size={16} /> Semana anterior</button>
          <button className={secondaryClass} disabled={!branch || Boolean(savingScheduleTaskId)} onClick={() => branch && setWeekStart(startOfWeek(dateInZone(branch.timezone)))}>Esta semana</button>
          <button className={secondaryClass} disabled={!weekStart || loading || Boolean(savingScheduleTaskId)} onClick={() => setWeekStart((current) => current ? addDays(current, 7) : current)}>Semana siguiente <ArrowRight size={16} /></button>
        </div>
      </section>

      {loading ? <p className="mt-8 text-sm text-slate-500">Cargando calendario…</p> : !branch ? (
        <section className={`${panelClass} mt-6`}><h2 className="font-semibold">Todavía no hay sucursales</h2><p className="mt-2 text-sm text-slate-500">Crea una sucursal y configura sus actividades para comenzar.</p></section>
      ) : (
        <section aria-label="Semana de actividades" className="mt-6 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-7">
          {days.map((date) => {
            const dayTasks = tasks.filter((task) => task.scheduled_for === date);
            const isPast = date < branchToday;
            return (
              <article key={date} className={`${panelClass} min-h-56`}>
                <div className="flex items-start justify-between gap-2">
                  <div><h3 className="font-semibold capitalize">{formatDay(date)}</h3><p className="mt-1 text-xs text-slate-500">{dayTasks.length} actividades</p></div>
                  {canManage && <button className="rounded-lg border border-stone-200 p-2 text-amber-800 hover:bg-amber-50 disabled:opacity-50 dark:border-slate-700 dark:hover:bg-slate-800" title={isPast ? "No se generan actividades retroactivas" : `Programar actividades para ${date}`} aria-label={`Programar actividades para ${formatDay(date)}`} disabled={isPast || Boolean(busyDate) || schedulingWeek || assigningToday || Boolean(savingScheduleTaskId)} onClick={() => void scheduleDay(date)}><CalendarClock size={16} /></button>}
                </div>
                {canManage && isPast && <p className="mt-2 text-[11px] text-slate-500">Fecha pasada; no se generan actividades retroactivas.</p>}
                {busyDate === date && <p className="mt-3 text-xs text-slate-500">Programando desde las reglas configuradas…</p>}
                {dayTasks.length === 0 ? (
                  <p className="mt-4 rounded-lg bg-stone-50 px-3 py-3 text-xs text-slate-500 dark:bg-slate-800">Sin actividades programadas.</p>
                ) : (
                  <ul className="mt-3 space-y-2">
                    {dayTasks.map((task) => (
                      <li key={task.id} id={`restaurant-task-${task.id}`} className={`rounded-xl border border-stone-100 bg-stone-50 p-3 dark:border-slate-700 dark:bg-slate-800 ${highlightTaskId === task.id ? "ring-2 ring-amber-500 ring-offset-2 dark:ring-offset-slate-950" : ""}`}>
                        <p className="text-sm font-medium">{task.name}</p>
                        <p className="mt-1 text-xs text-slate-500">{[task.area_name, task.assignee_name ?? "Sin responsable", task.estimated_minutes ? `${task.estimated_minutes} min` : null].filter(Boolean).join(" · ")}</p>
                        <span className={`mt-2 inline-flex rounded-full px-2 py-1 text-[11px] font-semibold ${task.status === "completed" ? "bg-emerald-100 text-emerald-800" : task.status === "in_progress" ? "bg-sky-100 text-sky-800" : "bg-amber-100 text-amber-900"}`}>{statusLabel(task.status)}</span>
                        {task.configuration_pending && <p className="mt-2 text-xs font-medium text-amber-800 dark:text-amber-300">Falta configurar puestos, zonas o criterios de asignación; se mantiene sin asignar.</p>}
                        {canManage && task.status === "pending" && task.task_source === "scheduled" && (() => {
                          const hasAssignedParts = (task.parts ?? []).some((part) => Boolean(part.assigned_to));
                          if (task.assigned_to || hasAssignedParts) {
                            return <p className="mt-3 text-xs text-slate-500">Quita las asignaciones antes de cambiar la fecha.</p>;
                          }
                          return <label className="mt-3 block text-xs font-semibold text-slate-600 dark:text-slate-300">
                            Cambiar fecha
                            <input
                              aria-label={`Cambiar fecha de ${task.name}`}
                              className={`${inputClass} mt-1 w-full`}
                              type="date"
                              min={branchToday}
                              value={task.scheduled_for}
                              disabled={Boolean(savingScheduleTaskId) || Boolean(busyDate) || schedulingWeek || assigningToday || Boolean(savingTaskId) || Boolean(savingPartId)}
                              onChange={(event) => void rescheduleTask(task, event.target.value)}
                            />
                          </label>;
                        })()}
                        {canManage && task.status === "pending" && !task.is_divisible && !task.configuration_pending && (
                          <label className="mt-3 block text-xs font-semibold text-slate-600 dark:text-slate-300">
                            Responsable
                            <select aria-label={`Responsable de ${task.name}`} className={`${inputClass} mt-1 w-full`} value={task.assigned_to ?? ""} disabled={savingTaskId === task.id || Boolean(savingPartId) || assigningToday || Boolean(savingScheduleTaskId)} onChange={(event) => void assignTask(task, event.target.value)}>
                              <option value="">Sin responsable</option>
                              {task.assigned_to && !assignableMembers.some((member) => member.id === task.assigned_to) && <option value={task.assigned_to} disabled>{task.assignee_name ?? "Responsable actual"} · ya no activo</option>}
                              {assignableMembers.map((member) => <option key={member.id} value={member.id}>{member.full_name ?? member.id}</option>)}
                            </select>
                          </label>
                        )}
                        {(task.parts ?? []).length > 0 && (
                          <ul className="mt-3 space-y-2 border-t border-stone-200 pt-3 dark:border-slate-700">
                            {(task.parts ?? []).map((part) => {
                              const currentMemberMissing = Boolean(part.assigned_to) && !assignableMembers.some((member) => member.id === part.assigned_to);
                              return (
                                <li key={part.id} className="rounded-lg bg-white p-2 text-xs dark:bg-slate-900">
                                  <p className="font-medium">{[part.zone_name ?? "Parte", part.assignee_name ?? "Sin responsable", `${part.estimated_minutes} min`, statusLabel(part.status)].join(" · ")}</p>
                                  {canManage && (task.status === "pending" || task.status === "in_progress") && part.status === "pending" && !task.configuration_pending && (
                                    <label className="mt-2 block font-semibold text-slate-600 dark:text-slate-300">
                                      Responsable de {part.zone_name ?? "la parte"}
                                      <select aria-label={`Responsable de ${part.zone_name ?? "la parte"}`} className={`${inputClass} mt-1 w-full`} value={part.assigned_to ?? ""} disabled={savingPartId === part.id || Boolean(savingTaskId) || assigningToday || Boolean(savingScheduleTaskId)} onChange={(event) => void assignTaskPart(task, part, event.target.value)}>
                                        <option value="">Sin responsable</option>
                                        {currentMemberMissing && <option value={part.assigned_to ?? ""} disabled>{part.assignee_name ?? "Responsable actual"} · ya no activo</option>}
                                        {assignableMembers.map((member) => <option key={member.id} value={member.id}>{member.full_name ?? member.id}</option>)}
                                      </select>
                                    </label>
                                  )}
                                </li>
                              );
                            })}
                          </ul>
                        )}
                      </li>
                    ))}
                  </ul>
                )}
              </article>
            );
          })}
        </section>
      )}
    </main>
  );
}
