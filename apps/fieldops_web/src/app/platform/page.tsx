"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabase } from "@/lib/supabase";
import { signOut } from "@/lib/auth";

type Company = {
  id: string; name: string; slug: string; status: string; industry: string | null;
  address?: string | null; phone?: string | null; email?: string | null; timezone?: string;
  created_at: string; active_user_count?: number; total_user_count?: number;
  branch_count?: number; active_branch_count?: number;
};
type Terms = {
  package_branch_count: number; monthly_price_per_branch_cents: number;
  additional_branch_monthly_price_cents: number; maximum_additional_branches: number;
  annual_custom_pricing_enabled: boolean; currency: string;
};
type License = {
  company_id: string; status: string; package_count: number; package_branch_count: number;
  additional_branch_count: number; licensed_branch_count: number;
  monthly_price_per_branch_cents: number; additional_branch_monthly_price_cents: number;
  currency: string; contract_reference: string; authorized_by: string; authorized_at: string;
  annual_price_override_cents: number | null; annual_approval_reference: string | null;
};
type Invitation = {
  id: string; company_id: string; email: string; full_name: string; status: string;
  expires_at: string; delivery_attempts: number; delivery_error_code: string | null;
  claimed_at: string | null; revoked_at: string | null; created_at: string;
};
type AuditEntry = {
  id: string; actor_id: string | null; actor_email?: string | null; action: string;
  target_type: string | null; target_id: string | null; before_json: unknown;
  after_json: unknown; created_at: string;
};
type Overview = {
  terms: Terms; companies: Company[]; licenses: License[];
  pending_invitation_count: number;
};
type CompanyDetail = {
  company: Company; user_count: number; branches: Array<{
    id: string; name: string; is_active: boolean; created_at: string;
    responsible_admins: Array<{ id: string; full_name: string; email: string | null }>;
  }>;
  license: License | null; invitations: Invitation[]; audit: AuditEntry[];
};
type Tab = "overview" | "customers" | "branches" | "licenses" | "invitations" | "audit";

const tabs: Array<{ id: Tab; label: string }> = [
  { id: "overview", label: "Resumen" }, { id: "customers", label: "Clientes" },
  { id: "branches", label: "Sucursales" }, { id: "licenses", label: "Licencias" },
  { id: "invitations", label: "Invitaciones" }, { id: "audit", label: "Auditoría" },
];
const panel = "rounded-2xl border border-stone-200 bg-white p-5 shadow-sm";
const input = "min-h-11 w-full rounded-lg border border-stone-300 bg-white px-3 py-2 text-sm text-slate-900 outline-none focus:border-amber-600 focus:ring-2 focus:ring-amber-100";
const primary = "inline-flex min-h-10 items-center justify-center rounded-lg bg-amber-600 px-4 py-2 text-sm font-semibold text-white hover:bg-amber-700 disabled:cursor-not-allowed disabled:opacity-50";
const secondary = "inline-flex min-h-10 items-center justify-center rounded-lg border border-stone-300 px-4 py-2 text-sm font-semibold text-slate-700 hover:bg-stone-50 disabled:opacity-50";

function money(cents: number | null | undefined, currency = "MXN") {
  if (typeof cents !== "number" || !Number.isFinite(cents)) return "No disponible";
  return new Intl.NumberFormat("es-MX", { style: "currency", currency }).format(cents / 100);
}
function date(value: string | null | undefined) {
  if (!value) return "—";
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? "—" : new Intl.DateTimeFormat("es-MX", { dateStyle: "medium" }).format(parsed);
}
function stateLabel(value: string) {
  return ({ active: "Activa", suspended: "Suspendida", sent: "Enviada", pending_delivery: "Pendiente de envío",
    delivery_failed: "Envío pendiente de reintento", claimed: "Aceptada", revoked: "Revocada", expired: "Vencida" } as Record<string, string>)[value] || value;
}

