"use client";

import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import { useSearchParams, useRouter } from "next/navigation";
import { Copy, Download, ExternalLink, FileText, Lock, Trash2, RefreshCw } from "lucide-react";
import { getSupabase } from "@/lib/supabase";

interface Gallery {
  id: string;
  job_id: string;
  name: string;
  description: string | null;
  share_token: string;
  expires_at: string | null;
  revoked_at: string | null;
  view_count: number;
  last_viewed_at: string | null;
  brand_watermark: boolean;
  created_at: string;
}

interface ShareToken {
  id: string;
  token: string;
  job_id: string;
  label: string | null;
  expires_at: string | null;
  revoked_at: string | null;
  view_count: number;
  last_viewed_at: string | null;
  brand_watermark: boolean;
  has_password: boolean;
  created_at: string;
}

type ReportTemplate = "photo_insurance_claim" | "photo_daily_log" | "photo_before_after";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL || "";
const ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || "";

function statusLabel(g: Gallery): { label: string; cls: string } {
  if (g.revoked_at) return { label: "Revoked", cls: "bg-stone-200 text-stone-700" };
  if (g.expires_at && new Date(g.expires_at) < new Date())
    return { label: "Expired", cls: "bg-red-100 text-red-700" };
  return { label: "Active", cls: "bg-emerald-100 text-emerald-700" };
}

