"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { AlertTriangle, ArrowRightLeft, Bell, CalendarClock, CheckCircle2, CircleDashed, ClipboardCheck, ClipboardList, RefreshCw, Settings2, Trash2, Users } from "lucide-react";
import { callFunctionJson } from "@/lib/function-client";
import { mexicoTimeZones } from "@/lib/mexico-timezones";
import { preferredRestaurantBranchId, rememberRestaurantBranchId } from "@/lib/restaurant-branch-selection";
import { useCurrentUser } from "@/lib/use-role";
import { getSupabase } from "@/lib/supabase";

type Row = Record<string, unknown>;
type Branch = { id: string; name: string; timezone: string; access_role: string; enable_time_clock?: boolean; meal_duration_minutes?: number | null };
type Task = Row & { id: string; name: string; status: string; assigned_to: string | null; assignee_name?: string | null; area_name?: string | null; estimated_minutes?: number; configuration_pending?: boolean; latest_pause_note?: string | null; requires_evidence?: boolean; evidence_policy?: string; parts?: Row[] };
type Dashboard = { branch?: Partial<Branch>; tasks: Task[]; coworker_tasks?: Task[]; incidents: Row[]; waste_bins: Row[]; shifts: Row[]; areas?: Row[]; members?: Row[]; active_time_sessions?: Row[]; today_time_sessions?: Row[]; my_time_sessions?: Row[]; handoffs?: Row[]; area_inspection_templates?: Row[]; area_inspections?: Row[]; handoff: { completed_tasks: Row[]; outstanding_tasks: Row[]; open_incidents: Row[] }; local_date: string; assignable_unassigned_count?: number; unread_notification_count?: number };
type AttendanceHistory = { date: string; timezone: string; can_manage: boolean; sessions: Row[] };
type OperationalWorkspace = { operational_states: Row[]; active_meals: Row[]; peer_meal_candidates?: Row[]; can_record_peer_meals?: boolean; task_reports: Row[]; task_report_reviews: Row[]; meal_plans: Row[]; meal_plan_slots?: Row[]; recommendations: Row[] };

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
  const [workspace, setWorkspace] = useState<OperationalWorkspace | null>(null);
  const [collaborationNotices, setCollaborationNotices] = useState<Row[]>([]);
  const [taskReceipts, setTaskReceipts] = useState<Row[]>([]);
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
      const [data, ops, inbox, receipts] = await Promise.all([
        callFunctionJson<Dashboard>("restaurant_ops", { query: { action: "dashboard", branch_id: id } }),
        callFunctionJson<OperationalWorkspace>("restaurant_ops", { query: { action: "operational_workspace", branch_id: id } }),
        callFunctionJson<{ requests: Row[] }>("restaurant_ops", { query: { action: "collaboration_inbox", branch_id: id } }),
        callFunctionJson<{ receipts: Row[] }>("restaurant_ops", { query: { action: "task_receipts", branch_id: id } }),
      ]);
      setDashboard(data);
      setWorkspace(ops);
      setCollaborationNotices(inbox.requests ?? []);
      setTaskReceipts(receipts.receipts ?? []);
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
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_task_receipts", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_collaboration_requests", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_member_operational_states", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_meal_sessions", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_task_reports", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_task_report_reviews", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_meal_plan_proposals", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_meal_plan_slots", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_operational_recommendations", filter: `branch_id=eq.${branchId}` }, refresh)
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
  if (!canManage) return <WorkerWorkspace
    branch={selectedBranch}
    branches={branches}
    branchId={branchId}
    dashboard={dashboard}
    workspace={workspace}
    notices={collaborationNotices}
    receipts={taskReceipts}
    userId={currentUser.userId}
    loading={loading}
    busy={busy}
    error={error}
    notice={notice}
    onBranchChange={(id) => { rememberRestaurantBranchId(id); setBranchId(id); }}
    onRefresh={() => void load()}
    run={run}
  />;
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
          {loading ? <p className="mt-6 text-sm text-slate-500">Cargando el turno…</p> : tasks.length === 0 ? <EmptyState text="Sin actividades programadas. Configura el calendario real de la sucursal para empezar." /> : <div className="mt-4 divide-y divide-stone-100 dark:divide-slate-800">{tasks.map((task) => <TaskRow key={task.id} task={task} receipt={taskReceipts.find((item) => item.task_id === task.id && item.employee_id === task.assigned_to)} canManage onRequestNotice={() => void run("request_collaborative_notice", { task_id: task.id, client_event_id: crypto.randomUUID() })} busy={busy} />)}</div>}
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
      <OperationalManagerPanel branchId={branchId} workspace={workspace} dashboard={dashboard} collaborationNotices={collaborationNotices} busy={busy} run={run} />
    </main>
  );
}

function Header({ title, subtitle, children }: { title: string; subtitle: string; children?: React.ReactNode }) {
  return <header className="flex flex-col gap-4 border-b border-stone-200 pb-5 dark:border-slate-800 md:flex-row md:items-end md:justify-between"><div><p className="text-xs font-semibold uppercase tracking-[0.18em] text-amber-700">Operación independiente</p><h1 className="mt-1 text-3xl font-bold tracking-tight">{title}</h1><p className="mt-1 text-sm text-slate-500">{subtitle}</p></div><div className="flex flex-wrap items-center gap-2">{children}</div></header>;
}

