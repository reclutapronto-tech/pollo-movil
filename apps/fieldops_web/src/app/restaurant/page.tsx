"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { AlertTriangle, ArrowRightLeft, Bell, CalendarClock, CheckCircle2, CircleDashed, ClipboardCheck, ClipboardList, RefreshCw, Settings2, Trash2 } from "lucide-react";
import { callFunctionJson } from "@/lib/function-client";
import { mexicoTimeZones } from "@/lib/mexico-timezones";
import { preferredRestaurantBranchId, rememberRestaurantBranchId } from "@/lib/restaurant-branch-selection";
import { useCurrentUser } from "@/lib/use-role";
import { getSupabase } from "@/lib/supabase";

type Row = Record<string, unknown>;
type Branch = { id: string; name: string; timezone: string; access_role: string; enable_time_clock?: boolean };
type Task = Row & { id: string; name: string; status: string; assigned_to: string | null; assignee_name?: string | null; area_name?: string | null; estimated_minutes?: number; configuration_pending?: boolean; latest_pause_note?: string | null; parts?: Row[] };
type Dashboard = { branch?: Partial<Branch>; tasks: Task[]; incidents: Row[]; waste_bins: Row[]; shifts: Row[]; areas?: Row[]; members?: Row[]; active_time_sessions?: Row[]; today_time_sessions?: Row[]; my_time_sessions?: Row[]; handoffs?: Row[]; area_inspection_templates?: Row[]; area_inspections?: Row[]; handoff: { completed_tasks: Row[]; outstanding_tasks: Row[]; open_incidents: Row[] }; local_date: string; assignable_unassigned_count?: number; unread_notification_count?: number };
type AttendanceHistory = { date: string; timezone: string; can_manage: boolean; sessions: Row[] };

const statusLabels: Record<string, string> = {
  pending: "Pendiente", in_progress: "En curso", paused: "Pausada", blocked: "Bloqueada", completed: "Terminada",
};

async function sendAction<T>(body: Record<string, unknown>) {
  return callFunctionJson<T>("restaurant_ops", {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
  });
}

