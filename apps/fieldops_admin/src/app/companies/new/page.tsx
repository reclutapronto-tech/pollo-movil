"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabase } from "@/lib/supabase";

function slugify(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "");
}

export default function NewCompanyPage() {
  const router = useRouter();

  const [name, setName] = useState("");
  const [slug, setSlug] = useState("");
  const [industry, setIndustry] = useState("");
  const [timezone, setTimezone] = useState("America/New_York");
  const [ownerEmail, setOwnerEmail] = useState("");
  const [ownerName, setOwnerName] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  const handleNameChange = (val: string) => {
    setName(val);
    setSlug(slugify(val));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    setError("");

    try {
      const sb = getSupabase();
      const {
        data: { session },
      } = await sb.auth.getSession();
      if (!session) throw new Error("No session");

      const baseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
      const res = await fetch(`${baseUrl}/functions/v1/platform_admin`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${session.access_token}`,
          "Content-Type": "application/json",
          "Idempotency-Key": crypto.randomUUID(),
        },
        body: JSON.stringify({
          action: "create_company",
          name,
          slug,
          industry: industry || null,
          timezone,
          owner_email: ownerEmail,
          owner_name: ownerName,
        }),
      });

      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.error ?? `Failed to create company (${res.status})`);
      }

      const data = await res.json();
      const newId = data.company_id ?? data.id ?? data.company?.id;

      if (newId) {
        router.push(`/companies/${newId}`);
      } else {
        router.push("/companies");
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="mx-auto max-w-lg">
      <h1 className="mb-6 text-xl font-semibold text-stone-900">
        Create Company
      </h1>

      <form
        onSubmit={handleSubmit}
        className="space-y-5 rounded-lg border border-stone-200 bg-white p-6"
      >
        <fieldset className="space-y-4">
          <legend className="mb-2 text-sm font-medium text-stone-500 uppercase tracking-wide">
            Company Details
          </legend>

          <div>
            <label className="mb-1 block text-sm font-medium text-stone-700">
              Company name *
            </label>
            <input
              type="text"
              value={name}
              onChange={(e) => handleNameChange(e.target.value)}
              required
              className="w-full rounded-md border border-stone-300 px-3 py-2 text-sm text-stone-900 focus:border-amber-500 focus:outline-none focus:ring-1 focus:ring-amber-500"
              placeholder="Acme Corp"
            />
          </div>

          <div>
            <label className="mb-1 block text-sm font-medium text-stone-700">
              Slug
            </label>
            <input
              type="text"
              value={slug}
              onChange={(e) => setSlug(e.target.value)}
              required
              className="w-full rounded-md border border-stone-300 bg-stone-50 px-3 py-2 text-sm text-stone-700 focus:border-amber-500 focus:outline-none focus:ring-1 focus:ring-amber-500"
            />
          </div>

          <div>
            <label className="mb-1 block text-sm font-medium text-stone-700">
              Industry
            </label>
            <input
              type="text"
              value={industry}
              onChange={(e) => setIndustry(e.target.value)}
              className="w-full rounded-md border border-stone-300 px-3 py-2 text-sm text-stone-900 focus:border-amber-500 focus:outline-none focus:ring-1 focus:ring-amber-500"
              placeholder="Agriculture, Landscaping, etc."
            />
          </div>

          <div>
            <label className="mb-1 block text-sm font-medium text-stone-700">
              Timezone
            </label>
            <select
              value={timezone}
              onChange={(e) => setTimezone(e.target.value)}
              className="w-full rounded-md border border-stone-300 px-3 py-2 text-sm text-stone-900 focus:border-amber-500 focus:outline-none focus:ring-1 focus:ring-amber-500"
            >
              <option value="America/New_York">Eastern (ET)</option>
              <option value="America/Chicago">Central (CT)</option>
              <option value="America/Denver">Mountain (MT)</option>
              <option value="America/Los_Angeles">Pacific (PT)</option>
              <option value="America/Anchorage">Alaska (AKT)</option>
              <option value="Pacific/Honolulu">Hawaii (HT)</option>
              <option value="UTC">UTC</option>
            </select>
          </div>
        </fieldset>

        <fieldset className="space-y-4 border-t border-stone-100 pt-5">
          <legend className="mb-2 text-sm font-medium text-stone-500 uppercase tracking-wide">
            Initial Owner
          </legend>

          <div>
            <label className="mb-1 block text-sm font-medium text-stone-700">
              Owner email *
            </label>
            <input
              type="email"
              value={ownerEmail}
              onChange={(e) => setOwnerEmail(e.target.value)}
              required
              className="w-full rounded-md border border-stone-300 px-3 py-2 text-sm text-stone-900 focus:border-amber-500 focus:outline-none focus:ring-1 focus:ring-amber-500"
              placeholder="admin@acmecorp.com"
            />
          </div>

          <div>
            <label className="mb-1 block text-sm font-medium text-stone-700">
              Owner full name *
            </label>
            <input
              type="text"
              value={ownerName}
              onChange={(e) => setOwnerName(e.target.value)}
              required
              className="w-full rounded-md border border-stone-300 px-3 py-2 text-sm text-stone-900 focus:border-amber-500 focus:outline-none focus:ring-1 focus:ring-amber-500"
              placeholder="Jane Doe"
            />
          </div>
        </fieldset>

        {error && (
          <div className="rounded-md border border-red-200 bg-red-50 p-3">
            <p className="text-sm text-red-700">{error}</p>
          </div>
        )}

        <button
          type="submit"
          disabled={submitting}
          className="w-full rounded-md bg-amber-500 px-4 py-2 text-sm font-medium text-white hover:bg-amber-600 disabled:opacity-50"
        >
          {submitting ? "Creating..." : "Create company"}
        </button>
      </form>
    </div>
  );
}
