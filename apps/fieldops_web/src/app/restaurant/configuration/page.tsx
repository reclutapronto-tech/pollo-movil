"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { ArrowLeft, CalendarClock, CalendarDays, ChevronLeft, ChevronRight, ClipboardCheck, Copy, Plus, Save, Store } from "lucide-react";
import { callFunctionJson } from "@/lib/function-client";
import { mexicoTimeZones } from "@/lib/mexico-timezones";
import { preferredRestaurantBranchId, rememberRestaurantBranchId } from "@/lib/restaurant-branch-selection";
import { getSupabase } from "@/lib/supabase";

type Row = Record<string, unknown>;
type Branch = { id: string; name: string; timezone: string; access_role: string; enable_time_clock?: boolean; require_gps_for_time_clock?: boolean; assignment_load_balance_weight?: number; assignment_heavy_rotation_weight?: number; assignment_priority_weight?: number };
type Settings = {
  branch: Branch; areas: Row[]; positions: Row[]; members: Row[]; employees_available_to_add: Row[];
  users?: Row[]; templates: Row[]; templatePositions: Row[]; zones: Row[]; shifts: Row[]; breaks: Row[];
  bins: Row[]; absences: Row[]; waste_position_ids: string[]; inspection_templates: Row[]; scheduled_tasks: Row[];
};
type Section = "areas" | "team" | "activities" | "agenda" | "shifts" | "assignment" | "waste" | "inspections" | "features";

const dayNames = ["Lun", "Mar", "Mié", "Jue", "Vie", "Sáb", "Dom"];
const roleNames: Record<string, string> = { admin: "Administrador", supervisor: "Supervisor", employee: "Empleado" };
const inputClass = "min-h-11 w-full rounded-lg border border-stone-300 bg-white px-3 text-sm text-slate-900 outline-none focus:border-amber-500 focus:ring-2 focus:ring-amber-100 dark:border-slate-700 dark:bg-slate-950 dark:text-slate-100";
const buttonClass = "inline-flex min-h-10 items-center justify-center gap-2 rounded-lg bg-slate-900 px-4 text-sm font-semibold text-white hover:bg-slate-700 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-amber-400 dark:text-slate-950";
const panelClass = "rounded-2xl border border-stone-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900";

function todayInTimezone(timezone: string) {
  const parts = new Intl.DateTimeFormat("en-CA", { timeZone: timezone, year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}

function addDateDays(value: string, days: number) {
  const date = new Date(`${value}T12:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

function mondayForDate(value: string) {
  const weekday = new Date(`${value}T12:00:00.000Z`).getUTCDay();
  return addDateDays(value, -(weekday === 0 ? 6 : weekday - 1));
}

async function post(body: Record<string, unknown>) {
  return callFunctionJson<Record<string, unknown>>("restaurant_ops", {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
  });
}

export default function RestaurantConfigurationPage() {
  const [branches, setBranches] = useState<Branch[]>([]);
  const [branchId, setBranchId] = useState("");
  const [shiftWeekStart, setShiftWeekStart] = useState("");
  const [settings, setSettings] = useState<Settings | null>(null);
  const [section, setSection] = useState<Section>("areas");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [inviteLink, setInviteLink] = useState<string | null>(null);
  const selectedBranchTimezone = branches.find((item) => item.id === branchId)?.timezone ?? "";

  const loadSettings = useCallback(async (id = branchId, weekStart = shiftWeekStart) => {
    if (!id) return;
    setLoading(true);
    setError(null);
    try {
      const result = await callFunctionJson<Settings>("restaurant_ops", { query: { action: "settings", branch_id: id, ...(weekStart ? { week_start: weekStart } : {}) } });
      setSettings(result);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "No se pudo cargar la configuración.");
    } finally {
      setLoading(false);
    }
  }, [branchId, shiftWeekStart]);

  useEffect(() => {
    let cancelled = false;
    callFunctionJson<{ branches: Branch[] }>("restaurant_ops", { query: { action: "branches" } })
      .then(({ branches: rows }) => {
        if (cancelled) return;
        const managers = (rows ?? []).filter((item) => ["admin", "supervisor"].includes(item.access_role));
        setBranches(managers);
        const preferredId = preferredRestaurantBranchId(managers);
        setBranchId((current) => current && managers.some((item) => item.id === current) ? current : preferredId);
        if (!managers.length) setLoading(false);
      })
      .catch((cause: unknown) => {
        if (!cancelled) { setError(cause instanceof Error ? cause.message : "No se pudieron cargar las sucursales."); setLoading(false); }
      });
    return () => { cancelled = true; };
  }, []);

  useEffect(() => {
    setInviteLink(null);
    if (selectedBranchTimezone) setShiftWeekStart(mondayForDate(todayInTimezone(selectedBranchTimezone)));
  }, [branchId, selectedBranchTimezone]);

  useEffect(() => { if (branchId && shiftWeekStart) void loadSettings(branchId, shiftWeekStart); }, [branchId, shiftWeekStart, loadSettings]);

  useEffect(() => {
    if (!branchId) return;
    const supabase = getSupabase();
    let refreshTimer: number | undefined;
    const refresh = () => {
      if (refreshTimer !== undefined) window.clearTimeout(refreshTimer);
      refreshTimer = window.setTimeout(() => void loadSettings(branchId, shiftWeekStart), 200);
    };
    const channel = supabase
      .channel(`pollo-configuration-${branchId}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_branches", filter: `id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_areas", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_positions", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_memberships", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_shifts", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_shift_breaks", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_activity_templates", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_activity_positions", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_activity_zones", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_waste_bins", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_waste_positions", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_inspection_templates", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_inspection_items", filter: `branch_id=eq.${branchId}` }, refresh)
      .subscribe();
    return () => {
      if (refreshTimer !== undefined) window.clearTimeout(refreshTimer);
      void supabase.removeChannel(channel);
    };
  }, [branchId, loadSettings, shiftWeekStart]);

  const perform = async (action: string, values: Record<string, unknown>, message = "Configuración guardada.") => {
    if (!branchId || busy) return;
    setBusy(true); setError(null); setNotice(null); setInviteLink(null);
    try {
      const result = await post({ action, branch_id: branchId, ...values });
      const resultMessage = action === "invite_member"
        ? result.already_member === true
          ? "Esta persona ya forma parte de la sucursal."
          : result.existing_account === true
          ? "La cuenta existente se incorporó a la sucursal."
          : result.email_sent === true
          ? "Invitación enviada al correo indicado."
          : "Invitación preparada. Comparte el enlace de acceso de forma segura."
        : message;
      if (action === "invite_member") {
        setInviteLink(typeof result.invite_link === "string" ? result.invite_link : null);
      }
      if (action === "save_branch_features") {
        setBranches((current) => current.map((branch) => branch.id === branchId
          ? { ...branch,
              ...(typeof result.name === "string" ? { name: result.name } : {}),
              ...(typeof result.timezone === "string" ? { timezone: result.timezone } : {}),
            } : branch));
      }
      setNotice(action === "schedule_tasks"
        ? `${Number(result.created_count ?? 0)} actividades nuevas programadas para la fecha seleccionada.`
        : resultMessage);
      await loadSettings(branchId);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "No se pudo guardar la configuración.");
    } finally { setBusy(false); }
  };

  if (!loading && branches.length === 0) return <main className="mx-auto max-w-4xl py-12"><section className={panelClass}><h1 className="text-2xl font-bold">Configuración de sucursal</h1><p className="mt-3 text-sm text-slate-500">No tienes permisos de administrador o supervisor en una sucursal de Pollo Móvil.</p><Link href="/restaurant" className="mt-5 inline-flex text-sm font-semibold text-amber-700">Volver a operación</Link></section></main>;

  const sections: { key: Section; label: string }[] = [
    { key: "areas", label: "Áreas y puestos" }, { key: "team", label: "Equipo y elegibilidad" },
    { key: "activities", label: "Actividades" }, { key: "agenda", label: "Agenda" }, { key: "shifts", label: "Horarios" }, { key: "assignment", label: "Asignación automática" }, { key: "waste", label: "Botes" }, { key: "inspections", label: "Inspecciones" }, { key: "features", label: "Funciones opcionales" },
  ];
  return (
    <main className="mx-auto max-w-7xl pb-12">
      <header className="flex flex-col gap-4 border-b border-stone-200 pb-5 dark:border-slate-800 sm:flex-row sm:items-end sm:justify-between">
        <div><Link href="/restaurant" className="inline-flex items-center gap-1 text-sm font-semibold text-amber-700"><ArrowLeft size={16} /> Volver al turno</Link><h1 className="mt-3 text-3xl font-bold tracking-tight">Configuración de sucursal</h1><p className="mt-1 text-sm text-slate-500">Define las reglas reales una vez. No se asigna ninguna actividad sin puestos elegibles.</p></div>
        <label className="min-w-56 text-xs font-semibold text-slate-500">Sucursal<select aria-label="Sucursal" className={`${inputClass} mt-1`} value={branchId} onChange={(event) => { rememberRestaurantBranchId(event.target.value); setBranchId(event.target.value); }}>{branches.map((branch) => <option value={branch.id} key={branch.id}>{branch.name}</option>)}</select></label>
      </header>
      {(error || notice) && <div role="status" className={`mt-5 rounded-xl border px-4 py-3 text-sm ${error ? "border-rose-200 bg-rose-50 text-rose-700" : "border-emerald-200 bg-emerald-50 text-emerald-800"}`}>
        {error ?? notice}
        {inviteLink && !error && <div className="mt-2 flex flex-wrap items-center gap-3">
          <a className="break-all font-medium underline" href={inviteLink} target="_blank" rel="noreferrer">Abrir enlace de invitación</a>
          <button type="button" className="inline-flex min-h-9 items-center gap-1 rounded-lg border border-current px-3 font-semibold" onClick={() => void navigator.clipboard.writeText(inviteLink).then(() => setNotice("Enlace de invitación copiado.")).catch(() => setNotice("No se pudo copiar automáticamente; abre el enlace y cópialo desde el navegador."))}><Copy size={14} />Copiar enlace</button>
        </div>}
      </div>}
      <nav aria-label="Secciones de configuración" className="mt-6 flex gap-2 overflow-x-auto pb-2">{sections.map((item) => <button key={item.key} aria-pressed={section === item.key} className={`min-h-10 shrink-0 rounded-full px-4 text-sm font-semibold ${section === item.key ? "bg-slate-900 text-white dark:bg-amber-400 dark:text-slate-950" : "border border-stone-200 bg-white text-slate-600 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-300"}`} onClick={() => setSection(item.key)}>{item.label}</button>)}</nav>
      {loading || !settings ? <div role="status" className={`${panelClass} mt-4`}>Cargando configuración…</div> : <div className="mt-4">{section === "areas" && <AreasPanel settings={settings} busy={busy} onSave={perform} />}{section === "team" && <TeamPanel settings={settings} busy={busy} onSave={perform} />}{section === "activities" && <ActivitiesPanel settings={settings} busy={busy} onSave={perform} />}{section === "agenda" && <AgendaPanel settings={settings} busy={busy} weekStart={shiftWeekStart} onWeekChange={setShiftWeekStart} onSave={perform} />}{section === "shifts" && <ShiftsPanel settings={settings} busy={busy} weekStart={shiftWeekStart} onWeekChange={setShiftWeekStart} onSave={perform} />}{section === "assignment" && <AssignmentPolicyPanel settings={settings} busy={busy} onSave={perform} />}{section === "waste" && <WastePanel settings={settings} busy={busy} onSave={perform} />}{section === "inspections" && <InspectionsPanel settings={settings} busy={busy} onSave={perform} />}{section === "features" && <FeaturesPanel settings={settings} busy={busy} onSave={perform} />}</div>}
    </main>
  );
}

