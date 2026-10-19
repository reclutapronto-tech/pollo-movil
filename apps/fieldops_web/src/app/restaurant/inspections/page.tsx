"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { ArrowLeft, ClipboardCheck, RefreshCw, Settings2, Trash2 } from "lucide-react";
import { callFunctionJson } from "@/lib/function-client";
import { preferredRestaurantBranchId, rememberRestaurantBranchId } from "@/lib/restaurant-branch-selection";
import { getSupabase } from "@/lib/supabase";

type Row = Record<string, unknown>;
type Branch = { id: string; name: string; timezone: string; access_role: string };
type InspectionItem = { id: string; label: string; sort_order?: number };
type InspectionTemplate = Row & { id: string; name: string; is_active: boolean; area_id: string | null; items: InspectionItem[] };
type Settings = { areas: Row[]; bins: Row[]; inspection_templates: InspectionTemplate[] };

const panelClass = "rounded-2xl border border-stone-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900";
const inputClass = "min-h-11 w-full rounded-lg border border-stone-300 bg-white px-3 text-sm text-slate-900 outline-none focus:border-amber-500 focus:ring-2 focus:ring-amber-100 dark:border-slate-700 dark:bg-slate-950 dark:text-slate-100";
const buttonClass = "inline-flex min-h-10 items-center justify-center gap-2 rounded-lg bg-slate-900 px-4 text-sm font-semibold text-white hover:bg-slate-700 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-amber-400 dark:text-slate-950";
const secondaryClass = "inline-flex min-h-10 items-center justify-center gap-2 rounded-lg border border-stone-300 px-3 text-sm font-semibold hover:bg-stone-50 dark:border-slate-700 dark:hover:bg-slate-800";
const resultLabels: Record<string, string> = { ok: "Correcto", needs_attention: "Requiere atención", not_applicable: "No aplica" };

function todayInZone(timeZone: string): string {
  const parts = new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}

function dateLabel(value: unknown): string {
  if (typeof value !== "string") return "Sin registro";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "Sin registro" : new Intl.DateTimeFormat("es-MX", { dateStyle: "medium", timeStyle: "short" }).format(date);
}

function intervalIsDue(interval: unknown, ...timestamps: unknown[]): boolean {
  const minutes = Number(interval);
  if (!Number.isInteger(minutes) || minutes < 1) return false;
  const anchors = timestamps
    .filter((value): value is string => typeof value === "string")
    .map((value) => new Date(value).getTime())
    .filter(Number.isFinite);
  if (!anchors.length) return true;
  return Date.now() >= Math.max(...anchors) + minutes * 60_000;
}