export default function RestaurantOperationsPage() {
  const currentUser = useCurrentUser();
  const [branches, setBranches] = useState<Branch[]>([]);
  const [branchId, setBranchId] = useState("");
  const [dashboard, setDashboard] = useState<Dashboard | null>(null);
  const [attendanceDateSelection, setAttendanceDateSelection] = useState<{ branchId: string; date: string } | null>(null);
  const [attendanceHistory, setAttendanceHistory] = useState<AttendanceHistory | null>(null);
  const [attendanceHistoryLoading, setAttendanceHistoryLoading] = useState(true);
  const [attendanceHistoryError, setAttendanceHistoryError] = useState<string | null>(null);
  const [attendanceRevision, setAttendanceRevision] = useState(0);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [newBranchName, setNewBranchName] = useState("");
  const [newBranchTimezone, setNewBranchTimezone] = useState("");
  const [handoffNote, setHandoffNote] = useState("");
  const [handoffRecipient, setHandoffRecipient] = useState("");
  const [handoffEventId, setHandoffEventId] = useState("");
  const [incidentDescription, setIncidentDescription] = useState("");
  const [incidentArea, setIncidentArea] = useState("");
  const [incidentUrgency, setIncidentUrgency] = useState("normal");
  const [incidentBlocking, setIncidentBlocking] = useState(false);
  const [incidentEventId, setIncidentEventId] = useState("");

  useEffect(() => {
    setHandoffNote("");
    setHandoffRecipient("");
    setHandoffEventId("");
    setIncidentDescription("");
    setIncidentArea("");
    setIncidentUrgency("normal");
    setIncidentBlocking(false);
    setIncidentEventId("");
  }, [branchId]);

  const selectedBranch = branches.find((item) => item.id === branchId) ?? null;
  const canManage = selectedBranch ? ["admin", "supervisor"].includes(selectedBranch.access_role) : false;
  const dashboardBranch = dashboard?.branch?.id === branchId ? dashboard.branch : undefined;
  const clockEnabled = dashboardBranch?.enable_time_clock ?? selectedBranch?.enable_time_clock ?? false;
  const attendanceDate = attendanceDateSelection?.branchId === branchId
    ? attendanceDateSelection.date
    : dashboard?.branch?.id === branchId ? dashboard.local_date : "";

  const load = useCallback(async (id = branchId) => {
    if (!id) return;
    setLoading(true);
    setError(null);
    try {
      const data = await callFunctionJson<Dashboard>("restaurant_ops", { query: { action: "dashboard", branch_id: id } });
      setDashboard(data);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "No se pudo cargar el turno.");
    } finally {
      setLoading(false);
    }
  }, [branchId]);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    callFunctionJson<{ branches: Branch[] }>("restaurant_ops", { query: { action: "branches" } })
      .then(({ branches: rows }) => {
        if (cancelled) return;
        const safeRows = rows ?? [];
        setBranches(safeRows);
        const preferredId = preferredRestaurantBranchId(safeRows);
        setBranchId((current) => current && safeRows.some((item) => item.id === current) ? current : preferredId);
        if (!safeRows.length) setLoading(false);
      })
      .catch((cause: unknown) => {
        if (!cancelled) {
          setError(cause instanceof Error ? cause.message : "No se pudieron cargar las sucursales.");
          setLoading(false);
        }
      });
    return () => { cancelled = true; };
  }, []);

  useEffect(() => {
    if (branchId) void load(branchId);
  }, [branchId, load]);

  useEffect(() => {
    if (!branchId || !clockEnabled || !attendanceDate) {
      setAttendanceHistory(null);
      setAttendanceHistoryLoading(false);
      return;
    }
    let cancelled = false;
    setAttendanceHistory(null);
    setAttendanceHistoryLoading(true);
    setAttendanceHistoryError(null);
    callFunctionJson<AttendanceHistory>("restaurant_ops", {
      query: { action: "attendance_history", branch_id: branchId, for_date: attendanceDate },
    })
      .then((result) => {
        if (!cancelled) setAttendanceHistory(result);
      })
      .catch((cause: unknown) => {
        if (!cancelled) {
          setAttendanceHistoryError(cause instanceof Error ? cause.message : "No se pudo cargar el historial.");
        }
      })
      .finally(() => {
        if (!cancelled) setAttendanceHistoryLoading(false);
      });
    return () => { cancelled = true; };
  }, [attendanceDate, attendanceRevision, branchId, clockEnabled]);

  useEffect(() => {
    if (!branchId) return;
    const supabase = getSupabase();
    let refreshTimer: number | undefined;
    const refresh = () => {
      if (refreshTimer !== undefined) window.clearTimeout(refreshTimer);
      refreshTimer = window.setTimeout(() => {
        void load(branchId);
        setAttendanceRevision((revision) => revision + 1);
      }, 200);
    };
    const channel = supabase
      .channel(`pollo-operations-${branchId}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_branches", filter: `id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_time_sessions", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_tasks", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_task_parts", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_incidents", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_absences", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_waste_inspections", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_waste_bins", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_shifts", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_memberships", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_shift_handoffs", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_inspections", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_inspection_templates", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_notifications", filter: `branch_id=eq.${branchId}` }, refresh)
      .subscribe();
    return () => {
      if (refreshTimer !== undefined) window.clearTimeout(refreshTimer);
      void supabase.removeChannel(channel);
    };
  }, [branchId, load]);

  const counts = useMemo(() => {
    const tasks = dashboard?.tasks ?? [];
    return {
      total: tasks.length,
      complete: tasks.filter((task) => task.status === "completed").length,
      open: tasks.filter((task) => task.status !== "completed").length,
      incidents: dashboard?.incidents.length ?? 0,
      dueBins: dashboard?.waste_bins.filter((bin) => bin.inspection_due === true).length ?? 0,
    };
  }, [dashboard]);

  const run = async (action: string, extra: Record<string, unknown> = {}) => {
    if (!branchId || busy) return false;
    setBusy(true);
    setError(null);
    setNotice(null);
    try {
      const result = await sendAction<Record<string, unknown>>({ action, branch_id: branchId, ...extra });
      if (action === "auto_assign") {
        const planner = result.planner === "timefold" ? "Timefold" : "planificador local";
        setNotice(`Asignadas: ${result.assigned_count ?? 0} con ${planner}. Pendientes sin candidato elegible: ${result.unassigned_count ?? 0}.`);
      } else if (action === "schedule_tasks") {
        setNotice(`Se crearon ${result.created_count ?? 0} tareas programadas nuevas. Las ya existentes no se duplicaron.`);
      } else if (action === "deliver_handoff") {
        setNotice("El relevo quedó guardado con el estado real de actividades e incidencias.");
        setHandoffNote("");
        setHandoffRecipient("");
      } else if (action === "acknowledge_handoff") {
        setNotice("Recepción del relevo confirmada.");
      } else if (action === "create_incident") {
        setNotice("Incidencia registrada para el equipo de la sucursal.");
      } else {
        setNotice("Cambio guardado.");
      }
      await load(branchId);
      return true;
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "No se pudo guardar el cambio.");
      return false;
    } finally {
      setBusy(false);
    }
  };

  const createBranch = async () => {
    if (newBranchName.trim().length < 2 || !newBranchTimezone || busy) return;
    setBusy(true);
    setError(null);
    try {
      const created = await sendAction<{ branch_id?: string }>({ action: "create_branch", name: newBranchName.trim(), timezone: newBranchTimezone });
      const { branches: rows } = await callFunctionJson<{ branches: Branch[] }>("restaurant_ops", { query: { action: "branches" } });
      setBranches(rows);
      const nextBranchId = created.branch_id && rows.some((branch) => branch.id === created.branch_id)
        ? created.branch_id
        : rows[0]?.id ?? "";
      rememberRestaurantBranchId(nextBranchId);
      setBranchId(nextBranchId);
      setNewBranchName("");
      setNotice("Sucursal creada sin áreas, puestos, botes, empleados ni horarios inventados. Configura la operación real de esta sucursal para comenzar.");
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "No se pudo crear la sucursal.");
    } finally {
      setBusy(false);
    }
  };

  if (currentUser.loading || (loading && !branches.length)) return <PageMessage>Conectando con la operación…</PageMessage>;
  if (error && !branches.length) return <PageMessage>{error}</PageMessage>;

  if (!branches.length) {
    const mayCreate = ["owner", "admin"].includes(currentUser.role ?? "");
    return (
      <main className="mx-auto max-w-3xl py-10">
        <Header title="Pollo Móvil" subtitle="Operación independiente por sucursal" />
        <section className="mt-8 rounded-2xl border border-stone-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
          <h2 className="text-lg font-semibold">Todavía no tienes una sucursal</h2>
          <p className="mt-2 text-sm text-slate-500">{mayCreate ? "Crea la sucursal piloto. No se cargarán horarios ni actividades inventadas." : "Pide a un administrador que cree una sucursal y te agregue al equipo."}</p>
          {mayCreate && <div className="mt-5 grid gap-3 sm:grid-cols-[minmax(180px,1fr)_minmax(240px,1fr)_auto]"><input className={inputClass} value={newBranchName} onChange={(event) => setNewBranchName(event.target.value)} maxLength={120} placeholder="Nombre de sucursal" /><select className={inputClass} aria-label="Zona horaria de la sucursal" value={newBranchTimezone} onChange={(event) => setNewBranchTimezone(event.target.value)}><option value="">Selecciona zona horaria</option>{mexicoTimeZones.map((timezone) => <option key={timezone.value} value={timezone.value}>{timezone.label}</option>)}</select><button className={primaryClass} disabled={busy || newBranchName.trim().length < 2 || !newBranchTimezone} onClick={() => void createBranch()}>{busy ? "Creando…" : "Crear sucursal"}</button></div>}
          {error && <p className="mt-3 text-sm text-rose-600">{error}</p>}
        </section>
      </main>
    );
  }

  const tasks = dashboard?.tasks ?? [];
  const incidents = dashboard?.incidents ?? [];
  return (
    <main className="mx-auto max-w-7xl pb-12">
      <Header title="Pollo Móvil" subtitle="Coordinación del turno; checador y GPS se activan por configuración">
        <select aria-label="Sucursal" className={inputClass} disabled={busy} value={branchId} onChange={(event) => { rememberRestaurantBranchId(event.target.value); setBranchId(event.target.value); }}>
          {branches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name}</option>)}
        </select>
        <Link className={secondaryClass} href="/restaurant/calendar"><CalendarClock size={16} /> Calendario</Link>
        <Link className={secondaryClass} href="/restaurant/inspections"><ClipboardList size={16} /> Inspecciones</Link>
        <Link className={secondaryClass} href="/restaurant/notifications"><Bell size={16} /> Notificaciones{(dashboard?.unread_notification_count ?? 0) > 0 && <span className="rounded-full bg-rose-600 px-1.5 py-0.5 text-[10px] font-bold leading-none text-white">{(dashboard?.unread_notification_count ?? 0) > 99 ? "99+" : dashboard?.unread_notification_count}</span>}</Link>
        <button aria-label="Actualizar turno" className={secondaryClass} onClick={() => void load()}><RefreshCw size={16} /> Actualizar</button>
        {canManage && <Link className={secondaryClass} href="/restaurant/configuration"><Settings2 size={16} /> Configuración</Link>}
      </Header>

      {(error || notice) && <div role="status" className={`mt-5 rounded-xl border px-4 py-3 text-sm ${error ? "border-rose-200 bg-rose-50 text-rose-700" : "border-emerald-200 bg-emerald-50 text-emerald-800"}`}>{error ?? notice}</div>}
      <div className="mt-6 flex flex-wrap items-center justify-between gap-3">
        <div><p className="text-sm font-medium text-slate-500">{selectedBranch?.name ?? "Sucursal"}</p><h2 className="text-2xl font-bold tracking-tight">Turno de hoy</h2><p className="mt-1 text-sm text-slate-500">Fecha local: {dashboard?.local_date ?? "—"} · Zona: {selectedBranch?.timezone ?? "—"}</p></div>
        {canManage && <div className="flex flex-wrap gap-2"><button className={secondaryClass} disabled={busy} onClick={() => void run("schedule_tasks")}><CalendarClock size={16} /> Programar hoy</button><button className={primaryClass} disabled={busy} onClick={() => void run("auto_assign")}><CheckCircle2 size={16} /> Asignar elegibles</button></div>}
      </div>

      <section aria-label="Resumen de turno" className="mt-6 grid gap-3 sm:grid-cols-2 xl:grid-cols-6">
        <Metric label="Actividades abiertas" value={counts.open} icon={<CircleDashed size={18} />} />
        <Metric label="Terminadas" value={counts.complete} icon={<CheckCircle2 size={18} />} />
        <Metric label="Incidencias abiertas" value={counts.incidents} icon={<AlertTriangle size={18} />} />
        <Metric label="Botes por revisar" value={counts.dueBins} icon={<Trash2 size={18} />} />
        {canManage && <Metric label="Asignaciones sin responsable" value={dashboard?.assignable_unassigned_count ?? 0} icon={<ClipboardList size={18} />} />}
        {canManage && clockEnabled && <Metric label="Con checador activo" value={dashboard?.active_time_sessions?.length ?? 0} icon={<CalendarClock size={18} />} />}
      </section>

      <div className="mt-7 grid gap-6 xl:grid-cols-[minmax(0,1.4fr)_minmax(320px,0.8fr)]">
        <section className={panelClass}>
          <div className="flex items-center justify-between gap-3"><div><h2 className="text-lg font-semibold">Actividades</h2><p className="text-sm text-slate-500">{counts.total} registradas para la fecha local</p></div>{canManage && <Link href="/restaurant/configuration" className="text-sm font-semibold text-amber-700 hover:underline">Editar calendario</Link>}</div>
          {loading ? <p className="mt-6 text-sm text-slate-500">Cargando el turno…</p> : tasks.length === 0 ? <EmptyState text="Sin actividades programadas. Configura el calendario real de la sucursal para empezar." /> : <div className="mt-4 divide-y divide-stone-100 dark:divide-slate-800">{tasks.map((task) => <TaskRow key={task.id} task={task} />)}</div>}
        </section>
        <div className="space-y-6">
          <section className={panelClass}>
            <div className="flex items-center gap-2"><Trash2 size={18} /><h2 className="text-lg font-semibold">Inspección de botes</h2></div>
            <p className="mt-1 text-sm text-slate-500">Declaraciones recientes, no mediciones automáticas.</p>
            <div className="mt-4 space-y-3">{(dashboard?.waste_bins ?? []).map((bin) => <div key={String(bin.id)} className="flex items-center justify-between gap-3 rounded-lg bg-stone-50 px-3 py-2.5 dark:bg-slate-800"><span className="text-sm font-medium">{String(bin.name ?? "Bote")}</span><span className="text-right text-xs text-slate-500">{bin.last_declared_state === "full" ? "Lleno" : bin.last_declared_state === "half" ? "A medias" : bin.last_declared_state === "low" ? "Vacío/poco" : "Sin declaración"}{bin.inspection_due === true ? " · revisar" : ""}</span></div>)}</div>
            <p className="mt-4 text-xs text-slate-500">El registro de estado se hace desde la app móvil para completar los tres botes en una sola inspección.</p>
          </section>
          <section className={panelClass}>
            <div className="flex items-center justify-between gap-2"><div className="flex items-center gap-2"><ClipboardCheck size={18} /><h2 className="text-lg font-semibold">Inspecciones de áreas</h2></div>{canManage && <Link href="/restaurant/configuration" className="text-sm font-semibold text-amber-700 hover:underline">Configurar</Link>}</div>
            <p className="mt-1 text-sm text-slate-500">Listas y criterios definidos por la sucursal.</p>
            {!dashboard?.area_inspection_templates?.length ? <EmptyState text="No hay listas de inspección configuradas." /> : <div className="mt-3 space-y-2">{dashboard.area_inspection_templates.map((template) => <div key={String(template.id)} className="rounded-lg bg-stone-50 px-3 py-2.5 dark:bg-slate-800"><p className="text-sm font-medium">{String(template.name)}</p><p className="mt-1 text-xs text-slate-500">{String(template.area_name ?? "Sin área")} · {(template.items as Row[] | undefined)?.length ?? 0} criterios{template.inspection_due === true ? " · Revisión pendiente" : ""}</p></div>)}</div>}
            {!!dashboard?.area_inspections?.length && <div className="mt-4 border-t border-stone-100 pt-3 dark:border-slate-800"><p className="text-xs font-semibold uppercase tracking-wide text-slate-500">Registros recientes</p><div className="mt-2 space-y-3">{dashboard.area_inspections.slice(0, 5).map((inspection) => {
              const findings = ((inspection.results as Row[] | undefined) ?? []).filter((result) => result.result_state === "needs_attention");
              return <div key={String(inspection.id)} className="rounded-lg bg-stone-50 px-3 py-2.5 text-sm dark:bg-slate-800"><div className="flex items-start justify-between gap-3"><span>{String(inspection.template_name ?? "Inspección")} · {String(inspection.inspector_name ?? "Equipo")}</span><span className={Number(inspection.needs_attention_count) > 0 ? "text-amber-700" : "text-emerald-700"}>{Number(inspection.needs_attention_count) > 0 ? `${String(inspection.needs_attention_count)} requieren atención` : "Sin alertas"}</span></div>{findings.slice(0, 3).map((item) => <p key={String(item.item_id)} className="mt-1 text-xs text-slate-500">• {String(item.item_label)}{item.note ? `: ${String(item.note)}` : ""}</p>)}</div>;
            })}</div></div>}
          </section>
          {clockEnabled && <section className={panelClass}>
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div className="flex items-center gap-2"><CalendarClock size={18} /><h2 className="text-lg font-semibold">Historial de checadas</h2></div>
              <span className="text-xs text-slate-500">{attendanceHistory?.sessions.length ?? 0} registros</span>
            </div>
            <label className="mt-3 flex max-w-xs flex-col gap-1 text-xs font-medium text-slate-600 dark:text-slate-300">
              Fecha de asistencia
              <input
                aria-label="Fecha de asistencia"
                className={inputClass}
                type="date"
                value={attendanceDate}
                max={dashboard?.branch?.id === branchId ? dashboard.local_date : undefined}
                onChange={(event) => setAttendanceDateSelection({ branchId, date: event.target.value })}
              />
            </label>
            <p className="mt-2 text-xs text-slate-500">Solo se muestran horarios de entrada y salida; no se incluyen ubicaciones.</p>
            {attendanceHistoryError && <div role="alert" className="mt-4 rounded-lg border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-700 dark:border-rose-900 dark:bg-rose-950 dark:text-rose-200">
              <p>{attendanceHistoryError}</p>
              <button className="mt-2 font-semibold underline" onClick={() => setAttendanceRevision((revision) => revision + 1)}>Reintentar</button>
            </div>}
            {attendanceHistoryLoading ? <p className="mt-4 text-sm text-slate-500">Cargando historial…</p>
              : !attendanceHistoryError && !(attendanceHistory?.sessions.length) ? <EmptyState text="No hay checadas para esta fecha." />
              : !attendanceHistoryError && <div className="mt-3 divide-y divide-stone-100 dark:divide-slate-800">{(attendanceHistory?.sessions ?? []).map((session) => {
                const employeeName = canManage ? String(session.employee_name ?? "Integrante del equipo") : null;
                const clockInDate = String(session.clock_in_local_date ?? "");
                const clockIn = String(session.clock_in_local_time ?? "Hora no disponible");
                const clockOut = typeof session.clock_out_local_time === "string" ? session.clock_out_local_time : null;
                const entryLabel = clockInDate && clockInDate !== attendanceDate ? `Entrada ${clockInDate}` : "Entrada";
                return <div key={String(session.id)} className="flex items-center justify-between gap-3 py-3"><div><p className="text-sm font-medium">{employeeName ?? entryLabel}</p><p className="mt-1 text-xs text-slate-500">{employeeName ? `${entryLabel} ` : ""}{clockIn} · {clockOut ? `salida ${clockOut}` : "sin salida"}</p></div><span className={`rounded-full px-2 py-1 text-xs font-semibold ${clockOut ? "bg-stone-100 text-slate-600 dark:bg-slate-800 dark:text-slate-300" : "bg-emerald-50 text-emerald-700"}`}>{clockOut ? "Cerrada" : "Activa"}</span></div>;
              })}</div>}
          </section>}
          <section className={panelClass}>
            <div className="flex items-center gap-2"><AlertTriangle size={18} /><h2 className="text-lg font-semibold">Incidencias</h2></div>
            <form className="mt-4 space-y-3" onSubmit={async (event) => {
              event.preventDefault();
              if (incidentDescription.trim().length < 3) return;
              const clientEventId = incidentEventId || crypto.randomUUID();
              setIncidentEventId(clientEventId);
              const saved = await run("create_incident", {
                client_event_id: clientEventId,
                description: incidentDescription.trim(),
                area_id: incidentArea || null,
                urgency: incidentUrgency,
                is_blocking: incidentBlocking,
              });
              if (saved) {
                setIncidentDescription(""); setIncidentArea(""); setIncidentUrgency("normal");
                setIncidentBlocking(false); setIncidentEventId("");
              }
            }}>
              <textarea aria-label="Descripción de incidencia" className={`${inputClass} min-h-20 w-full py-3`} disabled={busy} maxLength={1000} minLength={3} required value={incidentDescription} onChange={(event) => { setIncidentDescription(event.target.value); setIncidentEventId(""); }} placeholder="Describe una incidencia operativa real" />
              <div className="grid gap-2 sm:grid-cols-2">
                <select aria-label="Área de incidencia" className={`${inputClass} w-full`} disabled={busy} value={incidentArea} onChange={(event) => { setIncidentArea(event.target.value); setIncidentEventId(""); }}><option value="">Área sin especificar</option>{(dashboard?.areas ?? []).map((area) => <option key={String(area.id)} value={String(area.id)}>{String(area.name)}</option>)}</select>
                <select aria-label="Urgencia de incidencia" className={`${inputClass} w-full`} disabled={busy} value={incidentUrgency} onChange={(event) => { setIncidentUrgency(event.target.value); setIncidentEventId(""); }}><option value="low">Baja</option><option value="normal">Normal</option><option value="high">Alta</option><option value="urgent">Urgente</option></select>
              </div>
              <label className="flex items-center gap-2 text-xs text-slate-600 dark:text-slate-300"><input type="checkbox" disabled={busy} checked={incidentBlocking} onChange={(event) => { setIncidentBlocking(event.target.checked); setIncidentEventId(""); }} />Bloquea la operación hasta su atención</label>
              <button className={secondaryClass} disabled={busy || incidentDescription.trim().length < 3}>Registrar incidencia</button>
            </form>
            {!incidents.length ? <EmptyState text="No hay incidencias abiertas." /> : <div className="mt-4 space-y-3">{incidents.map((item) => <IncidentRow key={String(item.id)} item={item} members={dashboard?.members ?? []} canManage={canManage} onUpdate={(status, assignedTo, isBlocking) => void run("update_incident", { incident_id: item.id, status, assigned_to: assignedTo || null, is_blocking: isBlocking })} busy={busy} />)}</div>}
          </section>
          <section className={panelClass}>
            <div className="flex items-center gap-2"><ArrowRightLeft size={18} /><h2 className="text-lg font-semibold">Resumen de relevo</h2></div>
            <p className="mt-3 text-sm text-slate-600 dark:text-slate-300">{dashboard?.handoff.completed_tasks.length ?? 0} terminadas · {dashboard?.handoff.outstanding_tasks.length ?? 0} pendientes o pausadas · {dashboard?.handoff.open_incidents.length ?? 0} incidencias abiertas</p>
            <p className="mt-2 text-xs text-slate-500">Se arma a partir de la actividad real; nadie debe reescribir el reporte.</p>
          </section>
          <section className={panelClass}>
            <div className="flex items-center gap-2"><ArrowRightLeft size={18} /><h2 className="text-lg font-semibold">Entrega y recepción</h2></div>
            <p className="mt-2 text-sm text-slate-500">Guarda una fotografía de las actividades pendientes e incidencias abiertas al entregar.</p>
            <div className="mt-4 space-y-3">
              <select aria-label="Quién recibe el relevo" className={`${inputClass} w-full`} disabled={busy} value={handoffRecipient} onChange={(event) => { setHandoffRecipient(event.target.value); setHandoffEventId(""); }}>
                <option value="">Sin destinatario específico</option>
                {(dashboard?.members ?? []).filter((member) => member.user_id !== currentUser.userId).map((member) => <option key={String(member.user_id)} value={String(member.user_id)}>{String(member.user_name ?? "Miembro de sucursal")}</option>)}
              </select>
              <textarea aria-label="Nota de entrega" className={`${inputClass} min-h-24 w-full py-3`} disabled={busy} maxLength={1000} value={handoffNote} onChange={(event) => { setHandoffNote(event.target.value); setHandoffEventId(""); }} placeholder="Nota operativa opcional" />
              <button className={primaryClass} disabled={busy} onClick={async () => {
                const clientEventId = handoffEventId || crypto.randomUUID();
                setHandoffEventId(clientEventId);
                const saved = await run("deliver_handoff", { client_event_id: clientEventId, recipient_id: handoffRecipient || null, handoff_note: handoffNote });
                if (saved) setHandoffEventId("");
              }}>Entregar relevo</button>
              <p className="text-xs text-slate-500">Se requiere conexión para guardar el corte del turno con datos actualizados.</p>
            </div>
            <div className="mt-5 space-y-3">
              {(dashboard?.handoffs ?? []).length === 0 ? <EmptyState text="Aún no hay relevos registrados." /> : (dashboard?.handoffs ?? []).map((item) => {
                const snapshot = item.snapshot as { task_items?: Row[]; incident_items?: Row[] } | null;
                const taskItems = snapshot?.task_items ?? [];
                const incidentItems = snapshot?.incident_items ?? [];
                const acknowledged = Boolean(item.acknowledged_at);
                const canAcknowledge = !acknowledged && item.created_by !== currentUser.userId && (!item.recipient_id || item.recipient_id === currentUser.userId);
                return <article key={String(item.id)} className="rounded-xl border border-stone-200 p-3 dark:border-slate-700">
                  <div className="flex items-start justify-between gap-3"><div><h3 className="font-medium">{String(item.creator_name ?? "Equipo")} · {String(item.shift_date ?? "")}</h3><p className="mt-1 text-xs text-slate-500">{acknowledged ? `Recibido por ${String(item.acknowledged_by_name ?? "el equipo")}` : item.recipient_name ? `Pendiente de ${String(item.recipient_name)}` : "Pendiente de recepción del equipo"}</p></div>{canAcknowledge && <button className="shrink-0 rounded-lg border border-stone-200 px-3 py-2 text-xs font-semibold hover:bg-stone-50 disabled:opacity-50 dark:border-slate-700 dark:hover:bg-slate-800" disabled={busy} onClick={() => void run("acknowledge_handoff", { handoff_id: item.id })}>Confirmar recepción</button>}</div>
                  <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">{taskItems.length} actividades pendientes · {incidentItems.length} incidencias abiertas al entregar</p>
                  {taskItems.slice(0, 4).map((task) => <div key={String(task.id)} className="mt-1 text-xs text-slate-500"><p>• {String(task.name ?? "Actividad")}</p>{typeof task.latest_pause_note === "string" && <p className="ml-3 text-amber-800 dark:text-amber-300">Pausa: {task.latest_pause_note}</p>}{((task.parts as Row[] | undefined) ?? []).filter((part) => typeof part.latest_pause_note === "string").map((part) => <p key={String(part.id)} className="ml-3 text-amber-800 dark:text-amber-300">{String(part.zone_name ?? "Zona")} · Pausa: {String(part.latest_pause_note)}</p>)}</div>)}
                  {incidentItems.slice(0, 4).map((incident) => <p key={String(incident.id)} className="mt-1 text-xs text-slate-500">• Incidencia: {String(incident.description ?? "")}</p>)}
                  {typeof item.handoff_note === "string" && item.handoff_note && <p className="mt-2 whitespace-pre-wrap text-sm">{item.handoff_note}</p>}
                </article>;
              })}
            </div>
          </section>
        </div>
      </div>
    </main>
  );
}