function AreasPanel({ settings, busy, onSave }: { settings: Settings; busy: boolean; onSave: (action: string, values: Record<string, unknown>) => Promise<void> }) {
  const [areaId, setAreaId] = useState(""); const [area, setArea] = useState("");
  const [positionId, setPositionId] = useState(""); const [position, setPosition] = useState("");
  const selectArea = (item: Row) => { setAreaId(String(item.id)); setArea(String(item.name)); };
  const selectPosition = (item: Row) => { setPositionId(String(item.id)); setPosition(String(item.name)); };
  return <div className="grid gap-5 xl:grid-cols-2">
    <section className={panelClass}>
      <h2 className="text-lg font-semibold">Áreas físicas</h2><p className="mt-1 text-sm text-slate-500">Referencias del material compartido; la sucursal puede ajustar nombres.</p>
      <div className="mt-4 space-y-2">{settings.areas.map((item) => <button key={String(item.id)} aria-pressed={areaId === item.id} onClick={() => selectArea(item)} className={`w-full rounded-lg px-3 py-2 text-left text-sm ${areaId === item.id ? "bg-amber-50 dark:bg-amber-950/30" : "bg-stone-50 dark:bg-slate-800"}`}>{String(item.name)}</button>)}</div>
      <div className="mt-4 flex gap-2"><input aria-label="Nombre del área" className={inputClass} value={area} onChange={(event) => setArea(event.target.value)} placeholder="Nombre del área" /><button className={buttonClass} disabled={busy || area.trim().length < 2} onClick={() => void onSave("save_area", { ...(areaId ? { id: areaId } : {}), name: area.trim() }).then(() => { setArea(""); setAreaId(""); })}>{areaId ? <Save size={16} /> : <Plus size={16} />}{areaId ? "Guardar" : "Agregar"}</button></div>
    </section>
    <section className={panelClass}>
      <h2 className="text-lg font-semibold">Puestos laborales</h2><p className="mt-1 text-sm text-slate-500">Describen elegibilidad operativa, no permisos administrativos.</p>
      <div className="mt-4 space-y-2">{settings.positions.map((item) => <button key={String(item.id)} aria-pressed={positionId === item.id} onClick={() => selectPosition(item)} className={`w-full rounded-lg px-3 py-2 text-left text-sm ${positionId === item.id ? "bg-amber-50 dark:bg-amber-950/30" : "bg-stone-50 dark:bg-slate-800"}`}>{String(item.name)}</button>)}</div>
      <div className="mt-4 flex gap-2"><input aria-label="Nombre del puesto" className={inputClass} value={position} onChange={(event) => setPosition(event.target.value)} placeholder="Nombre del puesto" /><button className={buttonClass} disabled={busy || position.trim().length < 2} onClick={() => void onSave("save_position", { ...(positionId ? { id: positionId } : {}), name: position.trim() }).then(() => { setPosition(""); setPositionId(""); })}>{positionId ? <Save size={16} /> : <Plus size={16} />}{positionId ? "Guardar" : "Agregar"}</button></div>
    </section>
  </div>;
}

function TeamPanel({ settings, busy, onSave }: { settings: Settings; busy: boolean; onSave: (action: string, values: Record<string, unknown>, message?: string) => Promise<void> }) {
  const [newUser, setNewUser] = useState(""); const [newRole, setNewRole] = useState("employee");
  const [inviteName, setInviteName] = useState(""); const [inviteEmail, setInviteEmail] = useState("");
  const [memberId, setMemberId] = useState(""); const [role, setRole] = useState("employee"); const [positionIds, setPositionIds] = useState<string[]>([]);
  const members = useMemo(() => settings.members ?? [], [settings.members]);
  const selected = members.find((member) => member.user_id === memberId) ?? members[0];
  const activeId = memberId || String(selected?.user_id ?? "");
  const currentPositions = useMemo(() => activeId ? settings.members.find((row) => row.user_id === activeId)?.position_ids as string[] ?? [] : [], [activeId, settings.members]);
  useEffect(() => { if (selected && (!memberId || !members.some((member) => member.user_id === memberId))) { setMemberId(String(selected.user_id)); setRole(String(selected.access_role)); setPositionIds(currentPositions); } }, [memberId, members, selected, currentPositions]);
  const chooseMember = (id: string) => { setMemberId(id); const member = members.find((item) => item.user_id === id); setRole(String(member?.access_role ?? "employee")); setPositionIds((member?.position_ids as string[] | undefined) ?? []); };
  const togglePosition = (id: string) => setPositionIds((old) => old.includes(id) ? old.filter((item) => item !== id) : [...old, id]);
  return <div className="grid gap-5 xl:grid-cols-2"><section className={panelClass}><h2 className="text-lg font-semibold">Agregar cuenta existente</h2><p className="mt-1 text-sm text-slate-500">Solo cuentas activas de esta empresa pueden incorporarse.</p><div className="mt-4 grid gap-3 sm:grid-cols-[1fr_180px_auto]"><select aria-label="Cuenta" className={inputClass} value={newUser} onChange={(event) => setNewUser(event.target.value)}><option value="">Elige una cuenta</option>{settings.employees_available_to_add.map((item) => <option key={String(item.id)} value={String(item.id)}>{String(item.full_name ?? item.email ?? item.id)}</option>)}</select><select aria-label="Permiso administrativo" className={inputClass} value={newRole} onChange={(event) => setNewRole(event.target.value)}><option value="employee">Empleado</option><option value="supervisor">Supervisor</option><option value="admin">Administrador</option></select><button className={buttonClass} disabled={busy || !newUser} onClick={() => { void onSave("save_member", { user_id: newUser, access_role: newRole }).then(() => setNewUser("")); }}>Agregar</button></div><div className="mt-6 border-t border-stone-200 pt-5 dark:border-slate-700"><h3 className="font-semibold">Invitar persona nueva</h3><p className="mt-1 text-sm text-slate-500">La invitación crea una cuenta de empleado y la incorpora a esta sucursal. El rol administrativo se configura después.</p><div className="mt-3 grid gap-3"><label className="text-sm font-medium">Nombre completo<input className={`${inputClass} mt-1`} value={inviteName} onChange={(event) => setInviteName(event.target.value)} maxLength={120} autoComplete="name" /></label><label className="text-sm font-medium">Correo electrónico<input className={`${inputClass} mt-1`} type="email" value={inviteEmail} onChange={(event) => setInviteEmail(event.target.value)} maxLength={254} autoComplete="email" /></label><button type="button" className={buttonClass} disabled={busy || inviteName.trim().length < 2 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(inviteEmail.trim())} onClick={() => void onSave("invite_member", { full_name: inviteName.trim(), email: inviteEmail.trim() })}>Enviar invitación</button></div></div><div className="mt-6"><h3 className="font-semibold">Personal de la sucursal</h3><div className="mt-3 divide-y divide-stone-100 dark:divide-slate-800">{members.map((member) => <div key={String(member.user_id)} className="flex items-center justify-between gap-3 py-3 text-sm"><div className="min-w-0"><span className="block truncate">{String((member.user as Row | null)?.full_name ?? (member.user as Row | null)?.email ?? member.user_id)}</span><span className="text-xs text-slate-500">{roleNames[String(member.access_role)] ?? String(member.access_role)}</span></div><button type="button" className="min-h-9 shrink-0 rounded-lg border border-stone-300 px-3 text-xs font-semibold text-slate-700 hover:bg-stone-50 disabled:opacity-50 dark:border-slate-700 dark:text-slate-200 dark:hover:bg-slate-800" disabled={busy} onClick={() => { const name = String((member.user as Row | null)?.full_name ?? (member.user as Row | null)?.email ?? member.user_id); if (window.confirm(`Desactivar a ${name} en esta sucursal? El historial se conserva; las actividades pendientes se liberan para la próxima asignación automática, mientras que las actividades en curso y los turnos ya programados permanecen.`)) void onSave("set_member_active", { user_id: member.user_id, is_active: false }, "Acceso a la sucursal desactivado."); }}>Desactivar</button></div>)}</div></div></section><section className={panelClass}><h2 className="text-lg font-semibold">Elegibilidad por puesto</h2><p className="mt-1 text-sm text-slate-500">Una persona puede tener varios puestos; servicio al cliente no la excluye de tareas compatibles.</p><select aria-label="Empleado para configurar puestos" className={`${inputClass} mt-4`} value={activeId} onChange={(event) => chooseMember(event.target.value)}><option value="">Elige una persona</option>{members.map((member) => <option key={String(member.user_id)} value={String(member.user_id)}>{String((member.user as Row | null)?.full_name ?? (member.user as Row | null)?.email ?? member.user_id)}</option>)}</select>{selected && <><label className="mt-4 block text-sm font-medium">Permiso en la sucursal<select className={`${inputClass} mt-1`} value={role} onChange={(event) => setRole(event.target.value)}><option value="employee">Empleado</option><option value="supervisor">Supervisor</option><option value="admin">Administrador</option></select></label><div className="mt-4 space-y-2">{settings.positions.map((position) => <label key={String(position.id)} className="flex items-center gap-3 rounded-lg bg-stone-50 px-3 py-2.5 text-sm dark:bg-slate-800"><input type="checkbox" checked={positionIds.includes(String(position.id))} onChange={() => togglePosition(String(position.id))} />{String(position.name)}</label>)}</div><button className={`${buttonClass} mt-4`} disabled={busy} onClick={() => void onSave("save_member", { user_id: activeId, access_role: role }).then(() => onSave("save_member_positions", { user_id: activeId, position_ids: positionIds }))}><Save size={16} /> Guardar permisos y puestos</button></>}</section></div>;
}

