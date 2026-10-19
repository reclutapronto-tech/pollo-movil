"use client";

type TimelinePhoto = {
  id: string;
  occurredAt: string;
  workerName: string;
  taskName: string | null;
  mode: string;
  isCheckpoint: boolean;
  verificationCode: string | null;
};

export function PhotoTimelinePanel({ photos }: { photos: TimelinePhoto[] }) {
  const groups = photos.reduce<Record<string, TimelinePhoto[]>>((acc, photo) => {
    const dateKey = new Date(photo.occurredAt).toLocaleDateString(undefined, {
      weekday: "short",
      month: "short",
      day: "numeric",
      year: "numeric",
    });
    acc[dateKey] ??= [];
    acc[dateKey].push(photo);
    return acc;
  }, {});

  const groupEntries = Object.entries(groups);

  if (groupEntries.length === 0) {
    return (
      <div className="rounded-[28px] border border-dashed border-stone-300 bg-card p-12 text-center text-sm text-slate-500">
        No photo events yet for this project.
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {groupEntries.map(([dateLabel, items]) => (
        <section key={dateLabel} className="rounded-[28px] border border-stone-200 bg-card p-5 shadow-sm">
          <div className="mb-4 flex items-center justify-between gap-4">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">Timeline</p>
              <h3 className="mt-1 text-lg font-semibold text-slate-900">{dateLabel}</h3>
            </div>
            <span className="rounded-full bg-stone-100 px-3 py-1 text-xs font-semibold text-slate-600">
              {items.length} photos
            </span>
          </div>

          <div className="space-y-3">
            {items.map((photo) => (
              <div key={photo.id} className="flex gap-4 rounded-2xl border border-stone-100 bg-stone-50/70 p-4">
                <div className="mt-1 flex h-9 w-9 items-center justify-center rounded-full bg-amber-100 text-base">
                  📸
                </div>
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="font-semibold text-slate-900">{photo.workerName}</span>
                    <span className="text-sm text-slate-500">
                      {new Date(photo.occurredAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
                    </span>
                    {photo.isCheckpoint && (
                      <span className="rounded-full bg-amber-100 px-2 py-0.5 text-xs font-semibold text-amber-700">
                        Checkpoint
                      </span>
                    )}
                    {photo.mode !== "standard" && (
                      <span className="rounded-full bg-slate-900 px-2 py-0.5 text-xs font-semibold uppercase text-white">
                        {photo.mode}
                      </span>
                    )}
                  </div>
                  <div className="mt-1 text-sm text-slate-600">
                    {photo.taskName ? `Task: ${photo.taskName}` : "General photo"}
                  </div>
                  <div className="mt-2 text-xs text-slate-500">
                    {photo.verificationCode ? `Verification: ${photo.verificationCode}` : "Verification pending"}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </section>
      ))}
    </div>
  );
}
