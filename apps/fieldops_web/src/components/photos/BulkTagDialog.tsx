"use client";

import { useState } from "react";

interface Props {
  open: boolean;
  mediaAssetIds: string[];
  accessToken: string;
  onClose: () => void;
  onTagged: (count: number) => void;
}

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL || "";
const ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || "";

export function BulkTagDialog({ open, mediaAssetIds, accessToken, onClose, onTagged }: Props) {
  const [tag, setTag] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!open) return null;

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!tag.trim() || mediaAssetIds.length === 0) return;
    setSaving(true);
    setError(null);
    try {
      const res = await fetch(`${SUPABASE_URL}/functions/v1/tags`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          apikey: ANON_KEY,
          Authorization: `Bearer ${accessToken}`,
          "Idempotency-Key": crypto.randomUUID(),
        },
        body: JSON.stringify({ tag: tag.trim(), media_asset_ids: mediaAssetIds }),
      });
      const data = await res.json();
      if (!res.ok) {
        setError(data.message || "Failed to tag photos");
        return;
      }
      onTagged(data.tagged ?? mediaAssetIds.length);
      setTag("");
      onClose();
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-6" onClick={onClose}>
      <form
        className="w-full max-w-md rounded-2xl bg-card p-6 shadow-xl"
        onSubmit={handleSubmit}
        onClick={(e) => e.stopPropagation()}
      >
        <h2 className="text-lg font-bold text-slate-900">Tag {mediaAssetIds.length} photos</h2>
        <p className="mt-1 text-sm text-slate-500">Add a tag that will be attached to every selected photo.</p>
        <input
          value={tag}
          onChange={(e) => setTag(e.target.value)}
          placeholder="e.g. roof damage, exterior, before"
          className="mt-4 w-full rounded-lg border border-stone-200 px-3 py-2 text-sm focus:border-amber-500 focus:outline-none"
          autoFocus
          maxLength={64}
        />
        {error && <p className="mt-2 text-xs text-red-500">{error}</p>}
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
            disabled={saving || !tag.trim()}
            className="inline-flex min-h-11 items-center rounded-lg bg-slate-900 px-4 text-sm font-semibold text-white transition-colors hover:bg-slate-800 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-white disabled:bg-stone-100 disabled:text-slate-400"
          >
            {saving ? "Tagging…" : "Apply tag"}
          </button>
        </div>
      </form>
    </div>
  );
}
