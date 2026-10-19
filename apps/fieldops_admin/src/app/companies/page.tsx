"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { getSupabase } from "@/lib/supabase";
import type { CompanySummary } from "@/lib/types";

type StatusFilter = "all" | "active" | "suspended" | "trialing";

function StatusBadge({ status }: { status: string }) {
  const colors: Record<string, string> = {
    active: "bg-emerald-50 text-emerald-700",
    suspended: "bg-red-50 text-red-700",
    trialing: "bg-amber-50 text-amber-700",
  };
  return (
    <span
      className={`inline-block rounded-full px-2 py-0.5 text-xs font-medium ${
        colors[status] ?? "bg-stone-100 text-stone-600"
      }`}
    >
      {status}
    </span>
  );
}

export default function CompaniesPage() {
  const [companies, setCompanies] = useState<CompanySummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [filter, setFilter] = useState<StatusFilter>("all");

  const fetchCompanies = async () => {
    setLoading(true);
    setError("");

    try {
      const sb = getSupabase();
      const {
        data: { session },
      } = await sb.auth.getSession();
      if (!session) return;

      const baseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
      const res = await fetch(
        `${baseUrl}/functions/v1/platform_admin?action=list_companies`,
        { headers: { Authorization: `Bearer ${session.access_token}` } }
      );

      if (!res.ok) throw new Error("Failed to fetch companies");

      const data = await res.json();
      setCompanies(data.companies ?? data);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchCompanies();
  }, []);

  const filtered =
    filter === "all" ? companies : companies.filter((c) => c.status === filter);

  if (loading) {
    return <div className="text-stone-400">Loading companies...</div>;
  }

  if (error) {
    return (
      <div className="rounded-lg border border-red-200 bg-red-50 p-6">
        <p className="text-sm text-red-700">{error}</p>
        <button
          onClick={fetchCompanies}
          className="mt-3 rounded-md bg-stone-800 px-3 py-1.5 text-sm text-white hover:bg-stone-700"
        >
          Retry
        </button>
      </div>
    );
  }

  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-xl font-semibold text-stone-900">Companies</h1>
        <Link
          href="/companies/new"
          className="rounded-md bg-amber-500 px-4 py-2 text-sm font-medium text-white hover:bg-amber-600"
        >
          New company
        </Link>
      </div>

      <div className="mb-4 flex gap-2">
        {(["all", "active", "suspended", "trialing"] as StatusFilter[]).map(
          (s) => (
            <button
              key={s}
              onClick={() => setFilter(s)}
              className={`rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
                filter === s
                  ? "bg-stone-900 text-white"
                  : "bg-white text-stone-600 border border-stone-200 hover:bg-stone-50"
              }`}
            >
              {s === "all" ? "All" : s.charAt(0).toUpperCase() + s.slice(1)}
            </button>
          )
        )}
      </div>

      <div className="overflow-hidden rounded-lg border border-stone-200 bg-white">
        <table className="w-full text-left text-sm">
          <thead className="border-b border-stone-100 bg-stone-50">
            <tr>
              <th className="px-4 py-3 font-medium text-stone-600">Name</th>
              <th className="px-4 py-3 font-medium text-stone-600">Status</th>
              <th className="px-4 py-3 font-medium text-stone-600">Payment</th>
              <th className="px-4 py-3 font-medium text-stone-600">Users</th>
              <th className="px-4 py-3 font-medium text-stone-600">Created</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-stone-100">
            {filtered.map((c) => (
              <tr key={c.id} className="cursor-pointer hover:bg-stone-50">
                <td className="px-4 py-3">
                  <Link
                    href={`/companies/${c.id}`}
                    className="font-medium text-stone-900 hover:text-amber-600"
                  >
                    {c.name}
                  </Link>
                </td>
                <td className="px-4 py-3">
                  <StatusBadge status={c.status} />
                </td>
                <td className="px-4 py-3">
                  <StatusBadge status={c.payment_status} />
                </td>
                <td className="px-4 py-3 text-stone-600">
                  {c.active_user_count} / {c.total_user_count}
                </td>
                <td className="px-4 py-3 text-stone-500">
                  {new Date(c.created_at).toLocaleDateString()}
                </td>
              </tr>
            ))}
            {filtered.length === 0 && (
              <tr>
                <td
                  colSpan={5}
                  className="px-4 py-8 text-center text-stone-400"
                >
                  No companies found
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