function ActivitiesPanel({ settings, busy, onSave }: { settings: Settings; busy: boolean; onSave: (action: string, values: Record<string, unknown>) => Promise<void> }) {
  const [templateId, setTemplateId] = useState(""); const [name, setName] = useState(""); const [description, setDescription] = useState(""); const [type, setType] = useState("scheduled"); const [areaId, setAreaId] = useState("");
  const [days, setDays] = useState<number[]>([]); const [minutes, setMinutes] = useState(""); const [difficulty, setDifficulty] = useState(""); const [priority, setPriority] = useState("");
  const [positionIds, setPositionIds] = useState<string[]>([]); const [divisible, setDivisible] = useState(false); const [interruptible, setInterruptible] = useState(true); const [evidence, setEvidence] = useState(false); const [isActive, setIsActive] = useState(true); const [zones, setZones] = useState("");
  const loadTemplate = (id: string) => {
    setTemplateId(id);
    const row = settings.templates.find((item) => item.id === id);
    if (!row) {
      setName(""); setDescription(""); setType("scheduled"); setAreaId(""); setDays([]);
      setMinutes(""); setDifficulty(""); setPriority(""); setPositionIds([]);
      setZones(""); setDivisible(false); setInterruptible(true); setEvidence(false); setIsActive(true);
      return;
    }
    setName(String(row.name ?? "")); setDescription(String(row.description ?? ""));
    setType(String(row.activity_type ?? "scheduled")); setAreaId(String(row.area_id ?? ""));
    setDays((row.schedule_days as number[]) ?? []);
    setMinutes(row.estimated_minutes == null ? "" : String(row.estimated_minutes));
    setDifficulty(row.difficulty == null ? "" : String(row.difficulty));
    setPriority(row.priority == null ? "" : String(row.priority));
    setPositionIds(settings.templatePositions.filter((item) => item.activity_template_id === id).map((item) => String(item.position_id)));
    setDivisible(row.is_divisible === true); setInterruptible(row.interruptible !== false);
    setEvidence(row.requires_evidence === true); setIsActive(row.is_active === true);
    setZones(settings.zones.filter((item) => item.activity_template_id === id).map((item) => String(item.name)).join("\n"));
  };
  const toggleDay = (day: number) => setDays((old) => old.includes(day) ? old.filter((item) => item !== day) : [...old, day].sort((a, b) => a - b));
  const togglePosition = (id: string) => setPositionIds((old) => old.includes(id) ? old.filter((item) => item !== id) : [...old, id]);
  const estimatedMinutes = Number(minutes); const taskDifficulty = Number(difficulty); const taskPriority = Number(priority);
  const estimatesValid = Number.isInteger(estimatedMinutes) && estimatedMinutes >= 1 && estimatedMinutes <= 1440
    && Number.isInteger(taskDifficulty) && taskDifficulty >= 1 && taskDifficulty <= 5
    && Number.isInteger(taskPriority) && taskPriority >= 1 && taskPriority <= 5;
  const save = () => {
    const zoneNames = zones.split("\n").map((item) => item.trim()).filter(Boolean);
    const baseZoneMinutes = zoneNames.length ? Math.floor(estimatedMinutes / zoneNames.length) : 0;
    const extraZoneMinutes = zoneNames.length ? estimatedMinutes % zoneNames.length : 0;
    const cleanZones = zoneNames.map((zone, index) => ({
      name: zone,
      estimated_minutes: baseZoneMinutes + (index < extraZoneMinutes ? 1 : 0),
      difficulty: taskDifficulty,
      sort_order: index,
    }));
    void onSave("save_template", { ...(templateId ? { id: templateId } : {}), name, description, activity_type: type, area_id: areaId || null, schedule_days: days, estimated_minutes: estimatedMinutes, difficulty: taskDifficulty, priority: taskPriority, is_divisible: divisible, interruptible, requires_evidence: evidence, is_active: isActive, position_ids: positionIds, zones: cleanZones });
  };
  return <div className="grid gap-5 xl:grid-cols-[minmax(300px,0.8fr)_minmax(0,1.2fr)]"><section className={panelClass}><h2 className="text-lg font-semibold">Plantillas configuradas</h2><p className="mt-1 text-sm text-slate-500">Programar crea instancias idempotentes; completar es un evento distinto.</p><button className={`${buttonClass} mt-4`} onClick={() => loadTemplate("")}><Plus size={16} /> Nueva actividad</button><div className="mt-3 space-y-2">{settings.templates.map((item) => <button key={String(item.id)} className={`w-full rounded-lg border px-3 py-3 text-left text-sm ${templateId === item.id ? "border-amber-500 bg-amber-50 dark:bg-amber-950/30" : "border-stone-200 dark:border-slate-700"}`} onClick={() => loadTemplate(String(item.id))}><span className="font-semibold">{String(item.name)}</span><span className="mt-1 block text-xs text-slate-500">{String(item.activity_type)} · {String(item.estimated_minutes)} min · prioridad {String(item.priority)}{item.is_active === true ? " · Activa" : " · Inactiva"}</span></button>)}</div></section><section className={panelClass}><h2 className="text-lg font-semibold">{templateId ? "Editar actividad" : "Nueva actividad"}</h2><div className="mt-4 grid gap-3 sm:grid-cols-2"><label className="text-sm">Nombre<input className={`${inputClass} mt-1`} value={name} onChange={(event) => setName(event.target.value)} maxLength={120} /></label><label className="text-sm">Tipo<select className={`${inputClass} mt-1`} value={type} onChange={(event) => setType(event.target.value)}><option value="scheduled">Programada</option><option value="conditional">Condicional</option><option value="corrective">Correctiva</option></select></label><label className="text-sm">Área<select className={`${inputClass} mt-1`} value={areaId} onChange={(event) => setAreaId(event.target.value)}><option value="">Sin área</option>{settings.areas.map((item) => <option key={String(item.id)} value={String(item.id)}>{String(item.name)}</option>)}</select></label><label className="text-sm">Duración estimada (min)<input className={`${inputClass} mt-1`} type="number" min={1} max={1440} value={minutes} onChange={(event) => setMinutes(event.target.value)} /></label><label className="text-sm">Dificultad (1–5)<input className={`${inputClass} mt-1`} type="number" min={1} max={5} value={difficulty} onChange={(event) => setDifficulty(event.target.value)} /></label><label className="text-sm">Prioridad (1–5)<input className={`${inputClass} mt-1`} type="number" min={1} max={5} value={priority} onChange={(event) => setPriority(event.target.value)} /></label></div><label className="mt-3 block text-sm">Descripción<textarea className={`${inputClass} mt-1`} value={description} onChange={(event) => setDescription(event.target.value)} rows={2} maxLength={1000} /></label>{type === "scheduled" && <fieldset className="mt-4"><legend className="text-sm font-medium">Días programados (lunes a domingo)</legend><div className="mt-2 flex flex-wrap gap-2">{dayNames.map((day, index) => <label key={day} className="flex items-center gap-1 rounded-lg bg-stone-50 px-2.5 py-2 text-sm dark:bg-slate-800"><input type="checkbox" checked={days.includes(index + 1)} onChange={() => toggleDay(index + 1)} />{day}</label>)}</div></fieldset>}<fieldset className="mt-4"><legend className="text-sm font-medium">Puestos habilitados</legend><div className="mt-2 grid gap-2 sm:grid-cols-2">{settings.positions.map((position) => <label key={String(position.id)} className="flex items-center gap-2 rounded-lg bg-stone-50 px-3 py-2 text-sm dark:bg-slate-800"><input type="checkbox" checked={positionIds.includes(String(position.id))} onChange={() => togglePosition(String(position.id))} />{String(position.name)}</label>)}</div>{positionIds.length === 0 && <p className="mt-2 text-xs text-amber-700">Sin puestos: quedará marcada pendiente de configuración y no se asignará.</p>}</fieldset><div className="mt-4 grid gap-2 sm:grid-cols-2"><label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={divisible} onChange={(event) => setDivisible(event.target.checked)} />Dividir por zonas</label><label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={interruptible} onChange={(event) => setInterruptible(event.target.checked)} />Interrumpible ante servicio</label><label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={evidence} onChange={(event) => setEvidence(event.target.checked)} />Solicitar evidencia</label><label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={isActive} onChange={(event) => setIsActive(event.target.checked)} />Activa para programar</label></div>{divisible && <label className="mt-4 block text-sm">Una zona por renglón (se reparte la duración configurada)<textarea className={`${inputClass} mt-1`} rows={3} value={zones} onChange={(event) => setZones(event.target.value)} placeholder="Escribe cada zona real de esta sucursal, una por renglón" /></label>}{divisible && zones.split("\n").filter((item) => item.trim()).length > estimatedMinutes && <p className="mt-1 text-xs text-rose-700">La duración debe alcanzar al menos un minuto por zona.</p>}<button className={`${buttonClass} mt-5`} disabled={busy || name.trim().length < 2 || !estimatesValid || (type === "scheduled" && !days.length) || (divisible && (!zones.trim() || zones.split("\n").filter((item) => item.trim()).length > estimatedMinutes))} onClick={save}><Save size={16} /> Guardar actividad</button>{templateId && type !== "scheduled" && <button className="ml-2 mt-5 min-h-10 rounded-lg border border-stone-300 px-4 text-sm font-semibold hover:bg-stone-50 disabled:opacity-50 dark:border-slate-700 dark:hover:bg-slate-800" disabled={busy || !isActive} onClick={() => void onSave("create_task", { template_id: templateId, client_event_id: crypto.randomUUID() })}>Crear tarea hoy</button>}</section></div>;
}