function Header({ title, subtitle, children }: { title: string; subtitle: string; children?: React.ReactNode }) {
  return <header className="flex flex-col gap-4 border-b border-stone-200 pb-5 dark:border-slate-800 md:flex-row md:items-end md:justify-between"><div><p className="text-xs font-semibold uppercase tracking-[0.18em] text-amber-700">Operación independiente</p><h1 className="mt-1 text-3xl font-bold tracking-tight">{title}</h1><p className="mt-1 text-sm text-slate-500">{subtitle}</p></div><div className="flex flex-wrap items-center gap-2">{children}</div></header>;
}

function Metric({ label, value, icon }: { label: string; value: number; icon: React.ReactNode }) {
  return <div className="rounded-xl border border-stone-200 bg-white p-4 dark:border-slate-800 dark:bg-slate-900"><div className="flex items-center justify-between text-slate-500"><span className="text-sm">{label}</span>{icon}</div><p className="mt-2 text-3xl font-bold tabular-nums">{value}</p></div>;
}

function TaskRow({ task }: { task: Task }) {
  const parts = task.parts ?? [];
  return <article className="py-4"><div className="flex flex-wrap items-start justify-between gap-3"><div><h3 className="font-semibold">{task.name}</h3><p className="mt-1 text-sm text-slate-500">{[task.area_name, `${task.estimated_minutes ?? 0} min`, statusLabels[task.status] ?? task.status].filter(Boolean).join(" · ")}</p>{task.status === "paused" && task.latest_pause_note && <p className="mt-2 text-sm text-amber-800 dark:text-amber-300">Motivo de pausa: {task.latest_pause_note}</p>}</div><span className={`rounded-full px-2.5 py-1 text-xs font-semibold ${task.status === "completed" ? "bg-emerald-50 text-emerald-700" : "bg-amber-50 text-amber-800"}`}>{task.configuration_pending ? "Config. pendiente" : task.assignee_name ?? (task.assigned_to ? "Asignada" : "Sin responsable")}</span></div>{parts.map((part) => <div key={String(part.id)} className="mt-2 rounded-lg bg-stone-50 px-3 py-2 text-sm dark:bg-slate-800"><p>{String(part.zone_name ?? "Zona")} · {String(part.assignee_name ?? "Sin responsable")} · {statusLabels[String(part.status)] ?? String(part.status)}</p>{part.status === "paused" && typeof part.latest_pause_note === "string" && <p className="mt-1 text-xs text-amber-800 dark:text-amber-300">Motivo de pausa: {part.latest_pause_note}</p>}</div>)}</article>;
}