function WorkerWorkspace({ branch, branches, branchId, dashboard, workspace, notices, receipts, userId, loading, busy, error, notice, onBranchChange, onRefresh, run }: {
  branch: Branch | null; branches: Branch[]; branchId: string; dashboard: Dashboard | null;
  workspace: OperationalWorkspace | null; notices: Row[]; receipts: Row[]; userId: string | null;
  loading: boolean; busy: boolean; error: string | null; notice: string | null;
  onBranchChange: (id: string) => void; onRefresh: () => void;
  run: (action: string, extra?: Record<string, unknown>) => Promise<boolean>;
}) {
  const [declaredMealTime, setDeclaredMealTime] = useState("");
  const ownTasks = dashboard?.tasks ?? [];
  const peerTasks = dashboard?.coworker_tasks ?? [];
  const state = workspace?.operational_states.find((item) => item.employee_id === userId)?.state ?? "available";
  const meal = workspace?.active_meals.find((item) => item.employee_id === userId);
  const myApprovedMeals = workspace?.meal_plan_slots ?? [];
  const shift = dashboard?.shifts.find((item) => item.employee_id === userId && item.currently_active === true);
  // Connection state is not work availability. Without an active published
  // shift, don't present a default/missing state row as "Disponible".
  const effectiveState = meal ? "meal" : shift ? state : "off_shift";
  // datetime-local is branch-local wall time. The Edge Function converts it
  // using the branch timezone; do not reinterpret it in the browser timezone.
  const declaredMealAt = declaredMealTime || undefined;
  type WorkerTaskUnit = { task: Task; part: Row | null; responsibleId: string | null };
  const ownUnits: WorkerTaskUnit[] = ownTasks.flatMap((task): WorkerTaskUnit[] => {
      const parts = (task.parts ?? []).filter((part) => part.assigned_to === userId && part.status !== "completed");
      return parts.length ? parts.map((part) => ({ task, part, responsibleId: userId }))
        : task.assigned_to === userId && task.status !== "completed" ? [{ task, part: null, responsibleId: userId }] : [];
    });
  const peerUnits: WorkerTaskUnit[] = peerTasks.flatMap((task): WorkerTaskUnit[] => {
      const parts = (task.parts ?? []).filter((part) => part.assigned_to && part.assigned_to !== userId && part.status !== "completed");
      return parts.length ? parts.map((part) => ({ task, part, responsibleId: String(part.assigned_to) }))
        : task.assigned_to && task.assigned_to !== userId && task.status !== "completed" ? [{ task, part: null, responsibleId: task.assigned_to }] : [];
    });
  const units: WorkerTaskUnit[] = [...ownUnits, ...peerUnits];
  return <main className="mx-auto max-w-3xl pb-12">
    <Header title="Mi turno" subtitle="Pollo Móvil · espacio de trabajo" >
      <select aria-label="Sucursal" className={inputClass} disabled={busy} value={branchId} onChange={(event) => onBranchChange(event.target.value)}>{branches.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select>
      <button aria-label="Actualizar" className={secondaryClass} disabled={busy} onClick={onRefresh}><RefreshCw size={16} />Actualizar</button>
    </Header>
    {(error || notice) && <p role={error ? "alert" : "status"} className={`mt-4 rounded-xl px-4 py-3 text-sm ${error ? "bg-rose-50 text-rose-800" : "bg-emerald-50 text-emerald-800"}`}>{error ?? notice}</p>}
    <section className="mt-6 rounded-2xl border border-stone-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
      <h2 className="text-xl font-bold">Mi turno</h2>
      <p className="mt-1 text-sm text-slate-500">{branch?.name ?? "Sucursal"}{shift ? ` · ${String(shift.start_time)}–${String(shift.end_time)}` : " · No hay turno activo registrado"}</p>
      <p className="mt-3 text-sm">Estado: <strong>{effectiveState === "meal" ? "En comida — confirma tu regreso" : effectiveState === "occupied" ? "Ocupado" : effectiveState === "rest" ? "En descanso" : effectiveState === "off_shift" ? "Fuera de turno" : "Disponible"}</strong></p>
      <label className="mt-3 block max-w-sm text-xs font-medium text-slate-600">Hora declarada del movimiento (opcional)<input aria-label="Hora declarada del movimiento de comida" className={`${inputClass} mt-1 w-full`} type="datetime-local" value={declaredMealTime} onChange={(event) => setDeclaredMealTime(event.target.value)} /></label>
          {meal ? <button className={`${primaryClass} mt-3`} disabled={busy} onClick={() => void run("confirm_meal_return", { session_id: meal.id, state_after_return: "available", declared_at: declaredMealAt })}>Confirmar que regresé</button>
        : effectiveState !== "off_shift" && effectiveState !== "rest" && <div className="mt-3 flex flex-wrap gap-2">
          <button className={primaryClass} disabled={busy || effectiveState === "meal" || branch?.meal_duration_minutes == null} title={branch?.meal_duration_minutes == null ? "La duración de comida aún no está configurada por la sucursal." : undefined} onClick={() => void run("start_meal", { declared_at: declaredMealAt })}>Iniciar comida</button>
          <button className={secondaryClass} disabled={busy || effectiveState === "meal"} onClick={() => void run("set_operational_state", { state: effectiveState === "occupied" ? "available" : "occupied" })}>{effectiveState === "occupied" ? "Estoy disponible" : "Estoy ocupado"}</button>
        </div>}
    </section>
    {workspace?.can_record_peer_meals && workspace.peer_meal_candidates?.length ? <section className="mt-6 rounded-2xl border border-stone-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
      <h2 className="flex items-center gap-2 text-xl font-bold"><Users size={20} />Registrar comida por un compañero</h2>
      <p className="mt-1 text-sm text-slate-500">Solo compañeros con turno activo aparecen aquí. El servidor vuelve a validar la disponibilidad, el relevo de tareas y que ambos pertenezcan a la sucursal.</p>
      <div className="mt-3 space-y-2">{workspace.peer_meal_candidates.map((candidate) => {
        const employeeId = String(candidate.employee_id);
        const employeeShift = dashboard?.shifts.find((item) => String(item.employee_id) === employeeId && item.currently_active === true);
        const employeeName = String(candidate.employee_name ?? employeeShift?.employee_name ?? employeeId);
        const activeMealSessionId = typeof candidate.active_meal_session_id === "string" ? candidate.active_meal_session_id : null;
        const canStart = candidate.can_start_meal === true;
        return <article key={employeeId} className="flex flex-wrap items-center justify-between gap-3 rounded-xl border p-3">
          <div><p className="font-semibold">{employeeName}</p><p className="text-xs text-slate-500">{activeMealSessionId ? "En comida; falta confirmar el regreso" : String(candidate.state ?? "Disponible")}</p></div>
          {activeMealSessionId
            ? <div className="flex flex-wrap gap-2"><button className={secondaryClass} disabled={busy || effectiveState !== "available"} onClick={() => void run("confirm_meal_return", { session_id: activeMealSessionId, state_after_return: "available", declared_at: declaredMealAt })}>Confirmar regreso disponible</button><button className={secondaryClass} disabled={busy || effectiveState !== "available"} onClick={() => void run("confirm_meal_return", { session_id: activeMealSessionId, state_after_return: "busy", declared_at: declaredMealAt })}>Confirmar regreso ocupado</button></div>
            : <button className={secondaryClass} disabled={busy || effectiveState !== "available" || !canStart || branch?.meal_duration_minutes == null} title={!canStart ? "La persona necesita cerrar tareas activas o no está disponible para iniciar comida." : undefined} onClick={() => void run("start_meal", { employee_id: employeeId, declared_at: declaredMealAt })}>Registrar inicio de comida</button>}
        </article>;
      })}</div>
    </section> : null}
    {myApprovedMeals.length > 0 && <section className="mt-6 rounded-2xl border border-amber-200 bg-amber-50 p-5 dark:border-amber-900 dark:bg-amber-950/20"><h2 className="font-bold">Comida programada</h2><p className="mt-1 text-sm text-slate-600 dark:text-slate-300">Horario aprobado por gerencia; si cambia la operación, el gerente debe confirmar una modificación. El horario no inicia la comida automáticamente.</p>{myApprovedMeals.map((slot) => <p key={String(slot.id)} className="mt-3 text-sm font-semibold">{String(slot.starts_at_local)} – {String(slot.scheduled_end_at_local)}</p>)}</section>}
    <section className="mt-6 rounded-2xl border border-stone-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
      <h2 className="flex items-center gap-2 text-xl font-bold"><ClipboardList size={20} />Mis tareas</h2>
      {loading ? <p className="mt-4 text-sm text-slate-500">Cargando tareas…</p> : <div className="mt-3 space-y-3">{units.filter((unit) => unit.responsibleId === userId).map((unit) => <WorkerTaskCard key={`${unit.task.id}:${unit.part?.id ?? "task"}`} unit={unit} branchId={branchId} receipts={receipts} userId={userId} busy={busy} run={run} />)}{!units.some((unit) => unit.responsibleId === userId) && <EmptyState text="No tienes actividades asignadas en este momento." />}</div>}
    </section>
    <section className="mt-6 rounded-2xl border border-stone-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
      <h2 className="flex items-center gap-2 text-xl font-bold"><Users size={20} />Registrar actividad por un compañero</h2>
      <p className="mt-1 text-sm text-slate-500">Quedan guardados por separado el responsable y quien registra. Registrar no equivale a verificar.</p>
      <div className="mt-3 space-y-3">{units.filter((unit) => unit.responsibleId !== userId).map((unit) => <WorkerTaskCard key={`${unit.task.id}:${unit.part?.id ?? "task"}`} unit={unit} branchId={branchId} receipts={receipts} userId={userId} busy={busy} run={run} />)}{!units.some((unit) => unit.responsibleId !== userId) && <EmptyState text="No hay actividades abiertas de compañeros para registrar." />}</div>
    </section>
    <section className="mt-6 rounded-2xl border border-stone-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
      <h2 className="flex items-center gap-2 text-xl font-bold"><Bell size={20} />Avisos</h2>
      <div className="mt-3 space-y-3">{notices.map((item) => {
        const task = item.task as Row | null;
        const resolved = item.status === "resolved";
        const cancelled = item.status === "cancelled";
        const claimedByMe = item.claimed_by === userId;
        const claimedByOther = Boolean(item.claimed_by && !claimedByMe);
        return <article key={String(item.id)} className="rounded-xl border border-stone-200 p-4 dark:border-slate-700">
          <p className="font-semibold">{String(task?.name ?? "Aviso de compañero")}</p>
          <p className="mt-1 text-sm text-slate-500">{resolved ? "Aviso resuelto; la actividad sigue pendiente de su propio registro y validación." : cancelled ? "La solicitud dejó de estar activa porque ya no requiere aviso." : claimedByOther ? "Otro compañero reservó el aviso." : "¿Puedes comunicarle personalmente esta instrucción?"}</p>
          {!resolved && !cancelled && (!claimedByOther || (typeof item.claimed_until === "string" && Date.parse(item.claimed_until) <= Date.now())) && <div className="mt-3 flex flex-wrap gap-2">{!claimedByMe && <button className={secondaryClass} disabled={busy} onClick={() => void run("claim_collaborative_notice", { request_id: item.id })}>Voy a avisarle</button>}{claimedByMe && <><button className={primaryClass} disabled={busy} onClick={() => void run("resolve_collaborative_notice", { request_id: item.id, resolution: "peer_notified" })}>Ya le avisé</button><button className={secondaryClass} disabled={busy} onClick={() => void run("resolve_collaborative_notice", { request_id: item.id, resolution: "not_located" })}>No pude localizarlo</button></>}</div>}
        </article>;
      })}{notices.length === 0 && <EmptyState text="No hay avisos activos ni recientes." />}</div>
    </section>
  </main>;
}

function WorkerTaskCard({ unit, branchId, receipts, userId, busy, run }: { unit: { task: Task; part: Row | null; responsibleId: string | null }; branchId: string; receipts: Row[]; userId: string | null; busy: boolean; run: (action: string, extra?: Record<string, unknown>) => Promise<boolean> }) {
  const [file, setFile] = useState<File | null>(null);
  const [declaredAt, setDeclaredAt] = useState(() => new Date().toISOString().slice(0, 16));
  const [uploadError, setUploadError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const task = unit.task;
  const part = unit.part;
  const receipt = !part && unit.responsibleId === userId;
  const taskStatus = String(part?.status ?? task.status);
  const policy = String(task.evidence_policy ?? (task.requires_evidence ? "required" : "none"));
  const submit = async () => {
    if (!userId || !unit.responsibleId || (policy === "required" && !file)) return;
    setUploadError(null);
    setSubmitting(true);
    try {
      let evidencePath: string | null = null;
      if (file) {
        if (!new Set(["image/jpeg", "image/png", "image/webp"]).has(file.type) || file.size <= 0 || file.size > 10 * 1024 * 1024) throw new Error("Elige una imagen JPEG, PNG o WebP de hasta 10 MB.");
        const signed = await sendAction<{ object_path: string; token: string }>({ action: "sign_evidence_upload", branch_id: branchId, task_id: task.id, part_id: part?.id ?? null, mime_type: file.type, file_size_bytes: file.size });
        const { error } = await getSupabase().storage.from("restaurant-evidence").uploadToSignedUrl(signed.object_path, signed.token, file, { contentType: file.type, upsert: false });
        if (error) throw error;
        await sendAction({ action: "register_evidence", branch_id: branchId, task_id: task.id, part_id: part?.id ?? null, object_path: signed.object_path, mime_type: file.type, file_size_bytes: file.size });
        evidencePath = signed.object_path;
      }
      await run("record_task_report", { task_id: task.id, part_id: part?.id ?? null, responsible_employee_id: unit.responsibleId, declared_completed_at: new Date(declaredAt).toISOString(), evidence_path: evidencePath, client_event_id: crypto.randomUUID() });
    } catch (cause) {
      setUploadError(cause instanceof Error ? cause.message : "No se pudo adjuntar la evidencia.");
    } finally {
      setSubmitting(false);
    }
  };
  return <article className="rounded-xl border border-stone-200 p-4 dark:border-slate-700">
    <div className="flex items-start justify-between gap-3"><div><h3 className="font-semibold">{task.name}{part ? ` · ${String(part.zone_name ?? "Zona")}` : ""}</h3><p className="mt-1 text-sm text-slate-500">{String(task.area_name ?? "Área")}{unit.responsibleId !== userId ? ` · Responsable: ${String(part?.assignee_name ?? task.assignee_name ?? "Integrante asignado")}` : " · Responsable: tú"}</p></div><span className="text-xs font-semibold">{statusLabels[String(part?.status ?? task.status)] ?? String(part?.status ?? task.status)}</span></div>
    {receipt && <p className="mt-3 text-xs text-slate-500">Recepción: {String(receipts.find((item) => item.task_id === task.id && item.employee_id === userId)?.receipt_state ?? "sin registro")}</p>}
    {receipt && receipts.find((item) => item.task_id === task.id && item.employee_id === userId)?.receipt_state === "awaiting" && <button className="mt-2 rounded-lg border px-3 py-2 text-sm" disabled={busy || submitting} onClick={() => void run("confirm_task_receipt", { task_id: task.id })}>Confirmar recepción</button>}
    {unit.responsibleId === userId && taskStatus !== "completed" && <div className="mt-3 flex flex-wrap gap-2">{taskStatus === "pending" && <button className={secondaryClass} disabled={busy || submitting} onClick={() => void run("task_action", { task_id: task.id, part_id: part?.id ?? null, task_action: "start", client_event_id: crypto.randomUUID() })}>Comenzar</button>}{taskStatus === "in_progress" && <><button className={secondaryClass} disabled={busy || submitting} onClick={() => void run("task_action", { task_id: task.id, part_id: part?.id ?? null, task_action: "pause", client_event_id: crypto.randomUUID() })}>Pausar</button>{policy !== "required" && policy !== "independent_review" && <button className={primaryClass} disabled={busy || submitting} onClick={() => void run("task_action", { task_id: task.id, part_id: part?.id ?? null, task_action: "complete", client_event_id: crypto.randomUUID() })}>Terminar</button>}</>}{["paused", "blocked"].includes(taskStatus) && <button className={secondaryClass} disabled={busy || submitting} onClick={() => void run("task_action", { task_id: task.id, part_id: part?.id ?? null, task_action: "resume", client_event_id: crypto.randomUUID() })}>Continuar</button>}</div>}
    <label className="mt-3 block text-xs font-medium text-slate-500">Hora declarada de realización<input aria-label="Hora declarada de realización" className={`${inputClass} mt-1 w-full`} type="datetime-local" value={declaredAt} onChange={(event) => setDeclaredAt(event.target.value)} /></label>
    {policy !== "none" && <label className="mt-3 block text-xs font-medium text-slate-500">Evidencia {policy === "required" ? "(obligatoria)" : policy === "optional" ? "(opcional)" : "(validación independiente requerida)"}<input className="mt-1 block w-full text-sm" type="file" accept="image/jpeg,image/png,image/webp" onChange={(event) => setFile(event.target.files?.[0] ?? null)} /></label>}
    {uploadError && <p role="alert" className="mt-2 text-sm text-rose-700">{uploadError}</p>}
    <button className={`${primaryClass} mt-3`} disabled={busy || submitting || (policy === "required" && !file)} onClick={() => void submit()}>{submitting ? "Guardando…" : "Registrar actividad realizada"}</button>
  </article>;
}

function OperationalManagerPanel({ branchId, workspace, dashboard, collaborationNotices, busy, run }: { branchId: string; workspace: OperationalWorkspace | null; dashboard: Dashboard | null; collaborationNotices: Row[]; busy: boolean; run: (action: string, extra?: Record<string, unknown>) => Promise<boolean> }) {
  const [declaredMealTime, setDeclaredMealTime] = useState("");
  const declaredMealAt = declaredMealTime || undefined;
  const [historyEnd, setHistoryEnd] = useState(dashboard?.local_date ?? "");
  const [historyStart, setHistoryStart] = useState(() => {
    const date = dashboard?.local_date;
    if (!date) return "";
    const value = new Date(`${date}T00:00:00Z`); value.setUTCDate(value.getUTCDate() - 29);
    return value.toISOString().slice(0, 10);
  });
  useEffect(() => {
    const date = dashboard?.local_date;
    if (!date) return;
    const start = new Date(`${date}T00:00:00Z`); start.setUTCDate(start.getUTCDate() - 29);
    setHistoryEnd(date); setHistoryStart(start.toISOString().slice(0, 10));
  }, [dashboard?.local_date]);
  if (!workspace) return null;
  const pendingReports = workspace.task_reports.filter((report) => !workspace.task_report_reviews.some((review) => review.report_id === report.id));
  const reviewedReports = workspace.task_reports.filter((report) => workspace.task_report_reviews.some((review) => review.report_id === report.id)).slice(0, 12);
  const members = dashboard?.members ?? [];
  const memberName = (id: unknown) => String(members.find((member) => member.user_id === id)?.user_name ?? id ?? "Integrante");
  const escalatedNotices = collaborationNotices.filter((item) => item.status === "open" && item.manager_escalated_at != null);
  const activeMealByEmployee = new Map(workspace.active_meals.map((meal) => [String(meal.employee_id), meal]));
  const operationalStateByEmployee = new Map(workspace.operational_states.map((item) => [String(item.employee_id), String(item.state)]));
  const todayShiftEmployeeIds = new Set((dashboard?.shifts ?? []).filter((shift) =>
    shift.shift_date === dashboard?.local_date && shift.status === "published" && shift.currently_active === true).map((shift) => String(shift.employee_id)));
  for (const employeeId of activeMealByEmployee.keys()) todayShiftEmployeeIds.add(employeeId);
  return <section className="mt-7 grid gap-6 lg:grid-cols-2">
    <div className={panelClass}><h2 className="text-lg font-semibold">Avisos colaborativos escalados</h2><p className="mt-1 text-sm text-slate-500">Si el plazo de sucursal está configurado y nadie atiende, gerencia recibe el escalamiento. El sistema registra el aviso, no completa la tarea ni reemplaza el seguimiento presencial.</p><div className="mt-3 space-y-2">{escalatedNotices.map((item) => { const task = item.task as Row | null; return <article key={String(item.id)} className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm dark:border-amber-900 dark:bg-amber-950/20"><p className="font-semibold">{String(task?.name ?? `Tarea ${item.task_id}`)}</p><p className="mt-1 text-xs text-slate-600 dark:text-slate-300">Responsable: {memberName(item.target_employee_id)} · Escalado: {String(item.manager_escalated_at)}</p></article>; })}{!escalatedNotices.length && <EmptyState text="No hay avisos escalados pendientes." />}</div></div>
    <div className={panelClass}><h2 className="text-lg font-semibold">Disponibilidad y comidas</h2><p className="mt-1 text-sm text-slate-500">Un gerente puede registrar estados y comidas de compañeros sin teléfono. Solo se muestran turnos activos; el regreso de comida requiere confirmación y no se infiere por el reloj. La hora declarada es opcional y se interpreta en la zona horaria de la sucursal.</p><label className="mt-3 block max-w-sm text-xs font-medium text-slate-600">Hora declarada del movimiento<input aria-label="Hora declarada de comida de un compañero" className={`${inputClass} mt-1 w-full`} type="datetime-local" value={declaredMealTime} onChange={(event) => setDeclaredMealTime(event.target.value)} /></label><div className="mt-3 space-y-2">{members.filter((member) => member.is_active !== false && todayShiftEmployeeIds.has(String(member.user_id))).map((member) => { const employeeId = String(member.user_id); const meal = activeMealByEmployee.get(employeeId); const state = operationalStateByEmployee.get(employeeId) ?? "available"; return <div key={employeeId} className="rounded-lg border p-3 text-sm"><p className="font-semibold">{memberName(employeeId)} · {meal ? "En comida" : state}</p>{meal ? <div className="mt-2 flex flex-wrap gap-2"><button className="rounded-lg border px-3 py-2 text-xs font-semibold" disabled={busy} onClick={() => void run("confirm_meal_return", { session_id: meal.id, state_after_return: "available", declared_at: declaredMealAt })}>Regresó disponible</button><button className="rounded-lg border px-3 py-2 text-xs font-semibold" disabled={busy} onClick={() => void run("confirm_meal_return", { session_id: meal.id, state_after_return: "busy", declared_at: declaredMealAt })}>Regresó ocupado</button></div> : <div className="mt-2 flex flex-wrap items-end gap-2"><OperationalStateControl employeeId={employeeId} initialState={state} busy={busy} run={run} /><button className="rounded-lg border px-3 py-2 text-xs font-semibold" disabled={busy || dashboard?.branch?.meal_duration_minutes == null || ["rest", "off_shift"].includes(state)} onClick={() => void run("start_meal", { employee_id: employeeId, declared_at: declaredMealAt })}>Registrar inicio de comida</button></div>}</div>; })}{!todayShiftEmployeeIds.size && <EmptyState text="No hay turnos activos para registrar disponibilidad o comidas." />}</div></div>
    <div className={panelClass}><h2 className="text-lg font-semibold">Reportes por revisar</h2><p className="mt-1 text-sm text-slate-500">Responsable, registrador, hora declarada y hora de registro se conservan por separado.</p><div className="mt-3 space-y-3">{pendingReports.map((report) => <ManagerReportCard key={String(report.id)} report={report} branchId={branchId} responsibleName={memberName(report.responsible_employee_id)} recorderName={memberName(report.recorded_by)} busy={busy} run={run} />)}{!pendingReports.length && <EmptyState text="No hay reportes pendientes de validación." />}</div></div>
    <div className={panelClass}><h2 className="text-lg font-semibold">Historial de validaciones</h2><p className="mt-1 text-sm text-slate-500">La acción de registrar no se confunde con la revisión independiente.</p><div className="mt-3 space-y-2">{reviewedReports.map((report) => { const review = workspace.task_report_reviews.filter((item) => item.report_id === report.id).sort((a, b) => String(b.reviewed_at).localeCompare(String(a.reviewed_at)))[0]; return <article key={String(report.id)} className="rounded-lg border p-3 text-sm"><p className="font-semibold">{String(review?.decision === "accepted" ? "Aceptado" : "Rechazado")} · responsable {memberName(report.responsible_employee_id)}</p><p className="mt-1 text-xs text-slate-500">Registró {memberName(report.recorded_by)} · declarado {String(report.declared_completed_at)} · registrado {String(report.recorded_at)} · revisó {memberName(review?.reviewer_id)}</p>{typeof review?.note === "string" && review.note.length > 0 && <p className="mt-2">{review.note}</p>}</article>; })}{!reviewedReports.length && <EmptyState text="Todavía no hay reportes revisados." />}</div></div>
    <div className={panelClass}><h2 className="text-lg font-semibold">Propuestas de comida</h2><p className="mt-1 text-sm text-slate-500">El motor Timefold propone horarios para turnos publicados. Cada propuesta requiere aprobación humana; la comida iniciada no se modifica automáticamente.</p><button className={`${secondaryClass} mt-3`} disabled={busy || !dashboard?.local_date} onClick={() => void run("generate_meal_plan", { shift_date: dashboard?.local_date })}>Generar propuesta con Timefold</button><div className="mt-3 space-y-3">{workspace.meal_plans.filter((plan) => plan.status === "proposed").map((plan) => <MealPlanReviewCard key={String(plan.id)} plan={plan} members={members} busy={busy} onDecision={(decision, schedule) => run("decide_meal_plan", { plan_id: plan.id, decision, ...(schedule ? { schedule } : {}) })} />)}{!workspace.meal_plans.some((plan) => plan.status === "proposed") && <EmptyState text="No hay propuestas pendientes. Requiere duración de comida y turnos publicados; cobertura mínima puede hacer el problema inviable." />}</div></div>
    <div className={panelClass}><h2 className="text-lg font-semibold">Recomendaciones operativas</h2><p className="mt-1 text-sm text-slate-500">Cada elemento conserva fuente, periodo analizado y decisión del gerente. El análisis usa registros reales de tareas, inspecciones y turnos; las estimaciones no se presentan como mediciones.</p><button className={`${secondaryClass} mt-3`} disabled={busy || !dashboard?.local_date} onClick={() => void run("analyze_operational_coverage", { shift_date: dashboard?.local_date })}>Analizar cobertura de hoy</button><div className="mt-3 grid gap-2 sm:grid-cols-2"><label className="text-xs">Desde<input aria-label="Inicio del periodo analítico" className={`${inputClass} mt-1`} type="date" value={historyStart} max={historyEnd} onChange={(event) => setHistoryStart(event.target.value)} /></label><label className="text-xs">Hasta<input aria-label="Fin del periodo analítico" className={`${inputClass} mt-1`} type="date" value={historyEnd} min={historyStart} max={dashboard?.local_date} onChange={(event) => setHistoryEnd(event.target.value)} /></label></div><button className={`${secondaryClass} mt-2`} disabled={busy || !historyStart || !historyEnd || historyEnd < historyStart} onClick={() => void run("analyze_operational_history", { start_date: historyStart, end_date: historyEnd })}>Analizar historial operativo</button><p className="mt-1 text-xs text-slate-500">Hasta 90 días. No se usa POS ni se inventa una hora límite para tareas que solo tienen fecha programada.</p><div className="mt-3 space-y-3">{workspace.recommendations.map((item) => <RecommendationCard key={String(item.id)} item={item} busy={busy} run={run} />)}{!workspace.recommendations.length && <EmptyState text="Sin recomendaciones registradas a partir de datos operativos." />}</div></div>
  </section>;
}

function RecommendationCard({ item, busy, run }: { item: Row; busy: boolean; run: (action: string, extra?: Record<string, unknown>) => Promise<boolean> }) {
  const [outcome, setOutcome] = useState("");
  return <article className="rounded-xl border p-3"><p className="text-sm font-semibold">{String(item.category)} · {String(item.decision)}</p><p className="mt-1 text-sm">{String(item.explanation)}</p><p className="mt-1 text-xs text-slate-500">Periodo: {String(item.source_period_start)} – {String(item.source_period_end)} · Confianza: {item.confidence == null ? "no calculada" : String(item.confidence)}</p><details className="mt-2 text-xs"><summary>Datos fuente</summary><pre className="mt-2 overflow-auto">{JSON.stringify(item.source_data, null, 2)}</pre></details>{item.decision === "pending" && <div className="mt-3 space-y-2"><label className="block text-xs">Nota de decisión / resultado<textarea className={`${inputClass} mt-1 min-h-20 w-full py-2`} value={outcome} maxLength={1000} onChange={(event) => setOutcome(event.target.value)} placeholder="Registra el motivo o la adaptación decidida por el gerente." /></label><div className="flex flex-wrap gap-2"><button className={primaryClass} disabled={busy} onClick={() => void run("decide_recommendation", { recommendation_id: item.id, decision: "approved", note: outcome.trim() || undefined })}>Aprobar</button><button className={secondaryClass} disabled={busy || !outcome.trim()} onClick={() => void run("decide_recommendation", { recommendation_id: item.id, decision: "modified", note: outcome.trim() })}>Marcar modificada</button><button className={secondaryClass} disabled={busy} onClick={() => void run("decide_recommendation", { recommendation_id: item.id, decision: "rejected", note: outcome.trim() || undefined })}>Rechazar</button></div></div>}{typeof item.outcome_note === "string" && item.outcome_note && <p className="mt-2 text-xs text-slate-500">Nota del gerente: {String(item.outcome_note)}</p>}</article>;
}

function OperationalStateControl({ employeeId, initialState, busy, run }: {
  employeeId: string; initialState: string; busy: boolean;
  run: (action: string, extra?: Record<string, unknown>) => Promise<boolean>;
}) {
  const [state, setState] = useState(initialState);
  const [note, setNote] = useState("");
  useEffect(() => { setState(initialState); }, [initialState]);
  return <div className="flex flex-wrap items-end gap-2">
    <label className="text-xs font-medium text-slate-600">Estado laboral
      <select aria-label={`Estado laboral ${employeeId}`} className={`${inputClass} mt-1 min-h-9`} value={state} disabled={busy} onChange={(event) => setState(event.target.value)}>
        <option value="available">Disponible</option><option value="occupied">Ocupado</option>
        <option value="rest">En descanso</option><option value="off_shift">Fuera de turno</option>
      </select>
    </label>
    <label className="text-xs font-medium text-slate-600">Nota opcional
      <input aria-label={`Nota de estado ${employeeId}`} className={`${inputClass} mt-1 min-h-9`} maxLength={500} value={note} disabled={busy} onChange={(event) => setNote(event.target.value)} placeholder="Contexto operativo" />
    </label>
    <button className="min-h-9 rounded-lg border px-3 py-2 text-xs font-semibold" disabled={busy || state === initialState} onClick={async () => {
      const saved = await run("set_operational_state", { employee_id: employeeId, state, note: note.trim() || undefined });
      if (saved) setNote("");
    }}>Guardar estado</button>
  </div>;
}

function MealPlanReviewCard({ plan, members, busy, onDecision }: { plan: Row; members: Row[]; busy: boolean; onDecision: (decision: string, schedule?: Row[]) => Promise<boolean> }) {
  const original = Array.isArray(plan.proposed_schedule) ? plan.proposed_schedule as Row[] : [];
  const [schedule, setSchedule] = useState<Row[]>(original.map((slot) => ({ ...slot })));
  const updateTime = (index: number, field: "starts_at_local" | "scheduled_end_at_local", value: string) => setSchedule((current) => current.map((slot, itemIndex) => itemIndex === index ? { ...slot, [field]: value } : slot));
  const canModify = schedule.length > 0 && schedule.every((slot) => typeof slot.starts_at_local === "string" && typeof slot.scheduled_end_at_local === "string");
  return <article className="rounded-xl border p-3"><p className="text-sm font-semibold">Fecha: {String(plan.shift_date)} · Motor: {String(plan.planner)}</p><p className="mt-1 text-xs text-slate-500">Edita fecha y hora local; el servidor vuelve a comprobar turno, descanso, duración y traslapes.</p><div className="mt-3 space-y-3">{schedule.map((slot, index) => <div key={String(slot.employee_id)} className="grid gap-2 rounded-lg bg-stone-50 p-3 dark:bg-slate-800"><span className="text-sm font-medium">{String(members.find((member) => member.user_id === slot.employee_id)?.user_name ?? slot.employee_id)}</span><label className="text-xs">Inicio<input aria-label={`Inicio de comida ${String(slot.employee_id)}`} className={`${inputClass} mt-1`} type="datetime-local" value={String(slot.starts_at_local ?? "")} onChange={(event) => updateTime(index, "starts_at_local", event.target.value)} /></label><label className="text-xs">Fin<input aria-label={`Fin de comida ${String(slot.employee_id)}`} className={`${inputClass} mt-1`} type="datetime-local" value={String(slot.scheduled_end_at_local ?? "")} onChange={(event) => updateTime(index, "scheduled_end_at_local", event.target.value)} /></label></div>)}</div><div className="mt-3 flex flex-wrap gap-2"><button className={primaryClass} disabled={busy} onClick={() => void onDecision("approved", original)}>Aprobar propuesta</button><button className={secondaryClass} disabled={busy || !canModify} onClick={() => void onDecision("modified", schedule)}>Guardar horario modificado</button><button className={secondaryClass} disabled={busy} onClick={() => void onDecision("rejected")}>Rechazar</button></div></article>;
}

function ManagerReportCard({ report, branchId, responsibleName, recorderName, busy, run }: { report: Row; branchId: string; responsibleName: string; recorderName: string; busy: boolean; run: (action: string, extra?: Record<string, unknown>) => Promise<boolean> }) {
  const [evidenceUrl, setEvidenceUrl] = useState<string | null>(null);
  const [evidenceError, setEvidenceError] = useState<string | null>(null);
  const openEvidence = async () => {
    setEvidenceError(null);
    try {
      const result = await sendAction<{ signed_url: string }>({ action: "get_task_report_evidence", branch_id: branchId, report_id: report.id });
      setEvidenceUrl(result.signed_url);
    } catch (cause) {
      setEvidenceError(cause instanceof Error ? cause.message : "No se pudo abrir la evidencia.");
    }
  };
  return <article className="rounded-xl border p-3"><p className="text-sm font-semibold">Actividad {String(report.task_id)}</p><p className="mt-1 text-xs text-slate-500">Responsable: {responsibleName} · Registró: {recorderName}</p><p className="mt-1 text-xs text-slate-500">Realización declarada: {String(report.declared_completed_at)} · Registro efectivo: {String(report.recorded_at)}</p>{typeof report.evidence_path === "string" && <div className="mt-2">{evidenceUrl ? <a className="text-sm font-semibold text-amber-700 underline" href={evidenceUrl} target="_blank" rel="noreferrer">Abrir evidencia (enlace temporal)</a> : <button className="rounded-lg border px-3 py-2 text-xs font-semibold" onClick={() => void openEvidence()}>Cargar evidencia privada</button>}{evidenceError && <p role="alert" className="mt-1 text-xs text-rose-700">{evidenceError}</p>}</div>}<div className="mt-3 flex gap-2"><button className={primaryClass} disabled={busy} onClick={() => void run("review_task_report", { report_id: report.id, decision: "accepted" })}>Validar</button><button className={secondaryClass} disabled={busy} onClick={() => void run("review_task_report", { report_id: report.id, decision: "rejected" })}>Rechazar</button></div></article>;
}

function Metric({ label, value, icon }: { label: string; value: number; icon: React.ReactNode }) {
  return <div className="rounded-xl border border-stone-200 bg-white p-4 dark:border-slate-800 dark:bg-slate-900"><div className="flex items-center justify-between text-slate-500"><span className="text-sm">{label}</span>{icon}</div><p className="mt-2 text-3xl font-bold tabular-nums">{value}</p></div>;
}

function TaskRow({ task, receipt, canManage = false, onRequestNotice, busy = false }: {
  task: Task;
  receipt?: Row;
  canManage?: boolean;
  onRequestNotice?: () => void;
  busy?: boolean;
}) {
  const [clockNow, setClockNow] = useState(() => Date.now());
  const parts = task.parts ?? [];
  const escalationConfigured = receipt?.escalation_threshold_seconds != null;
  const assignedAt = Date.parse(String(receipt?.assignment_recorded_at ?? ""));
  const dueAt = escalationConfigured && Number.isFinite(assignedAt)
    ? assignedAt + Number(receipt?.escalation_threshold_seconds) * 1000 : null;
  useEffect(() => {
    if (receipt?.receipt_state !== "awaiting" || dueAt === null || dueAt <= clockNow) return;
    const timer = window.setTimeout(() => setClockNow(Date.now()), dueAt - clockNow);
    return () => window.clearTimeout(timer);
  }, [clockNow, dueAt, receipt?.receipt_state]);
  const escalationDue = receipt?.needs_escalation === true || (dueAt !== null && dueAt <= clockNow);
  const remainingSeconds = dueAt === null ? Number.NaN : Math.max(0, Math.ceil((dueAt - clockNow) / 1000));
  return <article className="py-4">
    <div className="flex flex-wrap items-start justify-between gap-3"><div><h3 className="font-semibold">{task.name}</h3><p className="mt-1 text-sm text-slate-500">{[task.area_name, `${task.estimated_minutes ?? 0} min`, statusLabels[task.status] ?? task.status].filter(Boolean).join(" · ")}</p>{task.status === "paused" && task.latest_pause_note && <p className="mt-2 text-sm text-amber-800 dark:text-amber-300">Motivo de pausa: {task.latest_pause_note}</p>}</div><span className={`rounded-full px-2.5 py-1 text-xs font-semibold ${task.status === "completed" ? "bg-emerald-50 text-emerald-700" : "bg-amber-50 text-amber-800"}`}>{task.configuration_pending ? "Config. pendiente" : task.assignee_name ?? (task.assigned_to ? "Asignada" : "Sin responsable")}</span></div>
    {parts.map((part) => <div key={String(part.id)} className="mt-2 rounded-lg bg-stone-50 px-3 py-2 text-sm dark:bg-slate-800"><p>{String(part.zone_name ?? "Zona")} · {String(part.assignee_name ?? "Sin responsable")} · {statusLabels[String(part.status)] ?? String(part.status)}</p>{part.status === "paused" && typeof part.latest_pause_note === "string" && <p className="mt-1 text-xs text-amber-800 dark:text-amber-300">Motivo de pausa: {part.latest_pause_note}</p>}</div>)}
    {receipt?.receipt_state === "awaiting" && canManage && <div className="mt-3 flex flex-wrap items-center gap-2"><span className="text-xs text-slate-500">Recepción aún no confirmada{escalationConfigured && !escalationDue && Number.isFinite(remainingSeconds) ? ` · aviso automático según política en ${remainingSeconds}s` : escalationDue ? " · plazo de recepción vencido" : ""}.</span>{onRequestNotice && <button className={secondaryClass} disabled={busy} onClick={onRequestNotice}>Solicitar aviso manual</button>}</div>}
  </article>;
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
