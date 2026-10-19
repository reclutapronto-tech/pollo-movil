"use client";

import { useEffect, useState } from "react";

interface TagRow {
  tag: string;
  count: number;
  media_asset_ids?: string[];
}

interface Props {
  jobId?: string | null;
  active: string[];
  onToggle: (tag: string) => void;
  accessToken: string;
  /** Optional callback: receives the full tag list so the parent can build
   *  a tag → media_asset_ids map for client-side filtering. */
  onTagsLoaded?: (tags: TagRow[]) => void;
}

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL || "";
const ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || "";

export function TagFilterBar({ jobId, active, onToggle, accessToken, onTagsLoaded }: Props) {
  const [tags, setTags] = useState<TagRow[]>([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    let cancelled = false;
    async function run() {
      if (!accessToken) return;
      setLoading(true);
      try {
        const url = new URL(`${SUPABASE_URL}/functions/v1/tags`);
        if (jobId) url.searchParams.set("job_id", jobId);
        url.searchParams.set("include_photos", "1");
        const res = await fetch(url.toString(), {
          headers: {
            apikey: ANON_KEY,
            Authorization: `Bearer ${accessToken}`,
          },
        });
        const data = await res.json();
        if (!cancelled) {
          const rows: TagRow[] = data.tags || [];
          setTags(rows);
          onTagsLoaded?.(rows);
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    }
    void run();
    return () => {
      cancelled = true;
    };
  }, [jobId, accessToken, onTagsLoaded]);

  if (!loading && tags.length === 0) return null;

  return (
    <div className="flex flex-wrap items-center gap-2">
      <span className="text-xs font-medium text-slate-500">Tags:</span>
      {tags.map((t) => {
        const isActive = active.includes(t.tag);
        return (
          <button
            key={t.tag}
            onClick={() => onToggle(t.tag)}
            className={`rounded-full border px-2.5 py-1 text-xs font-medium transition ${
              isActive
                ? "border-amber-500 bg-amber-500 text-white"
                : "border-stone-200 bg-card text-slate-700 hover:border-amber-300"
            }`}
          >
            {t.tag} · {t.count}
          </button>
        );
      })}
    </div>
  );
}
