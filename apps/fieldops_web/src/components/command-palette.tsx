"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { createPortal } from "react-dom";
import { useRouter } from "next/navigation";
import {
  Search,
  Navigation,
  Briefcase,
  User as UserIcon,
  Camera,
  type LucideIcon,
} from "lucide-react";
import { useI18n } from "@/lib/i18n";
import { getSupabase } from "@/lib/supabase";
import { useCurrentUser } from "@/lib/use-role";
import { isManagementRole } from "@/lib/roles";
import { NAV_ITEMS } from "@/lib/nav-items";

type ResultGroup = "pages" | "workers" | "jobs" | "photos";

interface CommandResult {
  id: string;
  group: ResultGroup;
  label: string;
  sublabel?: string;
  href: string;
  Icon: LucideIcon;
}

const GROUP_ORDER: ResultGroup[] = ["pages", "workers", "jobs", "photos"];

const GROUP_LABEL_KEY: Record<ResultGroup, string> = {
  pages: "commandPalette.pages",
  workers: "commandPalette.workers",
  jobs: "commandPalette.jobs",
  photos: "commandPalette.recentPhotos",
};

const DEBOUNCE_MS = 150;

export function CommandPalette() {
  const router = useRouter();
  const { t } = useI18n();
  const { role, companyId } = useCurrentUser();
  const canManageCompany = isManagementRole(role);

  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [remoteResults, setRemoteResults] = useState<CommandResult[]>([]);
  const [remoteLoading, setRemoteLoading] = useState(false);
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [mounted, setMounted] = useState(false);

  const inputRef = useRef<HTMLInputElement>(null);
  const debounceTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Mount flag for createPortal (avoid SSR window access).
  useEffect(() => setMounted(true), []);

  // Open/close on Cmd+K / Ctrl+K; close on ESC.
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      const isPaletteShortcut =
        (e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k";
      if (isPaletteShortcut) {
        e.preventDefault();
        setOpen((prev) => !prev);
      } else if (e.key === "Escape" && open) {
        setOpen(false);
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open]);

  // Focus input + reset selection on open.
  useEffect(() => {
    if (open) {
      setSelectedIndex(0);
      setTimeout(() => inputRef.current?.focus(), 0);
    } else {
      setQuery("");
      setRemoteResults([]);
    }
  }, [open]);

  // Page results: local filter on NAV_ITEMS (cheap, no network).
  const pageResults = useMemo<CommandResult[]>(() => {
    const q = query.trim().toLowerCase();
    const items = NAV_ITEMS.filter(
      (item) => !item.adminOnly || canManageCompany,
    );
    return items
      .filter((item) => {
        if (!q) return true;
        const label = t(item.labelKey).toLowerCase();
        return label.includes(q) || item.href.includes(q);
      })
      .slice(0, q ? 6 : 8)
      .map((item) => ({
        id: `page:${item.href}`,
        group: "pages" as const,
        label: t(item.labelKey),
        sublabel: item.href,
        href: item.href,
        Icon: item.icon,
      }));
  }, [query, canManageCompany, t]);

  // Remote results: workers + jobs + recent photos (debounced).
  useEffect(() => {
    if (!open || !companyId) {
      setRemoteResults([]);
      return;
    }
    const q = query.trim();
    if (debounceTimerRef.current) clearTimeout(debounceTimerRef.current);

    debounceTimerRef.current = setTimeout(async () => {
      setRemoteLoading(true);
      try {
        const supabase = getSupabase();

        // When query is empty, still show recent photos (helpful landing state).
        const searchTerm = q ? `%${q}%` : null;

        const workersPromise = searchTerm
          ? supabase
              .from("users")
              .select("id, full_name, role")
              .eq("company_id", companyId)
              .ilike("full_name", searchTerm)
              .order("full_name", { ascending: true })
              .limit(6)
          : Promise.resolve({ data: [], error: null });

        const jobsPromise = searchTerm
          ? supabase
              .from("jobs")
              .select("id, name, code")
              .eq("company_id", companyId)
              .is("deleted_at", null)
              .or(`name.ilike.${searchTerm},code.ilike.${searchTerm}`)
              .order("created_at", { ascending: false })
              .limit(6)
          : Promise.resolve({ data: [], error: null });

        const photosPromise = supabase
          .from("photo_events")
          .select("id, occurred_at, job_id, jobs!inner(name)")
          .eq("company_id", companyId)
          .order("occurred_at", { ascending: false })
          .limit(q ? 3 : 5);

        const [workersRes, jobsRes, photosRes] = await Promise.all([
          workersPromise,
          jobsPromise,
          photosPromise,
        ]);

        const merged: CommandResult[] = [];

        for (const w of workersRes.data ?? []) {
          merged.push({
            id: `worker:${w.id}`,
            group: "workers",
            label: (w as { full_name: string }).full_name ?? "—",
            sublabel: (w as { role: string | null }).role ?? "",
            href: `/workers?user=${(w as { id: string }).id}`,
            Icon: UserIcon,
          });
        }

        for (const j of jobsRes.data ?? []) {
          const job = j as { id: string; name: string; code: string | null };
          merged.push({
            id: `job:${job.id}`,
            group: "jobs",
            label: job.name,
            sublabel: job.code ?? undefined,
            href: `/timeline?job=${job.id}`,
            Icon: Briefcase,
          });
        }

        for (const p of photosRes.data ?? []) {
          const photo = p as unknown as {
            id: string;
            occurred_at: string;
            job_id: string;
            jobs: { name: string } | { name: string }[] | null;
          };
          const jobName = Array.isArray(photo.jobs)
            ? photo.jobs[0]?.name
            : photo.jobs?.name;
          const when = new Date(photo.occurred_at).toLocaleString(undefined, {
            month: "short",
            day: "numeric",
            hour: "2-digit",
            minute: "2-digit",
          });
          merged.push({
            id: `photo:${photo.id}`,
            group: "photos",
            label: jobName ?? "Unknown job",
            sublabel: when,
            href: `/photos?job_id=${photo.job_id}`,
            Icon: Camera,
          });
        }

        setRemoteResults(merged);
      } catch {
        setRemoteResults([]);
      } finally {
        setRemoteLoading(false);
      }
    }, DEBOUNCE_MS);

    return () => {
      if (debounceTimerRef.current) clearTimeout(debounceTimerRef.current);
    };
  }, [query, open, companyId]);

  const allResults = useMemo(() => {
    const combined = [...pageResults, ...remoteResults];
    // Keep GROUP_ORDER: pages first, then workers, jobs, photos.
    combined.sort(
      (a, b) => GROUP_ORDER.indexOf(a.group) - GROUP_ORDER.indexOf(b.group),
    );
    return combined;
  }, [pageResults, remoteResults]);

  // Group for rendering.
  const grouped = useMemo(() => {
    const map = new Map<ResultGroup, CommandResult[]>();
    for (const r of allResults) {
      if (!map.has(r.group)) map.set(r.group, []);
      map.get(r.group)!.push(r);
    }
    return Array.from(map.entries());
  }, [allResults]);

  // Clamp selected index when results change.
  useEffect(() => {
    if (selectedIndex >= allResults.length) {
      setSelectedIndex(Math.max(0, allResults.length - 1));
    }
  }, [allResults.length, selectedIndex]);

  const pickResult = useCallback(
    (r: CommandResult | undefined) => {
      if (!r) return;
      setOpen(false);
      router.push(r.href);
    },
    [router],
  );

  const onInputKey = useCallback(
    (e: React.KeyboardEvent<HTMLInputElement>) => {
      if (e.key === "ArrowDown") {
        e.preventDefault();
        setSelectedIndex((i) => Math.min(allResults.length - 1, i + 1));
      } else if (e.key === "ArrowUp") {
        e.preventDefault();
        setSelectedIndex((i) => Math.max(0, i - 1));
      } else if (e.key === "Enter") {
        e.preventDefault();
        pickResult(allResults[selectedIndex]);
      }
    },
    [allResults, selectedIndex, pickResult],
  );

  if (!mounted || !open) return null;

  const content = (
    <div
      className="fixed inset-0 z-[60] flex items-start justify-center bg-black/40 px-4 pt-[12vh] backdrop-blur-sm"
      onClick={() => setOpen(false)}
      role="dialog"
      aria-modal="true"
      aria-label={t("commandPalette.title")}
    >
      <div
        className="w-full max-w-xl overflow-hidden rounded-2xl border border-stone-200 bg-card shadow-2xl dark:border-slate-800 dark:bg-slate-900"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Input */}
        <div className="flex items-center gap-2 border-b border-stone-100 px-4 py-3 dark:border-slate-800">
          <Search size={16} className="text-slate-400" />
          <input
            ref={inputRef}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={onInputKey}
            placeholder={t("commandPalette.placeholder")}
            className="flex-1 bg-transparent text-sm text-slate-800 placeholder:text-slate-500 focus:outline-none dark:text-slate-100"
          />
          <kbd className="hidden rounded border border-stone-200 px-1.5 py-0.5 text-xs font-medium text-slate-500 sm:inline-block dark:border-slate-700 dark:text-slate-400">
            ESC
          </kbd>
        </div>

        {/* Results */}
        <div className="max-h-[60vh] overflow-y-auto py-1">
          {allResults.length === 0 && !remoteLoading && (
            <div className="px-4 py-8 text-center text-sm text-slate-500 dark:text-slate-400">
              {t("commandPalette.noResults")}
            </div>
          )}

          {grouped.map(([group, items]) => (
            <div key={group} className="py-1">
              <div className="px-4 pt-2 pb-1 text-xs font-semibold uppercase tracking-widest text-slate-500 dark:text-slate-400">
                {t(GROUP_LABEL_KEY[group])}
              </div>
              {items.map((r) => {
                const globalIdx = allResults.findIndex((x) => x.id === r.id);
                const isSel = globalIdx === selectedIndex;
                const Icon = r.Icon;
                return (
                  <button
                    key={r.id}
                    onMouseEnter={() => setSelectedIndex(globalIdx)}
                    onClick={() => pickResult(r)}
                    className={`flex w-full items-center gap-3 px-4 py-2 text-left text-sm ${
                      isSel
                        ? "bg-stone-100 text-slate-900 dark:bg-slate-800 dark:text-slate-100"
                        : "text-slate-700 dark:text-slate-400"
                    }`}
                  >
                    <Icon size={14} className="shrink-0 text-slate-400" />
                    <span className="flex-1 truncate">{r.label}</span>
                    {r.sublabel && (
                      <span className="truncate text-xs text-slate-500 dark:text-slate-400">
                        {r.sublabel}
                      </span>
                    )}
                    {isSel && (
                      <Navigation size={12} className="text-slate-400" />
                    )}
                  </button>
                );
              })}
            </div>
          ))}
        </div>

        {/* Footer hint */}
        <div className="flex items-center justify-between gap-3 border-t border-stone-100 bg-stone-50 px-4 py-2 text-xs text-slate-500 dark:border-slate-800 dark:bg-slate-950 dark:text-slate-400">
          <span className="flex items-center gap-3">
            <span>
              <kbd className="mr-1 rounded bg-card px-1 py-0.5 font-medium dark:bg-slate-800">
                ↑↓
              </kbd>
              {t("commandPalette.navigate")}
            </span>
            <span>
              <kbd className="mr-1 rounded bg-card px-1 py-0.5 font-medium dark:bg-slate-800">
                ↵
              </kbd>
              {t("commandPalette.open")}
            </span>
          </span>
          <span>
            <kbd className="mr-1 rounded bg-card px-1 py-0.5 font-medium dark:bg-slate-800">
              ?
            </kbd>
            {t("commandPalette.allShortcuts")}
          </span>
        </div>
      </div>
    </div>
  );

  return createPortal(content, document.body);
}
