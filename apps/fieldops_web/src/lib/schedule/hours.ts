import type { ConflictFlags, PtoRequest, ScheduleEntry } from "./types";

const OT_THRESHOLD = 40;

export function shiftHours(entry: Pick<ScheduleEntry, "start_time" | "end_time">) {
  const [sh, sm] = entry.start_time.split(":").map(Number);
  const [eh, em] = entry.end_time.split(":").map(Number);
  const minutes = (eh * 60 + em) - (sh * 60 + sm);
  return Math.max(0, minutes / 60);
}

/** Total scheduled hours per worker across visible range. */
export function workerHoursInRange(
  entries: ScheduleEntry[],
  rangeStart: string,
  rangeEnd: string,
): Map<string, number> {
  const out = new Map<string, number>();
  for (const e of entries) {
    if (e.date < rangeStart || e.date > rangeEnd) continue;
    out.set(e.worker_id, (out.get(e.worker_id) ?? 0) + shiftHours(e));
  }
  return out;
}

/** Map worker_id -> Set of dates (YYYY-MM-DD) where they have approved/pending PTO. */
export function workerPtoDates(ptoRequests: PtoRequest[]): Map<string, Set<string>> {
  const out = new Map<string, Set<string>>();
  for (const p of ptoRequests) {
    if (p.status !== "approved" && p.status !== "pending") continue;
    const set = out.get(p.user_id) ?? new Set<string>();
    const start = new Date(`${p.start_date}T00:00:00Z`);
    const end = new Date(`${p.end_date}T00:00:00Z`);
    const cursor = new Date(start);
    while (cursor <= end) {
      set.add(cursor.toISOString().slice(0, 10));
      cursor.setUTCDate(cursor.getUTCDate() + 1);
    }
    out.set(p.user_id, set);
  }
  return out;
}

export function detectConflicts(
  entry: ScheduleEntry,
  allEntries: ScheduleEntry[],
  ptoMap: Map<string, Set<string>>,
  hoursMap: Map<string, number>,
): ConflictFlags {
  const pto = ptoMap.get(entry.worker_id)?.has(entry.date) ?? false;
  const overtime = (hoursMap.get(entry.worker_id) ?? 0) > OT_THRESHOLD;
  const doubleBooked = allEntries.some(
    (e) =>
      e.id !== entry.id &&
      e.worker_id === entry.worker_id &&
      e.date === entry.date &&
      timesOverlap(e.start_time, e.end_time, entry.start_time, entry.end_time),
  );
  return { pto, doubleBooked, overtime };
}

function timesOverlap(aStart: string, aEnd: string, bStart: string, bEnd: string) {
  return aStart < bEnd && bStart < aEnd;
}
