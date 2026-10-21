"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabase } from "@/lib/supabase";
import { signOut } from "@/lib/auth";

type Overview = {
  terms: {
    package_branch_count: number;
    monthly_price_per_branch_cents: number;
    additional_branch_monthly_price_cents: number;
    maximum_additional_branches: number;
    annual_custom_pricing_enabled: boolean;
    currency: string;
  };
  companies: Array<{ id: string; name: string; slug: string; status: string }>;
  licenses: Array<{
    company_id: string;
    status: string;
    package_count: number;
    additional_branch_count: number;
    licensed_branch_count: number;
    contract_reference: string;
  }>;
};

export default function PlatformAdminPage() {
  const router = useRouter();
  const [overview, setOverview] = useState<Overview | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [working, setWorking] = useState(false);
  const [commerciallyAuthorized, setCommerciallyAuthorized] = useState(false);
  const [authorizationReference, setAuthorizationReference] = useState("");
  const [selectedCompany, setSelectedCompany] = useState("");
  const [packageCount, setPackageCount] = useState(1);
  const [additionalBranches, setAdditionalBranches] = useState(0);
  const [contractReference, setContractReference] = useState("");

  const request = useCallback(async (action: string, body?: Record<string, unknown>) => {
    const supabase = getSupabase();
    const { data } = await supabase.auth.getSession();
    if (!data.session) throw new Error("La sesión expiró. Inicia sesión de nuevo.");
    const baseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
    if (!baseUrl || !anonKey) throw new Error("Falta la configuración pública de Supabase.");
    const response = await fetch(`${baseUrl}/functions/v1/platform_admin${body ? "" : `?action=${encodeURIComponent(action)}`}`, {
      method: body ? "POST" : "GET",
      headers: {
        Authorization: `Bearer ${data.session.access_token}`,
        apikey: anonKey,
        ...(body ? { "Content-Type": "application/json" } : {}),
      },
      ...(body ? { body: JSON.stringify({ action, ...body }) } : {}),
    });
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.message || payload.error || `Error ${response.status}`);
    return payload;
  }, []);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const result = await request("platform_overview");
      setOverview(result as Overview);
    } catch (err) {
      setError(err instanceof Error ? err.message : "No se pudo cargar el panel de plataforma.");
    } finally {
      setLoading(false);
    }
  }, [request]);

  useEffect(() => { void load(); }, [load]);

  async function saveLicense() {
    setWorking(true);
    setError(null);
    try {
      await request("set_company_license", {
        commercially_authorized: commerciallyAuthorized,
        company_id: selectedCompany,
        package_count: packageCount,
        additional_branch_count: additionalBranches,
        contract_reference: contractReference,
      });
      setContractReference("");
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : "No se pudo registrar la licencia.");
    } finally {
      setWorking(false);
    }
  }

  async function saveTerms() {
    if (!overview) return;
    setWorking(true);
    setError(null);
    try {
      await request("update_license_terms", {
        commercially_authorized: commerciallyAuthorized,
        authorization_reference: authorizationReference,
        package_branch_count: overview.terms.package_branch_count,
        monthly_price_per_branch_cents: overview.terms.monthly_price_per_branch_cents,
        additional_branch_monthly_price_cents: overview.terms.additional_branch_monthly_price_cents,
        maximum_additional_branches: overview.terms.maximum_additional_branches,
        annual_custom_pricing_enabled: overview.terms.annual_custom_pricing_enabled,
        currency: overview.terms.currency,
      });
      setAuthorizationReference("");
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : "No se pudieron guardar las condiciones.");
    } finally {
      setWorking(false);
    }
  }

  const licenseByCompany = new Map((overview?.licenses || []).map((license) => [license.company_id, license]));

  return (
    <main className="min-h-screen bg-stone-50 p-6 text-slate-900">
      <header className="mx-auto flex max-w-6xl items-center justify-between">
        <div><p className="text-sm font-semibold text-amber-700">Pollo Móvil</p><h1 className="text-2xl font-bold">Administración de plataforma</h1></div>
        <button className="rounded-lg border px-4 py-2 text-sm" onClick={async () => { await signOut(); router.replace("/"); }}>Cerrar sesión</button>
      </header>
      <div className="mx-auto mt-6 max-w-6xl space-y-6">
        {error && <p role="alert" className="rounded-lg bg-red-50 p-3 text-sm text-red-700">{error}</p>}
        {loading ? <p>Cargando información de plataforma…</p> : overview && <>
          <section className="rounded-xl border bg-white p-5 shadow-sm">
            <h2 className="text-lg font-semibold">Clientes</h2>
            {overview.companies.length === 0 ? <p className="mt-3 text-sm text-slate-600">No hay empresas registradas. Tu acceso de plataforma no depende de una empresa o sucursal.</p> :
              <div className="mt-3 divide-y">{overview.companies.map((company) => <div key={company.id} className="grid gap-2 py-3 sm:grid-cols-3"><span className="font-medium">{company.name}</span><span className="text-sm text-slate-600">{company.slug}</span><span className="text-sm">{company.status}</span></div>)}</div>}
          </section>
          <section className="rounded-xl border bg-white p-5 shadow-sm">
            <h2 className="text-lg font-semibold">Condiciones comerciales configuradas</h2>
            <p className="mt-2 text-sm text-slate-700">Paquete base: {overview.terms.package_branch_count} sucursales · ${overview.terms.monthly_price_per_branch_cents / 100} MXN por sucursal/mes. Sucursal adicional: ${overview.terms.additional_branch_monthly_price_cents / 100} MXN/mes. Máximo antes de ampliar paquete: {overview.terms.maximum_additional_branches}. Tarifas anuales personalizadas: requieren aprobación registrada.</p>
            <div className="mt-4 grid gap-3 sm:grid-cols-2">
              <input aria-label="Referencia de autorización comercial" className="rounded-lg border px-3 py-2" placeholder="Referencia de autorización comercial" value={authorizationReference} onChange={(e) => setAuthorizationReference(e.target.value)} />
              <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={commerciallyAuthorized} onChange={(e) => setCommerciallyAuthorized(e.target.checked)} />Confirmo autorización comercial explícita para guardar estas condiciones</label>
            </div>
            <button disabled={working || !commerciallyAuthorized || !authorizationReference.trim()} onClick={saveTerms} className="mt-3 rounded-lg bg-slate-900 px-4 py-2 text-sm font-semibold text-white disabled:opacity-40">Registrar condiciones actuales y autorización</button>
          </section>
          <section className="rounded-xl border bg-white p-5 shadow-sm">
            <h2 className="text-lg font-semibold">Licencias de sucursales</h2>
            <div className="mt-3 divide-y">{overview.companies.map((company) => {
              const license = licenseByCompany.get(company.id);
              return <div key={company.id} className="py-3 text-sm"><strong>{company.name}</strong>{license ? <span className="ml-2 text-slate-600">{license.status}: {license.licensed_branch_count} sucursales · contrato {license.contract_reference}</span> : <span className="ml-2 text-amber-700">Sin licencia; no se habilitan sucursales.</span>}</div>;
            })}</div>
            {overview.companies.length > 0 && <div className="mt-5 grid gap-3 md:grid-cols-2">
              <select aria-label="Empresa" className="rounded-lg border px-3 py-2" value={selectedCompany} onChange={(e) => setSelectedCompany(e.target.value)}><option value="">Selecciona empresa</option>{overview.companies.map((company) => <option key={company.id} value={company.id}>{company.name}</option>)}</select>
              <input aria-label="Referencia contractual" className="rounded-lg border px-3 py-2" placeholder="Referencia contractual" value={contractReference} onChange={(e) => setContractReference(e.target.value)} />
              <label className="text-sm">Paquetes de 5 sucursales<input type="number" min={1} className="mt-1 block w-full rounded-lg border px-3 py-2" value={packageCount} onChange={(e) => setPackageCount(Number(e.target.value))} /></label>
              <label className="text-sm">Sucursales adicionales (antes de ampliar paquete)<input type="number" min={0} max={overview.terms.maximum_additional_branches} className="mt-1 block w-full rounded-lg border px-3 py-2" value={additionalBranches} onChange={(e) => setAdditionalBranches(Number(e.target.value))} /></label>
              <label className="flex items-center gap-2 text-sm md:col-span-2"><input type="checkbox" checked={commerciallyAuthorized} onChange={(e) => setCommerciallyAuthorized(e.target.checked)} />Confirmo autorización contractual/comercial para activar o cambiar esta licencia</label>
              <button disabled={working || !selectedCompany || !contractReference.trim() || !commerciallyAuthorized} onClick={saveLicense} className="rounded-lg bg-amber-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-40 md:col-span-2">Guardar licencia autorizada</button>
            </div>}
          </section>
        </>}
      </div>
    </main>
  );
}
