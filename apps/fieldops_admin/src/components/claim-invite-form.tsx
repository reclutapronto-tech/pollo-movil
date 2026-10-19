"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";

interface ClaimState {
  email: string;
  fullName: string;
  password: string;
}

export default function ClaimInviteForm() {
  const searchParams = useSearchParams();
  const inviteToken = useMemo(() => searchParams.get("token") ?? "", [searchParams]);

  const [form, setForm] = useState<ClaimState>({
    email: "",
    fullName: "",
    password: "",
  });
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    setError("");
    setSuccess("");

    try {
      if (!inviteToken) {
        throw new Error("Missing invite token.");
      }

      const baseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
      const res = await fetch(`${baseUrl}/functions/v1/platform_admin`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          action: "claim_invite",
          invite_token: inviteToken,
          email: form.email.trim(),
          full_name: form.fullName.trim(),
          password: form.password,
        }),
      });

      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(data.message ?? data.error ?? `Claim failed (${res.status})`);
      }

      setSuccess("Invite claimed. You can now sign in.");
      setForm({ email: "", fullName: "", password: "" });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="w-full max-w-md rounded-xl border border-stone-200 bg-white p-8 shadow-sm">
      <h1 className="text-xl font-semibold text-stone-900">Claim Admin Invite</h1>
      <p className="mt-2 text-sm text-stone-500">
        Finish your FieldOps platform-admin setup.
      </p>

      {!inviteToken && (
        <div className="mt-4 rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700">
          Missing invite token.
        </div>
      )}

      <form onSubmit={handleSubmit} className="mt-6 space-y-4">
        <div>
          <label className="mb-1 block text-sm font-medium text-stone-700">Email</label>
          <input
            type="email"
            value={form.email}
            onChange={(e) => setForm((prev) => ({ ...prev, email: e.target.value }))}
            required
            className="w-full rounded-md border border-stone-300 px-3 py-2 text-sm text-stone-900 focus:border-amber-500 focus:outline-none focus:ring-1 focus:ring-amber-500"
            placeholder="admin@fieldops.ai"
          />
        </div>

        <div>
          <label className="mb-1 block text-sm font-medium text-stone-700">Full name</label>
          <input
            type="text"
            value={form.fullName}
            onChange={(e) => setForm((prev) => ({ ...prev, fullName: e.target.value }))}
            required
            className="w-full rounded-md border border-stone-300 px-3 py-2 text-sm text-stone-900 focus:border-amber-500 focus:outline-none focus:ring-1 focus:ring-amber-500"
            placeholder="Jane Doe"
          />
        </div>

        <div>
          <label className="mb-1 block text-sm font-medium text-stone-700">Password</label>
          <input
            type="password"
            value={form.password}
            onChange={(e) => setForm((prev) => ({ ...prev, password: e.target.value }))}
            required
            minLength={8}
            className="w-full rounded-md border border-stone-300 px-3 py-2 text-sm text-stone-900 focus:border-amber-500 focus:outline-none focus:ring-1 focus:ring-amber-500"
            placeholder="Minimum 8 characters"
          />
        </div>

        {error && (
          <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700">
            {error}
          </div>
        )}

        {success && (
          <div className="rounded-md border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-700">
            {success} <Link href="/login" className="font-medium underline">Go to sign in</Link>
          </div>
        )}

        <button
          type="submit"
          disabled={submitting || !inviteToken}
          className="w-full rounded-md bg-stone-900 px-4 py-2 text-sm font-medium text-white hover:bg-stone-800 disabled:opacity-50"
        >
          {submitting ? "Claiming..." : "Claim invite"}
        </button>
      </form>
    </div>
  );
}
