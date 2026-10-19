"use client";

export function ProjectWorkspaceTabs({
  activeTab,
  onChange,
}: {
  activeTab: "feed" | "timeline" | "map";
  onChange: (tab: "feed" | "timeline" | "map") => void;
}) {
  const tabs: Array<{ value: "feed" | "timeline" | "map"; label: string }> = [
    { value: "feed", label: "Feed" },
    { value: "timeline", label: "Timeline" },
    { value: "map", label: "Map" },
  ];

  return (
    <div className="inline-flex rounded-2xl border border-stone-200 bg-card p-1 shadow-sm">
      {tabs.map((tab) => (
        <button
          key={tab.value}
          onClick={() => onChange(tab.value)}
          className={`rounded-xl px-4 py-2 text-sm font-semibold transition ${
            activeTab === tab.value
              ? "bg-slate-900 text-white"
              : "text-slate-500 hover:bg-stone-100 hover:text-slate-800"
          }`}
        >
          {tab.label}
        </button>
      ))}
    </div>
  );
}