function AgendaPanel({ settings, busy, weekStart, onWeekChange, onSave }: { settings: Settings; busy: boolean; weekStart: string; onWeekChange: (value: string) => void; onSave: (action: string, values: Record<string, unknown>, message?: string) => Promise<void> }) {
  const [targetDate, setTargetDate] = useState(weekStart);
  const [templateId, setTemplateId] = useState("");
  const weekEnd = addDateDays(weekStart, 6);
  const today = todayInTimezone(settings.branch.timezone);
  const weekIsPast = weekEnd < today;
  const earliestDate = weekStart < today ? today : weekStart;
  useEffect(() => {
    setTargetDate(weekIsPast ? weekStart : earliestDate);
  }, [earliestDate, weekIsPast, weekStart]);
  const weekDates = Array.from({ length: 7 }, (_, index) => addDateDays(weekStart, index));
  const dayLabel = (value: string) => new Intl.DateTimeFormat("es-MX", {
    weekday: "long", day: "2-digit", month: "short", timeZone: "UTC",
  }).format(new Date(`${value}T12:00:00.000Z`));
  const moveWeek = (offset: number) => onWeekChange(addDateDays(weekStart, offset * 7));
  const selectedTemplate = settings.templates.find((item) => item.id === templateId && item.is_active === true);
  return <div className="space-y-5">
    <section className={panelClass}>
      <div className="flex flex-wrap items-start justify-between gap-3"><div><h2 className="flex items-center gap-2 text-lg font-semibold"><CalendarClock size={19} className="text-amber-600" />Agenda semanal de actividades</h2><p className="mt-1 text-sm text-slate-500">Las actividades programadas se materializan según los días configurados. La creación es idempotente por sucursal, plantilla y fecha.</p></div><div className="flex items-center gap-2"><button type="button" aria-label="Semana anterior" className="min-h-10 rounded-lg border border-stone-200 px-3 dark:border-slate-700" onClick={() => moveWeek(-1)}><ChevronLeft size={18} /></button><span className="min-w-48 text-center text-sm font-medium">{dayLabel(weekStart)} – {dayLabel(addDateDays(weekStart, 6))}</span><button type="button" aria-label="Semana siguiente" className="min-h-10 rounded-lg border border-stone-200 px-3 dark:border-slate-700" onClick={() => moveWeek(1)}><ChevronRight size={18} /></button></div></div>
      <p className="mt-2 text-xs text-slate-500">La agenda solo crea actividades desde hoy en adelante; las fechas pasadas se conservan como historial.</p>
      <div className="mt-5 grid gap-3 sm:grid-cols-[minmax(180px,1fr)_minmax(240px,1.4fr)_auto_auto] sm:items-end">
        <label className="text-sm">Fecha para planificar<input className={`${inputClass} mt-1`} type="date" min={earliestDate} max={weekEnd} disabled={weekIsPast} value={targetDate} onChange={(event) => setTargetDate(event.target.value)} /></label>
        <label className="text-sm">Tarea puntual desde actividad configurada<select className={`${inputClass} mt-1`} value={templateId} onChange={(event) => setTemplateId(event.target.value)}><option value="">Selecciona actividad</option>{settings.templates.filter((item) => item.is_active === true).map((item) => <option key={String(item.id)} value={String(item.id)}>{String(item.name)} · {String(item.activity_type)}</option>)}</select></label>
        <button className={buttonClass} disabled={busy || !targetDate || targetDate < today || weekIsPast} onClick={() => void onSave("schedule_tasks", { for_date: targetDate }, "Agenda del día actualizada.")}><CalendarDays size={16} />Programar día</button>
        <button className={buttonClass} disabled={busy || !targetDate || targetDate < today || weekIsPast || !selectedTemplate} onClick={() => selectedTemplate && void onSave("create_task", { template_id: templateId, scheduled_for: targetDate, client_event_id: crypto.randomUUID() }, "Tarea puntual creada en la agenda.")}><Plus size={16} />Crear tarea</button>
      </div>
    </section>
    <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
      {weekDates.map((day) => {
        const tasks = settings.scheduled_tasks.filter((task) => String(task.scheduled_for) === day);
        return <section key={day} className={panelClass}>
          <h3 className="font-semibold capitalize">{dayLabel(day)}</h3>
          <p className="mt-1 text-xs text-slate-500">{tasks.length} {tasks.length === 1 ? "actividad" : "actividades"}</p>
          <div className="mt-3 space-y-2">{tasks.length ? tasks.map((task) => <article key={String(task.id)} className="rounded-lg border border-stone-200 p-3 text-sm dark:border-slate-700">
            <p className="font-semibold">{String(task.name)}</p>
            <p className="mt-1 text-xs text-slate-500">{String(task.area_name ?? "Sin área")} · {String(task.estimated_minutes ?? "—")} min · {String(task.status)}</p>
            <p className="mt-1 text-xs text-slate-500">{task.assigned_name ? `Responsable: ${String(task.assigned_name)}` : "Sin asignar"} · {String(task.task_source ?? "programada")}</p>
          </article>) : <p className="rounded-lg bg-stone-50 px-3 py-4 text-center text-sm text-slate-400 dark:bg-slate-800">Sin actividades materializadas.</p>}</div>
        </section>;
      })}
    </div>
  </div>;
}