export default function PlatformAdminPage() {
  const router = useRouter();
  const [overview, setOverview] = useState<Overview | null>(null);
  const [tab, setTab] = useState<Tab>("overview");
  const [selectedCompanyId, setSelectedCompanyId] = useState("");
  const [detail, setDetail] = useState<CompanyDetail | null>(null);
  const [companyUsers, setCompanyUsers] = useState<Array<{ id: string; full_name: string; email: string | null; role: string; is_active: boolean }>>([]);
  const [globalInvitations, setGlobalInvitations] = useState<Invitation[]>([]);
  const [globalAudit, setGlobalAudit] = useState<AuditEntry[]>([]);
  const [query, setQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState("all");
  const [loading, setLoading] = useState(true);
  const [working, setWorking] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [createKey, setCreateKey] = useState<string | null>(null);
  const [newCompany, setNewCompany] = useState({ name: "", slug: "", industry: "", timezone: "America/Mexico_City", admin_name: "", admin_email: "" });
  const [profileForm, setProfileForm] = useState({ name: "", industry: "", address: "", phone: "", email: "", timezone: "America/Mexico_City" });
  const [commerciallyAuthorized, setCommerciallyAuthorized] = useState(false);
  const [authorizationReference, setAuthorizationReference] = useState("");
  const [licenseTerms, setLicenseTerms] = useState<Terms | null>(null);
  const [licenseForm, setLicenseForm] = useState({ company_id: "", package_count: 1, additional_branch_count: 0, contract_reference: "" });

  const request = useCallback(async function request<T = Record<string, unknown>>(
    action: string,
    body?: Record<string, unknown>,
    options?: { idempotencyKey?: string; query?: Record<string, string> },
  ): Promise<T> {
    const supabase = getSupabase();
    const { data, error: sessionError } = await supabase.auth.getSession();
    if (sessionError || !data.session) throw new Error("La sesión expiró. Inicia sesión de nuevo.");
    const baseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
    if (!baseUrl || !anonKey) throw new Error("Falta la configuración pública de Supabase.");
    const queryString = new URLSearchParams({ action, ...(options?.query || {}) });
    const response = await fetch(`${baseUrl}/functions/v1/platform_admin?${queryString.toString()}`, {
      method: body ? "POST" : "GET",
      headers: {
        Authorization: `Bearer ${data.session.access_token}`, apikey: anonKey,
        ...(body ? { "Content-Type": "application/json" } : {}),
        ...(options?.idempotencyKey ? { "Idempotency-Key": options.idempotencyKey } : {}),
      },
      ...(body ? { body: JSON.stringify({ action, ...body }) } : {}),
    });
    const payload = await response.json().catch(() => null) as Record<string, unknown> | null;
    if (!response.ok) {
      const message = typeof payload?.message === "string" ? payload.message
        : typeof payload?.error === "string" ? payload.error : `La solicitud falló (${response.status}).`;
      throw new Error(message);
    }
    return payload as T;
  }, []);

  const loadOverview = useCallback(async () => {
    setLoading(true); setError(null);
    try {
      const data = await request<Overview>("platform_overview");
      setOverview(data);
      setLicenseTerms(data.terms as Terms);
    } catch (err) {
      setError(err instanceof Error ? err.message : "No se pudo cargar la consola.");
    } finally { setLoading(false); }
  }, [request]);

  const loadCompany = useCallback(async (companyId: string) => {
    if (!companyId) return;
    setSelectedCompanyId(companyId); setError(null);
    try {
      const [companyResult, usersResult] = await Promise.all([
        request<CompanyDetail>("company_detail", undefined, { query: { company_id: companyId } }),
        request<{ users: Array<{ id: string; full_name: string; email: string | null; role: string; is_active: boolean }> }>("company_users", undefined, { query: { company_id: companyId } }),
      ]);
      const nextDetail = companyResult;
      setDetail(nextDetail);
      setCompanyUsers(usersResult.users || []);
      setProfileForm({ name: nextDetail.company.name, industry: nextDetail.company.industry || "",
        address: nextDetail.company.address || "", phone: nextDetail.company.phone || "",
        email: nextDetail.company.email || "", timezone: nextDetail.company.timezone || "America/Mexico_City" });
      setLicenseForm((current) => ({ ...current, company_id: companyId,
        package_count: nextDetail.license?.package_count || 1,
        additional_branch_count: nextDetail.license?.additional_branch_count || 0,
        contract_reference: nextDetail.license?.contract_reference || "" }));
    } catch (err) { setError(err instanceof Error ? err.message : "No se pudo cargar la ficha del cliente."); }
  }, [request]);

  useEffect(() => { void loadOverview(); }, [loadOverview]);
  useEffect(() => {
    if (tab === "invitations") void request<{ invitations: Invitation[] }>("company_admin_invites").then((data) => setGlobalInvitations(data.invitations || []))
      .catch((err) => setError(err instanceof Error ? err.message : "No se pudieron cargar las invitaciones."));
    if (tab === "audit") void request<{ audit_logs: AuditEntry[] }>("audit", undefined, { query: { limit: "100" } }).then((data) => setGlobalAudit(data.audit_logs || []))
      .catch((err) => setError(err instanceof Error ? err.message : "No se pudo cargar la auditoría."));
  }, [request, tab]);

  const licensesByCompany = useMemo(() => new Map((overview?.licenses || []).map((license) => [license.company_id, license])), [overview]);
  const filteredCompanies = useMemo(() => (overview?.companies || []).filter((company) => {
    const matchesQuery = `${company.name} ${company.slug} ${company.industry || ""}`.toLocaleLowerCase().includes(query.toLocaleLowerCase());
    return matchesQuery && (statusFilter === "all" || company.status === statusFilter);
  }), [overview, query, statusFilter]);
  const activeCompanies = overview?.companies.filter((company) => company.status === "active").length || 0;
  const inactiveCompanies = Math.max(0, (overview?.companies.length || 0) - activeCompanies);
  const branchCount = overview?.companies.reduce((sum, company) => sum + (company.branch_count || 0), 0) || 0;
  const activeBranchCount = overview?.companies.reduce((sum, company) => sum + (company.active_branch_count || 0), 0) || 0;
  const licensedCapacity = overview?.licenses.filter((license) => license.status === "active")
    .reduce((sum, license) => sum + Number(license.licensed_branch_count || 0), 0) || 0;

  async function refresh(companyId = selectedCompanyId) {
    await loadOverview();
    if (companyId) await loadCompany(companyId);
  }
  async function createCompany(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setWorking(true); setError(null); setNotice(null);
    const key = createKey || crypto.randomUUID(); setCreateKey(key);
    try {
      const result = await request<{ invitation?: { message?: string }; company?: Company }>("create_company", newCompany, { idempotencyKey: key });
      setNotice(`${result.invitation?.message || "Cliente registrado."} La empresa no recibe sucursales activas hasta autorizar su licencia.`);
      setNewCompany({ name: "", slug: "", industry: "", timezone: "America/Mexico_City", admin_name: "", admin_email: "" });
      setCreateKey(null); setTab("customers"); await refresh(result.company?.id || "");
    } catch (err) { setError(err instanceof Error ? err.message : "No se pudo registrar la empresa."); }
    finally { setWorking(false); }
  }
  async function updateCompany(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (!detail) return;
    setWorking(true); setError(null); setNotice(null);
    try {
      await request("update_company", { company_id: detail.company.id, ...profileForm });
      setNotice("Información administrativa actualizada."); await refresh(detail.company.id);
    } catch (err) { setError(err instanceof Error ? err.message : "No se pudo actualizar la empresa."); }
    finally { setWorking(false); }
  }
  async function changeCompanyStatus() {
    if (!detail) return;
    const next = detail.company.status === "active" ? "suspended" : "active";
    const message = next === "suspended"
      ? "Suspenderá el acceso de esta empresa a los datos operativos. No se borrarán usuarios, sucursales ni historial. ¿Continuar?"
      : "Reactivará el acceso de esta empresa según sus licencias vigentes. ¿Continuar?";
    if (!window.confirm(message)) return;
    setWorking(true); setError(null); setNotice(null);
    try { await request("toggle_company", { company_id: detail.company.id, status: next }); setNotice(`Empresa ${next === "active" ? "reactivada" : "suspendida"}.`); await refresh(detail.company.id); }
    catch (err) { setError(err instanceof Error ? err.message : "No se pudo cambiar el estado."); }
    finally { setWorking(false); }
  }
  async function saveLicense(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setWorking(true); setError(null); setNotice(null);
    try {
      await request("set_company_license", { commercially_authorized: commerciallyAuthorized,
        company_id: licenseForm.company_id, package_count: Number(licenseForm.package_count),
        additional_branch_count: Number(licenseForm.additional_branch_count), contract_reference: licenseForm.contract_reference });
      setNotice("Autorización de licencia registrada en el historial."); setCommerciallyAuthorized(false); await refresh(licenseForm.company_id);
    } catch (err) { setError(err instanceof Error ? err.message : "No se pudo registrar la licencia."); }
    finally { setWorking(false); }
  }
  async function saveTerms(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (!licenseTerms) return;
    setWorking(true); setError(null); setNotice(null);
    try {
      await request("update_license_terms", { commercially_authorized: commerciallyAuthorized,
        authorization_reference: authorizationReference, ...licenseTerms });
      setNotice("Condiciones comerciales actualizadas con autorización registrada.");
      setCommerciallyAuthorized(false); setAuthorizationReference(""); await loadOverview();
    } catch (err) { setError(err instanceof Error ? err.message : "No se pudieron guardar las condiciones."); }
    finally { setWorking(false); }
  }
  async function invitationAction(action: "resend_company_admin_invite" | "revoke_company_admin_invite", invitation: Invitation) {
    if (action === "revoke_company_admin_invite" && !window.confirm(`¿Revocar la invitación de ${invitation.email}? El enlace dejará de conceder acceso.`)) return;
    setWorking(true); setError(null); setNotice(null);
    try {
      const result = await request<{ invitation?: { message?: string } }>(action, { invitation_id: invitation.id });
      setNotice(result.invitation?.message || "Estado de invitación actualizado.");
      if (selectedCompanyId) await refresh(selectedCompanyId);
      const list = await request<{ invitations: Invitation[] }>("company_admin_invites"); setGlobalInvitations(list.invitations || []);
    } catch (err) { setError(err instanceof Error ? err.message : "No se pudo completar la acción de invitación."); }
    finally { setWorking(false); }
  }

  const selectedCompany = overview?.companies.find((company) => company.id === selectedCompanyId) || null;

  return <main className="min-h-screen bg-stone-50 text-slate-900">
    <header className="border-b border-stone-200 bg-white">
      <div className="mx-auto flex max-w-7xl items-center justify-between gap-4 px-4 py-4 sm:px-6 lg:px-8">
        <div><p className="text-sm font-bold uppercase tracking-wide text-amber-700">Pollo Móvil · Consola SaaS</p><h1 className="text-xl font-bold sm:text-2xl">Administración de plataforma</h1></div>
        <button className={secondary} onClick={async () => { await signOut(); router.replace("/"); }}>Cerrar sesión</button>
      </div>
    </header>
    <div className="mx-auto max-w-7xl px-4 py-5 sm:px-6 lg:px-8">
      <nav aria-label="Navegación de plataforma" className="mb-5 flex gap-2 overflow-x-auto pb-1">
        {tabs.map((item) => <button key={item.id} role="tab" aria-selected={tab === item.id} onClick={() => setTab(item.id)}
          className={`min-h-10 shrink-0 rounded-lg px-4 text-sm font-semibold ${tab === item.id ? "bg-slate-900 text-white" : "border border-stone-300 bg-white text-slate-700 hover:bg-stone-100"}`}>{item.label}</button>)}
      </nav>
      {error && <div role="alert" className="mb-4 rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-800">{error}</div>}
      {notice && <div role="status" className="mb-4 rounded-xl border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-800">{notice}</div>}
      {loading ? <div role="status" className={`${panel} text-sm text-slate-600`}>Cargando información real de la plataforma…</div> : !overview ? <div className={panel}><p>No se pudo cargar la consola.</p><button className={`${secondary} mt-3`} onClick={() => void loadOverview()}>Reintentar</button></div> : <>
        {tab === "overview" && <section aria-label="Resumen" className="space-y-5">
          <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
            {[["Empresas", overview.companies.length], ["Empresas activas", activeCompanies], ["Empresas inactivas", inactiveCompanies], ["Sucursales registradas", branchCount], ["Invitaciones pendientes", overview.pending_invitation_count]].map(([label, value]) => <article key={String(label)} className={panel}><p className="text-sm text-slate-500">{label}</p><p className="mt-2 text-3xl font-bold">{value}</p></article>)}
          </div>
          <div className="grid gap-3 sm:grid-cols-3">
            <article className={panel}><p className="text-sm text-slate-500">Licencias contratadas</p><p className="mt-2 text-2xl font-bold">{licensedCapacity}</p></article>
            <article className={panel}><p className="text-sm text-slate-500">Licencias utilizadas</p><p className="mt-2 text-2xl font-bold">{activeBranchCount}</p></article>
            <article className={panel}><p className="text-sm text-slate-500">Disponibles</p><p className="mt-2 text-2xl font-bold">{Math.max(0, licensedCapacity - activeBranchCount)}</p></article>
          </div>
          <section className={panel}><h2 className="text-lg font-semibold">Clientes recientes</h2>
            {overview.companies.length ? <div className="mt-3 divide-y divide-stone-100">{overview.companies.slice(0, 8).map((company) => <button key={company.id} onClick={() => { setTab("customers"); void loadCompany(company.id); }} className="grid w-full gap-1 py-3 text-left sm:grid-cols-[1fr_1fr_auto] sm:items-center"><span className="font-medium">{company.name}</span><span className="text-sm text-slate-500">{company.slug}</span><span className="text-sm">{stateLabel(company.status)}</span></button>)}</div> : <p className="mt-3 text-sm text-slate-600">Aún no hay empresas clientes. La cuenta de plataforma no requiere pertenecer a una empresa.</p>}
          </section>
          <section className={panel}><h2 className="text-lg font-semibold">Notas de datos</h2><p className="mt-2 text-sm text-slate-600">Las licencias representan capacidad contractual configurada, no ingresos cobrados. Los datos se consultan desde Supabase; esta consola no muestra métricas financieras de cobro.</p></section>
        </section>}

        {tab === "customers" && <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)]">
          <section className={panel}><div className="flex flex-wrap items-end justify-between gap-3"><div><h2 className="text-lg font-semibold">Empresas clientes</h2><p className="mt-1 text-sm text-slate-500">Consulta y administra los datos existentes.</p></div><label className="text-sm">Estado<select className={`${input} mt-1`} value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}><option value="all">Todos</option><option value="active">Activas</option><option value="suspended">Suspendidas</option></select></label></div>
            <label className="mt-4 block text-sm">Buscar empresas<input className={`${input} mt-1`} value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Nombre, identificador o industria" /></label>
            <div className="mt-3 divide-y divide-stone-100">{filteredCompanies.length ? filteredCompanies.map((company) => <button key={company.id} onClick={() => void loadCompany(company.id)} className={`w-full rounded-lg px-2 py-3 text-left hover:bg-stone-50 ${selectedCompanyId === company.id ? "bg-amber-50" : ""}`}><span className="flex flex-wrap items-center justify-between gap-2"><strong>{company.name}</strong><span className="text-xs">{stateLabel(company.status)}</span></span><span className="mt-1 block text-sm text-slate-500">{company.slug} · {company.active_branch_count || 0} sucursales activas · {company.active_user_count || 0} cuentas activas</span></button>) : <p className="py-5 text-sm text-slate-500">No hay coincidencias para el filtro actual.</p>}</div>
          </section>
          <div className="space-y-5">
            <section className={panel}><h2 className="text-lg font-semibold">Registrar cliente e invitar administrador</h2><p className="mt-1 text-sm text-slate-600">No se crea una contraseña ni se activa una licencia. El acceso se otorga después de verificar el correo y aceptar la invitación.</p>
              <form className="mt-4 grid gap-3 sm:grid-cols-2" onSubmit={createCompany}>
                <label className="text-sm">Nombre de empresa<input required maxLength={160} className={`${input} mt-1`} value={newCompany.name} onChange={(e) => setNewCompany({ ...newCompany, name: e.target.value })} /></label>
                <label className="text-sm">Identificador URL<input required pattern="[a-z0-9]+(-[a-z0-9]+)*" maxLength={100} className={`${input} mt-1`} value={newCompany.slug} onChange={(e) => setNewCompany({ ...newCompany, slug: e.target.value.toLowerCase() })} /></label>
                <label className="text-sm">Industria (opcional)<input maxLength={120} className={`${input} mt-1`} value={newCompany.industry} onChange={(e) => setNewCompany({ ...newCompany, industry: e.target.value })} /></label>
                <label className="text-sm">Zona horaria<input required maxLength={100} className={`${input} mt-1`} value={newCompany.timezone} onChange={(e) => setNewCompany({ ...newCompany, timezone: e.target.value })} /></label>
                <label className="text-sm">Nombre del administrador<input required minLength={2} maxLength={120} autoComplete="name" className={`${input} mt-1`} value={newCompany.admin_name} onChange={(e) => setNewCompany({ ...newCompany, admin_name: e.target.value })} /></label>
                <label className="text-sm">Correo del administrador<input required type="email" maxLength={254} autoComplete="email" className={`${input} mt-1`} value={newCompany.admin_email} onChange={(e) => setNewCompany({ ...newCompany, admin_email: e.target.value })} /></label>
                <button className={`${primary} sm:col-span-2`} disabled={working}>{working ? "Registrando…" : "Registrar empresa y enviar invitación"}</button>
              </form>
            </section>
            {detail && <section className={panel}><div className="flex flex-wrap items-start justify-between gap-3"><div><h2 className="text-lg font-semibold">Ficha: {detail.company.name}</h2><p className="text-sm text-slate-500">{detail.company.slug} · registrada {date(detail.company.created_at)}</p></div><button className={secondary} disabled={working} onClick={() => void changeCompanyStatus()}>{detail.company.status === "active" ? "Suspender acceso" : "Reactivar empresa"}</button></div>
              <form className="mt-4 grid gap-3 sm:grid-cols-2" onSubmit={updateCompany}>
                <label className="text-sm">Nombre<input required maxLength={160} className={`${input} mt-1`} value={profileForm.name} onChange={(e) => setProfileForm({ ...profileForm, name: e.target.value })} /></label>
                <label className="text-sm">Industria<input className={`${input} mt-1`} value={profileForm.industry} onChange={(e) => setProfileForm({ ...profileForm, industry: e.target.value })} /></label>
                <label className="text-sm">Correo de contacto<input type="email" className={`${input} mt-1`} value={profileForm.email} onChange={(e) => setProfileForm({ ...profileForm, email: e.target.value })} /></label>
                <label className="text-sm">Teléfono<input className={`${input} mt-1`} value={profileForm.phone} onChange={(e) => setProfileForm({ ...profileForm, phone: e.target.value })} /></label>
                <label className="text-sm sm:col-span-2">Domicilio<input className={`${input} mt-1`} value={profileForm.address} onChange={(e) => setProfileForm({ ...profileForm, address: e.target.value })} /></label>
                <label className="text-sm">Zona horaria<input required className={`${input} mt-1`} value={profileForm.timezone} onChange={(e) => setProfileForm({ ...profileForm, timezone: e.target.value })} /></label>
                <button className={`${primary} self-end`} disabled={working}>Guardar ficha</button>
              </form>
              <h3 className="mt-6 font-semibold">Administradores y usuarios ({detail.user_count})</h3>
              {companyUsers.length ? <div className="mt-2 divide-y divide-stone-100">{companyUsers.map((person) => <div key={person.id} className="flex flex-wrap justify-between gap-2 py-2 text-sm"><span>{person.full_name} <span className="text-slate-500">{person.email || "Sin correo"}</span></span><span>{person.role}{person.is_active ? " · activo" : " · inactivo"}</span></div>)}</div> : <p className="mt-2 text-sm text-slate-500">Todavía no hay usuarios vinculados; el primer administrador recibirá una invitación.</p>}
            </section>}
          </div>
        </div>}

        {tab === "branches" && <section className={panel}><div className="flex flex-wrap items-end justify-between gap-3"><div><h2 className="text-lg font-semibold">Sucursales por empresa</h2><p className="mt-1 text-sm text-slate-500">La activación continúa protegida por el límite de licencias en PostgreSQL.</p></div><select aria-label="Seleccionar empresa" className={`${input} max-w-sm`} value={selectedCompanyId} onChange={(e) => void loadCompany(e.target.value)}><option value="">Selecciona empresa</option>{overview.companies.map((company) => <option key={company.id} value={company.id}>{company.name}</option>)}</select></div>
          {selectedCompany && detail ? <><div className="mt-4 grid gap-3 sm:grid-cols-3"><p className="rounded-xl bg-stone-50 p-3 text-sm">Registradas: <strong>{detail.branches.length}</strong></p><p className="rounded-xl bg-stone-50 p-3 text-sm">Activas: <strong>{detail.branches.filter((branch) => branch.is_active).length}</strong></p><p className="rounded-xl bg-stone-50 p-3 text-sm">Capacidad licenciada: <strong>{detail.license?.licensed_branch_count ?? "Sin licencia"}</strong></p></div>
            <div className="mt-4 divide-y divide-stone-100">{detail.branches.length ? detail.branches.map((branch) => <div key={branch.id} className="grid gap-2 py-3 sm:grid-cols-[1fr_auto_1fr] sm:items-center"><div><strong>{branch.name}</strong><p className="text-xs text-slate-500">ID {branch.id}</p></div><span className="text-sm">{branch.is_active ? "Activa" : "Inactiva"} · {date(branch.created_at)}</span><span className="text-sm text-slate-600">Administradores: {branch.responsible_admins.length ? branch.responsible_admins.map((person) => person.full_name).join(", ") : "No asignados"}</span></div>) : <p className="py-5 text-sm text-slate-500">No hay sucursales registradas para esta empresa.</p>}</div></> : <p className="mt-5 text-sm text-slate-500">Selecciona una empresa para consultar sus sucursales y responsables.</p>}
        </section>}

        {tab === "licenses" && <div className="space-y-5">
          <section className={panel}><h2 className="text-lg font-semibold">Licencias contratadas</h2><p className="mt-1 text-sm text-slate-600">Precio contractual configurado; no representa ingresos cobrados. Toda modificación requiere referencia contractual y autorización comercial.</p>
            <div className="mt-4 overflow-x-auto"><table className="w-full min-w-[720px] text-left text-sm"><thead><tr className="border-b text-xs uppercase text-slate-500"><th className="py-2">Empresa</th><th>Estado</th><th>Paquete</th><th>Uso / capacidad</th><th>Precio mensual contractual</th><th>Referencia</th></tr></thead><tbody>{overview.companies.map((company) => { const license = licensesByCompany.get(company.id); const monthly = license ? Number(license.package_count) * Number(license.package_branch_count) * Number(license.monthly_price_per_branch_cents) + Number(license.additional_branch_count) * Number(license.additional_branch_monthly_price_cents) : null; return <tr key={company.id} className="border-b border-stone-100"><td className="py-3 font-medium">{company.name}</td><td>{license ? stateLabel(license.status) : "Sin licencia"}</td><td>{license ? `${license.package_count} × ${license.package_branch_count}${license.additional_branch_count ? ` + ${license.additional_branch_count} adicional` : ""}` : "—"}</td><td>{company.active_branch_count || 0} / {license?.licensed_branch_count ?? 0}</td><td>{license ? money(monthly, license.currency) : "—"}</td><td>{license?.contract_reference || "—"}</td></tr>; })}</tbody></table></div>
          </section>
          <section className={panel}><h3 className="text-base font-semibold">Autorizar capacidad contratada</h3>
            <form className="mt-3 grid gap-3 md:grid-cols-2" onSubmit={saveLicense}>
              <label className="text-sm">Empresa<select required className={`${input} mt-1`} value={licenseForm.company_id} onChange={(e) => setLicenseForm({ ...licenseForm, company_id: e.target.value })}><option value="">Selecciona empresa</option>{overview.companies.map((company) => <option key={company.id} value={company.id}>{company.name}</option>)}</select></label>
              <label className="text-sm">Referencia contractual<input required maxLength={200} className={`${input} mt-1`} value={licenseForm.contract_reference} onChange={(e) => setLicenseForm({ ...licenseForm, contract_reference: e.target.value })} /></label>
              <label className="text-sm">Paquetes de {overview.terms.package_branch_count}<input type="number" min={1} required className={`${input} mt-1`} value={licenseForm.package_count} onChange={(e) => setLicenseForm({ ...licenseForm, package_count: Number(e.target.value) })} /></label>
              <label className="text-sm">Licencias individuales adicionales (antes de ampliar paquete)<input type="number" min={0} max={overview.terms.maximum_additional_branches} required className={`${input} mt-1`} value={licenseForm.additional_branch_count} onChange={(e) => setLicenseForm({ ...licenseForm, additional_branch_count: Number(e.target.value) })} /></label>
              <label className="flex items-start gap-2 text-sm md:col-span-2"><input type="checkbox" className="mt-1" checked={commerciallyAuthorized} onChange={(e) => setCommerciallyAuthorized(e.target.checked)} />Confirmo que la capacidad coincide con una autorización comercial/contractual registrada.</label>
              <button className={`${primary} md:col-span-2`} disabled={working || !commerciallyAuthorized}>{working ? "Guardando…" : "Registrar licencia autorizada"}</button>
            </form>
          </section>
          <section className={panel}><h3 className="text-base font-semibold">Términos configurables</h3><p className="mt-1 text-sm text-slate-600">Paquete base: {overview.terms.package_branch_count} · {money(overview.terms.monthly_price_per_branch_cents, overview.terms.currency)} por sucursal/mes · adicional individual: {money(overview.terms.additional_branch_monthly_price_cents, overview.terms.currency)} · máximo de adicionales antes de ampliar: {overview.terms.maximum_additional_branches}. Tarifas anuales requieren aprobación explícita.</p>
            <form className="mt-4 grid gap-3 sm:grid-cols-2" onSubmit={saveTerms}>
              <label className="text-sm">Sucursales por paquete<input type="number" min={1} required className={`${input} mt-1`} value={licenseTerms?.package_branch_count || 5} onChange={(e) => setLicenseTerms({ ...overview.terms, package_branch_count: Number(e.target.value) })} /></label>
              <label className="text-sm">Precio por sucursal (centavos)<input type="number" min={0} required className={`${input} mt-1`} value={licenseTerms?.monthly_price_per_branch_cents || 0} onChange={(e) => setLicenseTerms({ ...overview.terms, monthly_price_per_branch_cents: Number(e.target.value) })} /></label>
              <label className="text-sm">Precio adicional (centavos)<input type="number" min={0} required className={`${input} mt-1`} value={licenseTerms?.additional_branch_monthly_price_cents || 0} onChange={(e) => setLicenseTerms({ ...overview.terms, additional_branch_monthly_price_cents: Number(e.target.value) })} /></label>
              <label className="text-sm">Adicionales antes de ampliar paquete<input type="number" min={0} max={1} required className={`${input} mt-1`} value={licenseTerms?.maximum_additional_branches ?? 1} onChange={(e) => setLicenseTerms({ ...overview.terms, maximum_additional_branches: Number(e.target.value) })} /></label>
              <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={licenseTerms?.annual_custom_pricing_enabled || false} onChange={(e) => setLicenseTerms({ ...overview.terms, annual_custom_pricing_enabled: e.target.checked })} />Permitir precio anual excepcional con aprobación documentada</label>
              <label className="text-sm">Moneda<input required pattern="[A-Z]{3}" maxLength={3} className={`${input} mt-1`} value={licenseTerms?.currency || overview.terms.currency} onChange={(e) => setLicenseTerms({ ...overview.terms, currency: e.target.value.toUpperCase() })} /></label>
              <label className="text-sm sm:col-span-2">Referencia de autorización<input required maxLength={200} className={`${input} mt-1`} value={authorizationReference} onChange={(e) => setAuthorizationReference(e.target.value)} /></label>
              <label className="flex items-start gap-2 text-sm sm:col-span-2"><input type="checkbox" className="mt-1" checked={commerciallyAuthorized} onChange={(e) => setCommerciallyAuthorized(e.target.checked)} />Autorizo explícitamente este cambio de términos comerciales.</label>
              <button className={primary} disabled={working || !commerciallyAuthorized || !authorizationReference.trim()}>Guardar términos autorizados</button>
            </form>
          </section>
        </div>}

        {tab === "invitations" && <section className={panel}><h2 className="text-lg font-semibold">Invitaciones de administradores corporativos</h2><p className="mt-1 text-sm text-slate-600">No se exponen tokens. La cuenta obtiene rol corporativo únicamente tras verificar su correo y reclamar una invitación vigente.</p>
          {globalInvitations.length ? <div className="mt-4 divide-y divide-stone-100">{globalInvitations.map((invitation) => { const company = overview.companies.find((item) => item.id === invitation.company_id); const terminalConflict = ["existing_account_company_conflict", "account_already_has_company_access"].includes(invitation.delivery_error_code || ""); const canResend = ["pending_delivery", "delivery_failed", "sent"].includes(invitation.status) && !terminalConflict; const canRevoke = ["pending_delivery", "delivery_failed", "sent"].includes(invitation.status); const isExpired = new Date(invitation.expires_at).getTime() <= Date.now(); return <article key={invitation.id} className="grid gap-3 py-4 lg:grid-cols-[1fr_1fr_auto] lg:items-center"><div><strong>{invitation.full_name}</strong><p className="text-sm text-slate-600">{invitation.email} · {company?.name || "Empresa no disponible"}</p></div><div className="text-sm">{stateLabel(isExpired && canRevoke ? "expired" : invitation.status)} · vence {date(invitation.expires_at)}{invitation.delivery_error_code && <p className="text-xs text-amber-700">Pendiente de resolución: {invitation.delivery_error_code}</p>}</div><div className="flex gap-2"><button className={secondary} disabled={working || !canResend} onClick={() => void invitationAction("resend_company_admin_invite", invitation)}>Reenviar</button><button className="min-h-10 rounded-lg border border-red-300 px-3 text-sm font-semibold text-red-700 disabled:opacity-40" disabled={working || !canRevoke} onClick={() => void invitationAction("revoke_company_admin_invite", invitation)}>Revocar</button></div></article>; })}</div> : <p className="mt-4 text-sm text-slate-500">No hay invitaciones para mostrar.</p>}
        </section>}

        {tab === "audit" && <section className={panel}><h2 className="text-lg font-semibold">Registro administrativo</h2><p className="mt-1 text-sm text-slate-600">Eventos de solo lectura; contraseñas, tokens y enlaces se omiten antes de responder al cliente.</p>
          {globalAudit.length ? <div className="mt-4 divide-y divide-stone-100">{globalAudit.map((entry) => <article key={entry.id} className="grid gap-1 py-3 sm:grid-cols-[1fr_auto]"><div><strong>{entry.action}</strong><p className="text-sm text-slate-600">{entry.target_type || "—"} · {entry.target_id || "—"} · {entry.actor_email || entry.actor_id || "Sistema"}</p><details className="mt-1 text-xs text-slate-500"><summary className="cursor-pointer">Ver metadatos</summary><pre className="mt-2 overflow-x-auto whitespace-pre-wrap">{JSON.stringify({ before: entry.before_json, after: entry.after_json }, null, 2)}</pre></details></div><time className="text-sm text-slate-500">{date(entry.created_at)}</time></article>)}</div> : <p className="mt-4 text-sm text-slate-500">No hay eventos de auditoría disponibles.</p>}
        </section>}
      </>}
    </div>
  </main>;
}