function GalleriesInner() {
  const searchParams = useSearchParams();
  const router = useRouter();
  const jobId = searchParams.get("job_id");
  const [accessToken, setAccessToken] = useState("");
  const [galleries, setGalleries] = useState<Gallery[]>([]);
  const [shareTokens, setShareTokens] = useState<ShareToken[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [pdfBusy, setPdfBusy] = useState<string | null>(null);
  const [origin, setOrigin] = useState("");

  useEffect(() => {
    setOrigin(window.location.origin);
    const supabase = getSupabase();
    void supabase.auth.getSession().then(({ data }) => {
      setAccessToken(data.session?.access_token ?? "");
    });
  }, []);

  const loadData = useCallback(async () => {
    if (!accessToken) return;
    setLoading(true);
    setError(null);
    try {
      const galleriesUrl = new URL(`${SUPABASE_URL}/functions/v1/galleries`);
      if (jobId) galleriesUrl.searchParams.set("job_id", jobId);
      const [galleriesRes, tokensRes] = await Promise.all([
        fetch(galleriesUrl.toString(), {
          headers: { apikey: ANON_KEY, Authorization: `Bearer ${accessToken}` },
        }),
        fetch(`${SUPABASE_URL}/functions/v1/client_portal`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            apikey: ANON_KEY,
            Authorization: `Bearer ${accessToken}`,
          },
          body: JSON.stringify({ action: "list_tokens", job_id: jobId || undefined }),
        }),
      ]);
      const galleriesData = await galleriesRes.json();
      const tokensData = await tokensRes.json();
      if (!galleriesRes.ok) {
        setError(galleriesData.message || "Failed to load galleries");
        return;
      }
      setGalleries(galleriesData.galleries || []);
      setShareTokens(tokensData.tokens || []);
    } catch {
      setError("Failed to load. Check your connection.");
    } finally {
      setLoading(false);
    }
  }, [accessToken, jobId]);

  useEffect(() => {
    void loadData();
  }, [loadData]);

  async function handleRevokeGallery(id: string) {
    if (!confirm("Revoke this gallery? The public link will stop working.")) return;
    await fetch(`${SUPABASE_URL}/functions/v1/galleries`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        apikey: ANON_KEY,
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({ id, action: "revoke" }),
    });
    void loadData();
  }

  async function handleRotateToken(id: string) {
    if (!confirm("Rotate token? The old link will stop working.")) return;
    await fetch(`${SUPABASE_URL}/functions/v1/galleries`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        apikey: ANON_KEY,
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({ id, action: "rotate_token" }),
    });
    void loadData();
  }

  async function handleRevokeShareToken(token_id: string) {
    if (!confirm("Revoke this share link?")) return;
    await fetch(`${SUPABASE_URL}/functions/v1/client_portal`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: ANON_KEY,
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({ action: "revoke_token", token_id }),
    });
    void loadData();
  }

  async function handleDownloadPdf(gallery: Gallery, template: ReportTemplate) {
    setPdfBusy(gallery.id);
    try {
      const res = await fetch(`${SUPABASE_URL}/functions/v1/reports`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          apikey: ANON_KEY,
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify({ report_type: template, gallery_id: gallery.id, job_id: gallery.job_id }),
      });
      const data = await res.json();
      if (!res.ok || !data.signed_url) {
        alert(data.message || "PDF generation failed");
        return;
      }
      window.open(data.signed_url, "_blank");
    } finally {
      setPdfBusy(null);
    }
  }

  const pageTitle = useMemo(() => (jobId ? "Project deliverables" : "All galleries"), [jobId]);

  return (
    <div className="mx-auto max-w-6xl space-y-6 px-6 py-8">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">{pageTitle}</h1>
          <p className="mt-1 text-sm text-slate-500">
            Galleries and project share links. Generate PDF packets and manage access here.
          </p>
        </div>
        {jobId && (
          <button
            onClick={() =>
              router.push(`/photos?job_id=${encodeURIComponent(jobId)}&tab=feed`)
            }
            className="rounded-lg border border-stone-200 bg-card px-3 py-2 text-sm font-semibold text-slate-700 hover:bg-stone-50"
          >
            ← Back to photos
          </button>
        )}
      </div>

      {error && (
        <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">{error}</div>
      )}

      {/* ── Galleries section ────────────────────────── */}
      <section className="rounded-2xl bg-card p-6 shadow-sm">
        <h2 className="mb-4 text-lg font-bold text-slate-900">Galleries</h2>
        {loading ? (
          <p className="text-sm text-slate-500">Loading…</p>
        ) : galleries.length === 0 ? (
          <div className="rounded-xl border border-dashed border-stone-300 p-8 text-center text-sm text-slate-500">
            No galleries yet. Bulk-select photos on the Photos page and click &ldquo;Save as gallery&rdquo;.
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-stone-200 text-left text-xs font-semibold uppercase tracking-wider text-slate-500">
                  <th className="pb-2">Name</th>
                  <th className="pb-2">Status</th>
                  <th className="pb-2">Views</th>
                  <th className="pb-2">Expires</th>
                  <th className="pb-2">Link</th>
                  <th className="pb-2 text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                {galleries.map((g) => {
                  const st = statusLabel(g);
                  const publicUrl = `${origin}/g/${g.share_token}`;
                  const disabled = !!g.revoked_at;
                  return (
                    <tr key={g.id} className="border-b border-stone-100">
                      <td className="py-3">
                        <p className="font-medium text-slate-900">{g.name}</p>
                        {g.description && (
                          <p className="text-xs text-slate-500 line-clamp-1">{g.description}</p>
                        )}
                      </td>
                      <td>
                        <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${st.cls}`}>
                          {st.label}
                        </span>
                      </td>
                      <td>{g.view_count}</td>
                      <td className="text-xs text-slate-500">
                        {g.expires_at ? new Date(g.expires_at).toLocaleDateString() : "—"}
                      </td>
                      <td>
                        <div className="flex items-center gap-1.5">
                          <button
                            onClick={() => void navigator.clipboard.writeText(publicUrl)}
                            className="rounded border border-stone-200 p-1.5 text-slate-600 hover:bg-stone-50"
                            title="Copy link"
                            disabled={disabled}
                          >
                            <Copy size={13} />
                          </button>
                          <a
                            href={publicUrl}
                            target="_blank"
                            rel="noopener noreferrer"
                            className={`rounded border border-stone-200 p-1.5 text-slate-600 hover:bg-stone-50 ${
                              disabled ? "pointer-events-none opacity-40" : ""
                            }`}
                            title="Open link"
                          >
                            <ExternalLink size={13} />
                          </a>
                        </div>
                      </td>
                      <td className="text-right">
                        <div className="inline-flex items-center gap-1">
                          <select
                            disabled={disabled || pdfBusy === g.id}
                            defaultValue=""
                            onChange={(e) => {
                              const v = e.target.value as ReportTemplate | "";
                              if (v) void handleDownloadPdf(g, v);
                              e.target.value = "";
                            }}
                            className="rounded border border-stone-200 bg-card px-2 py-1 text-xs text-slate-700"
                          >
                            <option value="">
                              {pdfBusy === g.id ? "Generating…" : "Download PDF"}
                            </option>
                            <option value="photo_insurance_claim">Insurance claim</option>
                            <option value="photo_daily_log">Daily log</option>
                            <option value="photo_before_after">Before / After</option>
                          </select>
                          <button
                            onClick={() => handleRotateToken(g.id)}
                            className="rounded border border-stone-200 p-1.5 text-slate-600 hover:bg-stone-50"
                            title="Rotate link"
                            disabled={disabled}
                          >
                            <RefreshCw size={13} />
                          </button>
                          <button
                            onClick={() => handleRevokeGallery(g.id)}
                            className="rounded border border-red-200 p-1.5 text-red-600 hover:bg-red-50"
                            title="Revoke"
                            disabled={disabled}
                          >
                            <Trash2 size={13} />
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {/* ── Project share links ──────────────────────── */}
      <section className="rounded-2xl bg-card p-6 shadow-sm">
        <h2 className="mb-4 text-lg font-bold text-slate-900">Project share links</h2>
        {loading ? (
          <p className="text-sm text-slate-500">Loading…</p>
        ) : shareTokens.length === 0 ? (
          <div className="rounded-xl border border-dashed border-stone-300 p-6 text-center text-sm text-slate-500">
            No active share links.
          </div>
        ) : (
          <div className="space-y-2">
            {shareTokens.map((tk) => {
              const publicUrl = `${origin}/portal/${tk.token}`;
              const disabled = !!tk.revoked_at;
              return (
                <div
                  key={tk.id}
                  className={`flex items-center justify-between rounded-lg border border-stone-200 p-3 ${
                    disabled ? "opacity-50" : ""
                  }`}
                >
                  <div className="flex items-center gap-3">
                    {tk.has_password && <Lock size={14} className="text-amber-500" />}
                    <div>
                      <p className="text-sm font-medium text-slate-900">
                        {tk.label || "Unlabeled link"}
                      </p>
                      <p className="text-xs text-slate-500">
                        {tk.view_count} views ·
                        {tk.expires_at ? ` expires ${new Date(tk.expires_at).toLocaleDateString()}` : " never expires"}
                      </p>
                    </div>
                  </div>
                  <div className="flex items-center gap-1.5">
                    <button
                      onClick={() => void navigator.clipboard.writeText(publicUrl)}
                      disabled={disabled}
                      className="rounded border border-stone-200 p-1.5 text-slate-600 hover:bg-stone-50"
                      title="Copy link"
                    >
                      <Copy size={13} />
                    </button>
                    <a
                      href={publicUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                      className={`rounded border border-stone-200 p-1.5 text-slate-600 hover:bg-stone-50 ${
                        disabled ? "pointer-events-none opacity-40" : ""
                      }`}
                      title="Open"
                    >
                      <ExternalLink size={13} />
                    </a>
                    <button
                      onClick={() => handleRevokeShareToken(tk.id)}
                      disabled={disabled}
                      className="rounded border border-red-200 p-1.5 text-red-600 hover:bg-red-50"
                      title="Revoke"
                    >
                      <Trash2 size={13} />
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </section>

      <p className="flex items-center gap-2 text-xs text-slate-500">
        <FileText size={12} /> PDFs are stamped with verification codes and SHA-256 hashes for tamper-evident delivery.
        <Download size={12} className="ml-2" /> Links stay live until you revoke or the expiry passes.
      </p>
    </div>
  );
}

export default function GalleriesPage() {
  return (
    <Suspense fallback={<div className="flex min-h-screen items-center justify-center">Loading…</div>}>
      <GalleriesInner />
    </Suspense>
  );
}
