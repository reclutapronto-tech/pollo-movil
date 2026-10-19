"use client";

import { useCallback, useEffect, useState } from "react";
import { getSupabase } from "@/lib/supabase";

interface Project {
  id: string;
  name: string;
  code: string;
  status: string;
  site_name: string | null;
  geofence_radius_m: number | null;
  geofence_enforced: boolean;
}

interface ProjectForm {
  id: string;
  name: string;
  code: string;
  status: string;
  site_name: string;
  geofence_radius_m: string;
  geofence_enforced: boolean;
}

const STATUS_OPTIONS = [
  { value: "active", label: "Active" },
  { value: "in_progress", label: "In Progress" },
  { value: "completed", label: "Completed" },
  { value: "cancelled", label: "Cancelled" },
];

const STATUS_COLORS: Record<string, string> = {
  active: "bg-green-100 text-green-700",
  in_progress: "bg-blue-100 text-blue-700",
  completed: "bg-stone-100 text-slate-500",
  cancelled: "bg-red-100 text-red-500",
};

function emptyForm(): ProjectForm {
  return {
    id: "",
    name: "",
    code: "",
    status: "active",
    site_name: "",
    geofence_radius_m: "100",
    geofence_enforced: true,
  };
}

export default function ProjectsPage() {
  const [projects, setProjects] = useState<Project[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [form, setForm] = useState<ProjectForm | null>(null);
  const [isNew, setIsNew] = useState(false);
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  const loadProjects = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const supabase = getSupabase();
      const { data, error: err } = await supabase
        .from("jobs")
        .select("id, name, code, status, site_name, geofence_radius_m, geofence_enforced")
        .order("created_at", { ascending: false });
      if (err) throw err;
      setProjects((data as Project[]) ?? []);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to load projects");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadProjects();
  }, [loadProjects]);

  function openCreate() {
    setForm(emptyForm());
    setIsNew(true);
    setSaveError(null);
    setSaved(false);
  }

  function openEdit(project: Project) {
    setForm({
      id: project.id,
      name: project.name,
      code: project.code,
      status: project.status,
      site_name: project.site_name ?? "",
      geofence_radius_m: String(project.geofence_radius_m ?? 100),
      geofence_enforced: project.geofence_enforced ?? true,
    });
    setIsNew(false);
    setSaveError(null);
    setSaved(false);
  }

  function closeForm() {
    setForm(null);
    setSaveError(null);
  }

  async function saveProject() {
    if (!form || !form.name.trim() || !form.code.trim()) return;
    setSaving(true);
    setSaveError(null);
    try {
      const supabase = getSupabase();

      // Resolve company_id from the current user — required by jobs table
      const { data: sessionData } = await supabase.auth.getSession();
      const userId = sessionData.session?.user?.id;
      if (!userId) throw new Error("Not authenticated");

      const { data: userRow } = await supabase
        .from("users")
        .select("company_id")
        .eq("id", userId)
        .maybeSingle();
      if (!userRow?.company_id) throw new Error("No company found for this user. Complete company setup first.");

      const payload = {
        name: form.name.trim(),
        code: form.code.trim().toUpperCase(),
        status: form.status,
        site_name: form.site_name.trim() || null,
        geofence_radius_m: parseInt(form.geofence_radius_m) || 100,
        geofence_enforced: form.geofence_enforced,
        company_id: userRow.company_id,
      };

      if (isNew) {
        const { error: err } = await supabase.from("jobs").insert(payload);
        if (err) throw err;
      } else {
        const { error: err } = await supabase.from("jobs").update(payload).eq("id", form.id);
        if (err) throw err;
      }

      setSaved(true);
      setTimeout(() => {
        setSaved(false);
        setForm(null);
        loadProjects();
      }, 1200);
    } catch (e) {
      setSaveError(e instanceof Error ? e.message : "Failed to save project");
    } finally {
      setSaving(false);
    }
  }

  const activeCount = projects.filter((p) => p.status === "active" || p.status === "in_progress").length;

  return (
    <div>
      {/* Header */}
      <div className="mb-6 flex items-center justify-between">
        <div>
          <a
            href="/"
            className="mb-2 inline-flex items-center gap-1 text-sm font-medium text-slate-500 hover:text-slate-900"
          >
            <span>&larr;</span> Back to Dashboard
          </a>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">Projects</h1>
          <p className="mt-1 text-sm text-slate-500">
            {activeCount} active · {projects.length} total
          </p>
        </div>
        <button
          onClick={openCreate}
          className="rounded-xl bg-amber-500 px-5 py-2.5 text-sm font-semibold text-white hover:bg-amber-600"
        >
          + New Project
        </button>
      </div>

      {error && (
        <div className="mb-4 rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700 dark:border-red-900/50 dark:bg-red-950/30 dark:text-red-300">
          {error}
        </div>
      )}

      <div className="flex gap-6">
        {/* Project list */}
        <div className="flex-1">
          {loading && (
            <div className="flex items-center gap-2 text-sm text-slate-500">
              <div className="h-4 w-4 animate-spin rounded-full border-2 border-stone-200 border-t-slate-900" />
              Loading projects...
            </div>
          )}

          {!loading && projects.length === 0 && (
            <div className="rounded-2xl border-2 border-dashed border-stone-200 bg-card p-12 text-center">
              <div className="text-4xl mb-3">📋</div>
              <p className="text-sm font-medium text-slate-600">No projects yet</p>
              <p className="mt-1 text-xs text-slate-500">Create your first project to start scheduling shifts and tracking field activity.</p>
              <button
                onClick={openCreate}
                className="mt-4 rounded-xl bg-amber-500 px-5 py-2.5 text-sm font-semibold text-white hover:bg-amber-600"
              >
                + Create First Project
              </button>
            </div>
          )}

          <div className="space-y-2">
            {projects.map((project) => {
              const isEditing = form?.id === project.id;
              return (
                <button
                  key={project.id}
                  onClick={() => openEdit(project)}
                  className={`w-full rounded-xl border p-4 text-left transition-all ${
                    isEditing
                      ? "border-amber-400 bg-amber-50 shadow-sm"
                      : "border-stone-200 bg-card hover:border-stone-300 hover:shadow-sm"
                  }`}
                >
                  <div className="flex items-center justify-between">
                    <div>
                      <div className="flex items-center gap-2">
                        <span className="font-semibold text-slate-900">{project.name}</span>
                        <code className="rounded bg-stone-100 px-1.5 py-0.5 text-xs font-mono text-slate-500">
                          {project.code}
                        </code>
                      </div>
                      {project.site_name && (
                        <div className="mt-0.5 text-xs text-slate-500">📍 {project.site_name}</div>
                      )}
                    </div>
                    <span className={`rounded-full px-2.5 py-1 text-xs font-bold uppercase tracking-wide ${STATUS_COLORS[project.status] ?? "bg-stone-100 text-slate-500"}`}>
                      {project.status.replace("_", " ")}
                    </span>
                  </div>
                </button>
              );
            })}
          </div>
        </div>

        {/* Edit / Create panel */}
        {form && (
          <div className="w-96 flex-shrink-0">
            <div className="sticky top-6 rounded-2xl border border-stone-200 bg-card p-6 shadow-sm">
              <div className="mb-5 flex items-center justify-between">
                <h2 className="text-sm font-bold uppercase tracking-wider text-slate-500">
                  {isNew ? "New Project" : "Edit Project"}
                </h2>
                <button onClick={closeForm} className="text-xs text-slate-500 hover:text-slate-600">
                  Close
                </button>
              </div>

              <div className="space-y-4">
                <div>
                  <label className="mb-1 block text-xs font-semibold text-slate-600">
                    Project Name <span className="text-red-400">*</span>
                  </label>
                  <input
                    type="text"
                    value={form.name}
                    onChange={(e) => setForm({ ...form, name: e.target.value })}
                    placeholder="e.g. Grid Restoration — Phase 1"
                    className="w-full rounded-lg border border-stone-200 bg-stone-50 px-3 py-2.5 text-sm focus:border-ring focus:bg-card focus:outline-none"
                  />
                </div>

                <div>
                  <label className="mb-1 block text-xs font-semibold text-slate-600">
                    Project Code <span className="text-red-400">*</span>
                  </label>
                  <input
                    type="text"
                    value={form.code}
                    onChange={(e) => setForm({ ...form, code: e.target.value })}
                    placeholder="e.g. PROJ-001"
                    className="w-full rounded-lg border border-stone-200 bg-stone-50 px-3 py-2.5 text-sm uppercase focus:border-ring focus:bg-card focus:outline-none"
                  />
                </div>

                <div>
                  <label className="mb-1 block text-xs font-semibold text-slate-600">Site Address</label>
                  <input
                    type="text"
                    value={form.site_name}
                    onChange={(e) => setForm({ ...form, site_name: e.target.value })}
                    placeholder="123 Main St, Boston, MA"
                    className="w-full rounded-lg border border-stone-200 bg-stone-50 px-3 py-2.5 text-sm focus:border-ring focus:bg-card focus:outline-none"
                  />
                </div>

                <div>
                  <label className="mb-1 block text-xs font-semibold text-slate-600">Status</label>
                  <select
                    value={form.status}
                    onChange={(e) => setForm({ ...form, status: e.target.value })}
                    className="w-full rounded-lg border border-stone-200 bg-stone-50 px-3 py-2.5 text-sm focus:border-ring focus:bg-card focus:outline-none"
                  >
                    {STATUS_OPTIONS.map((opt) => (
                      <option key={opt.value} value={opt.value}>{opt.label}</option>
                    ))}
                  </select>
                </div>

                <div className="rounded-xl border border-stone-200 bg-stone-50 p-3">
                  <label className="flex cursor-pointer items-start gap-3">
                    <input
                      type="checkbox"
                      checked={form.geofence_enforced}
                      onChange={(e) => setForm({ ...form, geofence_enforced: e.target.checked })}
                      className="mt-0.5 h-4 w-4 rounded border-stone-300 text-amber-500 focus:ring-ring"
                    />
                    <span className="flex-1">
                      <span className="block text-sm font-semibold text-slate-700">
                        Enforce geofence on clock-in
                      </span>
                      <span className="mt-0.5 block text-xs text-slate-500">
                        When off, workers can clock in from anywhere. Leave on for on-site crews;
                        turn off for remote, hybrid, or office-based staff.
                      </span>
                    </span>
                  </label>
                </div>

                <div>
                  <label className="mb-1 block text-xs font-semibold text-slate-600">
                    Geofence Radius (meters)
                  </label>
                  <input
                    type="number"
                    min="10"
                    max="5000"
                    value={form.geofence_radius_m}
                    onChange={(e) => setForm({ ...form, geofence_radius_m: e.target.value })}
                    disabled={!form.geofence_enforced}
                    className="w-full rounded-lg border border-stone-200 bg-stone-50 px-3 py-2.5 text-sm focus:border-ring focus:bg-card focus:outline-none disabled:bg-stone-100 disabled:text-slate-400"
                  />
                  {!form.geofence_enforced && (
                    <p className="mt-1 text-xs text-slate-500">
                      Ignored while geofence enforcement is off.
                    </p>
                  )}
                </div>

                <div className="pt-2">
                  {saveError && (
                    <p className="mb-2 text-center text-sm font-medium text-red-500">{saveError}</p>
                  )}
                  {saved && (
                    <p className="mb-2 text-center text-sm font-medium text-green-600">
                      {isNew ? "Project created!" : "Project saved!"}
                    </p>
                  )}
                  <button
                    onClick={saveProject}
                    disabled={saving || !form.name.trim() || !form.code.trim()}
                    className="w-full rounded-xl bg-slate-900 py-3 text-sm font-semibold text-white transition-colors hover:bg-slate-800 disabled:bg-stone-100 disabled:text-slate-400 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-white"
                  >
                    {saving ? "Saving..." : isNew ? "Create Project" : "Save Changes"}
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
