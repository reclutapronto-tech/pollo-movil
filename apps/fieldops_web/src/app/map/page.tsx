"use client";

/* eslint-disable @typescript-eslint/no-explicit-any */

import { useCallback, useEffect, useRef, useState, useMemo } from "react";
import { useI18n } from "@/lib/i18n";
import { getSupabase } from "@/lib/supabase";

function getInitials(name: string): string {
  return name
    .split(" ")
    .map((w) => w[0])
    .join("")
    .toUpperCase()
    .slice(0, 2);
}

const MAPTILER_KEY =
  process.env.NEXT_PUBLIC_MAPTILER_KEY || "3EVTjBsPJIuw0UVfaNvL";

interface WorkerPin {
  user_id: string;
  full_name: string;
  gps_lat: number;
  gps_lng: number;
  event_subtype: string;
  occurred_at: string;
  job_name: string;
}

interface JobSite {
  id: string;
  name: string;
  code: string;
  site_lat: number;
  site_lng: number;
  geofence_radius_m: number;
}

export default function MapPage() {
  const { t } = useI18n();
  const mapContainer = useRef<HTMLDivElement>(null);
  const mapRef = useRef<any>(null);
  const markersRef = useRef<any[]>([]);
  const [workers, setWorkers] = useState<WorkerPin[]>([]);
  const [jobSites, setJobSites] = useState<JobSite[]>([]);
  const [loading, setLoading] = useState(true);
  const [mapReady, setMapReady] = useState(false);
  const [mapError, setMapError] = useState<string | null>(null);

  // Sidebar + filter state
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [filterClockedIn, setFilterClockedIn] = useState(false);
  const [filterJobSitesOnly, setFilterJobSitesOnly] = useState(false);
  const loadData = useCallback(async () => {
    try {
      const supabase = getSupabase();

      const { data: clockEvents } = await supabase
        .from("clock_events")
        .select(
          "user_id, gps_lat, gps_lng, event_subtype, occurred_at, users!clock_events_user_id_fkey(full_name), jobs!clock_events_job_id_fkey(name)",
        )
        .order("occurred_at", { ascending: false })
        .limit(100);

      const latestByWorker = new Map<string, WorkerPin>();
      for (const ce of clockEvents ?? []) {
        if (ce.gps_lat && ce.gps_lng && !latestByWorker.has(ce.user_id as string)) {
          latestByWorker.set(ce.user_id as string, {
            user_id: ce.user_id as string,
            full_name: (ce.users as any)?.full_name ?? t("mapPage.unknownWorker"),
            gps_lat: ce.gps_lat as number,
            gps_lng: ce.gps_lng as number,
            event_subtype: ce.event_subtype as string,
            occurred_at: ce.occurred_at as string,
            job_name: (ce.jobs as any)?.name ?? t("mapPage.unknownJob"),
          });
        }
      }
      setWorkers(Array.from(latestByWorker.values()));

      const { data: jobs } = await supabase
        .from("jobs")
        .select("id, name, code, site_lat, site_lng, geofence_radius_m")
        .in("status", ["active", "in_progress"])
        .not("site_lat", "is", null)
        .not("site_lng", "is", null);
      setJobSites((jobs as JobSite[]) ?? []);
    } catch {
      // Data load error — non-fatal, map still shows
    } finally {
      setLoading(false);
    }
  }, [t]);

  // Load MapTiler SDK (MapLibre-based, free)
  useEffect(() => {
    const script = document.createElement("script");
    script.src = "https://cdn.maptiler.com/maptiler-sdk-js/v2.3.0/maptiler-sdk.umd.min.js";
    script.onerror = () => {
      setMapError(t("mapPage.failedToLoadLibrary"));
      setLoading(false);
    };
    script.onload = () => {
      const link = document.createElement("link");
      link.rel = "stylesheet";
      link.href = "https://cdn.maptiler.com/maptiler-sdk-js/v2.3.0/maptiler-sdk.css";
      document.head.appendChild(link);
      setMapReady(true);
    };
    document.head.appendChild(script);
  }, [t]);

  // Init map with error handling
  useEffect(() => {
    if (!mapReady || !mapContainer.current || mapRef.current) return;

    try {
      const maptiler = (window as any).maptilersdk;
      if (!maptiler) {
        setMapError(t("mapPage.sdkUnavailable"));
        return;
      }

      maptiler.config.apiKey = MAPTILER_KEY;

      const map = new maptiler.Map({
        container: mapContainer.current,
        style: maptiler.MapStyle.STREETS,
        center: [-71.0589, 42.3601],
        zoom: 11,
      });

      map.on("error", (e: any) => {
        console.error("Map error:", e);
      });

      mapRef.current = map;
      loadData();
    } catch (e) {
      setMapError(`Map initialization failed: ${e instanceof Error ? e.message : "unknown error"}`);
    }

    return () => {
      if (mapRef.current) {
        mapRef.current.remove();
        mapRef.current = null;
      }
    };
  }, [mapReady, loadData, t]);

  // Filtered data for rendering (declared before marker useEffect that depends on them)
  const filteredWorkers = useMemo(() => {
    if (filterJobSitesOnly) return [];
    if (filterClockedIn) return workers.filter((w) => w.event_subtype === "clock_in");
    return workers;
  }, [workers, filterClockedIn, filterJobSitesOnly]);

  const filteredJobSites = useMemo(() => {
    return jobSites;
  }, [jobSites]);

  // Update markers (filter-aware + richer popups)
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !mapReady || mapError) return;

    try {
      const mt = (window as any).maptilersdk;

      for (const m of markersRef.current) m.remove();
      markersRef.current = [];

      // Count workers per job site for popup
      const workersPerSite = new Map<string, number>();
      for (const w of workers) {
        if (w.event_subtype === "clock_in") {
          workersPerSite.set(w.job_name, (workersPerSite.get(w.job_name) || 0) + 1);
        }
      }

      for (const site of filteredJobSites) {
        const el = document.createElement("div");
        el.style.cssText = "width:32px;height:32px;background:#F38B2A;border-radius:50%;border:3px solid white;box-shadow:0 2px 8px rgba(0,0,0,0.2);cursor:pointer;display:flex;align-items:center;justify-content:center;color:white;font-size:14px;font-weight:700;";
        el.textContent = "\u{1F4CD}";
        el.title = `${site.name} (${site.code})`;

        const siteWorkerCount = workersPerSite.get(site.name) || 0;
        const popupHtml = `<div style="font-family:system-ui;padding:8px;min-width:180px">
          <div style="font-weight:700;font-size:14px;margin-bottom:4px">${site.name}</div>
          <div style="color:#64748B;font-size:12px;margin-bottom:6px">${site.code} &middot; ${site.geofence_radius_m}m geofence</div>
          <div style="font-size:12px;color:#334155">${siteWorkerCount} ${t("mapPage.workers")}</div>
          <a href="/photos?job_id=${encodeURIComponent(site.id)}" style="display:inline-block;margin-top:6px;font-size:12px;color:#2563EB;text-decoration:none;font-weight:600">${t("mapPage.viewPhotos")} &rarr;</a>
        </div>`;

        const marker = new mt.Marker({ element: el })
          .setLngLat([site.site_lng, site.site_lat])
          .setPopup(new mt.Popup({ offset: 20 }).setHTML(popupHtml))
          .addTo(map);
        markersRef.current.push(marker);
      }

      for (const w of filteredWorkers) {
        const isClockedIn = w.event_subtype === "clock_in";
        const color = isClockedIn ? "#16A34A" : "#94A3B8";
        const initials = getInitials(w.full_name);

        const el = document.createElement("div");
        el.style.cssText = `width:28px;height:28px;background:${color};border-radius:50%;border:3px solid white;box-shadow:0 2px 8px rgba(0,0,0,0.25);cursor:pointer;display:flex;align-items:center;justify-content:center;color:white;font-size:10px;font-weight:700;`;
        el.textContent = initials;
        el.title = `${w.full_name} — ${isClockedIn ? t("mapPage.clockedInTitle") : t("mapPage.clockedOutTitle")}`;

        const popupHtml = `<div style="font-family:system-ui;padding:8px;min-width:200px">
          <div style="display:flex;align-items:center;gap:8px;margin-bottom:6px">
            <div style="width:32px;height:32px;border-radius:50%;background:${color};display:flex;align-items:center;justify-content:center;color:white;font-size:12px;font-weight:700;flex-shrink:0">${initials}</div>
            <div>
              <div style="font-weight:700;font-size:14px">${w.full_name}</div>
              <div style="color:${color};font-size:12px;font-weight:600">${isClockedIn ? `&#9679; ${t("mapPage.clockedInTitle")}` : `&#9675; ${t("mapPage.clockedOutTitle")}`}</div>
            </div>
          </div>
          <div style="font-size:12px;color:#334155;margin-bottom:2px">${w.job_name}</div>
          <div style="font-size:11px;color:#64748B">${new Date(w.occurred_at).toLocaleTimeString()}</div>
          <a href="/timeline?worker=${encodeURIComponent(w.user_id)}" style="display:inline-block;margin-top:6px;font-size:12px;color:#2563EB;text-decoration:none;font-weight:600">${t("mapPage.viewTimeline")} &rarr;</a>
        </div>`;

        const marker = new mt.Marker({ element: el })
          .setLngLat([w.gps_lng, w.gps_lat])
          .setPopup(new mt.Popup({ offset: 16 }).setHTML(popupHtml))
          .addTo(map);
        markersRef.current.push(marker);
      }

      const allCoords = [
        ...filteredWorkers.map((w) => [w.gps_lng, w.gps_lat]),
        ...filteredJobSites.map((s) => [s.site_lng, s.site_lat]),
      ];
      if (allCoords.length > 1) {
        const bounds = new mt.LngLatBounds();
        for (const c of allCoords) bounds.extend(c);
        map.fitBounds(bounds, { padding: 60 });
      } else if (allCoords.length === 1) {
        map.setCenter(allCoords[0]);
        map.setZoom(14);
      }
    } catch {
      // Marker error — non-fatal
    }
  }, [filteredWorkers, filteredJobSites, workers, mapReady, mapError, t]);

  useEffect(() => {
    const supabase = getSupabase();
    const channel = supabase
      .channel(`map-live-${Math.random().toString(36).slice(2)}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "clock_events",
        },
        () => loadData()
      )
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "jobs",
        },
        () => loadData()
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [loadData]);

  const clockedIn = workers.filter((w) => w.event_subtype === "clock_in").length;

  // Helper to pan/zoom to a worker pin
  const panToWorker = useCallback((w: WorkerPin) => {
    const map = mapRef.current;
    if (!map) return;
    map.flyTo({ center: [w.gps_lng, w.gps_lat], zoom: 16 });
  }, []);

  // Group sidebar workers by status
  const clockedInWorkers = workers.filter((w) => w.event_subtype === "clock_in");
  const clockedOutWorkers = workers.filter((w) => w.event_subtype !== "clock_in");

  return (
    <div>
      {/* Header */}
      <div className="mb-4 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900 dark:text-slate-100">{t("mapPage.title")}</h1>
          <p className="mt-0.5 text-sm text-slate-500 dark:text-slate-400">{t("mapPage.subtitle")}</p>
        </div>
        <div className="flex gap-4 text-xs">
          <div className="flex items-center gap-1.5">
            <span className="inline-block h-2.5 w-2.5 rounded-full bg-green-500" />
            <span className="text-slate-500 dark:text-slate-400">{t("mapPage.in", { count: clockedIn })}</span>
          </div>
          <div className="flex items-center gap-1.5">
            <span className="inline-block h-2.5 w-2.5 rounded-full bg-slate-400" />
            <span className="text-slate-500 dark:text-slate-400">{t("mapPage.out", { count: workers.length - clockedIn })}</span>
          </div>
          <div className="flex items-center gap-1.5">
            <span className="inline-block h-2.5 w-2.5 rounded-full bg-amber-500" />
            <span className="text-slate-500 dark:text-slate-400">{t("mapPage.sites", { count: jobSites.length })}</span>
          </div>
        </div>
      </div>

      {/* Filter toggles */}
      <div className="mb-3 flex flex-wrap items-center gap-2">
        <button
          onClick={() => setFilterClockedIn((v) => !v)}
          className={`rounded-full border px-3 py-1 text-xs font-medium transition-colors ${
            filterClockedIn
              ? "border-green-300 bg-green-50 text-green-700"
              : "border-stone-200 bg-card text-slate-500 dark:text-slate-400 hover:bg-stone-50 dark:bg-slate-950 dark:hover:bg-slate-900"
          }`}
        >
          <span className="mr-1 inline-block h-1.5 w-1.5 rounded-full bg-green-500" />
          {t("mapPage.clockedInOnly")}
        </button>
        <button
          onClick={() => setFilterJobSitesOnly((v) => !v)}
          className={`rounded-full border px-3 py-1 text-xs font-medium transition-colors ${
            filterJobSitesOnly
              ? "border-amber-300 bg-amber-50 text-amber-700"
              : "border-stone-200 bg-card text-slate-500 dark:text-slate-400 hover:bg-stone-50 dark:bg-slate-950 dark:hover:bg-slate-900"
          }`}
        >
          <span className="mr-1 inline-block h-1.5 w-1.5 rounded-full bg-amber-500" />
          {t("mapPage.jobSitesOnly")}
        </button>
        <button
          disabled
          className="cursor-not-allowed rounded-full border border-stone-200 bg-card px-3 py-1 text-xs font-medium text-slate-500"
          title="Coming soon"
        >
          {t("mapPage.showBreadcrumbs")}
        </button>
      </div>

      {/* Map error fallback */}
      {mapError && (
        <div className="rounded-2xl border border-red-100 bg-red-50 p-8 text-center">
          <div className="text-3xl text-red-300">{"\uD83D\uDDFA\uFE0F"}</div>
          <h3 className="mt-3 font-bold text-red-800">{t("mapPage.mapUnavailable")}</h3>
          <p className="mt-1 text-sm text-red-600">{mapError}</p>
          <p className="mt-3 text-xs text-red-400">
            {t("mapPage.getFreeKeyAt")}{" "}
            <a
              href="https://cloud.maptiler.com/account/keys/"
              target="_blank"
              rel="noopener noreferrer"
              className="underline"
            >
              cloud.maptiler.com
            </a>{" "}
            {t("mapPage.addItToEnv")}{" "}
            <code className="rounded bg-red-100 px-1 py-0.5">
              .env.local
            </code>{" "}
            {t("mapPage.asEnvKey")} <code className="rounded bg-red-100 px-1 py-0.5">NEXT_PUBLIC_MAPTILER_KEY</code>
          </p>

          {/* Fallback: show worker data as table */}
          {workers.length > 0 && (
            <div className="mx-auto mt-6 max-w-lg text-left">
              <p className="mb-2 text-xs font-semibold text-slate-500 dark:text-slate-400">
                {t("mapPage.workerPositions")}
              </p>
              <div className="overflow-hidden rounded-xl border border-stone-200 bg-card dark:border-slate-800 dark:bg-slate-900">
                <table className="w-full text-xs">
                  <thead>
                    <tr className="border-b bg-stone-50 dark:bg-slate-950 text-left text-slate-500 dark:text-slate-400">
                      <th className="px-3 py-2">{t("mapPage.worker")}</th>
                      <th className="px-3 py-2">{t("mapPage.status")}</th>
                      <th className="px-3 py-2">{t("mapPage.job")}</th>
                      <th className="px-3 py-2">{t("mapPage.gps")}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {workers.map((w) => (
                      <tr key={w.user_id} className="border-b border-stone-50">
                        <td className="px-3 py-2 font-medium text-slate-900 dark:text-slate-100">
                          {w.full_name}
                        </td>
                        <td className="px-3 py-2">
                          <span
                            className={
                              w.event_subtype === "clock_in"
                                ? "text-green-600"
                                : "text-slate-500 dark:text-slate-400"
                            }
                          >
                            {w.event_subtype === "clock_in"
                              ? `● ${t("mapPage.clockedInTitle")}`
                              : `○ ${t("mapPage.clockedOutTitle")}`}
                          </span>
                        </td>
                        <td className="px-3 py-2 text-slate-500 dark:text-slate-400">{w.job_name}</td>
                        <td className="px-3 py-2 font-mono text-slate-500 dark:text-slate-400">
                          {w.gps_lat.toFixed(4)}, {w.gps_lng.toFixed(4)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </div>
      )}

      {loading && !mapError && (
        <div className="flex h-96 items-center justify-center text-slate-500 dark:text-slate-400">
          <div className="h-5 w-5 animate-spin rounded-full border-2 border-stone-200 border-t-slate-900" />
          <span className="ml-3 text-sm">{t("mapPage.loadingMap")}</span>
        </div>
      )}

      {/* Map + Right sidebar layout */}
      {!mapError && (
        <div className="flex gap-0 overflow-hidden rounded-2xl border border-stone-200 shadow-sm">
          {/* Map container */}
          <div className="relative flex-1">
            <div
              ref={mapContainer}
              className="h-[600px] w-full"
              style={{ minHeight: "500px" }}
            />
          </div>

          {/* Right sidebar toggle button */}
          <button
            onClick={() => setSidebarOpen((v) => !v)}
            className="flex w-6 items-center justify-center border-l border-stone-200 bg-stone-50 text-slate-500 transition-colors hover:bg-stone-100 hover:text-slate-700 dark:border-slate-800 dark:bg-slate-950 dark:text-slate-400 dark:hover:bg-slate-900 dark:hover:text-slate-200"
            aria-label={sidebarOpen ? "Collapse sidebar" : "Expand sidebar"}
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              className={`h-4 w-4 transition-transform ${sidebarOpen ? "rotate-0" : "rotate-180"}`}
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              strokeWidth={2}
            >
              <path strokeLinecap="round" strokeLinejoin="round" d="M9 5l7 7-7 7" />
            </svg>
          </button>

          {/* Right sidebar panel — Who's Working */}
          {sidebarOpen && (
            <div className="flex w-72 flex-col border-l border-stone-200 bg-card">
              <div className="border-b border-stone-100 px-4 py-3">
                <h2 className="text-sm font-bold text-slate-900 dark:text-slate-100">
                  {t("mapPage.whosWorking")}
                </h2>
                <p className="text-xs text-slate-500 dark:text-slate-400">
                  {clockedIn} {t("mapPage.clockedInTitle").toLowerCase()}
                </p>
              </div>
              <div className="flex-1 overflow-y-auto">
                {/* Clocked-in group */}
                {clockedInWorkers.length > 0 && (
                  <div>
                    <div className="sticky top-0 bg-green-50 px-4 py-1.5 text-xs font-semibold text-green-700">
                      {t("mapPage.clockedInTitle")} ({clockedInWorkers.length})
                    </div>
                    {clockedInWorkers.map((w) => (
                      <button
                        key={w.user_id}
                        onClick={() => panToWorker(w)}
                        className="flex w-full items-center gap-3 border-b border-stone-50 px-4 py-2.5 text-left transition-colors hover:bg-stone-50 dark:bg-slate-950 dark:hover:bg-slate-900"
                      >
                        <div className="flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-full bg-green-500 text-xs font-bold text-white">
                          {getInitials(w.full_name)}
                        </div>
                        <div className="min-w-0 flex-1">
                          <div className="truncate text-xs font-semibold text-slate-900 dark:text-slate-100">
                            {w.full_name}
                          </div>
                          <div className="truncate text-xs text-slate-500 dark:text-slate-400">
                            {w.job_name}
                          </div>
                        </div>
                        <div className="text-xs text-slate-500">
                          {new Date(w.occurred_at).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
                        </div>
                      </button>
                    ))}
                  </div>
                )}
                {/* Clocked-out group */}
                {clockedOutWorkers.length > 0 && (
                  <div>
                    <div className="sticky top-0 bg-slate-50 px-4 py-1.5 text-xs font-semibold text-slate-500 dark:text-slate-400">
                      {t("mapPage.clockedOutTitle")} ({clockedOutWorkers.length})
                    </div>
                    {clockedOutWorkers.map((w) => (
                      <button
                        key={w.user_id}
                        onClick={() => panToWorker(w)}
                        className="flex w-full items-center gap-3 border-b border-stone-50 px-4 py-2.5 text-left transition-colors hover:bg-stone-50 dark:bg-slate-950 dark:hover:bg-slate-900"
                      >
                        <div className="flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-full bg-slate-300 text-xs font-bold text-white">
                          {getInitials(w.full_name)}
                        </div>
                        <div className="min-w-0 flex-1">
                          <div className="truncate text-xs font-semibold text-slate-500 dark:text-slate-400">
                            {w.full_name}
                          </div>
                          <div className="truncate text-xs text-slate-500">
                            {w.job_name}
                          </div>
                        </div>
                        <div className="text-xs text-slate-500">
                          {new Date(w.occurred_at).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
                        </div>
                      </button>
                    ))}
                  </div>
                )}
                {workers.length === 0 && !loading && (
                  <div className="px-4 py-8 text-center text-xs text-slate-500">
                    {t("common.noData")}
                  </div>
                )}
              </div>
            </div>
          )}
        </div>
      )}

      {/* Refresh indicator */}
      <div className="mt-2 text-center text-xs text-slate-500 dark:text-slate-400">
        {t("mapPage.refreshEvery")}
      </div>
    </div>
  );
}