function ShiftsPanel({ settings, busy, weekStart, onWeekChange, onSave }: { settings: Settings; busy: boolean; weekStart: string; onWeekChange: (value: string) => void; onSave: (action: string, values: Record<string, unknown>, message?: string) => Promise<void> }) {
  const [employee, setEmployee] = useState(""); const [date, setDate] = useState(() => todayInTimezone(settings.branch.timezone)); const [start, setStart] = useState(""); const [end, setEnd] = useState(""); const [breaks, setBreaks] = useState<Array<{ start_time: string; end_time: string }>>([]); const [published, setPublished] = useState(false); const [selectedShiftId, setSelectedShiftId] = useState("");
  const [absenceEmployee, setAbsenceEmployee] = useState(""); const [absenceStart, setAbsenceStart] = useState(""); const [absenceEnd, setAbsenceEnd] = useState(""); const [absenceStatus, setAbsenceStatus] = useState("pending"); const [absenceNote, setAbsenceNote] = useState("");
  useEffect(() => setDate(todayInTimezone(settings.branch.timezone)), [settings.branch.timezone]);
  useEffect(() => { setAbsenceStart(""); setAbsenceEnd(""); }, [settings.branch.timezone]);
  const nameFor = (userId: unknown) => {
    const member = settings.members.find((item) => item.user_id === userId);
    const user = (member?.user as Row | null) ?? settings.users?.find((item) => item.id === userId) ?? null;
    return String(user?.full_name ?? user?.email ?? userId ?? "Persona");
  };
  const weekDates = Array.from({ length: 7 }, (_, index) => addDateDays(weekStart, index));
  const weekEnd = weekDates[6] ?? weekStart;
  const weekShifts = settings.shifts.filter((shift) => {
    const shiftDate = String(shift.shift_date ?? "");
    return shiftDate >= weekStart && shiftDate <= weekEnd && shift.status !== "cancelled";
  });
  const publishedWeekShifts = weekShifts.filter((shift) => shift.status === "published");
  const publishedEmployeeCount = new Set(
    publishedWeekShifts.map((shift) => String(shift.employee_id ?? "")).filter(Boolean),
  ).size;
  const draftWeekShifts = weekShifts.filter((shift) => shift.status === "draft");
  const pendingWeekAbsences = settings.absences.filter((absence) =>
    absence.status === "pending"
    && String(absence.start_date ?? "") <= weekEnd
    && String(absence.end_date ?? "") >= weekStart,
  );
  const clearShiftEditor = () => {
    setSelectedShiftId(""); setEmployee(""); setDate(weekStart); setStart(""); setEnd(""); setBreaks([]); setPublished(false);
  };
  const editShift = (shift: Row) => {
    const shiftId = String(shift.id);
    const shiftDate = String(shift.shift_date);
    const shiftBreaks = settings.breaks.filter((item) => String(item.shift_id) === shiftId);
    setSelectedShiftId(shiftId);
    setEmployee(String(shift.employee_id));
    setDate(shiftDate);
    setStart(String(shift.start_time).slice(0, 5));
    setEnd(String(shift.end_time).slice(0, 5));
    setBreaks(shiftBreaks.map((item) => ({ start_time: String(item.start_time).slice(0, 5), end_time: String(item.end_time).slice(0, 5) })));
    setPublished(shift.status === "published");
    onWeekChange(mondayForDate(shiftDate));
  };
  const moveWeek = (offset: number) => {
    const next = addDateDays(weekStart, offset * 7);
    onWeekChange(next);
    setDate(next);
  };
  const dayLabel = (value: string) => new Intl.DateTimeFormat("es-MX", {
    weekday: "short", day: "2-digit", month: "short", timeZone: "UTC",
  }).format(new Date(`${value}T12:00:00.000Z`));
  return <div className="space-y-5">
    <section className={panelClass}>
      <h2 className="text-lg font-semibold">Turnos y descansos</h2>
      <p className="mt-1 text-sm text-slate-500">Hora local: {String(settings.branch.timezone)}. Los descansos excluyen candidatos durante ese intervalo; no se aceptan turnos traslapados para la misma persona.</p>
      <p className="mt-2 text-xs text-slate-500">Al editar un turno publicado puedes reasignarlo a otra persona o cambiar su horario; el turno anterior se retira y se notifica el nuevo a quien quede asignado.</p>
      <div className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <label className="text-sm">Empleado<select className={`${inputClass} mt-1`} value={employee} onChange={(event) => setEmployee(event.target.value)}><option value="">Selecciona</option>{settings.members.filter((item) => item.access_role === "employee").map((item) => <option key={String(item.user_id)} value={String(item.user_id)}>{nameFor(item.user_id)}</option>)}</select></label>
        <label className="text-sm">Fecha<input className={`${inputClass} mt-1`} type="date" value={date} onChange={(event) => setDate(event.target.value)} /></label>
        <label className="text-sm">Entrada<input className={`${inputClass} mt-1`} type="time" value={start} onChange={(event) => setStart(event.target.value)} /></label>
        <label className="text-sm">Salida<input className={`${inputClass} mt-1`} type="time" value={end} onChange={(event) => setEnd(event.target.value)} /></label>
      </div>
      <div className="mt-4 rounded-xl border border-stone-200 p-3 dark:border-slate-700">
        <div className="flex flex-wrap items-center justify-between gap-2"><p className="text-sm font-semibold">Descansos configurados: {breaks.length}</p><button type="button" className="min-h-9 rounded-lg border border-stone-300 px-3 text-sm disabled:opacity-50 dark:border-slate-600" disabled={busy || breaks.length >= 8} onClick={() => setBreaks((current) => [...current, { start_time: "", end_time: "" }])}>Agregar descanso</button></div>
        {breaks.map((item, index) => <div key={index} className="mt-3 grid gap-3 sm:grid-cols-[1fr_1fr_auto] sm:items-end">
          <label className="text-sm">Inicio<input className={`${inputClass} mt-1`} type="time" value={item.start_time} onChange={(event) => setBreaks((current) => current.map((value, rowIndex) => rowIndex === index ? { ...value, start_time: event.target.value } : value))} /></label>
          <label className="text-sm">Fin<input className={`${inputClass} mt-1`} type="time" value={item.end_time} onChange={(event) => setBreaks((current) => current.map((value, rowIndex) => rowIndex === index ? { ...value, end_time: event.target.value } : value))} /></label>
          <button type="button" className="min-h-10 rounded-lg border border-rose-200 px-3 text-sm text-rose-700 dark:border-rose-900 dark:text-rose-300" disabled={busy} onClick={() => setBreaks((current) => current.filter((_, rowIndex) => rowIndex !== index))}>Quitar</button>
        </div>)}
      </div>
      <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
        <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={published} onChange={(event) => setPublished(event.target.checked)} />Publicar turno</label>
        <div className="flex flex-wrap gap-2">
          {selectedShiftId && <button type="button" className="min-h-10 rounded-lg border border-stone-300 px-3 text-sm font-semibold dark:border-slate-600" disabled={busy} onClick={clearShiftEditor}>Cancelar edición</button>}
          <button className={buttonClass} disabled={busy || !employee || !date || !start || !end || breaks.some((item) => !item.start_time || !item.end_time)} onClick={() => void onSave("save_shift", { ...(selectedShiftId ? { shift_id: selectedShiftId } : {}), employee_id: employee, shift_date: date, start_time: start, end_time: end, status: published ? "published" : "draft", breaks }, selectedShiftId ? "Turno actualizado." : "Turno guardado.")}><Save size={16} /> {selectedShiftId ? "Actualizar turno" : "Guardar turno"}</button>
        </div>
      </div>
      <div className="mt-8 flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-2"><CalendarDays size={18} className="text-amber-600" /><h3 className="font-semibold">Calendario semanal de turnos</h3></div>
        <div className="flex items-center gap-2"><button type="button" aria-label="Semana anterior" className="min-h-10 rounded-lg border border-stone-200 px-3 dark:border-slate-700" onClick={() => moveWeek(-1)}><ChevronLeft size={18} /></button><span className="min-w-48 text-center text-sm font-medium">{dayLabel(weekStart)} – {dayLabel(weekEnd)}</span><button type="button" aria-label="Semana siguiente" className="min-h-10 rounded-lg border border-stone-200 px-3 dark:border-slate-700" onClick={() => moveWeek(1)}><ChevronRight size={18} /></button><button type="button" className="min-h-10 rounded-lg border border-stone-200 px-3 text-sm dark:border-slate-700" onClick={() => { const today = todayInTimezone(settings.branch.timezone); onWeekChange(mondayForDate(today)); setDate(today); }}>Hoy</button></div>
      </div>
      <div className="mt-3 grid gap-2 sm:grid-cols-2 xl:grid-cols-4">
        <ScheduleSummary label="Turnos publicados" value={publishedWeekShifts.length} tone="emerald" />
        <ScheduleSummary label="Personas programadas" value={publishedEmployeeCount} tone="slate" />
        <ScheduleSummary label="Borradores" value={draftWeekShifts.length} tone="amber" />
        <ScheduleSummary label="Ausencias por revisar" value={pendingWeekAbsences.length} tone="rose" />
      </div>
      <div className="mt-3 overflow-x-auto"><div className="grid min-w-[850px] grid-cols-7 gap-2">
        {weekDates.map((day, dayIndex) => {
          const overnightCarry = dayIndex === 0 ? addDateDays(day, -1) : "";
          const dayShifts = settings.shifts.filter((shift) => {
            const shiftDate = String(shift.shift_date);
            const crossesMidnight = String(shift.end_time) <= String(shift.start_time);
            return shiftDate === day || Boolean(overnightCarry && shiftDate === overnightCarry && crossesMidnight)
              || (dayIndex > 0 && shiftDate === addDateDays(day, -1) && crossesMidnight);
          });
          const publishedDayCount = dayShifts.filter((shift) => shift.status === "published").length;
          const draftDayCount = dayShifts.filter((shift) => shift.status === "draft").length;
          return <section key={day} className="min-h-36 rounded-xl border border-stone-200 bg-stone-50/70 p-2 dark:border-slate-700 dark:bg-slate-950/50">
            <button type="button" className="w-full rounded-md px-1 py-1 text-left text-xs font-bold uppercase text-slate-600 hover:bg-amber-50 dark:text-slate-300 dark:hover:bg-slate-800" onClick={() => setDate(day)}>{dayLabel(day)}</button>
            <p className="px-1 text-[11px] text-slate-500">{publishedDayCount} publicados · {draftDayCount} borradores</p>
            <div className="mt-2 space-y-2">{dayShifts.length ? dayShifts.map((shift) => {
              const isCarry = String(shift.shift_date) !== day;
              const shiftBreaks = settings.breaks.filter((item) => item.shift_id === shift.id);
              return <article key={`${String(shift.id)}-${day}`} className={`rounded-lg border px-2 py-2 text-xs ${shift.status === "published" ? "border-emerald-200 bg-emerald-50 dark:border-emerald-900 dark:bg-emerald-950/30" : shift.status === "cancelled" ? "border-rose-200 bg-rose-50/70 dark:border-rose-900 dark:bg-rose-950/20" : "border-stone-200 bg-white dark:border-slate-700 dark:bg-slate-900"}`}>
                <p className="truncate font-semibold" title={nameFor(shift.employee_id)}>{nameFor(shift.employee_id)}</p>
                <p className="mt-1 tabular-nums">{isCarry ? "Continúa · " : ""}{String(shift.start_time).slice(0, 5)}–{String(shift.end_time).slice(0, 5)}</p>
                {shiftBreaks.map((item, index) => <p key={String(item.id ?? index)} className="mt-1 text-slate-500">Descanso {String(item.start_time).slice(0, 5)}–{String(item.end_time).slice(0, 5)}</p>)}
                <p className="mt-1 text-slate-500">{shift.status === "published" ? "Publicado" : shift.status === "cancelled" ? "Cancelado" : "Borrador"}</p>
                {shift.status !== "cancelled" && <div className="mt-2 flex flex-wrap gap-2">
                  <button type="button" className="min-h-8 rounded-md border border-stone-300 px-2 hover:bg-stone-50 dark:border-slate-600 dark:hover:bg-slate-800" disabled={busy} onClick={() => editShift(shift)}>Editar turno</button>
                  <button type="button" className="min-h-8 rounded-md border border-rose-200 px-2 text-rose-700 hover:bg-rose-50 disabled:opacity-50 dark:border-rose-900 dark:text-rose-300 dark:hover:bg-rose-950/30" disabled={busy} onClick={() => { if (window.confirm(`¿Cancelar el turno de ${nameFor(shift.employee_id)} del ${String(shift.shift_date)}?`)) void onSave("cancel_shift", { shift_id: String(shift.id) }, "Turno cancelado."); }}>Cancelar turno</button>
                </div>}
              </article>;
            }) : <p className="px-1 py-3 text-center text-xs text-slate-400">Sin turnos</p>}</div>
          </section>;
        })}
      </div></div>
      <p className="mt-2 text-xs text-slate-500">Selecciona un día para preparar un turno. Los turnos que cruzan medianoche también aparecen como continuación al día siguiente.</p>
    </section>
    <section className={panelClass}>
      <h2 className="text-lg font-semibold">Ausencias</h2><p className="mt-1 text-sm text-slate-500">Solo ausencias aprobadas excluyen a la persona de asignaciones automáticas.</p>
      <div className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <label className="text-sm">Empleado<select className={`${inputClass} mt-1`} value={absenceEmployee} onChange={(event) => setAbsenceEmployee(event.target.value)}><option value="">Selecciona</option>{settings.members.map((item) => <option key={String(item.user_id)} value={String(item.user_id)}>{nameFor(item.user_id)}</option>)}</select></label>
        <label className="text-sm">Desde<input className={`${inputClass} mt-1`} type="date" value={absenceStart} onChange={(event) => setAbsenceStart(event.target.value)} /></label>
        <label className="text-sm">Hasta<input className={`${inputClass} mt-1`} type="date" value={absenceEnd} onChange={(event) => setAbsenceEnd(event.target.value)} /></label>
        <label className="text-sm">Estado<select className={`${inputClass} mt-1`} value={absenceStatus} onChange={(event) => setAbsenceStatus(event.target.value)}><option value="approved">Aprobada</option><option value="pending">Pendiente</option><option value="denied">Rechazada</option></select></label>
        <label className="text-sm">Nota<input className={`${inputClass} mt-1`} value={absenceNote} onChange={(event) => setAbsenceNote(event.target.value)} maxLength={300} placeholder="Opcional" /></label>
        <button className={`${buttonClass} self-end`} disabled={busy || !absenceEmployee || !absenceStart || !absenceEnd || absenceEnd < absenceStart} onClick={() => void onSave("save_absence", { employee_id: absenceEmployee, start_date: absenceStart, end_date: absenceEnd, status: absenceStatus, note: absenceNote }).then(() => setAbsenceNote(""))}><Save size={16} /> Registrar ausencia</button>
      </div>
      {settings.absences.length > 0 && <div className="mt-5 space-y-2">{settings.absences.map((absence) => <article key={String(absence.id)} className="flex flex-wrap items-center justify-between gap-3 rounded-lg bg-stone-50 px-3 py-3 text-sm dark:bg-slate-800"><p>{nameFor(absence.employee_id)} · {String(absence.start_date)} a {String(absence.end_date)} · {String(absence.status)}{absence.note ? ` · ${String(absence.note)}` : ""}</p>{absence.status === "pending" && <div className="flex gap-2"><button className={buttonClass} disabled={busy} onClick={() => void onSave("review_absence", { absence_id: absence.id, status: "approved" })}>Aprobar</button><button className={buttonClass} disabled={busy} onClick={() => void onSave("review_absence", { absence_id: absence.id, status: "denied" })}>No aprobar</button></div>}</article>)}</div>}
    </section>
  </div>;
}

