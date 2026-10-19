"use client";

interface ProjectBrowserProject {
  id: string;
  name: string;
  code: string;
  status?: string;
  photoCount?: number;
  lastPhotoAt?: string | null;
}

export function ProjectBrowser({
  projects,
  search,
  onSearchChange,
  viewMode,
  onViewModeChange,
  onOpenProject,
}: {
  projects: ProjectBrowserProject[];
  search: string;
  onSearchChange: (value: string) => void;
  viewMode: "icons" | "list";
  onViewModeChange: (value: "icons" | "list") => void;
  onOpenProject: (projectId: string) => void;
}) {
  const normalizedSearch = search.trim().toLowerCase();
  const filteredProjects = projects.filter((project) => {
    if (!normalizedSearch) return true;
    return (
      project.name.toLowerCase().includes(normalizedSearch) ||
      project.code.toLowerCase().includes(normalizedSearch)
    );
  });

  return (
    <section className="space-y-5">
      <div className="rounded-[28px] border border-stone-200 bg-[linear-gradient(135deg,rgba(255,251,235,0.92),rgba(255,255,255,0.98))] p-5 shadow-sm">
        <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.24em] text-amber-700/70">
              Project Library
            </p>
            <h3 className="mt-1 text-2xl font-semibold tracking-tight text-slate-900">
              Browse photo folders by project
            </h3>
            <p className="mt-1 max-w-2xl text-sm text-slate-600">
              Open a project to review proof photos in feed, timeline, or map form without leaving the page.
            </p>
          </div>

          <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
            <input
              value={search}
              onChange={(event) => onSearchChange(event.target.value)}
              placeholder="Search projects"
              className="min-w-[220px] rounded-2xl border border-stone-300 bg-card px-4 py-2.5 text-sm text-slate-700 shadow-sm focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30"
            />
            <div className="flex rounded-2xl border border-stone-200 bg-card p-1 shadow-sm">
              <button
                onClick={() => onViewModeChange("icons")}
                className={`rounded-xl px-3 py-2 text-sm font-semibold transition ${
                  viewMode === "icons" ? "bg-slate-900 text-white" : "text-slate-500 hover:text-slate-700"
                }`}
              >
                Icons
              </button>
              <button
                onClick={() => onViewModeChange("list")}
                className={`rounded-xl px-3 py-2 text-sm font-semibold transition ${
                  viewMode === "list" ? "bg-slate-900 text-white" : "text-slate-500 hover:text-slate-700"
                }`}
              >
                List
              </button>
            </div>
          </div>
        </div>
      </div>

      {filteredProjects.length === 0 ? (
        <div className="rounded-[28px] border border-dashed border-stone-300 bg-card p-12 text-center text-sm text-slate-500">
          No matching projects yet.
        </div>
      ) : viewMode === "icons" ? (
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {filteredProjects.map((project) => (
            <button
              key={project.id}
              onClick={() => onOpenProject(project.id)}
              className="group rounded-[28px] border border-stone-200 bg-card p-5 text-left shadow-sm transition hover:-translate-y-0.5 hover:border-amber-300 hover:shadow-md"
            >
              <div className="flex items-start justify-between gap-4">
                <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-amber-100 text-3xl shadow-inner shadow-amber-200/60">
                  📁
                </div>
                <span className="rounded-full bg-stone-100 px-3 py-1 text-xs font-semibold uppercase tracking-wide text-slate-500">
                  {project.status ?? "active"}
                </span>
              </div>

              <div className="mt-5">
                <h4 className="text-lg font-semibold text-slate-900 transition group-hover:text-amber-700">
                  {project.name}
                </h4>
                <p className="mt-1 text-sm text-slate-500">{project.code}</p>
              </div>

              <div className="mt-5 flex items-end justify-between gap-4">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">
                    Photos
                  </p>
                  <p className="mt-1 text-2xl font-semibold text-slate-900">
                    {project.photoCount ?? 0}
                  </p>
                </div>
                <div className="text-right">
                  <p className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">
                    Last Activity
                  </p>
                  <p className="mt-1 text-sm text-slate-600">
                    {project.lastPhotoAt ? new Date(project.lastPhotoAt).toLocaleDateString() : "No photos"}
                  </p>
                </div>
              </div>
            </button>
          ))}
        </div>
      ) : (
        <div className="overflow-hidden rounded-[28px] border border-stone-200 bg-card shadow-sm">
          {filteredProjects.map((project) => (
            <button
              key={project.id}
              onClick={() => onOpenProject(project.id)}
              className="flex w-full items-center gap-4 border-b border-stone-100 px-5 py-4 text-left transition hover:bg-amber-50/50 last:border-b-0"
            >
              <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-amber-100 text-2xl">
                📁
              </div>
              <div className="min-w-0 flex-1">
                <div className="truncate text-base font-semibold text-slate-900">{project.name}</div>
                <div className="truncate text-sm text-slate-500">{project.code}</div>
              </div>
              <div className="hidden text-right sm:block">
                <div className="text-xs font-semibold uppercase tracking-[0.16em] text-slate-500">Photos</div>
                <div className="text-sm font-semibold text-slate-700">{project.photoCount ?? 0}</div>
              </div>
              <div className="hidden text-right lg:block">
                <div className="text-xs font-semibold uppercase tracking-[0.16em] text-slate-500">Last Activity</div>
                <div className="text-sm text-slate-600">
                  {project.lastPhotoAt ? new Date(project.lastPhotoAt).toLocaleDateString() : "No photos"}
                </div>
              </div>
              <span className="rounded-full bg-stone-100 px-3 py-1 text-xs font-semibold uppercase tracking-wide text-slate-500">
                {project.status ?? "active"}
              </span>
            </button>
          ))}
        </div>
      )}
    </section>
  );
}
