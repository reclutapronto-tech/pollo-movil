import type { ViewMode } from "./types";

export function asDateKey(value: Date) {
  return value.toISOString().slice(0, 10);
}

export function parseDate(value: string) {
  return new Date(`${value}T12:00:00Z`);
}

export function startOfWeek(value: Date) {
  const copy = new Date(value);
  const day = copy.getUTCDay();
  const offset = day === 0 ? -6 : 1 - day;
  copy.setUTCDate(copy.getUTCDate() + offset);
  return copy;
}

export function startOfMonth(value: Date) {
  return new Date(Date.UTC(value.getUTCFullYear(), value.getUTCMonth(), 1));
}

export function buildVisibleDates(anchorKey: string, viewMode: ViewMode): Date[] {
  const anchor = parseDate(anchorKey);
  if (viewMode === "day") return [anchor];
  if (viewMode === "week") {
    const start = startOfWeek(anchor);
    return Array.from({ length: 7 }, (_, i) => addDays(start, i));
  }
  if (viewMode === "twoWeek") {
    const start = startOfWeek(anchor);
    return Array.from({ length: 14 }, (_, i) => addDays(start, i));
  }
  // Month: project-level heatmap shows full month grid (Sun..Sat rows)
  const monthStart = startOfMonth(anchor);
  const monthEnd = new Date(Date.UTC(anchor.getUTCFullYear(), anchor.getUTCMonth() + 1, 0));
  const calStart = startOfWeek(monthStart);
  const calEnd = startOfWeek(monthEnd);
  calEnd.setUTCDate(calEnd.getUTCDate() + 6);
  const out: Date[] = [];
  const cursor = new Date(calStart);
  while (cursor <= calEnd) {
    out.push(new Date(cursor));
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }
  return out;
}

function addDays(d: Date, n: number) {
  const c = new Date(d);
  c.setUTCDate(c.getUTCDate() + n);
  return c;
}

export function shiftAnchor(anchorKey: string, viewMode: ViewMode, dir: 1 | -1) {
  const a = parseDate(anchorKey);
  if (viewMode === "day") a.setUTCDate(a.getUTCDate() + dir);
  if (viewMode === "week") a.setUTCDate(a.getUTCDate() + 7 * dir);
  if (viewMode === "twoWeek") a.setUTCDate(a.getUTCDate() + 14 * dir);
  if (viewMode === "month") a.setUTCMonth(a.getUTCMonth() + dir);
  return asDateKey(a);
}

export function formatRangeLabel(anchorKey: string, viewMode: ViewMode, dates: Date[]) {
  const anchor = parseDate(anchorKey);
  if (viewMode === "day") {
    return anchor.toLocaleDateString(undefined, { weekday: "long", month: "short", day: "numeric", year: "numeric" });
  }
  if (viewMode === "month") {
    return anchor.toLocaleDateString(undefined, { month: "long", year: "numeric" });
  }
  const first = dates[0];
  const last = dates[dates.length - 1];
  const f = (d: Date) => d.toLocaleDateString(undefined, { month: "short", day: "numeric" });
  return `${f(first)} – ${f(last)}`;
}

export function isWeekend(d: Date) {
  const day = d.getUTCDay();
  return day === 0 || day === 6;
}

export function isToday(d: Date) {
  const now = new Date();
  return (
    d.getUTCFullYear() === now.getUTCFullYear() &&
    d.getUTCMonth() === now.getUTCMonth() &&
    d.getUTCDate() === now.getUTCDate()
  );
}
