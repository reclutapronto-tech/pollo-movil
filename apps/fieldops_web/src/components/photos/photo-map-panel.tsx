"use client";

/* eslint-disable @typescript-eslint/no-explicit-any */

import { useEffect, useRef, useState } from "react";

type MapPhoto = {
  id: string;
  occurredAt: string;
  workerName: string;
  gpsLat: number | null;
  gpsLng: number | null;
  imageUrl?: string;
};

const MAPTILER_KEY = process.env.NEXT_PUBLIC_MAPTILER_KEY || "3EVTjBsPJIuw0UVfaNvL";

export function PhotoMapPanel({ photos }: { photos: MapPhoto[] }) {
  const mapContainer = useRef<HTMLDivElement>(null);
  const mapRef = useRef<any>(null);
  const markersRef = useRef<any[]>([]);
  const [mapReady, setMapReady] = useState(false);
  const [mapError, setMapError] = useState<string | null>(null);

  const photoPins = photos.filter(
    (photo) => typeof photo.gpsLat === "number" && typeof photo.gpsLng === "number",
  );

  useEffect(() => {
    if ((window as any).maptilersdk) {
      setMapReady(true);
      return;
    }

    const script = document.createElement("script");
    script.src = "https://cdn.maptiler.com/maptiler-sdk-js/v2.3.0/maptiler-sdk.umd.min.js";
    script.onload = () => {
      const link = document.createElement("link");
      link.rel = "stylesheet";
      link.href = "https://cdn.maptiler.com/maptiler-sdk-js/v2.3.0/maptiler-sdk.css";
      document.head.appendChild(link);
      setMapReady(true);
    };
    script.onerror = () => setMapError("Could not load the map library.");
    document.head.appendChild(script);

    return () => {
      script.remove();
    };
  }, []);

  useEffect(() => {
    if (!mapReady || !mapContainer.current || mapRef.current || photoPins.length === 0) return;

    const maptiler = (window as any).maptilersdk;
    if (!maptiler) {
      setMapError("Map SDK unavailable.");
      return;
    }

    maptiler.config.apiKey = MAPTILER_KEY;
    const map = new maptiler.Map({
      container: mapContainer.current,
      style: maptiler.MapStyle.STREETS,
      center: [photoPins[0].gpsLng, photoPins[0].gpsLat],
      zoom: 13,
    });
    mapRef.current = map;

    return () => {
      if (mapRef.current) {
        mapRef.current.remove();
        mapRef.current = null;
      }
    };
  }, [mapReady, photoPins]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;

    const maptiler = (window as any).maptilersdk;
    for (const marker of markersRef.current) marker.remove();
    markersRef.current = [];

    const bounds = new maptiler.LngLatBounds();
    for (const photo of photoPins) {
      const markerElement = document.createElement("div");
      markerElement.style.cssText =
        "width:18px;height:18px;border-radius:999px;background:#f59e0b;border:3px solid white;box-shadow:0 2px 8px rgba(0,0,0,0.2);";

      const popup = new maptiler.Popup({ offset: 16 }).setHTML(`
        <div style="min-width:180px;font-family:system-ui">
          <div style="font-weight:700;font-size:13px;margin-bottom:4px">${photo.workerName}</div>
          <div style="font-size:12px;color:#475569">${new Date(photo.occurredAt).toLocaleString()}</div>
          <div style="font-size:11px;color:#64748b;margin-top:4px">${photo.gpsLat?.toFixed(5)}, ${photo.gpsLng?.toFixed(5)}</div>
        </div>
      `);

      const marker = new maptiler.Marker({ element: markerElement })
        .setLngLat([photo.gpsLng as number, photo.gpsLat as number])
        .setPopup(popup)
        .addTo(map);

      markersRef.current.push(marker);
      bounds.extend([photo.gpsLng as number, photo.gpsLat as number]);
    }

    if (photoPins.length > 1) {
      map.fitBounds(bounds, { padding: 60 });
    }
  }, [photoPins]);

  if (photoPins.length === 0) {
    return (
      <div className="rounded-[28px] border border-dashed border-stone-300 bg-card p-12 text-center text-sm text-slate-500">
        No geo-tagged photos are available for this project yet.
      </div>
    );
  }

  return (
    <section className="overflow-hidden rounded-[28px] border border-stone-200 bg-card shadow-sm">
      <div className="border-b border-stone-100 px-5 py-4">
        <p className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">Map View</p>
        <h3 className="mt-1 text-lg font-semibold text-slate-900">Photos by capture location</h3>
      </div>
      {mapError ? (
        <div className="p-8 text-sm text-red-700">{mapError}</div>
      ) : (
        <div ref={mapContainer} className="h-[480px] w-full bg-stone-100" />
      )}
    </section>
  );
}