function IncidentRow({ item, members, canManage, onUpdate, busy }: { item: Row; members: Row[]; canManage: boolean; onUpdate: (status: string, assignee: string, isBlocking: boolean) => void; busy: boolean }) {
  const [status, setStatus] = useState(String(item.status ?? "open"));
  const [assignee, setAssignee] = useState(String(item.assigned_to ?? ""));
  const [blocking, setBlocking] = useState(item.is_blocking === true);
  useEffect(() => { setStatus(String(item.status ?? "open")); setAssignee(String(item.assigned_to ?? "")); setBlocking(item.is_blocking === true); }, [item.status, item.assigned_to, item.is_blocking]);
  return <article className="rounded-xl border border-stone-200 p-3 dark:border-slate-700"><div className="flex items-start justify-between gap-3"><div><p className="font-medium">{String(item.description ?? "Incidencia")}</p><p className="mt-1 text-xs text-slate-500">{[item.area_name, item.urgency, item.assignee_name, blocking ? "Bloquea trabajo" : null].filter(Boolean).join(" · ")}</p></div><span className="shrink-0 text-xs font-semibold">{status === "open" ? "Abierta" : status === "in_progress" ? "En atención" : "Resuelta"}</span></div>{canManage && <div className="mt-3 grid gap-2 sm:grid-cols-2"><label className="text-xs font-medium text-slate-500">Estado<select aria-label="Estado de incidencia" className={`${inputClass} mt-1 min-h-9`} value={status} onChange={(event) => setStatus(event.target.value)}><option value="open">Abierta</option><option value="in_progress">En atención</option><option value="resolved">Resuelta</option></select></label><label className="text-xs font-medium text-slate-500">Responsable<select aria-label="Responsable de incidencia" className={`${inputClass} mt-1 min-h-9`} value={assignee} onChange={(event) => setAssignee(event.target.value)}><option value="">Sin responsable</option>{members.map((member) => <option key={String(member.user_id)} value={String(member.user_id)}>{String(member.user_name ?? member.user_id)}</option>)}</select></label><label className="flex items-center gap-2 text-xs"><input type="checkbox" checked={blocking} onChange={(event) => setBlocking(event.target.checked)} />Bloquea el trabajo</label><button className="min-h-9 rounded-lg border border-stone-200 px-3 text-xs font-semibold hover:bg-stone-50 disabled:opacity-50 dark:border-slate-700 dark:hover:bg-slate-800" disabled={busy} onClick={() => onUpdate(status, assignee, blocking)}>Guardar incidencia</button></div>}</article>;
}

