"use client";

import { Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useSearchParams, useRouter } from "next/navigation";
import { useI18n } from "@/lib/i18n";
import { getSupabase } from "@/lib/supabase";
import { SkeletonPhotoGrid } from "@/components/ui/skeleton";
import { ProjectBrowser } from "@/components/photos/project-browser";
import { ProjectWorkspaceTabs } from "@/components/photos/project-workspace-tabs";
import { PhotoTimelinePanel } from "@/components/photos/photo-timeline-panel";
import { PhotoMapPanel } from "@/components/photos/photo-map-panel";
import { TagFilterBar } from "@/components/photos/TagFilterBar";
import { BulkTagDialog } from "@/components/photos/BulkTagDialog";
import { SaveAsGalleryDialog } from "@/components/photos/SaveAsGalleryDialog";
import { ShareLinkDialog } from "@/components/photos/ShareLinkDialog";
import { PhotoReviewActions, type ReviewStatus } from "@/components/photos/PhotoReviewActions";
import { PhotoCommentsPanel } from "@/components/photos/PhotoCommentsPanel";
import { useCurrentUser } from "@/lib/use-role";

interface PhotoEntry {
  id: string;
  occurred_at: string;
  media_asset_id: string;
  is_checkpoint: boolean;
  gps_lat: number | null;
  gps_lng: number | null;
  user_id: string;
  users: { full_name: string } | null;
  task_id: string | null;
  tasks: { name: string } | null;
  media_assets: {
    id: string;
    verification_code: string | null;
    storage_path: string;
    bucket_name: string;
    sha256_hash: string | null;
    kind: string;
    stamped_media_id: string | null;
    metadata: Record<string, unknown>;
  } | null;
}

type DisplayAsset = NonNullable<PhotoEntry["media_assets"]>;
type ResolvedPhotoEntry = PhotoEntry & {
  displayAsset: DisplayAsset | null;
};

function buildSignedUrlCacheKey(photoId: string, asset: DisplayAsset | null) {
  return `${photoId}:${asset?.bucket_name ?? ""}:${asset?.storage_path ?? ""}`;
}

function getDisplayAsset(
  photo: PhotoEntry,
  stampedAssetsById: Map<string, DisplayAsset>,
): DisplayAsset | null {
  const originalAsset = photo.media_assets;
  if (!originalAsset) return null;

  if (originalAsset.stamped_media_id) {
    return stampedAssetsById.get(originalAsset.stamped_media_id) ?? originalAsset;
  }

  return originalAsset;
}

export default function PhotosPage() {
  return (
    <Suspense
      fallback={
        <SkeletonPhotoGrid count={6} />
      }
    >
      <PhotoFeedContent />
    </Suspense>
  );
}

interface ProjectOption {
  id: string;
  name: string;
  code: string;
  status?: string;
  photoCount?: number;
  lastPhotoAt?: string | null;
}

