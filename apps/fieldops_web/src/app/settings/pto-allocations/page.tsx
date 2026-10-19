"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useCurrentUser } from "@/lib/use-role";
import { isManagementRole } from "@/lib/roles";
import { callFunctionJson } from "@/lib/function-client";
import { SkeletonTable } from "@/components/ui/skeleton";

const PTO_TYPES = ["vacation", "sick", "personal"] as const;
type PtoType = (typeof PTO_TYPES)[number];

const TYPE_LABELS: Record<PtoType, string> = {
  vacation: "Vacation",
  sick: "Sick",
  personal: "Personal",
};

interface AllocationRow {
  user_id: string;
  worker_name: string;
  pto_type: PtoType;
  year: number;
  total_days: number;
  is_default?: boolean;
}

interface AllocationsListResponse {
  allocations?: AllocationRow[];
}

interface UpsertResponse {
  allocation?: AllocationRow;
}

type WorkerGroup = {
  userId: string;
  name: string;
  values: Record<PtoType, { value: number; isDefault: boolean }>;
};

type RowSaveState = "idle" | "saving" | "saved" | "error";
type SaveMap = Record<string, RowSaveState>;

const currentUtcYear = () => new Date().getUTCFullYear();

function rowKey(userId: string, type: PtoType) {
  return `${userId}:${type}`;
}

