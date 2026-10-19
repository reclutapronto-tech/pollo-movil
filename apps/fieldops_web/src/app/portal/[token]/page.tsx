"use client";

import { useCallback, useEffect, useState } from "react";
import { useParams } from "next/navigation";
import { CheckCircle, Circle, XCircle, Camera, Clock, MapPin } from "lucide-react";

interface PortalJob {
  id: string;
  name: string;
  code: string;
  status: string;
  address: string | null;
  start_date: string | null;
  end_date: string | null;
}

interface PortalCompany {
  name: string;
  logo: string | null;
}

interface PortalPhoto {
  id: string;
  storage_url: string;
  stamp_metadata: Record<string, unknown> | null;
  created_at: string;
  asset_type: string;
}

interface PortalTask {
  id: string;
  name: string;
  status: string;
  requires_photo: boolean;
  sort_order: number;
}

export default function ClientPortalPage() {
  const { token } = useParams<{ token: string }>();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [job, setJob] = useState<PortalJob | null>(null);
  const [company, setCompany] = useState<PortalCompany | null>(null);
  const [photos, setPhotos] = useState<PortalPhoto[]>([]);
  const [tasks, setTasks] = useState<PortalTask[]>([]);
  const [label, setLabel] = useState<string | null>(null);
  const [selectedPhoto, setSelectedPhoto] = useState<PortalPhoto | null>(null);

  const fetchPortalData = useCallback(async () => {
    try {
      const res = await fetch(
        `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/client_portal?token=${token}`,
        { headers: { apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || "" } }
      );
      const data = await res.json();
      if (!res.ok) {
        setError(data.message || "This link is invalid or has expired.");
        return;
      }
      setJob(data.job);
      setCompany(data.company);
      setPhotos(data.photos || []);
      setTasks(data.tasks || []);
      setLabel(data.label || null);
    } catch {
      setError("Failed to load job details. Please try again.");
    } finally {
      setLoading(false);
    }
  }, [token]);

  useEffect(() => {
    if (!token) return;
    fetchPortalData();
  }, [token, fetchPortalData]);

  function taskIcon(status: string) {
    if (status === "completed") return <CheckCircle size={18} className="text-emerald-500" />;
    if (status === "blocked") return <XCircle size={18} className="text-red-400" />;
    return <Circle size={18} className="text-stone-300" />;
  }

  const completedTasks = tasks.filter((t) => t.status === "completed").length;

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-stone-50">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-amber-500 border-t-transparent" />
      </div>
    );
  }

  if (error || !job) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center bg-stone-50 px-4 text-center">
        <div className="rounded-2xl bg-card p-10 shadow-sm">
          <div className="mb-4 text-4xl">🔒</div>
          <h1 className="text-xl font-bold text-slate-900">Link unavailable</h1>
          <p className="mt-2 text-slate-500">{error || "This link is no longer active."}</p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-stone-50">
      {/* Header */}
      <div className="border-b border-stone-200 bg-card px-6 py-4">
        <div className="mx-auto flex max-w-4xl items-center justify-between">
          <div className="flex items-center gap-3">
            {company?.logo && (
              <img src={company.logo} alt={company.name} className="h-8 w-8 rounded-lg object-cover" />
            )}
            <div>
              <p className="text-xs font-medium text-slate-500">{company?.name}</p>
              <p className="text-sm font-bold text-slate-900">Job Progress Report</p>
            </div>
          </div>
          {label && (
            <span className="rounded-full bg-amber-100 px-3 py-1 text-xs font-medium text-amber-800">
              {label}
            </span>
          )}
        </div>
      </div>

      <div className="mx-auto max-w-4xl space-y-6 px-6 py-8">
        {/* Job summary */}
        <div className="rounded-2xl bg-card p-6 shadow-sm">
          <div className="flex items-start justify-between">
            <div>
              <h1 className="text-2xl font-bold text-slate-900">{job.name}</h1>
              <p className="mt-1 font-mono text-sm text-slate-500">{job.code}</p>
            </div>
            <span className={`rounded-full px-3 py-1 text-xs font-semibold ${
              job.status === "completed" ? "bg-emerald-100 text-emerald-800" :
              job.status === "in_progress" ? "bg-amber-100 text-amber-800" :
              "bg-stone-100 text-stone-800"
            }`}>
              {job.status.replace("_", " ")}
            </span>
          </div>
          <div className="mt-4 flex flex-wrap gap-4 text-sm text-slate-500">
            {job.address && (
              <span className="flex items-center gap-1.5">
                <MapPin size={14} /> {job.address}
              </span>
            )}
            {job.start_date && (
              <span className="flex items-center gap-1.5">
                <Clock size={14} /> Started {new Date(job.start_date).toLocaleDateString()}
              </span>
            )}
          </div>

          {/* Task progress */}
          {tasks.length > 0 && (
            <div className="mt-5">
              <div className="mb-2 flex items-center justify-between text-sm">
                <span className="font-medium text-slate-700">Task progress</span>
                <span className="text-slate-500">{completedTasks}/{tasks.length}</span>
              </div>
              <div className="h-2 w-full overflow-hidden rounded-full bg-stone-100">
                <div
                  className="h-full rounded-full bg-emerald-500 transition-all"
                  style={{ width: `${tasks.length ? (completedTasks / tasks.length) * 100 : 0}%` }}
                />
              </div>
            </div>
          )}
        </div>

        {/* Photos */}
        {photos.length > 0 && (
          <div>
            <div className="mb-3 flex items-center gap-2">
              <Camera size={18} className="text-amber-500" />
              <h2 className="text-lg font-bold text-slate-900">Photo Proof ({photos.length})</h2>
            </div>
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
              {photos.map((photo) => (
                <button
                  key={photo.id}
                  onClick={() => setSelectedPhoto(photo)}
                  className="group relative overflow-hidden rounded-xl bg-stone-200 shadow-sm"
                  style={{ aspectRatio: "4/3" }}
                >
                  <img
                    src={photo.storage_url}
                    alt="Job photo"
                    className="h-full w-full object-cover transition-transform group-hover:scale-105"
                    loading="lazy"
                  />
                  <div className="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/60 to-transparent p-2">
                    <p className="text-xs text-white/80">
                      {new Date(photo.created_at).toLocaleDateString()}
                    </p>
                  </div>
                </button>
              ))}
            </div>
          </div>
        )}

        {/* Tasks */}
        {tasks.length > 0 && (
          <div>
            <h2 className="mb-3 text-lg font-bold text-slate-900">Task Checklist</h2>
            <div className="divide-y divide-stone-100 rounded-2xl bg-card shadow-sm">
              {tasks.map((task) => (
                <div key={task.id} className="flex items-center gap-3 px-5 py-3.5">
                  {taskIcon(task.status)}
                  <span className={`flex-1 text-sm ${task.status === "completed" ? "text-slate-500 line-through" : "text-slate-800"}`}>
                    {task.name}
                  </span>
                  {task.requires_photo && (
                    <Camera size={14} className="text-slate-500" />
                  )}
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Footer */}
        <p className="text-center text-xs text-slate-500">
          Powered by FieldOps AI — tamper-evident field documentation
        </p>
      </div>

      {/* Photo lightbox */}
      {selectedPhoto && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-4"
          onClick={() => setSelectedPhoto(null)}
        >
          <img
            src={selectedPhoto.storage_url}
            alt="Job photo"
            className="max-h-[90vh] max-w-[90vw] rounded-xl object-contain shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          />
        </div>
      )}
    </div>
  );
}
