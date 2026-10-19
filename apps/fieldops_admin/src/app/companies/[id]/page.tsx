"use client";

import { useEffect, useState } from "react";
import { useParams } from "next/navigation";
import Link from "next/link";
import { getSupabase } from "@/lib/supabase";
import type { CompanyDetail, CompanyUser, AuditLogEntry } from "@/lib/types";

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

function InfoRow({ label, value }: { label: string; value: string | null }) {
  return (
    <div className="flex justify-between py-2">
      <span className="text-sm text-stone-500">{label}</span>
      <span className="text-sm font-medium text-stone-900">
        {value ?? "---"}
      </span>
    </div>
  );
}

export default function CompanyDetailPage() {
  const params = useParams();
  const companyId = params.id as string;

  const [company, setCompany] = useState<CompanyDetail | null>(null);
  const [users, setUsers] = useState<CompanyUser[]>([]);
  const [audit, setAudit] = useState<AuditLogEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [toggling, setToggling] = useState(false);

  const getToken = async () => {
    const sb = getSupabase();
    const {
      data: { session },
    } = await sb.auth.getSession();
    return session?.access_token;
  };

  const apiCall = async (params: string) => {
    const token = await getToken();
    if (!token) throw new Error("No session");
    const baseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const res = await fetch(
      `${baseUrl}/functions/v1/platform_admin?${params}`,
      { headers: { Authorization: `Bearer ${token}` } }
    );
    if (!res.ok) throw new Error(`API error: ${res.status}`);
    return res.json();
  };

  const fetchAll = async () => {
    setLoading(true);
    setError("");

    try {
      const [companyData, usersData, auditData] = await Promise.all([
        apiCall(`action=company_detail&company_id=${companyId}`),
        apiCall(`action=company_users&company_id=${companyId}`),
        apiCall(`action=audit&company_id=${companyId}&limit=20`),
      ]);

      setCompany(companyData.company ?? companyData);
      setUsers(usersData.users ?? usersData);
      setAudit(auditData.audit_logs ?? auditData.audit ?? auditData);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchAll();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [companyId]);

  const toggleStatus = async () => {
    if (!company) return;
    setToggling(true);

    try {
      const newStatus =
        company.status === "active" ? "suspended" : "active";
      const token = await getToken();
      if (!token) throw new Error("No session");

      const baseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
      const res = await fetch(
        `${baseUrl}/functions/v1/platform_admin`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            action: "toggle_company",
            company_id: companyId,
            status: newStatus,
          }),
        }
      );

      if (!res.ok) throw new Error("Failed to update status");

      setCompany({ ...company, status: newStatus });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error");
    } finally {
      setToggling(false);
    }
  };

  if (loading) {
    return <div className="text-stone-400">Loading company...</div>;
  }

  if (error) {
    return (
      <div className="rounded-lg border border-red-200 bg-red-50 p-6">
        <p className="text-sm text-red-700">{error}</p>
        <button
          onClick={fetchAll}
          className="mt-3 rounded-md bg-stone-800 px-3 py-1.5 text-sm text-white hover:bg-stone-700"
        >
          Retry
        </button>
      </div>
    );
  }

  if (!company) {
    return <div className="text-stone-400">Company not found</div>;
  }

  return (
    <div>
      <div className="mb-6 flex items-center gap-3">
        <Link
          href="/companies"
          className="text-sm text-stone-400 hover:text-stone-600"
        >
          Companies
        </Link>
        <span className="text-stone-300">/</span>
        <h1 className="text-xl font-semibold text-stone-900">
          {company.name}
        </h1>
      </div>

      {/* Company Info */}
      <div className="mb-8 grid grid-cols-2 gap-6">
        <div className="rounded-lg border border-stone-200 bg-white p-5">
          <h2 className="mb-3 text-sm font-medium text-stone-500 uppercase tracking-wide">
            Company Info
          </h2>
          <div className="divide-y divide-stone-100">
            <InfoRow label="Slug" value={company.slug} />
            <InfoRow label="Industry" value={company.industry} />
            <InfoRow label="Timezone" value={company.timezone} />
            <InfoRow
              label="Created"
              value={new Date(company.created_at).toLocaleDateString()}
            />
            <div className="flex items-center justify-between py-2">
              <span className="text-sm text-stone-500">Status</span>
              <StatusBadge status={company.status} />
            </div>
            <div className="flex items-center justify-between py-2">
              <span className="text-sm text-stone-500">Payment</span>
              <StatusBadge status={company.payment_status} />
            </div>
          </div>
        </div>

        <div className="rounded-lg border border-stone-200 bg-white p-5">
          <h2 className="mb-3 text-sm font-medium text-stone-500 uppercase tracking-wide">
            Actions
          </h2>
          <button
            onClick={toggleStatus}
            disabled={toggling}
            className={`rounded-md px-4 py-2 text-sm font-medium text-white disabled:opacity-50 ${
              company.status === "active"
                ? "bg-red-600 hover:bg-red-700"
                : "bg-emerald-600 hover:bg-emerald-700"
            }`}
          >
            {toggling
              ? "Updating..."
              : company.status === "active"
              ? "Suspend company"
              : "Activate company"}
          </button>
        </div>
      </div>

      {/* Users */}
      <div className="mb-8">
        <h2 className="mb-3 text-sm font-medium text-stone-500 uppercase tracking-wide">
          Users ({users.length})
        </h2>
        <div className="overflow-hidden rounded-lg border border-stone-200 bg-white">
          <table className="w-full text-left text-sm">
            <thead className="border-b border-stone-100 bg-stone-50">
              <tr>
                <th className="px-4 py-3 font-medium text-stone-600">Name</th>
                <th className="px-4 py-3 font-medium text-stone-600">Email</th>
                <th className="px-4 py-3 font-medium text-stone-600">Role</th>
                <th className="px-4 py-3 font-medium text-stone-600">
                  Active
                </th>
                <th className="px-4 py-3 font-medium text-stone-600">
                  Joined
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-stone-100">
              {users.map((u) => (
                <tr key={u.id} className="hover:bg-stone-50">
                  <td className="px-4 py-3 font-medium text-stone-900">
                    {u.full_name}
                  </td>
                  <td className="px-4 py-3 text-stone-600">
                    {u.email ?? "---"}
                  </td>
                  <td className="px-4 py-3">
                    <span className="rounded bg-stone-100 px-2 py-0.5 text-xs font-medium text-stone-600">
                      {u.role}
                    </span>
                  </td>
                  <td className="px-4 py-3">
                    {u.is_active ? (
                      <span className="text-emerald-600">Yes</span>
                    ) : (
                      <span className="text-stone-400">No</span>
                    )}
                  </td>
                  <td className="px-4 py-3 text-stone-500">
                    {new Date(u.created_at).toLocaleDateString()}
                  </td>
                </tr>
              ))}
              {users.length === 0 && (
                <tr>
                  <td
                    colSpan={5}
                    className="px-4 py-8 text-center text-stone-400"
                  >
                    No users
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Audit Log */}
      <div>
        <h2 className="mb-3 text-sm font-medium text-stone-500 uppercase tracking-wide">
          Audit Log
        </h2>
        <div className="overflow-hidden rounded-lg border border-stone-200 bg-white">
          <table className="w-full text-left text-sm">
            <thead className="border-b border-stone-100 bg-stone-50">
              <tr>
                <th className="px-4 py-3 font-medium text-stone-600">
                  Action
                </th>
                <th className="px-4 py-3 font-medium text-stone-600">Actor</th>
                <th className="px-4 py-3 font-medium text-stone-600">
                  Target
                </th>
                <th className="px-4 py-3 font-medium text-stone-600">When</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-stone-100">
              {audit.map((a) => (
                <tr key={a.id} className="hover:bg-stone-50">
                  <td className="px-4 py-3 font-medium text-stone-900">
                    {a.action}
                  </td>
                  <td className="px-4 py-3 text-stone-600">
                    {a.actor_email}
                  </td>
                  <td className="px-4 py-3 text-stone-500">
                    {a.target_type}
                  </td>
                  <td className="px-4 py-3 text-stone-500">
                    {new Date(a.created_at).toLocaleString()}
                  </td>
                </tr>
              ))}
              {audit.length === 0 && (
                <tr>
                  <td
                    colSpan={4}
                    className="px-4 py-8 text-center text-stone-400"
                  >
                    No audit entries
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
