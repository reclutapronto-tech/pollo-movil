"use client";

import { useState } from "react";
import { Copy } from "lucide-react";

interface Props {
  open: boolean;
  jobId: string;
  mediaAssetIds: string[];
  accessToken: string;
  onClose: () => void;
}

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL || "";
const ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || "";

export function SaveAsGalleryDialog({
  open,
  jobId,
  mediaAssetIds,
  accessToken,
  onClose,
}: Props) {
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [password, setPassword] = useState("");
  const [expiresDays, setExpiresDays] = useState<number | "">("");
  const [brandWatermark, setBrandWatermark] = useState(true);
  const [saving, setSaving] = useState(false);
  const [shareUrl, setShareUrl] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  if (!open) return null;

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!name.trim() || mediaAssetIds.length === 0) return;
    setSaving(true);
    setError(null);
    try {
      const res = await fetch(`${SUPABASE_URL}/functions/v1/galleries`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          apikey: ANON_KEY,
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          job_id: jobId,
          name: name.trim(),
          description: description.trim() || null,
          media_asset_ids: mediaAssetIds,
          password: password || null,
          expires_days: expiresDays || null,
          brand_watermark: brandWatermark,
        }),
      });
      const data = await res.json();
      if (!res.ok) {
        setError(data.message || "Failed to create gallery");
        return;
      }
      const origin = typeof window !== "undefined" ? window.location.origin : "";
      setShareUrl(`${origin}${data.share_url}`);
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-6" onClick={onClose}>
      <div className="w-full max-w-md rounded-2xl bg-card p-6 shadow-xl" onClick={(e) => e.stopPropagation()}>
        {shareUrl ? (
          <>
            <h2 className="text-lg font-bold text-slate-900">Gallery ready</h2>
            <p className="mt-1 text-sm text-slate-500">
              Share this link with your client. {password && "They'll need the password you set."}
            </p>
            <div className="mt-4 flex items-center gap-2 rounded-lg border border-stone-200 bg-stone-50 p-3">
              <code className="flex-1 truncate text-xs text-slate-700">{shareUrl}</code>
              <button
                onClick={() => void navigator.clipboard.writeText(shareUrl)}
                className="rounded bg-slate-900 p-1.5 text-white hover:bg-slate-800"
                title="Copy link"
              >
                <Copy size={14} />
              </button>
            </div>
            <button
              onClick={onClose}
              className="mt-5 w-full rounded-lg inline-flex min-h-11 items-center justify-center bg-slate-900 text-sm font-semibold text-white transition-colors hover:bg-slate-800 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-white"
            >
              Done
            </button>
          </>
        ) : (
          <form onSubmit={handleSubmit}>
            <h2 className="text-lg font-bold text-slate-900">
              Save {mediaAssetIds.length} photos as gallery
            </h2>
            <p className="mt-1 text-sm text-slate-500">
              Creates a shareable link with optional password and expiry.
            </p>
            <div className="mt-4 space-y-3">
              <div>
                <label className="text-xs font-medium text-slate-700">Name</label>
                <input
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="e.g. Roof inspection for Smith claim"
                  className="mt-1 w-full rounded-lg border border-stone-200 px-3 py-2 text-sm focus:border-amber-500 focus:outline-none"
                  maxLength={160}
                  required
                  autoFocus
                />
              </div>
              <div>
                <label className="text-xs font-medium text-slate-700">Description (optional)</label>
                <textarea
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                  rows={2}
                  className="mt-1 w-full rounded-lg border border-stone-200 px-3 py-2 text-sm focus:border-amber-500 focus:outline-none"
                />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-xs font-medium text-slate-700">Password (optional)</label>
                  <input
                    type="text"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder="Leave blank for no password"
                    className="mt-1 w-full rounded-lg border border-stone-200 px-3 py-2 text-sm focus:border-amber-500 focus:outline-none"
                  />
                </div>
                <div>
                  <label className="text-xs font-medium text-slate-700">Expires in days</label>
                  <input
                    type="number"
                    min={1}
                    max={365}
                    value={expiresDays}
                    onChange={(e) => setExpiresDays(e.target.value ? Number(e.target.value) : "")}
                    placeholder="Never"
                    className="mt-1 w-full rounded-lg border border-stone-200 px-3 py-2 text-sm focus:border-amber-500 focus:outline-none"
                  />
                </div>
              </div>
              <label className="flex items-center gap-2 text-sm text-slate-700">
                <input
                  type="checkbox"
                  checked={brandWatermark}
                  onChange={(e) => setBrandWatermark(e.target.checked)}
                />
                Apply our logo as a watermark on shared photos
              </label>
            </div>
            {error && <p className="mt-3 text-xs text-red-500">{error}</p>}
            <div className="mt-5 flex justify-end gap-2">
              <button
                type="button"
                onClick={onClose}
                className="rounded-lg border border-stone-200 px-4 py-2 text-sm font-medium text-slate-700"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={saving || !name.trim()}
                className="inline-flex min-h-11 items-center rounded-lg bg-slate-900 px-4 text-sm font-semibold text-white transition-colors hover:bg-slate-800 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-white disabled:bg-stone-100 disabled:text-slate-400"
              >
                {saving ? "Creating…" : "Create gallery"}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}
