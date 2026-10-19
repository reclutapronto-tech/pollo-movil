"use client";

import { useCallback, useEffect, useState } from "react";
import { MessageSquare } from "lucide-react";
import { getSupabase } from "@/lib/supabase";
import { useCurrentUser } from "@/lib/use-role";
import { PhotoCommentComposer } from "@/components/photos/PhotoCommentComposer";
import { PhotoCommentList } from "@/components/photos/PhotoCommentList";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL || "";
const ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || "";

export interface PhotoComment {
  id: string;
  parent_id: string | null;
  author_id: string;
  author: { full_name: string; avatar_url: string | null } | null;
  body: string;
  deleted: boolean;
  created_at: string;
  updated_at: string;
  mention_user_ids: string[];
}

interface Props {
  mediaAssetId: string;
  companyId: string;
  accessToken: string;
}

/**
 * Comments sidebar for a single photo (media_asset). Fetches via the
 * photo-comments edge function, renders the threaded list + composer, and
 * subscribes to realtime so new comments/deletes appear live for everyone
 * viewing the same photo. Mirrors the realtime pattern in PhotoReviewActions.
 */
export function PhotoCommentsPanel({ mediaAssetId, companyId, accessToken }: Props) {
  const { userId, role } = useCurrentUser();
  const [comments, setComments] = useState<PhotoComment[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!accessToken) return;
    try {
      const res = await fetch(
        `${SUPABASE_URL}/functions/v1/photo-comments?media_asset_id=${encodeURIComponent(mediaAssetId)}`,
        {
          headers: {
            apikey: ANON_KEY,
            Authorization: `Bearer ${accessToken}`,
          },
        },
      );
      const data = await res.json();
      if (!res.ok) {
        setError(data.message || "Failed to load comments");
        return;
      }
      setComments((data.comments as PhotoComment[]) ?? []);
      setError(null);
    } catch {
      setError("Failed to load comments");
    } finally {
      setLoading(false);
    }
  }, [mediaAssetId, accessToken]);

  useEffect(() => {
    setLoading(true);
    load();
    const supabase = getSupabase();
    const channel = supabase
      .channel(`photo-comments-${mediaAssetId}-${Math.random().toString(36).slice(2)}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "photo_comments",
          filter: `media_asset_id=eq.${mediaAssetId}`,
        },
        () => load(),
      )
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, [mediaAssetId, load]);

  const handleDelete = useCallback(
    async (commentId: string) => {
      try {
        const res = await fetch(`${SUPABASE_URL}/functions/v1/photo-comments`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            apikey: ANON_KEY,
            Authorization: `Bearer ${accessToken}`,
          },
          body: JSON.stringify({ action: "delete", comment_id: commentId }),
        });
        if (res.ok) load();
      } catch {
        // Realtime reload will reconcile on next change; surface nothing here.
      }
    },
    [accessToken, load],
  );

  const visibleCount = comments.filter((c) => !c.deleted).length;

  return (
    <div className="flex h-full flex-col">
      <div className="flex items-center gap-2 border-b border-stone-200 pb-3 dark:border-slate-700">
        <MessageSquare size={16} className="text-slate-500 dark:text-slate-400" />
        <h4 className="text-sm font-semibold text-slate-800 dark:text-slate-100">
          Comments{visibleCount > 0 ? ` (${visibleCount})` : ""}
        </h4>
      </div>

      <div className="min-h-0 flex-1 overflow-y-auto py-4">
        {loading ? (
          <p className="py-6 text-center text-sm text-slate-400 dark:text-slate-500">Loading…</p>
        ) : error ? (
          <p className="py-6 text-center text-sm text-rose-600 dark:text-rose-400">{error}</p>
        ) : (
          <PhotoCommentList
            comments={comments}
            currentUserId={userId}
            role={role}
            mediaAssetId={mediaAssetId}
            companyId={companyId}
            accessToken={accessToken}
            onChanged={load}
            onDelete={handleDelete}
          />
        )}
      </div>

      <div className="border-t border-stone-200 pt-3 dark:border-slate-700">
        <PhotoCommentComposer
          mediaAssetId={mediaAssetId}
          companyId={companyId}
          accessToken={accessToken}
          onPosted={load}
        />
      </div>
    </div>
  );
}