function EmptyState({ text }: { text: string }) { return <p className="mt-4 rounded-xl bg-stone-50 px-4 py-5 text-sm text-slate-500 dark:bg-slate-800">{text}</p>; }
function PageMessage({ children }: { children: React.ReactNode }) { return <main className="mx-auto max-w-4xl py-12"><div role="status" className="rounded-xl border border-stone-200 bg-white p-6 text-sm dark:border-slate-800 dark:bg-slate-900">{children}</div></main>; }

const panelClass = "rounded-2xl border border-stone-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900";
const inputClass = "min-h-11 rounded-lg border border-stone-300 bg-white px-3 text-sm text-slate-900 outline-none focus:border-amber-500 focus:ring-2 focus:ring-amber-100 dark:border-slate-700 dark:bg-slate-950 dark:text-slate-100";
const primaryClass = "inline-flex min-h-11 items-center justify-center gap-2 rounded-lg bg-slate-900 px-4 text-sm font-semibold text-white hover:bg-slate-700 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-amber-400 dark:text-slate-950 dark:hover:bg-amber-300";
const secondaryClass = "inline-flex min-h-11 items-center justify-center gap-2 rounded-lg border border-stone-300 bg-white px-4 text-sm font-semibold text-slate-700 hover:bg-stone-50 disabled:opacity-50 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-200 dark:hover:bg-slate-800";