export default function RestaurantInspectionsPage() {
  const [branches, setBranches] = useState<Branch[]>([]);
  const [branchId, setBranchId] = useState("");
  const [settings, setSettings] = useState<Settings | null>(null);
  const [answers, setAnswers] = useState<Record<string, string>>({});
  const [itemNotes, setItemNotes] = useState<Record<string, string>>({});
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [binStates, setBinStates] = useState<Record<string, string>>({});
  const [inspectionEventIds, setInspectionEventIds] = useState<Record<string, string>>({});
  const [wasteEventId, setWasteEventId] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  const branch = useMemo(() => branches.find((item) => item.id === branchId) ?? null, [branches, branchId]);
  const load = useCallback(async (id = branchId) => {
    if (!id) return;
    setLoading(true);
    setError("");
    try {
      const result = await callFunctionJson<Settings>("restaurant_ops", { query: { action: "inspection_setup", branch_id: id } });
      setSettings(result);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "No se pudo cargar la configuración de inspecciones.");
    } finally {
      setLoading(false);
    }
  }, [branchId]);

  useEffect(() => {
    let active = true;
    callFunctionJson<{ branches: Branch[] }>("restaurant_ops", { query: { action: "branches" } })
      .then(({ branches: available }) => {
        if (!active) return;
        const rows = available ?? [];
        setBranches(rows);
        const preferredId = preferredRestaurantBranchId(rows);
        setBranchId((current) => current && rows.some((item) => item.id === current) ? current : preferredId);
        if (!rows.length) setLoading(false);
      })
      .catch((cause: unknown) => {
        if (active) {
          setError(cause instanceof Error ? cause.message : "No se pudieron cargar las sucursales.");
          setLoading(false);
        }
      });
    return () => { active = false; };
  }, []);

  useEffect(() => {
    setSettings(null);
    setAnswers({});
    setItemNotes({});
    setNotes({});
    setBinStates({});
    setInspectionEventIds({});
    setWasteEventId("");
    if (branchId) void load(branchId);
  }, [branchId, load]);

  useEffect(() => {
    if (!branchId) return;
    const supabase = getSupabase();
    let timer: number | undefined;
    const refresh = () => {
      if (timer !== undefined) window.clearTimeout(timer);
      timer = window.setTimeout(() => void load(branchId), 250);
    };
    const channel = supabase
      .channel(`pollo-inspections-${branchId}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_inspection_templates", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_inspection_items", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_inspections", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_waste_bins", filter: `branch_id=eq.${branchId}` }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "restaurant_waste_inspections", filter: `branch_id=eq.${branchId}` }, refresh)
      .subscribe();
    return () => {
      if (timer !== undefined) window.clearTimeout(timer);
      void supabase.removeChannel(channel);
    };
  }, [branchId, load]);

  const submitAreaInspection = async (template: InspectionTemplate) => {
    if (!branchId || saving) return;
    const items = template.items ?? [];
    if (!items.length || items.some((item) => !answers[`${template.id}:${item.id}`])) {
      setError("Registra un resultado para cada punto antes de guardar.");
      return;
    }
    setSaving(true); setError(""); setNotice("");
    const clientEventId = inspectionEventIds[template.id] ?? crypto.randomUUID();
    setInspectionEventIds((current) => ({ ...current, [template.id]: clientEventId }));
    try {
      const result = await callFunctionJson<{ needs_attention_count?: number }>("restaurant_ops", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "record_area_inspection",
          branch_id: branchId,
          template_id: template.id,
          client_event_id: clientEventId,
          results: items.map((item) => ({
            item_id: item.id,
            result_state: answers[`${template.id}:${item.id}`],
            note: itemNotes[`${template.id}:${item.id}`] ?? "",
          })),
          note: notes[template.id] ?? "",
        }),
      });
      const message = typeof result.needs_attention_count === "number" && result.needs_attention_count > 0
        ? `Inspección guardada; ${result.needs_attention_count} punto(s) requieren atención.`
        : "Inspección de área guardada.";
      setNotice(message);
      setAnswers((current) => Object.fromEntries(Object.entries(current).filter(([key]) => !key.startsWith(`${template.id}:`))));
      setItemNotes((current) => Object.fromEntries(Object.entries(current).filter(([key]) => !key.startsWith(`${template.id}:`))));
      setNotes((current) => ({ ...current, [template.id]: "" }));
      setInspectionEventIds((current) => { const next = { ...current }; delete next[template.id]; return next; });
      await load(branchId);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "No se pudo guardar la inspección.");
    } finally { setSaving(false); }
  };

  const submitWasteInspection = async () => {
    if (!branchId || !settings || saving) return;
    const activeBins = (settings.bins ?? []).filter((bin) => bin.is_active === true);
    if (!activeBins.length || activeBins.some((bin) => !binStates[String(bin.id)])) {
      setError("Declara el estado de cada contenedor activo antes de guardar.");
      return;
    }
    setSaving(true); setError(""); setNotice("");
    const clientEventId = wasteEventId || crypto.randomUUID();
    setWasteEventId(clientEventId);
    try {
      await callFunctionJson("restaurant_ops", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "inspect_waste",
          branch_id: branchId,
          client_event_id: clientEventId,
          results: activeBins.map((bin) => ({ bin_id: bin.id, state: binStates[String(bin.id)] })),
        }),
      });
      setNotice("Revisión de contenedores guardada.");
      setBinStates({});
      setWasteEventId("");
      await load(branchId);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "No se pudo guardar la revisión de contenedores.");
    } finally { setSaving(false); }
  };

  if (!loading && !branches.length) return <main className="mx-auto max-w-4xl py-12"><section className={panelClass}><h1 className="text-2xl font-bold">Inspecciones de sucursal</h1><p className="mt-3 text-sm text-slate-500">No tienes acceso a una sucursal activa de Pollo Móvil.</p></section></main>;

  const templates = (settings?.inspection_templates ?? []).filter((item) => item.is_active === true);
  const bins = (settings?.bins ?? []).filter((item) => item.is_active === true);
  const areaName = (id: unknown) => settings?.areas.find((area) => area.id === id)?.name ?? "Sucursal";

  return <main className="mx-auto max-w-5xl pb-12">
    <header className="flex flex-wrap items-end justify-between gap-4 border-b border-stone-200 pb-5 dark:border-slate-800">
      <div><p className="text-sm font-semibold text-amber-700">Pollo Móvil</p><h1 className="mt-1 text-3xl font-bold tracking-tight">Inspecciones</h1><p className="mt-1 text-sm text-slate-500">Registra observaciones reales según las listas configuradas por la sucursal.</p></div>
      <div className="flex flex-wrap items-center gap-2"><select aria-label="Sucursal" className={inputClass} value={branchId} onChange={(event) => { rememberRestaurantBranchId(event.target.value); setBranchId(event.target.value); }}>{branches.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select><Link href="/restaurant" className={secondaryClass}><ArrowLeft size={16} /> Operación</Link>{branch && ["admin", "supervisor"].includes(branch.access_role) && <Link href="/restaurant/configuration" className={secondaryClass}><Settings2 size={16} /> Configuración</Link>}<button className={secondaryClass} disabled={loading || !branchId} onClick={() => void load()}><RefreshCw size={16} /> Actualizar</button></div>
    </header>
    {(error || notice) && <div role="status" className={`mt-5 rounded-xl border px-4 py-3 text-sm ${error ? "border-rose-200 bg-rose-50 text-rose-700" : "border-emerald-200 bg-emerald-50 text-emerald-800"}`}>{error || notice}</div>}
    {loading || !settings ? <section className={`${panelClass} mt-6`} role="status">Cargando listas de inspección…</section> : <>
      <section className={`${panelClass} mt-6`}><div className="flex items-start gap-3"><ClipboardCheck className="mt-0.5 text-amber-700" size={20} /><div><h2 className="font-semibold">Listas de área configuradas</h2><p className="mt-1 text-sm text-slate-500">La persona registra el estado observado; las inspecciones no usan GPS ni mediciones automáticas.</p></div></div>
        {!templates.length ? <p className="mt-5 rounded-xl bg-stone-50 p-4 text-sm text-slate-500 dark:bg-slate-800">Esta sucursal todavía no tiene listas de inspección activas. Una persona administradora puede configurarlas.</p> : <div className="mt-5 space-y-5">{templates.map((template) => { const due = intervalIsDue(template.inspection_interval_minutes, template.last_inspected_at); return <section key={template.id} className="rounded-xl border border-stone-200 p-4 dark:border-slate-700"><div className="flex flex-wrap items-start justify-between gap-2"><div><h3 className="font-semibold">{template.name}</h3><p className="mt-1 text-xs text-slate-500">{String(areaName(template.area_id))} · Última inspección: {dateLabel(template.last_inspected_at)}</p></div><div className="flex flex-wrap gap-2">{typeof template.inspection_interval_minutes === "number" && <span className="rounded-full bg-stone-100 px-3 py-1 text-xs text-slate-600 dark:bg-slate-800">Cada {template.inspection_interval_minutes} min</span>}{due && typeof template.inspection_interval_minutes === "number" && <span className="rounded-full bg-amber-100 px-3 py-1 text-xs font-semibold text-amber-800">Revisión pendiente</span>}</div></div>
          {!template.items.length ? <p className="mt-3 text-sm text-amber-700">La lista no tiene puntos activos para registrar.</p> : <div className="mt-4 divide-y divide-stone-100 dark:divide-slate-800">{template.items.map((item) => { const key = `${template.id}:${item.id}`; return <div key={item.id} className="grid gap-2 py-3 sm:grid-cols-[minmax(0,1fr)_220px]"><label className="self-center text-sm font-medium" htmlFor={`inspection-${template.id}-${item.id}`}>{item.label}</label><select id={`inspection-${template.id}-${item.id}`} className={inputClass} disabled={saving} value={answers[key] ?? ""} onChange={(event) => { setAnswers((current) => ({ ...current, [key]: event.target.value })); setInspectionEventIds((current) => { const next = { ...current }; delete next[template.id]; return next; }); }}><option value="">Selecciona resultado</option>{Object.entries(resultLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select>{answers[key] === "needs_attention" && <input className={`${inputClass} sm:col-start-2`} disabled={saving} aria-label={`Nota: ${item.label}`} placeholder="Describe qué requiere atención" maxLength={500} value={itemNotes[key] ?? ""} onChange={(event) => { setItemNotes((current) => ({ ...current, [key]: event.target.value })); setInspectionEventIds((current) => { const next = { ...current }; delete next[template.id]; return next; }); }} />}</div>; })}</div>}
          <label className="mt-3 block text-xs font-medium text-slate-500">Nota general (opcional)<textarea className={`${inputClass} mt-1 min-h-20 py-2`} disabled={saving} maxLength={1000} value={notes[template.id] ?? ""} onChange={(event) => { setNotes((current) => ({ ...current, [template.id]: event.target.value })); setInspectionEventIds((current) => { const next = { ...current }; delete next[template.id]; return next; }); }} /></label>
          <div className="mt-4 flex justify-end"><button className={buttonClass} disabled={saving || !template.items.length || template.items.some((item) => !answers[`${template.id}:${item.id}`])} onClick={() => void submitAreaInspection(template)}><ClipboardCheck size={16} /> {saving ? "Guardando…" : "Guardar inspección"}</button></div>
        </section>; })}</div>}
      </section>
      <section className={`${panelClass} mt-5`}><div className="flex items-start gap-3"><Trash2 className="mt-0.5 text-amber-700" size={20} /><div><h2 className="font-semibold">Inspección de contenedores</h2><p className="mt-1 text-sm text-slate-500">Declaración del equipo para cada contenedor activo; no se usan sensores.</p></div></div>
        {!bins.length ? <p className="mt-5 rounded-xl bg-stone-50 p-4 text-sm text-slate-500 dark:bg-slate-800">No hay contenedores activos configurados en esta sucursal.</p> : <><div className="mt-4 divide-y divide-stone-100 dark:divide-slate-800">{bins.map((bin) => { const due = intervalIsDue(bin.inspection_interval_minutes, bin.last_inspected_at, bin.last_bag_changed_at); const stateLabel = ({ low: "Poco o vacío", half: "A medias", full: "Lleno" } as Record<string, string>)[String(bin.last_state)] ?? "Sin registro"; return <div key={String(bin.id)} className="grid gap-2 py-3 sm:grid-cols-[minmax(0,1fr)_220px] sm:items-center"><div><div className="flex flex-wrap items-center gap-2 text-sm font-medium">{String(bin.name)}{due && typeof bin.inspection_interval_minutes === "number" && <span className="rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-semibold text-amber-800">Revisión pendiente</span>}</div><div className="mt-1 text-xs text-slate-500">Último estado declarado: {stateLabel} · Última revisión: {dateLabel(bin.last_inspected_at)}</div></div><select className={inputClass} disabled={saving} aria-label={`Estado: ${String(bin.name)}`} value={binStates[String(bin.id)] ?? ""} onChange={(event) => { setBinStates((current) => ({ ...current, [String(bin.id)]: event.target.value })); setWasteEventId(""); }}><option value="">Selecciona estado observado</option><option value="low">Poco o vacío</option><option value="half">A medias</option><option value="full">Lleno</option></select></div>; })}</div><div className="mt-4 flex justify-end"><button className={buttonClass} disabled={saving || bins.some((bin) => !binStates[String(bin.id)])} onClick={() => void submitWasteInspection()}><Trash2 size={16} />{saving ? "Guardando…" : "Guardar revisión"}</button></div></>}
      </section>
      <p className="mt-4 text-xs text-slate-500">Fecha local de sucursal: {branch ? todayInZone(branch.timezone) : "—"}</p>
    </>}
  </main>;
}
