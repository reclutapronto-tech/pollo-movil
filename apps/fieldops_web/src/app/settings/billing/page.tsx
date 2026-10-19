"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { getSupabase } from "@/lib/supabase";
import { isManagementRole } from "@/lib/roles";
import { useCurrentUser } from "@/lib/use-role";

interface BillingCompany {
  id: string;
  name: string;
  billing_mode: string;
  payment_status: string;
  billing_plan: string;
  billing_email: string | null;
  stripe_customer_id: string | null;
}

export default function BillingPage() {
  const currentUser = useCurrentUser();
  const [company, setCompany] = useState<BillingCompany | null>(null);
  const [activeUsers, setActiveUsers] = useState(0);
  const [loading, setLoading] = useState(true);
  const [launching, setLaunching] = useState(false);
  const [error, setError] = useState("");

  const loadBilling = useCallback(async () => {
    if (!currentUser.companyId) return;

    setLoading(true);
    setError("");

    try {
      const supabase = getSupabase();
      const [{ data: companyData, error: companyError }, { count: activeCount, error: countError }] = await Promise.all([
        supabase
          .from("companies")
          .select("id, name, billing_mode, payment_status, billing_plan, billing_email, stripe_customer_id")
          .eq("id", currentUser.companyId)
          .single(),
        supabase
          .from("users")
          .select("*", { count: "exact", head: true })
          .eq("company_id", currentUser.companyId)
          .eq("is_active", true),
      ]);

      if (companyError) throw companyError;
      if (countError) throw countError;

      setCompany(companyData);
      setActiveUsers(activeCount || 0);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load billing");
    } finally {
      setLoading(false);
    }
  }, [currentUser.companyId]);

  useEffect(() => {
    if (!currentUser.loading && currentUser.companyId) {
      loadBilling();
    } else if (!currentUser.loading) {
      setLoading(false);
    }
  }, [currentUser.companyId, currentUser.loading, loadBilling]);

  async function handleManageBilling() {
    setLaunching(true);
    setError("");

    try {
      const supabase = getSupabase();
      const { data: sessionData } = await supabase.auth.getSession();
      const token = sessionData.session?.access_token;
      if (!token) throw new Error("Not authenticated");

      const response = await fetch(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/billing_portal`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          return_url: window.location.href,
        }),
      });

      const data = await response.json().catch(() => ({}));
      if (data.mode === "demo") {
        setError("Demo billing mode is active. Stripe portal will be available after billing is connected.");
        setLaunching(false);
        return;
      }

      if (!response.ok || !data.url) {
        throw new Error(data.message ?? data.error ?? "Failed to launch billing portal");
      }

      window.location.assign(data.url);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to launch billing portal");
      setLaunching(false);
    }
  }

  if (!currentUser.loading && !isManagementRole(currentUser.role)) {
    return (
      <div className="mt-20 text-center">
        <h2 className="text-xl font-bold text-slate-900">Access Denied</h2>
        <p className="mt-2 text-sm text-slate-500">Only owners and administrators can access billing.</p>
        <Link href="/" className="mt-4 inline-block text-sm font-medium text-amber-600 hover:text-amber-700">
          &larr; Back to dashboard
        </Link>
      </div>
    );
  }

  if (loading || currentUser.loading) {
    return <div className="pt-20 text-sm text-slate-500">Loading billing...</div>;
  }

  return (
    <div className="mx-auto max-w-3xl">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">Manage Billing</h1>
          <p className="mt-1 text-sm text-slate-500">Review plan, status, and launch the Stripe billing portal.</p>
        </div>
        {company?.billing_mode === "demo" ? (
          <span className="rounded-xl border border-amber-200 bg-amber-50 px-4 py-2 text-sm font-semibold text-amber-700">
            Demo billing mode
          </span>
        ) : (
          <button
            onClick={handleManageBilling}
            disabled={launching}
            className="rounded-xl bg-slate-900 px-5 py-2.5 text-sm font-semibold text-white shadow-sm hover:bg-slate-800 disabled:bg-stone-100 disabled:text-slate-400"
          >
            {launching ? "Opening..." : "Open billing portal"}
          </button>
        )}
      </div>

      {error && (
        <div className="mt-6 rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          {error}
        </div>
      )}

      <div className="mt-6 grid gap-4 md:grid-cols-2">
        <div className="rounded-2xl border border-stone-200 bg-card p-5 shadow-sm">
          <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">Plan</p>
          <p className="mt-2 text-2xl font-semibold text-slate-900">{company?.billing_plan ?? "starter"}</p>
          <p className="mt-2 text-sm text-slate-500">Active users: {activeUsers}</p>
        </div>

        <div className="rounded-2xl border border-stone-200 bg-card p-5 shadow-sm">
          <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">Mode</p>
          <p className="mt-2 text-2xl font-semibold capitalize text-slate-900">{company?.billing_mode ?? "demo"}</p>
          <p className="mt-2 text-sm text-slate-500">
            {company?.billing_mode === "demo"
              ? "Running free while billing is not yet connected."
              : "Stripe-backed subscription state is active."}
          </p>
        </div>

        <div className="rounded-2xl border border-stone-200 bg-card p-5 shadow-sm">
          <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">Status</p>
          <p className="mt-2 text-2xl font-semibold text-slate-900">{company?.payment_status ?? "trialing"}</p>
          <p className="mt-2 text-sm text-slate-500">
            Billing email: {company?.billing_email || currentUser.email || "Not set"}
          </p>
        </div>
      </div>

      <div className="mt-6 rounded-2xl border border-stone-200 bg-card p-5 shadow-sm">
        <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">Customer record</p>
        <p className="mt-2 text-sm text-slate-600">
          Company: <span className="font-medium text-slate-900">{company?.name ?? currentUser.companyName ?? "Unknown"}</span>
        </p>
        <p className="mt-2 text-sm text-slate-600">
          Stripe customer: <span className="font-medium text-slate-900">{company?.stripe_customer_id ?? "Will be created on first portal launch"}</span>
        </p>
      </div>
    </div>
  );
}
