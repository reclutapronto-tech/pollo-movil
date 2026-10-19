"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { getSupabase } from "@/lib/supabase";
import type { CompanySummary } from "@/lib/types";

function StatCard({
  label,
  value,
}: {
  label: string;
  value: string | number;
}) {
  return (
    <div className="rounded-lg border border-stone-200 bg-white p-5">
      <p className="text-sm text-stone-500">{label}</p>
      <p className="mt-1 text-2xl font-semibold text-stone-900">{value}</p>
    </div>
  );
}

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

export default function DashboardPage() {
  const [companies, setCompanies] = useState<CompanySummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  const fetchData = async () => {
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
    fetchData();
  }, []);

  if (loading) {
    return <div className="text-stone-400">Loading dashboard...</div>;
  }

  if (error) {
    return (
      <div className="rounded-lg border border-red-200 bg-red-50 p-6">
        <p className="text-sm text-red-700">{error}</p>
        <button
          onClick={fetchData}
          className="mt-3 rounded-md bg-stone-800 px-3 py-1.5 text-sm text-white hover:bg-stone-700"
        >
          Retry
        </button>
      </div>
    );
  }

  const activeCount = companies.filter((c) => c.status === "active").length;
  const totalUsers = companies.reduce((s, c) => s + c.total_user_count, 0);
  const recentCompanies = [...companies]
    .sort(
      (a, b) =>
        new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
    )
    .slice(0, 10);

  return (
    <div>
      <h1 className="mb-6 text-xl font-semibold text-stone-900">Dashboard</h1>

      <div className="mb-8 grid grid-cols-3 gap-4">
        <StatCard label="Total companies" value={companies.length} />
        <StatCard label="Active companies" value={activeCount} />
        <StatCard label="Total users" value={totalUsers} />
      </div>

      <h2 className="mb-3 text-sm font-medium text-stone-500 uppercase tracking-wide">
        Recent companies
      </h2>

      <div className="overflow-hidden rounded-lg border border-stone-200 bg-white">
        <table className="w-full text-left text-sm">
          <thead className="border-b border-stone-100 bg-stone-50">
            <tr>
              <th className="px-4 py-3 font-medium text-stone-600">Name</th>
              <th className="px-4 py-3 font-medium text-stone-600">Status</th>
              <th className="px-4 py-3 font-medium text-stone-600">Users</th>
              <th className="px-4 py-3 font-medium text-stone-600">Created</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-stone-100">
            {recentCompanies.map((c) => (
              <tr key={c.id} className="hover:bg-stone-50">
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
                <td className="px-4 py-3 text-stone-600">
                  {c.active_user_count} / {c.total_user_count}
                </td>
                <td className="px-4 py-3 text-stone-500">
                  {new Date(c.created_at).toLocaleDateString()}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
