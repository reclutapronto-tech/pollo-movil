"use client";

import { useEffect, useState } from "react";
import { getSupabase } from "@/lib/supabase";
import type { PlatformAdmin } from "@/lib/types";

export default function AdminsPage() {
  const [admins, setAdmins] = useState<PlatformAdmin[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  // Invite form
  const [inviteEmail, setInviteEmail] = useState("");
  const [inviting, setInviting] = useState(false);
  const [inviteResult, setInviteResult] = useState("");
  const [showInviteForm, setShowInviteForm] = useState(false);

  const getToken = async () => {
    const sb = getSupabase();
    const {
      data: { session },
    } = await sb.auth.getSession();
    return session?.access_token;
  };

  const fetchAdmins = async () => {
    setLoading(true);
    setError("");

    try {
      const token = await getToken();
      if (!token) return;

      const baseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
      const res = await fetch(
        `${baseUrl}/functions/v1/platform_admin?action=list_admins`,
        { headers: { Authorization: `Bearer ${token}` } }
      );

      if (!res.ok) throw new Error("Failed to fetch admins");

      const data = await res.json();
      setAdmins(data.admins ?? data);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchAdmins();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const handleInvite = async (e: React.FormEvent) => {
    e.preventDefault();
    setInviting(true);
    setInviteResult("");

    try {
      const token = await getToken();
      if (!token) throw new Error("No session");

      const baseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
      const res = await fetch(`${baseUrl}/functions/v1/platform_admin`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          action: "create_invite",
          email: inviteEmail,
        }),
      });

      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.error ?? `Invite failed (${res.status})`);
      }

      const data = await res.json();
      const link = data.claim_url ?? "";

      if (link) {
        setInviteResult(link);
        await navigator.clipboard.writeText(link).catch(() => {});
      } else {
        setInviteResult("Invite sent successfully");
      }

      setInviteEmail("");
      fetchAdmins();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error");
    } finally {
      setInviting(false);
    }
  };

  const copyToClipboard = async (text: string) => {
    try {
      await navigator.clipboard.writeText(text);
    } catch {
      // Fallback: ignore
    }
  };

  if (loading) {
    return <div className="text-stone-400">Loading admins...</div>;
  }

  if (error) {
    return (
      <div className="rounded-lg border border-red-200 bg-red-50 p-6">
        <p className="text-sm text-red-700">{error}</p>
        <button
          onClick={fetchAdmins}
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
        <h1 className="text-xl font-semibold text-stone-900">
          Platform Admins
        </h1>
        <button
          onClick={() => setShowInviteForm(!showInviteForm)}
          className="rounded-md bg-amber-500 px-4 py-2 text-sm font-medium text-white hover:bg-amber-600"
        >
          {showInviteForm ? "Cancel" : "Invite new admin"}
        </button>
      </div>

      {showInviteForm && (
        <div className="mb-6 rounded-lg border border-stone-200 bg-white p-5">
          <form onSubmit={handleInvite} className="flex gap-3">
            <input
              type="email"
              value={inviteEmail}
              onChange={(e) => setInviteEmail(e.target.value)}
              required
              placeholder="new-admin@fieldops.ai"
              className="flex-1 rounded-md border border-stone-300 px-3 py-2 text-sm text-stone-900 focus:border-amber-500 focus:outline-none focus:ring-1 focus:ring-amber-500"
            />
            <button
              type="submit"
              disabled={inviting}
              className="rounded-md bg-stone-900 px-4 py-2 text-sm font-medium text-white hover:bg-stone-800 disabled:opacity-50"
            >
              {inviting ? "Sending..." : "Send invite"}
            </button>
          </form>

          {inviteResult && (
            <div className="mt-3 flex items-center gap-2 rounded-md bg-emerald-50 p-3">
              <p className="flex-1 truncate text-sm text-emerald-700">
                {inviteResult}
              </p>
              {inviteResult.startsWith("http") && (
                <button
                  onClick={() => copyToClipboard(inviteResult)}
                  className="shrink-0 rounded bg-emerald-100 px-2 py-1 text-xs font-medium text-emerald-800 hover:bg-emerald-200"
                >
                  Copy
                </button>
              )}
            </div>
          )}
        </div>
      )}

      <div className="overflow-hidden rounded-lg border border-stone-200 bg-white">
        <table className="w-full text-left text-sm">
          <thead className="border-b border-stone-100 bg-stone-50">
            <tr>
              <th className="px-4 py-3 font-medium text-stone-600">Name</th>
              <th className="px-4 py-3 font-medium text-stone-600">Email</th>
              <th className="px-4 py-3 font-medium text-stone-600">Role</th>
              <th className="px-4 py-3 font-medium text-stone-600">Active</th>
              <th className="px-4 py-3 font-medium text-stone-600">Since</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-stone-100">
            {admins.map((a) => (
              <tr key={a.id} className="hover:bg-stone-50">
                <td className="px-4 py-3 font-medium text-stone-900">
                  {a.full_name}
                </td>
                <td className="px-4 py-3 text-stone-600">{a.email}</td>
                <td className="px-4 py-3">
                  <span className="rounded bg-stone-100 px-2 py-0.5 text-xs font-medium text-stone-600">
                    {a.role}
                  </span>
                </td>
                <td className="px-4 py-3">
                  {a.is_active ? (
                    <span className="text-emerald-600">Yes</span>
                  ) : (
                    <span className="text-stone-400">No</span>
                  )}
                </td>
                <td className="px-4 py-3 text-stone-500">
                  {new Date(a.created_at).toLocaleDateString()}
                </td>
              </tr>
            ))}
            {admins.length === 0 && (
              <tr>
                <td
                  colSpan={5}
                  className="px-4 py-8 text-center text-stone-400"
                >
                  No admins found
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