function ScheduleSummary({ label, value, tone }: { label: string; value: number; tone: "emerald" | "slate" | "amber" | "rose" }) {
  const toneClass = {
    emerald: "border-emerald-200 bg-emerald-50 text-emerald-800 dark:border-emerald-900 dark:bg-emerald-950/30 dark:text-emerald-200",
    slate: "border-stone-200 bg-stone-50 text-slate-800 dark:border-slate-700 dark:bg-slate-950/40 dark:text-slate-100",
    amber: "border-amber-200 bg-amber-50 text-amber-800 dark:border-amber-900 dark:bg-amber-950/30 dark:text-amber-200",
    rose: "border-rose-200 bg-rose-50 text-rose-800 dark:border-rose-900 dark:bg-rose-950/30 dark:text-rose-200",
  }[tone];

  return <article className={`rounded-xl border px-3 py-2 ${toneClass}`}>
    <p className="text-xs font-medium opacity-80">{label}</p>
    <p className="mt-1 text-2xl font-semibold tabular-nums">{value}</p>
  </article>;
}

function WastePanel({ settings, busy, onSave }: { settings: Settings; busy: boolean; onSave: (action: string, values: Record<string, unknown>) => Promise<void> }) {
  const [intervals, setIntervals] = useState<Record<string, string>>(() => Object.fromEntries(settings.bins.map((bin) => [String(bin.id), bin.inspection_interval_minutes == null ? "" : String(bin.inspection_interval_minutes)])));
  const [names, setNames] = useState<Record<string, string>>(() => Object.fromEntries(settings.bins.map((bin) => [String(bin.id), String(bin.name ?? "")])));
  const [taskNames, setTaskNames] = useState<Record<string, string>>(() => Object.fromEntries(settings.bins.map((bin) => [String(bin.id), String(bin.bag_change_activity_name ?? "")])));
  const [taskMinutes, setTaskMinutes] = useState<Record<string, string>>(() => Object.fromEntries(settings.bins.map((bin) => [String(bin.id), bin.bag_change_minutes == null ? "" : String(bin.bag_change_minutes)])));
  const [taskDifficulties, setTaskDifficulties] = useState<Record<string, string>>(() => Object.fromEntries(settings.bins.map((bin) => [String(bin.id), bin.bag_change_difficulty == null ? "" : String(bin.bag_change_difficulty)])));
  const [taskPriorities, setTaskPriorities] = useState<Record<string, string>>(() => Object.fromEntries(settings.bins.map((bin) => [String(bin.id), bin.bag_change_priority == null ? "" : String(bin.bag_change_priority)])));
  const [newBinName, setNewBinName] = useState("");
  const [newTaskName, setNewTaskName] = useState("");
  const [newTaskMinutes, setNewTaskMinutes] = useState("");
  const [newTaskDifficulty, setNewTaskDifficulty] = useState("");
  const [newTaskPriority, setNewTaskPriority] = useState("");
  const [newInspectionInterval, setNewInspectionInterval] = useState("");
  const [positionIds, setPositionIds] = useState<string[]>(settings.waste_position_ids ?? []);
  useEffect(() => {
    setIntervals(Object.fromEntries(settings.bins.map((bin) => [String(bin.id), bin.inspection_interval_minutes == null ? "" : String(bin.inspection_interval_minutes)])));
    setNames(Object.fromEntries(settings.bins.map((bin) => [String(bin.id), String(bin.name ?? "")])));
    setTaskNames(Object.fromEntries(settings.bins.map((bin) => [String(bin.id), String(bin.bag_change_activity_name ?? "")])));
    setTaskMinutes(Object.fromEntries(settings.bins.map((bin) => [String(bin.id), bin.bag_change_minutes == null ? "" : String(bin.bag_change_minutes)])));
    setTaskDifficulties(Object.fromEntries(settings.bins.map((bin) => [String(bin.id), bin.bag_change_difficulty == null ? "" : String(bin.bag_change_difficulty)])));
    setTaskPriorities(Object.fromEntries(settings.bins.map((bin) => [String(bin.id), bin.bag_change_priority == null ? "" : String(bin.bag_change_priority)])));
    setPositionIds(settings.waste_position_ids ?? []);
  }, [settings]);
  const toggle = (id: string) => setPositionIds((old) => old.includes(id) ? old.filter((value) => value !== id) : [...old, id]);
  const validPolicy = (id: string) => {
    const minutes = Number(taskMinutes[id]); const difficulty = Number(taskDifficulties[id]); const priority = Number(taskPriorities[id]);
    return (taskNames[id] ?? "").trim().length >= 2 && (taskNames[id] ?? "").trim().length <= 120
      && Number.isInteger(minutes) && minutes >= 1 && minutes <= 1440
      && Number.isInteger(difficulty) && difficulty >= 1 && difficulty <= 5
      && Number.isInteger(priority) && priority >= 1 && priority <= 5;
  };
  const newPolicyValid = newTaskName.trim().length >= 2 && newTaskName.trim().length <= 120
    && Number.isInteger(Number(newTaskMinutes)) && Number(newTaskMinutes) >= 1 && Number(newTaskMinutes) <= 1440
    && Number.isInteger(Number(newTaskDifficulty)) && Number(newTaskDifficulty) >= 1 && Number(newTaskDifficulty) <= 5
    && Number.isInteger(Number(newTaskPriority)) && Number(newTaskPriority) >= 1 && Number(newTaskPriority) <= 5
    && (!newInspectionInterval || (Number.isInteger(Number(newInspectionInterval)) && Number(newInspectionInterval) >= 1 && Number(newInspectionInterval) <= 10080));
  const wastePolicy = (id: string) => ({
    bag_change_activity_name: taskNames[id]?.trim() ?? "",
    bag_change_minutes: Number(taskMinutes[id]),
    bag_change_difficulty: Number(taskDifficulties[id]),
    bag_change_priority: Number(taskPriorities[id]),
  });
  return <div className="grid gap-5 xl:grid-cols-2">
    <section className={panelClass}>
      <div className="flex items-center gap-2"><Store size={18} /><h2 className="text-lg font-semibold">Contenedores de residuos</h2></div>
      <p className="mt-1 text-sm text-slate-500">Cada sucursal define el contenedor y la tarea real que se generará si se declara lleno. El intervalo vacío no crea un límite artificial.</p>
      <div className="mt-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
        <label className="text-sm">Nombre del contenedor<input className={`${inputClass} mt-1`} value={newBinName} onChange={(event) => setNewBinName(event.target.value)} maxLength={120} placeholder="Nombre de esta sucursal" /></label>
        <label className="text-sm">Tarea cuando esté lleno<input className={`${inputClass} mt-1`} value={newTaskName} onChange={(event) => setNewTaskName(event.target.value)} maxLength={120} placeholder="Nombre definido por la sucursal" /></label>
        <label className="text-sm">Duración de la tarea (min)<input className={`${inputClass} mt-1`} type="number" min={1} max={1440} value={newTaskMinutes} onChange={(event) => setNewTaskMinutes(event.target.value)} /></label>
        <label className="text-sm">Dificultad (1–5)<input className={`${inputClass} mt-1`} type="number" min={1} max={5} value={newTaskDifficulty} onChange={(event) => setNewTaskDifficulty(event.target.value)} /></label>
        <label className="text-sm">Prioridad (1–5)<input className={`${inputClass} mt-1`} type="number" min={1} max={5} value={newTaskPriority} onChange={(event) => setNewTaskPriority(event.target.value)} /></label>
        <label className="text-sm">Intervalo de revisión (min, opcional)<input className={`${inputClass} mt-1`} type="number" min={1} max={10080} value={newInspectionInterval} onChange={(event) => setNewInspectionInterval(event.target.value)} /></label>
        <button className={`${buttonClass} sm:col-span-2 xl:col-span-3`} disabled={busy || newBinName.trim().length < 2 || !newPolicyValid} onClick={() => void onSave("save_bin", { name: newBinName.trim(), inspection_interval_minutes: newInspectionInterval || null, bag_change_activity_name: newTaskName.trim(), bag_change_minutes: Number(newTaskMinutes), bag_change_difficulty: Number(newTaskDifficulty), bag_change_priority: Number(newTaskPriority) }).then(() => { setNewBinName(""); setNewTaskName(""); setNewTaskMinutes(""); setNewTaskDifficulty(""); setNewTaskPriority(""); setNewInspectionInterval(""); })}><Plus size={16} /> Agregar contenedor configurado</button>
      </div>
      {!settings.bins.length && <p className="mt-4 rounded-lg bg-stone-50 px-3 py-4 text-sm text-slate-500 dark:bg-slate-800">Todavía no hay contenedores configurados.</p>}
      <div className="mt-4 space-y-3">{settings.bins.map((bin) => {
        const binId = String(bin.id);
        const active = bin.is_active === true;
        return <div key={binId} className={`grid gap-3 rounded-lg border p-3 md:grid-cols-2 xl:grid-cols-3 ${active ? "border-stone-200 bg-stone-50 dark:border-slate-700 dark:bg-slate-800" : "border-stone-200 bg-stone-100/70 opacity-70 dark:border-slate-700 dark:bg-slate-950"}`}>
          <label className="text-sm">{active ? "Nombre del contenedor" : "Contenedor inactivo"}<input className={`${inputClass} mt-1`} value={names[binId] ?? ""} onChange={(event) => setNames((old) => ({ ...old, [binId]: event.target.value }))} maxLength={120} /></label>
          <label className="text-sm">Tarea cuando esté lleno<input className={`${inputClass} mt-1`} value={taskNames[binId] ?? ""} onChange={(event) => setTaskNames((old) => ({ ...old, [binId]: event.target.value }))} maxLength={120} /></label>
          <label className="text-sm">Duración tarea (min)<input className={`${inputClass} mt-1`} type="number" min={1} max={1440} value={taskMinutes[binId] ?? ""} onChange={(event) => setTaskMinutes((old) => ({ ...old, [binId]: event.target.value }))} /></label>
          <label className="text-sm">Dificultad (1–5)<input className={`${inputClass} mt-1`} type="number" min={1} max={5} value={taskDifficulties[binId] ?? ""} onChange={(event) => setTaskDifficulties((old) => ({ ...old, [binId]: event.target.value }))} /></label>
          <label className="text-sm">Prioridad (1–5)<input className={`${inputClass} mt-1`} type="number" min={1} max={5} value={taskPriorities[binId] ?? ""} onChange={(event) => setTaskPriorities((old) => ({ ...old, [binId]: event.target.value }))} /></label>
          <label className="text-sm">Intervalo revisión (min)<input aria-label={`Intervalo de ${names[binId] ?? binId} en minutos`} className={`${inputClass} mt-1`} type="number" min={1} max={10080} value={intervals[binId] ?? ""} onChange={(event) => setIntervals((old) => ({ ...old, [binId]: event.target.value }))} /></label>
          {!validPolicy(binId) && <p className="text-xs text-amber-700 md:col-span-2 xl:col-span-3">Completa la tarea, duración, dificultad y prioridad antes de usar este contenedor en una inspección.</p>}
          <div className="flex flex-wrap gap-2 md:col-span-2 xl:col-span-3 md:justify-end">
            <button className="min-h-10 rounded-lg border border-stone-300 px-3 text-sm font-semibold hover:bg-white disabled:opacity-50 dark:border-slate-600 dark:hover:bg-slate-700" disabled={busy || (names[binId] ?? "").trim().length < 2 || !validPolicy(binId)} onClick={() => void onSave("save_bin", { bin_id: binId, name: (names[binId] ?? "").trim(), inspection_interval_minutes: intervals[binId] || null, ...wastePolicy(binId) })}><Save size={15} className="mr-1 inline" />Guardar</button>
            <button className="min-h-10 rounded-lg border border-stone-300 px-3 text-sm font-semibold hover:bg-white disabled:opacity-50 dark:border-slate-600 dark:hover:bg-slate-700" disabled={busy || (!active && !validPolicy(binId))} onClick={() => void onSave("save_bin", { bin_id: binId, name: (names[binId] ?? String(bin.name)).trim(), inspection_interval_minutes: intervals[binId] || null, ...(validPolicy(binId) ? wastePolicy(binId) : {}), is_active: !active })}>{active ? "Desactivar" : "Reactivar"}</button>
          </div>
        </div>;
      })}</div>
    </section>
    <section className={panelClass}>
      <h2 className="text-lg font-semibold">Puestos que pueden cambiar bolsa</h2><p className="mt-1 text-sm text-slate-500">El encargado define la elegibilidad; una inspección “lleno” genera una sola tarea pendiente por contenedor activo.</p>
      <div className="mt-4 space-y-2">{settings.positions.map((position) => <label key={String(position.id)} className="flex items-center gap-3 rounded-lg bg-stone-50 px-3 py-2.5 text-sm dark:bg-slate-800"><input type="checkbox" checked={positionIds.includes(String(position.id))} onChange={() => toggle(String(position.id))} />{String(position.name)}</label>)}</div>
      {!settings.positions.length && <p className="mt-3 text-sm text-slate-500">Agrega puestos antes de definir quién puede cambiar bolsas.</p>}
      <button className={`${buttonClass} mt-4`} disabled={busy} onClick={() => void onSave("save_waste_positions", { position_ids: positionIds })}><Save size={16} /> Guardar elegibilidad</button>
    </section>
  </div>;
}