function PhotoFeedContent() {
  const { t } = useI18n();
  const router = useRouter();
  const searchParams = useSearchParams();
  const jobId = searchParams.get("job_id");
  const activeTab = (searchParams.get("tab") || "feed").toLowerCase();

  const PHOTOS_PAGE_SIZE = 30;

  const [photos, setPhotos] = useState<ResolvedPhotoEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [jobName, setJobName] = useState<string | null>(null);
  const [projects, setProjects] = useState<ProjectOption[]>([]);

  const [projectSearch, setProjectSearch] = useState("");
  const [projectBrowserView, setProjectBrowserView] = useState<"icons" | "list">("icons");

  // Load all projects for the browser and enrich with photo counts / last activity.
  useEffect(() => {
    const supabase = getSupabase();
    Promise.all([
      supabase.from("jobs").select("id, name, code, status").order("name"),
      supabase.from("photo_events").select("job_id, occurred_at").order("occurred_at", { ascending: false }),
    ]).then(([jobsResult, photosResult]) => {
      const baseProjects = (jobsResult.data as ProjectOption[]) ?? [];
      const statsByJob = new Map<string, { count: number; lastPhotoAt: string | null }>();

      for (const row of photosResult.data ?? []) {
        const jobKey = row.job_id as string;
        const current = statsByJob.get(jobKey) ?? { count: 0, lastPhotoAt: null };
        statsByJob.set(jobKey, {
          count: current.count + 1,
          lastPhotoAt: current.lastPhotoAt ?? (row.occurred_at as string),
        });
      }

      setProjects(
        baseProjects.map((project) => ({
          ...project,
          photoCount: statsByJob.get(project.id)?.count ?? 0,
          lastPhotoAt: statsByJob.get(project.id)?.lastPhotoAt ?? null,
        })),
      );
    });
  }, []);
  const [signedUrls, setSignedUrls] = useState<Record<string, string>>({});
  const urlCacheRef = useRef<Record<string, string>>({});
  const [hasMorePhotos, setHasMorePhotos] = useState(false);
  const [loadingMorePhotos, setLoadingMorePhotos] = useState(false);

  // Filter state
  const [filterDate, setFilterDate] = useState("");
  const [filterWorker, setFilterWorker] = useState("");
  const [filterTask, setFilterTask] = useState("");
  const [filterMode, setFilterMode] = useState("");
  const [filterCheckpoint, setFilterCheckpoint] = useState(false);
  const [filterVerified, setFilterVerified] = useState<"all" | "verified" | "unverified">("all");
  const [reviewFilter, setReviewFilter] = useState<"all" | "unreviewed" | "approved" | "flagged">("all");
  const [reviewStatusMap, setReviewStatusMap] = useState<Map<string, ReviewStatus>>(new Map());
  const { companyId: currentCompanyId } = useCurrentUser();

  // Lightbox state
  const [selectedPhotoIndex, setSelectedPhotoIndex] = useState<number | null>(null);

  // View mode state
  const [feedViewMode, setFeedViewMode] = useState<"gallery" | "sheet">("gallery");

  // Bulk select state
  const [selectedPhotos, setSelectedPhotos] = useState<Set<string>>(new Set());
  const [codeCopied, setCodeCopied] = useState(false);
  const [exporting, setExporting] = useState(false);

  // Sprint 8.5 sharing slice — tag filter + share dialog state
  const [accessToken, setAccessToken] = useState<string>("");
  const [activeTagFilter, setActiveTagFilter] = useState<string[]>([]);
  const [tagPhotoMap, setTagPhotoMap] = useState<Record<string, string[]>>({});
  const [showTagDialog, setShowTagDialog] = useState(false);
  const [showGalleryDialog, setShowGalleryDialog] = useState(false);
  const [showShareDialog, setShowShareDialog] = useState(false);

  useEffect(() => {
    const supabase = getSupabase();
    void supabase.auth.getSession().then(({ data }) => {
      setAccessToken(data.session?.access_token ?? "");
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      setAccessToken(session?.access_token ?? "");
    });
    return () => {
      sub.subscription.unsubscribe();
    };
  }, []);

  // media_asset_ids of currently-selected rows (tags + galleries need these,
  // not the photo_event IDs that `selectedPhotos` stores).
  const selectedMediaAssetIds = useMemo(() => {
    if (selectedPhotos.size === 0) return [] as string[];
    return photos
      .filter((p) => selectedPhotos.has(p.id))
      .map((p) => p.media_asset_id)
      .filter((id): id is string => typeof id === "string" && id.length > 0);
  }, [photos, selectedPhotos]);

  const loadPhotos = useCallback(async () => {
    setLoading(true);
    setError(null);

    if (!jobId) {
      setPhotos([]);
      setJobName(null);
      setHasMorePhotos(false);
      setLoading(false);
      return;
    }

    try {
      const supabase = getSupabase();

      const { data: job } = await supabase
        .from("jobs")
        .select("name")
        .eq("id", jobId)
        .maybeSingle();
      if (job) setJobName(job.name);

      const { data, error: err } = await supabase
        .from("photo_events")
        .select(`
          id,
          occurred_at,
          media_asset_id,
          is_checkpoint,
          gps_lat,
          gps_lng,
          user_id,
          task_id,
          users!photo_events_user_id_fkey ( full_name ),
          tasks ( name ),
          media_assets!photo_events_media_asset_id_fkey (
            id,
            verification_code,
            storage_path,
            bucket_name,
            sha256_hash,
            kind,
            stamped_media_id,
            metadata
          )
        `)
        .eq("job_id", jobId)
        .order("occurred_at", { ascending: false })
        .limit(PHOTOS_PAGE_SIZE);

      if (err) throw err;
      const photoData = (data as unknown as PhotoEntry[]) ?? [];
      setHasMorePhotos(photoData.length === PHOTOS_PAGE_SIZE);

      const stampedIds = photoData
        .map((photo) => photo.media_assets?.stamped_media_id)
        .filter((id): id is string => Boolean(id));

      let stampedAssetsById = new Map<string, DisplayAsset>();
      if (stampedIds.length > 0) {
        const { data: stampedAssets, error: stampedErr } = await supabase
          .from("media_assets")
          .select(`
            id,
            verification_code,
            storage_path,
            bucket_name,
            sha256_hash,
            kind,
            stamped_media_id,
            metadata
          `)
          .in("id", stampedIds);

        if (stampedErr) throw stampedErr;

        stampedAssetsById = new Map(
          ((stampedAssets as DisplayAsset[] | null) ?? []).map((asset) => [asset.id, asset]),
        );
      }

      const resolvedPhotos = photoData.map((photo) => ({
        ...photo,
        displayAsset: getDisplayAsset(photo, stampedAssetsById),
      }));
      setPhotos(resolvedPhotos);

      // Generate signed URLs only for display assets not already cached.
      const nextSignedUrls: Record<string, string> = {};
      const newPhotos = resolvedPhotos.filter((photo) => {
        const cacheKey = buildSignedUrlCacheKey(photo.id, photo.displayAsset);
        return !urlCacheRef.current[cacheKey];
      });
      await Promise.allSettled(
        newPhotos.map(async (photo) => {
          const asset = photo.displayAsset;
          if (!asset?.storage_path || !asset?.bucket_name) return;
          const { data: urlData } = await supabase.storage
            .from(asset.bucket_name)
            .createSignedUrl(asset.storage_path, 3600);
          if (urlData?.signedUrl) {
            const cacheKey = buildSignedUrlCacheKey(photo.id, asset);
            urlCacheRef.current[cacheKey] = urlData.signedUrl;
          }
        })
      );
      resolvedPhotos.forEach((photo) => {
        const cacheKey = buildSignedUrlCacheKey(photo.id, photo.displayAsset);
        if (urlCacheRef.current[cacheKey]) {
          nextSignedUrls[photo.id] = urlCacheRef.current[cacheKey];
        }
      });
      setSignedUrls(nextSignedUrls);
    } catch (e) {
      setError(e instanceof Error ? e.message : t("photos.failedToLoad"));
    } finally {
      setLoading(false);
    }
  }, [jobId, t]);

  const loadMorePhotos = useCallback(async () => {
    if (!jobId) return;
    setLoadingMorePhotos(true);
    try {
      const supabase = getSupabase();
      const { data, error: err } = await supabase
        .from("photo_events")
        .select(`
          id,
          occurred_at,
          media_asset_id,
          is_checkpoint,
          gps_lat,
          gps_lng,
          user_id,
          task_id,
          users!photo_events_user_id_fkey ( full_name ),
          tasks ( name ),
          media_assets!photo_events_media_asset_id_fkey (
            id,
            verification_code,
            storage_path,
            bucket_name,
            sha256_hash,
            kind,
            stamped_media_id,
            metadata
          )
        `)
        .eq("job_id", jobId)
        .order("occurred_at", { ascending: false })
        .range(photos.length, photos.length + PHOTOS_PAGE_SIZE - 1);

      if (err) throw err;
      const photoData = (data as unknown as PhotoEntry[]) ?? [];
      setHasMorePhotos(photoData.length === PHOTOS_PAGE_SIZE);

      // Resolve stamped assets for new page
      const stampedIds = photoData
        .map((photo) => photo.media_assets?.stamped_media_id)
        .filter((id): id is string => Boolean(id));

      let stampedAssetsById = new Map<string, DisplayAsset>();
      if (stampedIds.length > 0) {
        const { data: stampedAssets, error: stampedErr } = await supabase
          .from("media_assets")
          .select(`
            id,
            verification_code,
            storage_path,
            bucket_name,
            sha256_hash,
            kind,
            stamped_media_id,
            metadata
          `)
          .in("id", stampedIds);

        if (stampedErr) throw stampedErr;
        stampedAssetsById = new Map(
          ((stampedAssets as DisplayAsset[] | null) ?? []).map((asset) => [asset.id, asset]),
        );
      }

      const resolvedNew = photoData.map((photo) => ({
        ...photo,
        displayAsset: getDisplayAsset(photo, stampedAssetsById),
      }));

      // Generate signed URLs for new photos
      await Promise.allSettled(
        resolvedNew.map(async (photo) => {
          const asset = photo.displayAsset;
          if (!asset?.storage_path || !asset?.bucket_name) return;
          const { data: urlData } = await supabase.storage
            .from(asset.bucket_name)
            .createSignedUrl(asset.storage_path, 3600);
          if (urlData?.signedUrl) {
            const cacheKey = buildSignedUrlCacheKey(photo.id, asset);
            urlCacheRef.current[cacheKey] = urlData.signedUrl;
          }
        })
      );

      const newSignedUrls: Record<string, string> = {};
      resolvedNew.forEach((photo) => {
        const cacheKey = buildSignedUrlCacheKey(photo.id, photo.displayAsset);
        if (urlCacheRef.current[cacheKey]) {
          newSignedUrls[photo.id] = urlCacheRef.current[cacheKey];
        }
      });

      setPhotos((prev) => [...prev, ...resolvedNew]);
      setSignedUrls((prev) => ({ ...prev, ...newSignedUrls }));
    } catch (e) {
      setError(e instanceof Error ? e.message : t("photos.failedToLoad"));
    } finally {
      setLoadingMorePhotos(false);
    }
  }, [jobId, photos.length, t]);

  useEffect(() => {
    loadPhotos();

    if (!jobId) return;

    const supabase = getSupabase();
    const channel = supabase
      .channel(`photos-job-${jobId}-${Math.random().toString(36).slice(2)}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "photo_events",
          filter: `job_id=eq.${jobId}`,
        },
        async (payload) => {
          // Fetch the full new row with joins instead of reloading all photos
          const newId = (payload.new as { id?: string })?.id;
          if (!newId) return;
          const { data } = await supabase
            .from("photo_events")
            .select(`
              id,
              occurred_at,
              media_asset_id,
              is_checkpoint,
              gps_lat,
              gps_lng,
              user_id,
              task_id,
              users!photo_events_user_id_fkey ( full_name ),
              tasks ( name ),
              media_assets!photo_events_media_asset_id_fkey (
                id,
                verification_code,
                storage_path,
                bucket_name,
                sha256_hash,
                kind,
                stamped_media_id,
                metadata
              )
            `)
            .eq("id", newId)
            .maybeSingle();
          if (!data) return;
          const photo = data as unknown as PhotoEntry;
          const resolved: ResolvedPhotoEntry = { ...photo, displayAsset: photo.media_assets ?? null };
          const asset = resolved.displayAsset;
          if (asset?.storage_path && asset?.bucket_name) {
            const { data: urlData } = await supabase.storage
              .from(asset.bucket_name)
              .createSignedUrl(asset.storage_path, 3600);
            if (urlData?.signedUrl) {
              const cacheKey = buildSignedUrlCacheKey(resolved.id, asset);
              urlCacheRef.current[cacheKey] = urlData.signedUrl;
              setSignedUrls((prev) => ({ ...prev, [resolved.id]: urlData.signedUrl }));
            }
          }
          setPhotos((prev) => [resolved, ...prev]);
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [jobId, loadPhotos]);

  // Fetch review status for all currently-loaded photos + subscribe to live updates (FUX-013c).
  useEffect(() => {
    if (photos.length === 0 || !currentCompanyId) {
      setReviewStatusMap(new Map());
      return;
    }

    const photoIds = photos.map((p) => p.id);
    const supabase = getSupabase();
    let cancelled = false;

    async function loadReviews() {
      const { data } = await supabase
        .from("photo_reviews")
        .select("photo_event_id, status")
        .eq("company_id", currentCompanyId)
        .in("photo_event_id", photoIds);
      if (cancelled) return;
      const next = new Map<string, ReviewStatus>();
      for (const row of (data ?? []) as Array<{
        photo_event_id: string;
        status: ReviewStatus;
      }>) {
        next.set(row.photo_event_id, row.status);
      }
      setReviewStatusMap(next);
    }
    loadReviews();

    const channel = supabase
      .channel(
        `photo-reviews-${currentCompanyId}-${Math.random().toString(36).slice(2)}`,
      )
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "photo_reviews",
          filter: `company_id=eq.${currentCompanyId}`,
        },
        (payload) => {
          const row = (payload.new ?? payload.old) as {
            photo_event_id?: string;
            status?: ReviewStatus;
          } | null;
          if (!row?.photo_event_id) return;
          setReviewStatusMap((prev) => {
            const next = new Map(prev);
            if (payload.eventType === "DELETE") {
              next.delete(row.photo_event_id!);
            } else if (row.status) {
              next.set(row.photo_event_id!, row.status);
            }
            return next;
          });
        },
      )
      .subscribe();

    return () => {
      cancelled = true;
      supabase.removeChannel(channel);
    };
  }, [photos, currentCompanyId]);

  function formatTime(iso: string) {
    return new Date(iso).toLocaleString(undefined, {
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });
  }

  // Stats derived from all photos
  const stats = useMemo(() => {
    let verified = 0;
    let unverified = 0;
    let checkpoints = 0;
    let beforeCount = 0;
    let afterCount = 0;
    for (const p of photos) {
      const asset = p.displayAsset ?? p.media_assets;
      const code = asset?.verification_code ?? p.media_assets?.verification_code;
      const hash = asset?.sha256_hash ?? p.media_assets?.sha256_hash;
      if (code || hash) verified++;
      else unverified++;
      if (p.is_checkpoint) checkpoints++;
      const meta = asset?.metadata as Record<string, unknown> | undefined;
      const mode = ((meta?.mode as string) ?? "").toLowerCase();
      if (mode === "before") beforeCount++;
      else if (mode === "after") afterCount++;
    }
    return { total: photos.length, verified, unverified, checkpoints, beforeCount, afterCount };
  }, [photos]);

  // Derive unique workers and tasks for filter dropdowns
  const uniqueWorkers = useMemo(() => {
    const names = new Set<string>();
    photos.forEach((p) => {
      const name = (p.users as { full_name: string } | null)?.full_name;
      if (name) names.add(name);
    });
    return Array.from(names).sort();
  }, [photos]);

  const uniqueTasks = useMemo(() => {
    const names = new Set<string>();
    photos.forEach((p) => {
      const name = (p.tasks as { name: string } | null)?.name;
      if (name) names.add(name);
    });
    return Array.from(names).sort();
  }, [photos]);

  // Apply filters
  const filteredPhotos = useMemo(() => {
    return photos.filter((photo) => {
      // Date filter
      if (filterDate) {
        const photoDate = new Date(photo.occurred_at).toISOString().slice(0, 10);
        if (photoDate !== filterDate) return false;
      }
      // Worker filter
      if (filterWorker) {
        const name = (photo.users as { full_name: string } | null)?.full_name ?? "";
        if (name !== filterWorker) return false;
      }
      // Task filter
      if (filterTask) {
        const name = (photo.tasks as { name: string } | null)?.name ?? "";
        if (name !== filterTask) return false;
      }
      // Mode filter (Before/After/Standard)
      if (filterMode) {
        const asset = photo.displayAsset ?? photo.media_assets;
        const meta = asset?.metadata as Record<string, unknown> | undefined;
        const mode = (meta?.mode as string) ?? "standard";
        if (mode.toLowerCase() !== filterMode.toLowerCase()) return false;
      }
      // Checkpoint-only filter
      if (filterCheckpoint && !photo.is_checkpoint) return false;
      // Verified/unverified filter
      if (filterVerified !== "all") {
        const asset = photo.displayAsset ?? photo.media_assets;
        const isVerified = !!(asset?.verification_code || asset?.sha256_hash);
        if (filterVerified === "verified" && !isVerified) return false;
        if (filterVerified === "unverified" && isVerified) return false;
      }
      // Active tag filter — photo must carry every selected tag (AND-match).
      if (activeTagFilter.length > 0) {
        for (const tag of activeTagFilter) {
          const ids = tagPhotoMap[tag.toLowerCase()] ?? [];
          if (!ids.includes(photo.media_asset_id)) return false;
        }
      }
      // Review-status filter (FUX-013c). Absent row = "unreviewed".
      if (reviewFilter !== "all") {
        const status = reviewStatusMap.get(photo.id) ?? "unreviewed";
        if (status !== reviewFilter) return false;
      }
      return true;
    });
  }, [photos, filterDate, filterWorker, filterTask, filterMode, filterCheckpoint, filterVerified, activeTagFilter, tagPhotoMap, reviewFilter, reviewStatusMap]);

  // Tab counts ignore the reviewFilter itself (so "all" still shows all).
  const reviewCounts = useMemo(() => {
    const counts = { all: photos.length, unreviewed: 0, approved: 0, flagged: 0 };
    for (const p of photos) {
      const status = reviewStatusMap.get(p.id) ?? "unreviewed";
      if (status === "unreviewed") counts.unreviewed++;
      else if (status === "approved") counts.approved++;
      else if (status === "flagged") counts.flagged++;
    }
    return counts;
  }, [photos, reviewStatusMap]);

  // Bulk selection helpers
  function togglePhotoSelection(id: string) {
    setSelectedPhotos((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  function toggleSelectAll() {
    if (selectedPhotos.size === filteredPhotos.length) {
      setSelectedPhotos(new Set());
    } else {
      setSelectedPhotos(new Set(filteredPhotos.map((p) => p.id)));
    }
  }

  function downloadSelected() {
    filteredPhotos.forEach((photo) => {
      if (selectedPhotos.has(photo.id) && signedUrls[photo.id]) {
        window.open(signedUrls[photo.id], "_blank");
      }
    });
  }

  // Lightbox helpers
  function openLightbox(index: number) {
    setSelectedPhotoIndex(index);
    setCodeCopied(false);
  }
  function closeLightbox() {
    setSelectedPhotoIndex(null);
    setCodeCopied(false);
  }
  function goToPrevPhoto() {
    setSelectedPhotoIndex((i) => (i !== null && i > 0 ? i - 1 : i));
    setCodeCopied(false);
  }
  function goToNextPhoto() {
    setSelectedPhotoIndex((i) =>
      i !== null && i < filteredPhotos.length - 1 ? i + 1 : i,
    );
    setCodeCopied(false);
  }

  async function copyVerificationCode(code: string) {
    try {
      await navigator.clipboard.writeText(code);
      setCodeCopied(true);
      setTimeout(() => setCodeCopied(false), 2000);
    } catch {
      // fallback — ignore
    }
  }

  /** Export Proof Pack — generates a JSON manifest + opens download links for selected photos */
  async function exportProofPack() {
    if (selectedPhotos.size === 0) return;
    setExporting(true);
    try {
      const selected = filteredPhotos.filter((p) => selectedPhotos.has(p.id));
      const manifest = {
        export_type: "FieldOps Proof Pack",
        exported_at: new Date().toISOString(),
        job_id: jobId,
        job_name: jobName,
        total_photos: selected.length,
        photos: selected.map((p) => {
          const asset = p.displayAsset ?? p.media_assets;
          const originalAsset = p.media_assets;
          return {
            id: p.id,
            captured_at: p.occurred_at,
            worker: (p.users as { full_name: string } | null)?.full_name ?? "Unknown",
            task: (p.tasks as { name: string } | null)?.name ?? null,
            is_checkpoint: p.is_checkpoint,
            verification_code: asset?.verification_code ?? originalAsset?.verification_code ?? null,
            sha256_hash: asset?.sha256_hash ?? originalAsset?.sha256_hash ?? null,
            mode: ((asset?.metadata as Record<string, unknown>)?.mode as string) ?? "standard",
          };
        }),
      };
      const blob = new Blob([JSON.stringify(manifest, null, 2)], { type: "application/json" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `proof-pack-${jobName ?? jobId ?? "export"}-${new Date().toISOString().slice(0, 10)}.json`;
      a.click();
      URL.revokeObjectURL(url);

      // Also open the photo downloads
      selected.forEach((photo) => {
        if (signedUrls[photo.id]) {
          window.open(signedUrls[photo.id], "_blank");
        }
      });
    } finally {
      setExporting(false);
    }
  }

  const lightboxPhoto = selectedPhotoIndex !== null ? filteredPhotos[selectedPhotoIndex] : null;

  return (
    <div>
      <div className="mb-6">
        <a
          href="/"
          className="mb-3 inline-flex items-center gap-1 text-sm font-medium text-slate-500 hover:text-slate-900"
        >
          <span>&larr;</span> {t("common.backToDashboard")}
        </a>

        <h1 className="text-2xl font-bold tracking-tight text-slate-900 dark:text-slate-100">
          {jobName ? t("photos.titleWithJob", { jobName }) : t("photos.title")}
        </h1>
        <p className="mt-1 text-sm text-slate-600 dark:text-slate-400">{t("photos.subtitle")}</p>
        {jobId ? (
          <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
            <div className="flex items-center gap-3">
              <button
                onClick={() => router.push("/photos")}
                className="rounded-2xl border border-stone-200 bg-card px-4 py-2 text-sm font-semibold text-slate-600 shadow-sm hover:bg-stone-50"
              >
                All Projects
              </button>
              <ProjectWorkspaceTabs
                activeTab={activeTab === "timeline" || activeTab === "map" ? activeTab : "feed"}
                onChange={(tab) => router.push(`/photos?job_id=${encodeURIComponent(jobId)}&tab=${tab}`)}
              />
            </div>
            <div className="rounded-2xl border border-amber-200 bg-amber-50 px-4 py-2 text-sm font-medium text-amber-700">
              {photos.length > 0 ? t("photos.liveUpdates", { count: photos.length }) : "Project workspace ready"}
            </div>
          </div>
        ) : (
          <p className="mt-1 text-sm text-slate-500">
            Open a project folder to review proof photos by feed, timeline, or map.
          </p>
        )}

        {/* Stats summary bar */}
        {jobId && !loading && !error && photos.length > 0 && (
          <div className="mt-4 grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
            <div className="rounded-xl border border-stone-200 bg-card px-4 py-3 text-center">
              <p className="text-2xl font-bold text-slate-900">{stats.total}</p>
              <p className="text-xs text-slate-500">Total Photos</p>
            </div>
            <div className="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-center">
              <p className="text-2xl font-bold text-emerald-700">{stats.verified}</p>
              <p className="text-xs text-emerald-600">Verified</p>
            </div>
            <div className="rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-center">
              <p className="text-2xl font-bold text-amber-700">{stats.unverified}</p>
              <p className="text-xs text-amber-600">Pending</p>
            </div>
            <div className="rounded-xl border border-blue-200 bg-blue-50 px-4 py-3 text-center">
              <p className="text-2xl font-bold text-blue-700">{stats.checkpoints}</p>
              <p className="text-xs text-blue-600">Checkpoints</p>
            </div>
            <div className="rounded-xl border border-violet-200 bg-violet-50 px-4 py-3 text-center">
              <p className="text-2xl font-bold text-violet-700">{stats.beforeCount}</p>
              <p className="text-xs text-violet-600">Before</p>
            </div>
            <div className="rounded-xl border border-rose-200 bg-rose-50 px-4 py-3 text-center">
              <p className="text-2xl font-bold text-rose-700">{stats.afterCount}</p>
              <p className="text-xs text-rose-600">After</p>
            </div>
          </div>
        )}
      </div>

      {!jobId && (
        <ProjectBrowser
          projects={projects}
          search={projectSearch}
          onSearchChange={setProjectSearch}
          viewMode={projectBrowserView}
          onViewModeChange={setProjectBrowserView}
          onOpenProject={(projectId) => router.push(`/photos?job_id=${encodeURIComponent(projectId)}&tab=feed`)}
        />
      )}

      {/* Review status tabs (FUX-013c) */}
      {jobId && activeTab === "feed" && photos.length > 0 && (
        <div className="mb-3 flex flex-wrap gap-2">
          {(["all", "unreviewed", "flagged", "approved"] as const).map((f) => {
            const active = reviewFilter === f;
            return (
              <button
                key={f}
                onClick={() => setReviewFilter(f)}
                className={`rounded-full px-3 py-1 text-xs font-semibold transition-colors ${
                  active
                    ? f === "flagged"
                      ? "bg-rose-600 text-white"
                      : f === "approved"
                        ? "bg-emerald-600 text-white"
                        : "bg-slate-900 text-white dark:bg-slate-100 dark:text-slate-900"
                    : "bg-stone-100 text-slate-600 hover:bg-stone-200 dark:bg-slate-800 dark:text-slate-400 dark:hover:bg-slate-700"
                }`}
              >
                {t(`photoReview.tab.${f}`)} ·{" "}
                <span className="tabular-nums">{reviewCounts[f]}</span>
              </button>
            );
          })}
        </div>
      )}

      {/* View mode switcher */}
      {jobId && activeTab === "feed" && photos.length > 0 && (
        <div className="mb-4 flex gap-1 rounded-xl bg-stone-100 p-1 w-fit">
          {(["gallery", "sheet"] as const).map((mode) => (
            <button
              key={mode}
              onClick={() => setFeedViewMode(mode)}
              className={`flex items-center gap-1.5 rounded-lg px-4 py-2 text-sm font-semibold transition-all ${
                feedViewMode === mode
                  ? "bg-card text-slate-900 shadow-sm"
                  : "text-slate-500 hover:text-slate-700"
              }`}
            >
              {mode === "gallery" ? (
                <><svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}><path strokeLinecap="round" strokeLinejoin="round" d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zm10 0a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zm10 0a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z" /></svg>Gallery</>
              ) : (
                <><svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}><path strokeLinecap="round" strokeLinejoin="round" d="M3 10h18M3 14h18M10 3v18" /></svg>Sheet</>
              )}
            </button>
          ))}
        </div>
      )}

      {/* Filter bar */}
      {jobId && activeTab === "feed" && photos.length > 0 && (
        <div className="mb-4 flex flex-wrap items-center gap-3 rounded-xl border border-stone-200 bg-card p-3">
          {/* Date */}
          <label className="flex items-center gap-1.5 text-sm text-slate-600">
            {t("photos.filterByDate")}
            <input
              type="date"
              value={filterDate}
              onChange={(e) => setFilterDate(e.target.value)}
              className="rounded-lg border border-stone-200 bg-slate-50 px-2.5 py-1.5 text-sm text-slate-700 focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30"
            />
          </label>

          {/* Worker */}
          <select
            value={filterWorker}
            onChange={(e) => setFilterWorker(e.target.value)}
            className="rounded-lg border border-stone-200 bg-slate-50 px-2.5 py-1.5 text-sm text-slate-700 focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30"
          >
            <option value="">{t("photos.allWorkers")}</option>
            {uniqueWorkers.map((w) => (
              <option key={w} value={w}>{w}</option>
            ))}
          </select>

          {/* Task */}
          <select
            value={filterTask}
            onChange={(e) => setFilterTask(e.target.value)}
            className="rounded-lg border border-stone-200 bg-slate-50 px-2.5 py-1.5 text-sm text-slate-700 focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30"
          >
            <option value="">{t("photos.allTasks")}</option>
            {uniqueTasks.map((tk) => (
              <option key={tk} value={tk}>{tk}</option>
            ))}
          </select>

          {/* Mode (Before/After) */}
          <select
            value={filterMode}
            onChange={(e) => setFilterMode(e.target.value)}
            className="rounded-lg border border-stone-200 bg-slate-50 px-2.5 py-1.5 text-sm text-slate-700 focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30"
          >
            <option value="">{t("photos.allModes")}</option>
            <option value="before">{t("photos.before")}</option>
            <option value="after">{t("photos.after")}</option>
            <option value="standard">{t("photos.standard")}</option>
          </select>

          {/* Verified filter */}
          <select
            value={filterVerified}
            onChange={(e) => setFilterVerified(e.target.value as "all" | "verified" | "unverified")}
            className="rounded-lg border border-stone-200 bg-slate-50 px-2.5 py-1.5 text-sm text-slate-700 focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30"
          >
            <option value="all">All verification</option>
            <option value="verified">Verified only</option>
            <option value="unverified">Unverified only</option>
          </select>

          {/* Checkpoint toggle */}
          <label className="flex items-center gap-1.5 text-sm text-slate-600 cursor-pointer select-none">
            <input
              type="checkbox"
              checked={filterCheckpoint}
              onChange={(e) => setFilterCheckpoint(e.target.checked)}
              className="h-4 w-4 rounded border-stone-300 text-blue-500 focus:ring-blue-400"
            />
            Checkpoints only
          </label>

          {/* Select All + Bulk Download */}
          <div className="ml-auto flex items-center gap-3">
            <label className="flex items-center gap-1.5 text-sm text-slate-600 cursor-pointer select-none">
              <input
                type="checkbox"
                checked={filteredPhotos.length > 0 && selectedPhotos.size === filteredPhotos.length}
                onChange={toggleSelectAll}
                className="h-4 w-4 rounded border-stone-300 text-amber-500 focus:ring-ring"
              />
              {t("photos.selectAll")}
            </label>
            {selectedPhotos.size > 0 && (
              <>
                <button
                  onClick={downloadSelected}
                  className="rounded-lg bg-amber-500 px-3 py-1.5 text-sm font-semibold text-white hover:bg-amber-600 transition-colors"
                >
                  {t("photos.downloadSelected")} ({selectedPhotos.size})
                </button>
                <button
                  onClick={exportProofPack}
                  disabled={exporting}
                  className="rounded-lg bg-emerald-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-emerald-700 transition-colors disabled:bg-stone-100 disabled:text-slate-400"
                >
                  {exporting ? "Exporting..." : `Export Proof Pack (${selectedPhotos.size})`}
                </button>
                <button
                  onClick={() => setShowTagDialog(true)}
                  disabled={selectedMediaAssetIds.length === 0}
                  className="rounded-lg bg-slate-700 px-3 py-1.5 text-sm font-semibold text-white hover:bg-slate-800 transition-colors disabled:bg-stone-100 disabled:text-slate-400"
                >
                  Tag ({selectedMediaAssetIds.length})
                </button>
                {jobId && (
                  <button
                    onClick={() => setShowGalleryDialog(true)}
                    disabled={selectedMediaAssetIds.length === 0}
                    className="rounded-lg bg-indigo-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-indigo-700 transition-colors disabled:bg-stone-100 disabled:text-slate-400"
                  >
                    Save as gallery ({selectedMediaAssetIds.length})
                  </button>
                )}
              </>
            )}
            {jobId && (
              <>
                <button
                  onClick={() => setShowShareDialog(true)}
                  className="rounded-lg border border-slate-300 bg-card px-3 py-1.5 text-sm font-semibold text-slate-700 hover:bg-slate-50 transition-colors"
                >
                  Share link
                </button>
                <button
                  onClick={() =>
                    router.push(`/galleries?job_id=${encodeURIComponent(jobId)}`)
                  }
                  className="rounded-lg border border-slate-300 bg-card px-3 py-1.5 text-sm font-semibold text-slate-700 hover:bg-slate-50 transition-colors"
                >
                  Manage deliverables
                </button>
              </>
            )}
          </div>
        </div>
      )}

      {jobId && accessToken && (
        <TagFilterBar
          jobId={jobId}
          active={activeTagFilter}
          accessToken={accessToken}
          onToggle={(tag) =>
            setActiveTagFilter((prev) =>
              prev.includes(tag) ? prev.filter((t) => t !== tag) : [...prev, tag],
            )
          }
          onTagsLoaded={(rows) => {
            const map: Record<string, string[]> = {};
            for (const row of rows) {
              map[row.tag.toLowerCase()] = row.media_asset_ids ?? [];
            }
            setTagPhotoMap(map);
          }}
        />
      )}

      {error && jobId && (
        <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          {error}
          <button
            onClick={loadPhotos}
            className="ml-3 font-semibold underline"
          >
            {t("common.retry")}
          </button>
        </div>
      )}

      {loading && jobId && (
        <SkeletonPhotoGrid count={6} />
      )}

      {!loading && !error && jobId && photos.length === 0 && (
        <div className="rounded-xl border border-stone-200 bg-card p-8 text-center text-slate-500">
          {t("photos.noPhotos")}
        </div>
      )}

      {!loading && !error && jobId && activeTab === "timeline" && (
        <PhotoTimelinePanel
          photos={photos.map((photo) => {
            const asset = photo.displayAsset ?? photo.media_assets;
            const meta = asset?.metadata as Record<string, unknown> | undefined;
            return {
              id: photo.id,
              occurredAt: photo.occurred_at,
              workerName: (photo.users as { full_name: string } | null)?.full_name ?? t("photos.unknownWorker"),
              taskName: (photo.tasks as { name: string } | null)?.name ?? null,
              mode: ((meta?.mode as string) ?? "standard").toLowerCase(),
              isCheckpoint: photo.is_checkpoint,
              verificationCode: asset?.verification_code ?? null,
            };
          })}
        />
      )}

      {!loading && !error && jobId && activeTab === "map" && (
        <PhotoMapPanel
          photos={photos.map((photo) => ({
            id: photo.id,
            occurredAt: photo.occurred_at,
            workerName: (photo.users as { full_name: string } | null)?.full_name ?? t("photos.unknownWorker"),
            gpsLat: photo.gps_lat,
            gpsLng: photo.gps_lng,
            imageUrl: signedUrls[photo.id],
          }))}
        />
      )}

      {/* Sheet view */}
      {jobId && activeTab === "feed" && feedViewMode === "sheet" && filteredPhotos.length > 0 && (
        <div className="mb-6 overflow-x-auto rounded-2xl border border-stone-200 bg-card">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-stone-100 bg-stone-50">
                <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">Photo</th>
                <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">Worker</th>
                <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">Task</th>
                <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">Time</th>
                <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">Type</th>
                <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">Status</th>
                <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">Code</th>
              </tr>
            </thead>
            <tbody>
              {filteredPhotos.map((photo, index) => {
                const worker = (photo.users as { full_name: string } | null)?.full_name ?? t("photos.unknownWorker");
                const task = (photo.tasks as { name: string } | null)?.name ?? null;
                const asset = photo.displayAsset ?? photo.media_assets;
                const code = asset?.verification_code ?? photo.media_assets?.verification_code;
                const hash = asset?.sha256_hash ?? photo.media_assets?.sha256_hash;
                const isVerified = !!(code || hash);
                const meta = asset?.metadata as Record<string, unknown> | undefined;
                const mode = ((meta?.mode as string) ?? "standard").toLowerCase();
                const url = signedUrls[photo.id];
                return (
                  <tr
                    key={photo.id}
                    onClick={() => openLightbox(index)}
                    className="cursor-pointer border-b border-stone-50 hover:bg-stone-50 transition-colors"
                  >
                    <td className="px-4 py-2">
                      {url ? (
                        <img src={url} alt="" className="h-12 w-16 rounded-lg object-cover" />
                      ) : (
                        <div className="flex h-12 w-16 items-center justify-center rounded-lg bg-stone-100 text-xl">📸</div>
                      )}
                    </td>
                    <td className="px-4 py-2 font-medium text-slate-800">{worker}</td>
                    <td className="px-4 py-2 text-slate-500">{task ?? <span className="text-stone-300">—</span>}</td>
                    <td className="px-4 py-2 text-slate-500 whitespace-nowrap">{formatTime(photo.occurred_at)}</td>
                    <td className="px-4 py-2">
                      <span className={`rounded-full px-2 py-0.5 text-xs font-bold uppercase ${
                        mode === "before" ? "bg-violet-100 text-violet-700" :
                        mode === "after" ? "bg-rose-100 text-rose-700" :
                        "bg-stone-100 text-slate-500"
                      }`}>{mode}</span>
                    </td>
                    <td className="px-4 py-2">
                      {isVerified ? (
                        <span className="inline-flex items-center gap-1 rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-semibold text-emerald-700 dark:bg-emerald-950/40 dark:text-emerald-300">
                          <svg className="h-3 w-3" fill="currentColor" viewBox="0 0 20 20" aria-hidden="true"><path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" /></svg>
                          Verified
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1 rounded-full bg-amber-100 px-2 py-0.5 text-xs font-semibold text-amber-700 dark:bg-amber-950/40 dark:text-amber-300">
                          <svg className="h-3 w-3" fill="currentColor" viewBox="0 0 20 20" aria-hidden="true"><path fillRule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clipRule="evenodd" /></svg>
                          Pending
                        </span>
                      )}
                    </td>
                    <td className="px-4 py-2">
                      {code ? (
                        <code className="rounded bg-slate-100 px-1.5 py-0.5 text-xs font-mono text-slate-600">{code as string}</code>
                      ) : <span className="text-stone-300">—</span>}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {/* Masonry photo grid */}
      {jobId && activeTab === "feed" && feedViewMode === "gallery" && <div className="columns-1 sm:columns-2 lg:columns-3 gap-4">
        {filteredPhotos.map((photo, index) => {
          const workerName =
            (photo.users as { full_name: string } | null)?.full_name ??
            t("photos.unknownWorker");
          const taskName =
            (photo.tasks as { name: string } | null)?.name ?? null;
          const originalAsset = photo.media_assets as PhotoEntry["media_assets"];
          const asset = photo.displayAsset ?? originalAsset;
          const verificationCode = asset?.verification_code ?? originalAsset?.verification_code;
          const sha256 = asset?.sha256_hash ?? originalAsset?.sha256_hash;
          const isVerified = !!(verificationCode || sha256);
          const meta = asset?.metadata as Record<string, unknown> | undefined;
          const photoMode = ((meta?.mode as string) ?? "").toLowerCase();
          const stampData =
            ((asset?.metadata as Record<string, Record<string, unknown>>)?.proof_stamp) ??
            ((originalAsset?.metadata as Record<string, Record<string, unknown>>)?.proof_stamp);
          const stampLines = (stampData?.lines as string[]) ?? [];

          return (
            <div
              key={photo.id}
              className={`break-inside-avoid mb-4 overflow-hidden rounded-2xl border shadow-sm transition-shadow hover:shadow-md ${
                isVerified
                  ? "border-emerald-200 bg-card"
                  : "border-stone-200 bg-card"
              }`}
            >
              {/* Photo with stamp overlay */}
              <div
                className="relative bg-slate-100 cursor-pointer"
                onClick={() => openLightbox(index)}
              >
                {/* Bulk select checkbox */}
                <div
                  className="absolute left-2 top-2 z-10"
                  onClick={(e) => e.stopPropagation()}
                >
                  <input
                    type="checkbox"
                    checked={selectedPhotos.has(photo.id)}
                    onChange={() => togglePhotoSelection(photo.id)}
                    className="h-4 w-4 rounded border-stone-300 text-amber-500 focus:ring-ring cursor-pointer"
                  />
                </div>

                {signedUrls[photo.id] ? (
                  <img
                    src={signedUrls[photo.id]}
                    alt={`${t("photos.captured")}: ${workerName}`}
                    className="w-full object-cover"
                    loading="lazy"
                  />
                ) : (
                  <div className="flex h-48 items-center justify-center text-4xl">
                    📸
                  </div>
                )}
                {/* Stamp overlay */}
                {stampLines.length > 0 && (
                  <div className="absolute bottom-2 left-2 right-2 rounded-lg bg-black/65 px-3 py-2 text-xs leading-relaxed text-white">
                    {stampLines.map((line, i) => (
                      <div
                        key={i}
                        className={i === 0 ? "font-bold text-xs" : ""}
                      >
                        {line}
                      </div>
                    ))}
                  </div>
                )}

                {/* Top-right badges */}
                <div className="absolute right-2 top-2 flex flex-col items-end gap-1">
                  {(photo.is_checkpoint as boolean) && (
                    <span className="rounded-full bg-amber-500 px-2 py-0.5 text-xs font-bold text-white">
                      {t("photos.checkpoint")}
                    </span>
                  )}
                  {photoMode === "before" && (
                    <span className="rounded-full bg-violet-500 px-2 py-0.5 text-xs font-bold text-white">
                      BEFORE
                    </span>
                  )}
                  {photoMode === "after" && (
                    <span className="rounded-full bg-rose-500 px-2 py-0.5 text-xs font-bold text-white">
                      AFTER
                    </span>
                  )}
                </div>
              </div>

              {/* Photo info */}
              <div className="p-4">
                <div className="flex items-center justify-between">
                  <span className="font-semibold text-slate-900">
                    {workerName}
                  </span>
                  <span className="text-xs text-slate-500">
                    {formatTime(photo.occurred_at)}
                  </span>
                </div>
                {taskName && (
                  <p className="mt-1 text-sm text-slate-500">
                    {t("photos.task", { taskName })}
                  </p>
                )}
                <div className="mt-2 flex items-center gap-2 flex-wrap">
                  {isVerified ? (
                    <span className="inline-flex items-center gap-1 rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-semibold text-emerald-700 dark:bg-emerald-950/40 dark:text-emerald-300">
                      <svg className="h-3 w-3" fill="currentColor" viewBox="0 0 20 20" aria-hidden="true"><path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" /></svg>
                      Verified
                    </span>
                  ) : (
                    <span className="inline-flex items-center gap-1 rounded-full bg-amber-100 px-2 py-0.5 text-xs font-semibold text-amber-700 dark:bg-amber-950/40 dark:text-amber-300">
                      <svg className="h-3 w-3" fill="currentColor" viewBox="0 0 20 20" aria-hidden="true"><path fillRule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clipRule="evenodd" /></svg>
                      Pending
                    </span>
                  )}
                  {verificationCode && (
                    <code className="rounded bg-slate-100 px-2 py-0.5 text-xs font-mono text-slate-600">
                      {verificationCode as string}
                    </code>
                  )}
                </div>
                {/* Review actions (FUX-013c) */}
                {currentCompanyId && (
                  <div className="mt-3 border-t border-stone-100 pt-3 dark:border-slate-800">
                    <PhotoReviewActions
                      photoEventId={photo.id}
                      photoOccurredAt={photo.occurred_at}
                      companyId={currentCompanyId}
                      compact
                    />
                  </div>
                )}
              </div>
            </div>
          );
        })}
      </div>}

      {/* Load More */}
      {jobId && activeTab === "feed" && hasMorePhotos && (
        <div className="mt-6 flex justify-center">
          <button
            onClick={loadMorePhotos}
            disabled={loadingMorePhotos}
            className="mx-auto flex items-center gap-2 rounded-xl border border-stone-200 bg-card px-6 py-2.5 text-sm font-semibold text-slate-600 shadow-sm hover:bg-stone-50 disabled:bg-stone-100 disabled:text-slate-400"
          >
            {loadingMorePhotos ? t("common.loadingMore") : t("common.loadMore")}
          </button>
        </div>
      )}

      {/* Lightbox modal */}
      {jobId && activeTab === "feed" && lightboxPhoto && selectedPhotoIndex !== null && (() => {
        const lbWorker =
          (lightboxPhoto.users as { full_name: string } | null)?.full_name ??
          t("photos.unknownWorker");
        const lbTask =
          (lightboxPhoto.tasks as { name: string } | null)?.name ?? null;
        const lbOriginalAsset = lightboxPhoto.media_assets as PhotoEntry["media_assets"];
        const lbAsset = lightboxPhoto.displayAsset ?? lbOriginalAsset;
        const lbVerificationCode = lbAsset?.verification_code ?? lbOriginalAsset?.verification_code;
        const lbSha256 = lbAsset?.sha256_hash ?? lbOriginalAsset?.sha256_hash;
        const lbIsVerified = !!(lbVerificationCode || lbSha256);
        const lbMeta = lbAsset?.metadata as Record<string, unknown> | undefined;
        const lbMode = ((lbMeta?.mode as string) ?? "").toLowerCase();
        const lbStampData =
          ((lbAsset?.metadata as Record<string, Record<string, unknown>>)?.proof_stamp) ??
          ((lbOriginalAsset?.metadata as Record<string, Record<string, unknown>>)?.proof_stamp);
        const lbStampLines = (lbStampData?.lines as string[]) ?? [];

        return (
          <div
            className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4"
            onClick={closeLightbox}
          >
            <div
              className="relative max-h-[90vh] w-full max-w-5xl overflow-y-auto rounded-2xl bg-card shadow-2xl"
              onClick={(e) => e.stopPropagation()}
            >
              {/* Header */}
              <div className="flex items-center justify-between border-b border-stone-200 px-6 py-4">
                <div className="flex items-center gap-3">
                  <h3 className="text-lg font-bold text-slate-900">
                    {t("photos.enlarged")}
                  </h3>
                  {lbIsVerified ? (
                    <span className="inline-flex items-center gap-1 rounded-full bg-emerald-100 px-2.5 py-1 text-xs font-semibold text-emerald-700">
                      <svg className="h-3.5 w-3.5" fill="currentColor" viewBox="0 0 20 20"><path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" /></svg>
                      Verified
                    </span>
                  ) : (
                    <span className="inline-flex items-center gap-1 rounded-full bg-amber-100 px-2.5 py-1 text-xs font-semibold text-amber-700">
                      Pending Verification
                    </span>
                  )}
                  {lbMode === "before" && (
                    <span className="rounded-full bg-violet-100 px-2.5 py-1 text-xs font-semibold text-violet-700">Before</span>
                  )}
                  {lbMode === "after" && (
                    <span className="rounded-full bg-rose-100 px-2.5 py-1 text-xs font-semibold text-rose-700">After</span>
                  )}
                </div>
                <button
                  onClick={closeLightbox}
                  className="rounded-lg p-1 text-slate-500 hover:bg-slate-100 hover:text-slate-700"
                  aria-label={t("photos.close")}
                >
                  <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>

              {/* Image */}
              <div className="relative bg-slate-100">
                {/* Prev/Next arrows */}
                {selectedPhotoIndex > 0 && (
                  <button
                    onClick={goToPrevPhoto}
                    className="absolute left-2 top-1/2 z-10 -translate-y-1/2 rounded-full bg-black/50 p-2 text-white hover:bg-black/70"
                    aria-label={t("photos.previous")}
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
                    </svg>
                  </button>
                )}
                {selectedPhotoIndex < filteredPhotos.length - 1 && (
                  <button
                    onClick={goToNextPhoto}
                    className="absolute right-2 top-1/2 z-10 -translate-y-1/2 rounded-full bg-black/50 p-2 text-white hover:bg-black/70"
                    aria-label={t("photos.next")}
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
                    </svg>
                  </button>
                )}

                {signedUrls[lightboxPhoto.id] ? (
                  <img
                    src={signedUrls[lightboxPhoto.id]}
                    alt={`${t("photos.captured")}: ${lbWorker}`}
                    className="w-full object-contain max-h-[60vh]"
                  />
                ) : (
                  <div className="flex h-64 items-center justify-center text-5xl">
                    📸
                  </div>
                )}
              </div>

              {/* Metadata + comments (two-pane on lg) */}
              <div className="grid lg:grid-cols-2">
              <div className="space-y-3 p-6">
                <div className="flex items-center justify-between">
                  <span className="text-lg font-semibold text-slate-900">{lbWorker}</span>
                  <span className="text-sm text-slate-500">{formatTime(lightboxPhoto.occurred_at)}</span>
                </div>
                {lbTask && (
                  <p className="text-sm text-slate-600">
                    {t("photos.task", { taskName: lbTask })}
                  </p>
                )}
                {lbVerificationCode && (
                  <div className="flex items-center gap-2">
                    <code className="rounded bg-slate-100 px-2 py-1 text-sm font-mono text-slate-700">
                      {lbVerificationCode as string}
                    </code>
                    <button
                      onClick={() => copyVerificationCode(lbVerificationCode as string)}
                      className="rounded-lg border border-stone-200 px-3 py-1 text-sm font-medium text-slate-600 hover:bg-slate-50 transition-colors"
                    >
                      {codeCopied ? t("photos.codeCopied") : t("photos.copyCode")}
                    </button>
                  </div>
                )}
                {/* SHA-256 integrity hash — tamper-proof evidence */}
                {lbSha256 && (
                  <div className="rounded-lg border border-emerald-200 bg-emerald-50 px-4 py-3">
                    <p className="text-xs font-semibold uppercase tracking-wider text-emerald-700 mb-1">Integrity Hash (SHA-256)</p>
                    <code className="block text-xs font-mono text-emerald-800 break-all">{lbSha256}</code>
                  </div>
                )}
                {lbStampLines.length > 0 && (
                  <div className="rounded-lg bg-slate-50 px-4 py-3 text-xs leading-relaxed text-slate-600">
                    {lbStampLines.map((line, i) => (
                      <div key={i} className={i === 0 ? "font-bold text-sm text-slate-800" : ""}>
                        {line}
                      </div>
                    ))}
                  </div>
                )}
                {lightboxPhoto.is_checkpoint && (
                  <span className="inline-block rounded-full bg-amber-500 px-3 py-1 text-xs font-bold text-white">
                    {t("photos.checkpoint")}
                  </span>
                )}
                {/* Photo counter */}
                <p className="text-xs text-slate-500 text-center pt-2">
                  {selectedPhotoIndex + 1} of {filteredPhotos.length}
                </p>
              </div>

              {/* Comments sidebar */}
              {lightboxPhoto.media_asset_id && (
                <div className="flex h-[50vh] flex-col border-t border-stone-200 p-4 dark:border-slate-700 lg:h-[60vh] lg:border-l lg:border-t-0">
                  <PhotoCommentsPanel
                    mediaAssetId={lightboxPhoto.media_asset_id}
                    companyId={currentCompanyId ?? ""}
                    accessToken={accessToken}
                  />
                </div>
              )}
              </div>
            </div>
          </div>
        );
      })()}

      {/* Sprint 8.5 — sharing dialogs */}
      <BulkTagDialog
        open={showTagDialog}
        mediaAssetIds={selectedMediaAssetIds}
        accessToken={accessToken}
        onClose={() => setShowTagDialog(false)}
        onTagged={() => {
          // Clear selection after a successful bulk tag so the bar resets.
          setSelectedPhotos(new Set());
        }}
      />
      {jobId && (
        <SaveAsGalleryDialog
          open={showGalleryDialog}
          jobId={jobId}
          mediaAssetIds={selectedMediaAssetIds}
          accessToken={accessToken}
          onClose={() => setShowGalleryDialog(false)}
        />
      )}
      {jobId && (
        <ShareLinkDialog
          open={showShareDialog}
          jobId={jobId}
          accessToken={accessToken}
          onClose={() => setShowShareDialog(false)}
        />
      )}
    </div>
  );
}
