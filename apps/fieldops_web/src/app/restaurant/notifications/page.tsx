"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { ArrowLeft, ArrowRightLeft, Bell, CalendarClock, Check, Circle, ClipboardCheck, RefreshCw, TriangleAlert } from "lucide-react";
import { callFunctionJson } from "@/lib/function-client";
import { preferredRestaurantBranchId, rememberRestaurantBranchId } from "@/lib/restaurant-branch-selection";
import { getSupabase } from "@/lib/supabase";
import { useCurrentUser } from "@/lib/use-role";

type Branch = { id: string; name: string };
type Notification = {
  id: string;
  notification_type: string;
  title: string;
  body: string;
  entity_type: string;
  entity_id: string;
  data?: Record<string, unknown>;
  created_at: string;
  read_at: string | null;
};
type Inbox = { notifications: Notification[]; unread_count: number };

export default function RestaurantNotificationsPage() {
  const router = useRouter();
  const currentUser = useCurrentUser();
  const [branches, setBranches] = useState<Branch[]>([]);
  const [branchId, setBranchId] = useState("");
  const [inbox, setInbox] = useState<Inbox>({ notifications: [], unread_count: 0 });
  const [loading, setLoading] = useState(true);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const loadInbox = useCallback(async (id = branchId) => {
    if (!id) return;
    setLoading(true);
    setError(null);
    try {
      const result = await callFunctionJson<Inbox>("restaurant_ops", {
        query: { action: "notification_inbox", branch_id: id },
      });
      setInbox(result);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "No se pudieron cargar las notificaciones.");
    } finally {
      setLoading(false);
    }
  }, [branchId]);

  useEffect(() => {
    let cancelled = false;
    callFunctionJson<{ branches: Branch[] }>("restaurant_ops", { query: { action: "branches" } })
      .then(({ branches: rows }) => {
        if (cancelled) return;
        const availableBranches = rows ?? [];
        setBranches(availableBranches);
        const preferredId = preferredRestaurantBranchId(availableBranches);
        setBranchId((current) => current && availableBranches.some((branch) => branch.id === current)
          ? current
          : preferredId);
        if (!availableBranches.length) setLoading(false);
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
    if (branchId) void loadInbox(branchId);
  }, [branchId, loadInbox]);

  useEffect(() => {
    if (!branchId || !currentUser.userId) return;
    const supabase = getSupabase();
    const channel = supabase
      .channel(`pollo-notifications-${branchId}-${currentUser.userId}`)
      .on("postgres_changes", {
        event: "*",
        schema: "public",
        table: "restaurant_notifications",
        filter: `branch_id=eq.${branchId}`,
      }, () => void loadInbox(branchId))
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [branchId, currentUser.userId, loadInbox]);

  const markRead = async (notificationId?: string) => {
    if (!branchId || busyId) return;
    setBusyId(notificationId ?? "all");
    setError(null);
    try {
      await callFunctionJson("restaurant_ops", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(notificationId
          ? { action: "mark_notification_read", branch_id: branchId, notification_id: notificationId }
          : { action: "mark_all_notifications_read", branch_id: branchId }),
      });
      await loadInbox(branchId);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "No se pudo actualizar la notificación.");
    } finally {
      setBusyId(null);
    }
  };

  const openNotification = (item: Notification) => {
    if (busyId) return;
    if (!item.read_at) void markRead(item.id);
    rememberRestaurantBranchId(branchId);
    const type = item.notification_type;
    const target = type.startsWith("shift_cover_")
      ? "/restaurant/coverage"
      : type.startsWith("shift_handoff_")
      ? "/restaurant"
      : type === "inspection_attention" || type === "inspection_due" || type === "waste_inspection_due"
      ? "/restaurant/inspections"
      : type === "task_assigned" || type === "task_part_assigned" || type === "waste_task_assigned" || type.startsWith("shift_")
      ? "/restaurant/calendar"
      : "/restaurant";
    if (target !== "/restaurant/calendar") {
      router.push(target);
      return;
    }
    const params = new URLSearchParams({ branch_id: branchId });
    const targetDate = item.data?.scheduled_for ?? item.data?.shift_date;
    if (typeof targetDate === "string" && /^\d{4}-\d{2}-\d{2}$/.test(targetDate)) {
      params.set("date", targetDate);
    }
    if (item.entity_type === "task") {
      const taskId = typeof item.data?.task_id === "string" ? item.data.task_id : item.entity_id;
      if (taskId) params.set("task_id", taskId);
    }
    router.push(`${target}?${params.toString()}`);
  };

  return (
    <main className="mx-auto max-w-4xl pb-12">
      <header className="flex flex-col gap-4 border-b border-stone-200 pb-5 dark:border-slate-800 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <Link href="/restaurant" className="mb-3 inline-flex items-center gap-2 text-sm font-medium text-slate-500 hover:text-slate-900 dark:hover:text-slate-100">
            <ArrowLeft size={16} /> Operación
          </Link>
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-amber-700">Pollo Móvil</p>
          <h1 className="mt-1 flex items-center gap-2 text-3xl font-bold tracking-tight"><Bell size={26} /> Notificaciones</h1>
          <p className="mt-1 text-sm text-slate-500">Asignaciones, incidencias, relevos y solicitudes de cobertura de tu sucursal.</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {branches.length > 1 && <select aria-label="Sucursal" className={controlClass} value={branchId} onChange={(event) => { rememberRestaurantBranchId(event.target.value); setBranchId(event.target.value); }}>{branches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name}</option>)}</select>}
          <button className={controlClass} onClick={() => void loadInbox()}><RefreshCw size={16} /> Actualizar</button>
          <button className={controlClass} disabled={!inbox.unread_count || !!busyId} onClick={() => void markRead()}><Check size={16} /> Leer todo</button>
        </div>
      </header>

      {error && <p role="status" className="mt-5 rounded-xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-700">{error}</p>}
      <section aria-label="Bandeja de notificaciones" className="mt-6 overflow-hidden rounded-2xl border border-stone-200 bg-white dark:border-slate-800 dark:bg-slate-900">
        <div className="flex items-center justify-between border-b border-stone-100 px-5 py-4 dark:border-slate-800">
          <h2 className="font-semibold">{branches.find((branch) => branch.id === branchId)?.name ?? "Sucursal"}</h2>
          <span className="text-sm text-slate-500">{inbox.unread_count} sin leer</span>
        </div>
        {loading ? <p className="px-5 py-8 text-sm text-slate-500">Cargando notificaciones…</p>
          : inbox.notifications.length === 0 ? <div className="px-5 py-10 text-center text-sm text-slate-500"><Bell className="mx-auto mb-3" size={24} />No tienes notificaciones todavía.</div>
            : <ul className="divide-y divide-stone-100 dark:divide-slate-800">{inbox.notifications.map((item) => <li key={item.id} className={`flex items-start gap-4 px-5 py-4 ${item.read_at ? "" : "bg-amber-50/40 dark:bg-amber-950/10"}`}>
              <div className="mt-0.5 text-amber-700">{item.notification_type.startsWith("incident_") ? <TriangleAlert size={19} /> : item.notification_type.startsWith("shift_handoff_") ? <ArrowRightLeft size={19} /> : item.notification_type.startsWith("shift_") || item.notification_type.startsWith("absence_") ? <CalendarClock size={19} /> : <ClipboardCheck size={19} />}</div>
              <div className="min-w-0 flex-1"><div className="flex items-center gap-2"><h3 className="font-semibold">{item.title}</h3>{!item.read_at && <Circle size={8} className="fill-amber-500 text-amber-500" />}</div><p className="mt-1 whitespace-pre-wrap text-sm text-slate-600 dark:text-slate-300">{item.body}</p><time className="mt-2 block text-xs text-slate-500" dateTime={item.created_at}>{new Date(item.created_at).toLocaleString("es-MX", { dateStyle: "medium", timeStyle: "short" })}</time><button type="button" className="mt-2 text-xs font-semibold text-amber-800 underline underline-offset-2 hover:text-amber-900 disabled:opacity-50 dark:text-amber-300" disabled={!!busyId || !branchId} onClick={() => void openNotification(item)}>Abrir módulo relacionado</button></div>
              {!item.read_at && <button className="shrink-0 rounded-lg border border-stone-200 px-3 py-2 text-xs font-semibold hover:bg-white disabled:opacity-50 dark:border-slate-700 dark:hover:bg-slate-800" disabled={!!busyId} onClick={() => void markRead(item.id)}>{busyId === item.id ? "Guardando…" : "Marcar leída"}</button>}
            </li>)}</ul>}
      </section>
    </main>
  );
}

const controlClass = "inline-flex min-h-10 items-center justify-center gap-2 rounded-lg border border-stone-300 bg-white px-3 text-sm font-medium text-slate-700 hover:bg-stone-50 disabled:opacity-50 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-200 dark:hover:bg-slate-800";