function InspectionsPanel({ settings, busy, onSave }: { settings: Settings; busy: boolean; onSave: (action: string, values: Record<string, unknown>) => Promise<void> }) {
  const [templateId, setTemplateId] = useState("");
  const [name, setName] = useState("");
  const [areaId, setAreaId] = useState("");
  const [interval, setInterval] = useState("");
  const [itemsText, setItemsText] = useState("");
  const [isActive, setIsActive] = useState(true);

  useEffect(() => {
    const template = settings.inspection_templates.find((item) => item.id === templateId);
    if (!template) return;
    setName(String(template.name ?? ""));
    setAreaId(String(template.area_id ?? ""));
    setInterval(template.inspection_interval_minutes == null ? "" : String(template.inspection_interval_minutes));
    setIsActive(template.is_active === true);
    setItemsText((template.items as Row[] ?? []).map((item) => String(item.label ?? "")).join("\n"));
  }, [templateId, settings.inspection_templates]);

  const startNew = () => {
    setTemplateId(""); setName(""); setAreaId(""); setInterval(""); setItemsText(""); setIsActive(true);
  };
  const itemRows = itemsText.split(/\r?\n/).map((label) => label.trim()).filter(Boolean);
  const invalidItems = itemRows.some((label) => label.length < 2 || label.length > 180);
  const save = () => {
    if (busy || name.trim().length < 2 || itemRows.length === 0 || itemRows.length > 100 || invalidItems) return;
    void onSave("save_inspection_template", {
      ...(templateId ? { id: templateId } : {}),
      name: name.trim(), area_id: areaId || null,
      inspection_interval_minutes: interval || null, is_active: isActive,
      items: itemRows.map((label) => ({ label })),
    });
  };

  return <div className="grid gap-5 xl:grid-cols-[minmax(300px,0.8fr)_minmax(0,1.2fr)]">
    <section className={panelClass}>
      <div className="flex items-center justify-between gap-3"><div><h2 className="text-lg font-semibold">Listas configuradas</h2><p className="mt-1 text-sm text-slate-500">Cada criterio lo define la sucursal.</p></div><button className={buttonClass} onClick={startNew}><Plus size={16} /> Nueva lista</button></div>
      <div className="mt-4 space-y-2">{settings.inspection_templates.map((template) => <button key={String(template.id)} aria-pressed={templateId === template.id} className={`w-full rounded-lg border px-3 py-3 text-left ${templateId === template.id ? "border-amber-500 bg-amber-50 dark:bg-amber-950/30" : "border-stone-200 dark:border-slate-700"}`} onClick={() => setTemplateId(String(template.id))}><span className="font-semibold">{String(template.name)}</span><span className="mt-1 block text-xs text-slate-500">{settings.areas.find((area) => area.id === template.area_id)?.name as string ?? "Sin área"} · {((template.items as Row[] | undefined) ?? []).filter((item) => item.is_active !== false).length} criterios · {template.is_active === true ? "Activa" : "Pausada"}</span></button>)}</div>
      {settings.inspection_templates.length === 0 && <p className="mt-4 text-sm text-slate-500">Aún no hay listas; no se precargan estándares.</p>}
    </section>
    <section className={panelClass}>
      <h2 className="flex items-center gap-2 text-lg font-semibold"><ClipboardCheck size={18} />{templateId ? "Editar lista" : "Nueva lista de inspección"}</h2>
      <p className="mt-1 text-sm text-slate-500">Un criterio por renglón. Al guardar cambios se conserva el historial con el texto observado en cada inspección.</p>
      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <label className="text-sm">Nombre<input className={`${inputClass} mt-1`} maxLength={120} value={name} onChange={(event) => setName(event.target.value)} placeholder="Nombre definido por la sucursal" /></label>
        <label className="text-sm">Área<select className={`${inputClass} mt-1`} value={areaId} onChange={(event) => setAreaId(event.target.value)}><option value="">Sin área</option>{settings.areas.map((area) => <option key={String(area.id)} value={String(area.id)}>{String(area.name)}</option>)}</select></label>
        <label className="text-sm">Intervalo opcional (minutos)<input className={`${inputClass} mt-1`} type="number" min={1} max={10080} value={interval} onChange={(event) => setInterval(event.target.value)} placeholder="Sin intervalo" /></label>
        <label className="flex items-center gap-2 self-end pb-3 text-sm"><input type="checkbox" checked={isActive} onChange={(event) => setIsActive(event.target.checked)} />Lista activa</label>
      </div>
      <label className="mt-3 block text-sm">Criterios<textarea className={`${inputClass} mt-1 min-h-48 py-3`} maxLength={18000} value={itemsText} onChange={(event) => setItemsText(event.target.value)} placeholder="Escribe aquí los criterios acordados por la sucursal, uno por línea." /></label>
      <p className={`mt-1 text-xs ${invalidItems || itemRows.length > 100 ? "text-rose-600" : "text-slate-500"}`}>{itemRows.length} criterio(s) · entre 1 y 100 · 2 a 180 caracteres cada uno</p>
      <button className={`${buttonClass} mt-4`} disabled={busy || name.trim().length < 2 || itemRows.length < 1 || itemRows.length > 100 || invalidItems} onClick={save}><Save size={16} /> Guardar lista</button>
    </section>
  </div>;
}

