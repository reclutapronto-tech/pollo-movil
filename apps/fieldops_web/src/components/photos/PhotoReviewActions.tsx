"use client";

import { useCallback, useEffect, useState } from "react";
import { CheckCircle2, Flag, Clock4, X } from "lucide-react";
import { getSupabase } from "@/lib/supabase";
import { useCurrentUser } from "@/lib/use-role";
import { isSupervisorOrAbove } from "@/lib/roles";
import { useI18n } from "@/lib/i18n";

export type ReviewStatus = "unreviewed" | "approved" | "flagged";

interface PhotoReview {
  photo_event_id: string;
  photo_occurred_at: string;
  status: ReviewStatus;
  flag_reason: string | null;
  reviewed_at: string | null;
}

/**
 * Inline approve/flag controls + live status badge for a single photo_event.
 *
 * Writes to `photo_reviews` (see migration 20260420500000_photo_reviews.sql);
 * the composite PK matches photo_events(id, occurred_at). RLS blocks workers
 * from writing — only supervisors+ see the action buttons.
 *
 * Realtime: subscribes to photo_reviews UPDATE/INSERT filtered by this
 * photo_event_id so multiple supervisors triaging in parallel see each
 * other's decisions immediately.
 */
export function PhotoReviewActions({
  photoEventId,
  photoOccurredAt,
  companyId,
  compact = false,
}: {
  photoEventId: string;
  photoOccurredAt: string;
  companyId: string;
  compact?: boolean;
}) {
  const { t } = useI18n();
  const { role } = useCurrentUser();
  const canReview = isSupervisorOrAbove(role);

  const [review, setReview] = useState<PhotoReview | null>(null);
  const [busy, setBusy] = useState(false);
  const [flagging, setFlagging] = useState(false);
  const [flagReason, setFlagReason] = useState("");
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const supabase = getSupabase();
    const { data } = await supabase
      .from("photo_reviews")
      .select("photo_event_id, photo_occurred_at, status, flag_reason, reviewed_at")
      .eq("photo_event_id", photoEventId)
      .maybeSingle();
    setReview(data as PhotoReview | null);
  }, [photoEventId]);

  useEffect(() => {
    load();
    const supabase = getSupabase();
    const channel = supabase
      .channel(
        `photo-review-${photoEventId}-${Math.random().toString(36).slice(2)}`,
      )
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "photo_reviews",
          filter: `photo_event_id=eq.${photoEventId}`,
        },
        () => load(),
      )
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, [photoEventId, load]);

  const upsertReview = useCallback(
    async (status: ReviewStatus, reason: string | null) => {
      setBusy(true);
      setError(null);
      try {
        const supabase = getSupabase();
        const { error: err } = await supabase.from("photo_reviews").upsert(
          {
            photo_event_id: photoEventId,
            photo_occurred_at: photoOccurredAt,
            company_id: companyId,
            status,
            flag_reason: reason,
            reviewed_at: new Date().toISOString(),
          },
          { onConflict: "photo_event_id,photo_occurred_at" },
        );
        if (err) throw err;
        setFlagging(false);
        setFlagReason("");
      } catch (e) {
        setError(e instanceof Error ? e.message : "Update failed");
      } finally {
        setBusy(false);
      }
    },
    [photoEventId, photoOccurredAt, companyId],
  );

  const status: ReviewStatus = review?.status ?? "unreviewed";

  const badge = (
    <span
      className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-semibold ${
        status === "approved"
          ? "bg-emerald-50 text-emerald-700 dark:bg-emerald-950/40 dark:text-emerald-300"
          : status === "flagged"
            ? "bg-rose-50 text-rose-700 dark:bg-rose-950/40 dark:text-rose-300"
            : "bg-stone-100 text-slate-500 dark:bg-slate-800 dark:text-slate-400"
      }`}
    >
      {status === "approved" ? (
        <CheckCircle2 size={10} />
      ) : status === "flagged" ? (
        <Flag size={10} />
      ) : (
        <Clock4 size={10} />
      )}
      {t(`photoReview.status.${status}`)}
    </span>
  );

  if (!canReview) {
    // Workers just see the badge (if any review exists yet).
    return review ? badge : null;
  }

  if (compact && !flagging) {
    return (
      <div className="flex items-center gap-1.5">
        {badge}
        <button
          onClick={() => upsertReview("approved", null)}
          disabled={busy || status === "approved"}
          className="rounded-md bg-emerald-50 px-1.5 py-0.5 text-xs font-semibold text-emerald-700 hover:bg-emerald-100 disabled:bg-stone-100 disabled:text-slate-400 dark:bg-emerald-950/40 dark:text-emerald-300 dark:hover:bg-emerald-950/60"
          aria-label={t("photoReview.approve")}
        >
          ✓
        </button>
        <button
          onClick={() => setFlagging(true)}
          disabled={busy}
          className="rounded-md bg-rose-50 px-1.5 py-0.5 text-xs font-semibold text-rose-700 hover:bg-rose-100 disabled:bg-stone-100 disabled:text-slate-400 dark:bg-rose-950/40 dark:text-rose-300 dark:hover:bg-rose-950/60"
          aria-label={t("photoReview.flag")}
        >
          ⚑
        </button>
      </div>
    );
  }

  if (flagging) {
    return (
      <div className="space-y-2 rounded-lg border border-rose-200 bg-rose-50 p-2 dark:border-rose-900/40 dark:bg-rose-950/30">
        <input
          type="text"
          value={flagReason}
          onChange={(e) => setFlagReason(e.target.value)}
          placeholder={t("photoReview.flagReasonPlaceholder")}
          autoFocus
          className="w-full rounded-md border border-rose-200 bg-card px-2 py-1 text-xs dark:border-rose-900/60 dark:bg-slate-900 dark:text-slate-100"
        />
        <div className="flex gap-1.5">
          <button
            onClick={() => upsertReview("flagged", flagReason.trim() || null)}
            disabled={busy || flagReason.trim().length < 3}
            className="rounded-md bg-rose-600 px-2 py-1 text-xs font-semibold text-white hover:bg-rose-700 disabled:bg-stone-100 disabled:text-slate-400"
          >
            {t("photoReview.confirmFlag")}
          </button>
          <button
            onClick={() => {
              setFlagging(false);
              setFlagReason("");
            }}
            disabled={busy}
            className="rounded-md bg-stone-100 px-2 py-1 text-xs font-semibold text-slate-600 hover:bg-stone-200 dark:bg-slate-800 dark:text-slate-400 dark:hover:bg-slate-700"
            aria-label={t("common.cancel")}
          >
            <X size={10} />
          </button>
        </div>
        {error && (
          <p className="text-xs text-rose-700 dark:text-rose-400">{error}</p>
        )}
      </div>
    );
  }

  return (
    <div className="flex flex-wrap items-center gap-2">
      {badge}
      <button
        onClick={() => upsertReview("approved", null)}
        disabled={busy || status === "approved"}
        className="inline-flex items-center gap-1 rounded-md bg-emerald-50 px-2 py-1 text-xs font-semibold text-emerald-700 hover:bg-emerald-100 disabled:bg-stone-100 disabled:text-slate-400 dark:bg-emerald-950/40 dark:text-emerald-300 dark:hover:bg-emerald-950/60"
      >
        <CheckCircle2 size={12} /> {t("photoReview.approve")}
      </button>
      <button
        onClick={() => setFlagging(true)}
        disabled={busy}
        className="inline-flex items-center gap-1 rounded-md bg-rose-50 px-2 py-1 text-xs font-semibold text-rose-700 hover:bg-rose-100 disabled:bg-stone-100 disabled:text-slate-400 dark:bg-rose-950/40 dark:text-rose-300 dark:hover:bg-rose-950/60"
      >
        <Flag size={12} /> {t("photoReview.flag")}
      </button>
      {review?.flag_reason && status === "flagged" && (
        <span className="text-xs italic text-rose-700 dark:text-rose-400">
          &ldquo;{review.flag_reason}&rdquo;
        </span>
      )}
      {error && (
        <span className="text-xs text-rose-700 dark:text-rose-400">{error}</span>
      )}
    </div>
  );
}
