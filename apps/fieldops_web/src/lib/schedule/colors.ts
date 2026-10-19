// Deterministic color palette for project bars. Soft backgrounds for legibility.
const PALETTE = [
  { bg: "bg-amber-100", border: "border-amber-400", text: "text-amber-900", dot: "bg-amber-500" },
  { bg: "bg-sky-100", border: "border-sky-400", text: "text-sky-900", dot: "bg-sky-500" },
  { bg: "bg-emerald-100", border: "border-emerald-400", text: "text-emerald-900", dot: "bg-emerald-500" },
  { bg: "bg-fuchsia-100", border: "border-fuchsia-400", text: "text-fuchsia-900", dot: "bg-fuchsia-500" },
  { bg: "bg-indigo-100", border: "border-indigo-400", text: "text-indigo-900", dot: "bg-indigo-500" },
  { bg: "bg-rose-100", border: "border-rose-400", text: "text-rose-900", dot: "bg-rose-500" },
  { bg: "bg-teal-100", border: "border-teal-400", text: "text-teal-900", dot: "bg-teal-500" },
  { bg: "bg-orange-100", border: "border-orange-400", text: "text-orange-900", dot: "bg-orange-500" },
];

export type ProjectColor = (typeof PALETTE)[number];

function hash(s: string) {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
  return Math.abs(h);
}

export function projectColor(jobId: string): ProjectColor {
  return PALETTE[hash(jobId) % PALETTE.length];
}