function AssignmentPolicyPanel({ settings, busy, onSave }: { settings: Settings; busy: boolean; onSave: (action: string, values: Record<string, unknown>) => Promise<void> }) {
  const branch = settings.branch;
  const [weights, setWeights] = useState({
    loadBalance: String(branch.assignment_load_balance_weight ?? 100),
    heavyRotation: String(branch.assignment_heavy_rotation_weight ?? 60),
    priority: String(branch.assignment_priority_weight ?? 100),
  });
  useEffect(() => setWeights({
    loadBalance: String(branch.assignment_load_balance_weight ?? 100),
    heavyRotation: String(branch.assignment_heavy_rotation_weight ?? 60),
    priority: String(branch.assignment_priority_weight ?? 100),
  }), [branch.assignment_load_balance_weight, branch.assignment_heavy_rotation_weight, branch.assignment_priority_weight]);

  const values = Object.values(weights).map(Number);
  const valid = values.every((value) => Number.isInteger(value) && value >= 0 && value <= 1000);
  const update = (key: keyof typeof weights, value: string) => setWeights((current) => ({ ...current, [key]: value }));
  return <section className={panelClass}>
    <h2 className="text-lg font-semibold">Reglas de asignación</h2>
    <p className="mt-1 max-w-3xl text-sm text-slate-500">Ajusta cuánto pesan el equilibrio de carga, la rotación de tareas pesadas y la prioridad al dejar una tarea sin asignar. Cero desactiva esa preferencia; la elegibilidad por puesto, el turno y la capacidad siguen siendo reglas obligatorias.</p>
    <div className="mt-5 grid gap-4 md:grid-cols-3">
      <label className="text-sm font-medium">Equilibrio de carga
        <input className={`${inputClass} mt-1`} type="number" min={0} max={1000} step={1} value={weights.loadBalance} onChange={(event) => update("loadBalance", event.target.value)} />
        <span className="mt-1 block text-xs font-normal text-slate-500">Peso predeterminado: 100.</span>
      </label>
      <label className="text-sm font-medium">Rotación de tareas pesadas
        <input className={`${inputClass} mt-1`} type="number" min={0} max={1000} step={1} value={weights.heavyRotation} onChange={(event) => update("heavyRotation", event.target.value)} />
        <span className="mt-1 block text-xs font-normal text-slate-500">Peso predeterminado: 60.</span>
      </label>
      <label className="text-sm font-medium">Prioridad sin asignar
        <input className={`${inputClass} mt-1`} type="number" min={0} max={1000} step={1} value={weights.priority} onChange={(event) => update("priority", event.target.value)} />
        <span className="mt-1 block text-xs font-normal text-slate-500">Peso predeterminado: 100.</span>
      </label>
    </div>
    <button type="button" className={`${buttonClass} mt-5`} disabled={busy || !valid} onClick={() => void onSave("save_assignment_policy", {
      assignment_load_balance_weight: Number(weights.loadBalance),
      assignment_heavy_rotation_weight: Number(weights.heavyRotation),
      assignment_priority_weight: Number(weights.priority),
    })}><Save size={16} />Guardar reglas</button>
  </section>;
}

function FeaturesPanel({ settings, busy, onSave }: { settings: Settings; busy: boolean; onSave: (action: string, values: Record<string, unknown>) => Promise<void> }) {
  const [branchName, setBranchName] = useState(settings.branch.name);
  const [clockEnabled, setClockEnabled] = useState(settings.branch.enable_time_clock === true);
  const [gpsRequired, setGpsRequired] = useState(settings.branch.require_gps_for_time_clock === true);
  const [timezone, setTimezone] = useState(settings.branch.timezone);
  useEffect(() => {
    setBranchName(settings.branch.name);
    setClockEnabled(settings.branch.enable_time_clock === true);
    setGpsRequired(settings.branch.require_gps_for_time_clock === true);
    setTimezone(settings.branch.timezone);
  }, [settings.branch.name, settings.branch.enable_time_clock, settings.branch.require_gps_for_time_clock, settings.branch.timezone]);
  return <section className={`${panelClass} max-w-3xl`}><h2 className="text-lg font-semibold">Sucursal, asistencia y ubicación</h2><label className="mt-5 block text-sm font-medium">Nombre de sucursal<input className={`${inputClass} mt-1`} value={branchName} onChange={(event) => setBranchName(event.target.value)} maxLength={120} /></label><p className="mt-5 text-sm text-slate-500">La zona horaria define el día operativo y la lectura de horarios. Cambiarla puede cambiar la fecha local de eventos existentes.</p><label className="mt-2 block text-sm font-medium">Zona horaria<select className={`${inputClass} mt-1`} value={timezone} onChange={(event) => setTimezone(event.target.value)}>{mexicoTimeZones.map((item) => <option key={item.value} value={item.value}>{item.label}</option>)}</select></label><p className="mt-2 text-xs text-slate-500">Zona actual: {settings.branch.timezone}</p><p className="mt-6 text-sm text-slate-500">Estas funciones son opcionales e independientes del trabajo operativo. Checador apagado por defecto; GPS también apagado por defecto.</p><label className="mt-3 flex items-start gap-3 rounded-xl border border-stone-200 p-4 dark:border-slate-700"><input className="mt-1" type="checkbox" checked={clockEnabled} onChange={(event) => { setClockEnabled(event.target.checked); if (!event.target.checked) setGpsRequired(false); }} /><span><span className="block font-semibold">Habilitar checador de entrada y salida</span><span className="mt-1 block text-sm text-slate-500">Muestra la pestaña Checador en la app. Guarda asistencia operativa; no calcula nómina.</span></span></label><label className={`mt-3 flex items-start gap-3 rounded-xl border border-stone-200 p-4 dark:border-slate-700 ${clockEnabled ? "" : "opacity-50"}`}><input className="mt-1" type="checkbox" checked={gpsRequired} disabled={!clockEnabled} onChange={(event) => setGpsRequired(event.target.checked)} /><span><span className="block font-semibold">Solicitar GPS al marcar entrada y salida</span><span className="mt-1 block text-sm text-slate-500">Pide ubicación al momento del registro. No usa GPS en segundo plano ni conserva trayectorias.</span></span></label><button className={`${buttonClass} mt-5`} disabled={busy || branchName.trim().length < 2 || !timezone} onClick={() => void onSave("save_branch_features", { name: branchName.trim(), timezone, enable_time_clock: clockEnabled, require_gps_for_time_clock: clockEnabled && gpsRequired })}><Save size={16} /> Guardar sucursal</button></section>;
}