export default function PtoAllocationsPage() {
  const currentUser = useCurrentUser();
  const [year, setYear] = useState<number>(currentUtcYear());
  const [rows, setRows] = useState<AllocationRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [saveState, setSaveState] = useState<SaveMap>({});
  const [saveError, setSaveError] = useState<Record<string, string>>({});
  const [drafts, setDrafts] = useState<Record<string, string>>({});

  const authorized = isManagementRole(currentUser.role);

  const load = useCallback(async () => {
    setError(null);
    try {
      const payload = await callFunctionJson<AllocationsListResponse>("pto", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "allocations_list", year }),
      });
      setRows(payload.allocations ?? []);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load allocations");
    } finally {
      setLoading(false);
    }
  }, [year]);

  useEffect(() => {
    if (currentUser.loading) return;
    if (!authorized) {
      setLoading(false);
      return;
    }
    setLoading(true);
    load();
  }, [authorized, currentUser.loading, load]);

  const groups = useMemo<WorkerGroup[]>(() => {
    const byUser = new Map<string, WorkerGroup>();
    for (const row of rows) {
      if (!PTO_TYPES.includes(row.pto_type)) continue;
      let group = byUser.get(row.user_id);
      if (!group) {
        group = {
          userId: row.user_id,
          name: row.worker_name,
          values: {
            vacation: { value: 0, isDefault: true },
            sick: { value: 0, isDefault: true },
            personal: { value: 0, isDefault: true },
          },
        };
        byUser.set(row.user_id, group);
      }
      group.values[row.pto_type] = {
        value: Number(row.total_days ?? 0),
        isDefault: Boolean(row.is_default),
      };
    }
    return Array.from(byUser.values()).sort((a, b) =>
      a.name.localeCompare(b.name),
    );
  }, [rows]);

  async function save(userId: string, type: PtoType, rawValue: string) {
    const parsed = Number(rawValue);
    if (!Number.isFinite(parsed) || parsed < 0) {
      setSaveError((m) => ({
        ...m,
        [rowKey(userId, type)]: "Must be a non-negative number",
      }));
      setSaveState((m) => ({ ...m, [rowKey(userId, type)]: "error" }));
      return;
    }

    const key = rowKey(userId, type);
    setSaveError((m) => {
      const next = { ...m };
      delete next[key];
      return next;
    });
    setSaveState((m) => ({ ...m, [key]: "saving" }));

    try {
      const payload = await callFunctionJson<UpsertResponse>("pto", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Idempotency-Key": crypto.randomUUID(),
        },
        body: JSON.stringify({
          action: "allocations_upsert",
          user_id: userId,
          pto_type: type,
          year,
          total_days: parsed,
        }),
      });

      setRows((prev) => {
        const existingIdx = prev.findIndex(
          (r) => r.user_id === userId && r.pto_type === type && r.year === year,
        );
        const next = [...prev];
        const serverRow: AllocationRow = payload.allocation ?? {
          user_id: userId,
          worker_name:
            groups.find((g) => g.userId === userId)?.name ?? "Worker",
          pto_type: type,
          year,
          total_days: parsed,
          is_default: false,
        };
        serverRow.is_default = false;
        if (existingIdx >= 0) next[existingIdx] = serverRow;
        else next.push(serverRow);
        return next;
      });
      setDrafts((d) => {
        const next = { ...d };
        delete next[key];
        return next;
      });
      setSaveState((m) => ({ ...m, [key]: "saved" }));
      setTimeout(() => {
        setSaveState((m) => {
          if (m[key] !== "saved") return m;
          const { [key]: _, ...rest } = m;
          return rest;
        });
      }, 1500);
    } catch (err) {
      setSaveError((m) => ({
        ...m,
        [key]: err instanceof Error ? err.message : "Failed to save",
      }));
      setSaveState((m) => ({ ...m, [key]: "error" }));
    }
  }

  if (currentUser.loading) {
    return (
      <div className="p-6">
        <SkeletonTable rows={6} cols={4} />
      </div>
    );
  }

  if (!authorized) {
    return (
      <div className="p-6">
        <div className="rounded-2xl border border-stone-200 bg-card p-6">
          <h1 className="text-xl font-semibold text-stone-900">
            Access denied
          </h1>
          <p className="mt-2 text-sm text-stone-500">
            Only admins and owners can manage PTO allocations.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="p-6">
      <header className="mb-4 flex items-end justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold text-stone-900">
            PTO Allocations
          </h1>
          <p className="mt-1 text-sm text-stone-500">
            Set each worker&apos;s annual PTO days. Workers without an explicit
            allocation use the default (10 vacation / 5 sick / 3 personal).
          </p>
        </div>
        <label className="flex flex-col text-xs font-medium text-stone-500">
          Year
          <select
            value={year}
            onChange={(e) => setYear(Number(e.target.value))}
            className="mt-1 rounded-lg border border-stone-300 bg-card px-3 py-2 text-sm text-stone-900"
          >
            {[-1, 0, 1].map((offset) => {
              const y = currentUtcYear() + offset;
              return (
                <option key={y} value={y}>
                  {y}
                </option>
              );
            })}
          </select>
        </label>
      </header>

      {error && (
        <div className="mb-4 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
          {error}
        </div>
      )}

      {loading ? (
        <SkeletonTable rows={8} cols={5} />
      ) : groups.length === 0 ? (
        <div className="rounded-2xl border border-stone-200 bg-card p-6 text-sm text-stone-500">
          No active workers in this company.
        </div>
      ) : (
        <div className="overflow-hidden rounded-2xl border border-stone-200 bg-card">
          <table className="w-full text-sm">
            <thead className="bg-stone-50 text-xs uppercase text-stone-500">
              <tr>
                <th className="p-3 text-left">Worker</th>
                {PTO_TYPES.map((t) => (
                  <th key={t} className="p-3 text-left">
                    {TYPE_LABELS[t]}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {groups.map((group) => (
                <tr key={group.userId} className="border-t border-stone-100">
                  <td className="p-3 font-medium text-stone-900">
                    {group.name}
                  </td>
                  {PTO_TYPES.map((t) => {
                    const key = rowKey(group.userId, t);
                    const cell = group.values[t];
                    const draft = drafts[key];
                    const display =
                      draft !== undefined ? draft : String(cell.value);
                    const status = saveState[key] ?? "idle";
                    const errMsg = saveError[key];
                    return (
                      <td key={t} className="p-3 align-top">
                        <div className="flex items-center gap-2">
                          <input
                            type="number"
                            min={0}
                            step={0.5}
                            value={display}
                            onChange={(e) =>
                              setDrafts((d) => ({
                                ...d,
                                [key]: e.target.value,
                              }))
                            }
                            onBlur={(e) => {
                              const next = e.target.value.trim();
                              if (next === String(cell.value)) return;
                              void save(group.userId, t, next);
                            }}
                            aria-label={`${TYPE_LABELS[t]} days for ${group.name}`}
                            className="w-20 rounded-lg border border-stone-300 bg-card px-2 py-1.5 text-sm text-stone-900"
                          />
                          {cell.isDefault && (
                            <span className="rounded-full bg-stone-100 px-2 py-0.5 text-xs font-medium uppercase text-stone-500">
                              Default
                            </span>
                          )}
                          {status === "saving" && (
                            <span className="text-xs text-stone-400">
                              Saving…
                            </span>
                          )}
                          {status === "saved" && (
                            <span className="text-xs text-green-600">
                              Saved
                            </span>
                          )}
                        </div>
                        {status === "error" && errMsg && (
                          <p className="mt-1 text-xs text-red-600">{errMsg}</p>
                        )}
                      </td>
                    );
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
