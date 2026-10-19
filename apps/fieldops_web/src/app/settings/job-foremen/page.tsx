"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useCurrentUser } from "@/lib/use-role";
import { isManagementRole } from "@/lib/roles";
import { getSupabase } from "@/lib/supabase";
import { SkeletonTable } from "@/components/ui/skeleton";

interface JobRow {
  id: string;
  name: string;
  code: string;
  status: string;
}

interface AssignmentRow {
  id: string;
  job_id: string;
  user_id: string;
  is_active: boolean;
}

interface ForemanOption {
  id: string;
  full_name: string;
}

interface JobDisplay {
  job: JobRow;
  currentAssignmentId: string | null;
  currentForemanId: string | null;
  currentForemanName: string | null;
}

// Matches public.job_status enum: draft | active | in_progress | review | completed | archived.
// Excludes completed + archived so foremen can only be assigned to open jobs.
const ACTIVE_JOB_STATUSES = [
  "draft",
  "active",
  "in_progress",
  "review",
] as const;

type RowSave = "idle" | "saving" | "saved" | "error";

export default function JobForemenPage() {
  const currentUser = useCurrentUser();
  const authorized = isManagementRole(currentUser.role);

  const [jobs, setJobs] = useState<JobDisplay[]>([]);
  const [foremen, setForemen] = useState<ForemanOption[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [rowState, setRowState] = useState<Record<string, RowSave>>({});
  const [rowError, setRowError] = useState<Record<string, string>>({});

  const load = useCallback(async () => {
    if (!currentUser.companyId || !currentUser.userId) return;
    setError(null);
    const supabase = getSupabase();

    try {
      const [jobsRes, foremenRes] = await Promise.all([
        supabase
          .from("jobs")
          .select("id, name, code, status")
          .eq("company_id", currentUser.companyId)
          .in("status", ACTIVE_JOB_STATUSES as unknown as string[])
          .order("name", { ascending: true }),
        supabase
          .from("users")
          .select("id, full_name")
          .eq("company_id", currentUser.companyId)
          .eq("role", "foreman")
          .eq("is_active", true)
          .order("full_name", { ascending: true }),
      ]);

      if (jobsRes.error) throw jobsRes.error;
      if (foremenRes.error) throw foremenRes.error;

      const jobRows = (jobsRes.data ?? []) as JobRow[];
      const foremenRows = (foremenRes.data ?? []) as ForemanOption[];

      const assignmentsRes =
        jobRows.length === 0
          ? { data: [] as AssignmentRow[], error: null }
          : await supabase
              .from("assignments")
              .select("id, job_id, user_id, is_active")
              .eq("company_id", currentUser.companyId)
              .eq("assigned_role", "foreman")
              .eq("is_active", true)
              .in(
                "job_id",
                jobRows.map((j) => j.id),
              );
      if (assignmentsRes.error) throw assignmentsRes.error;

      const assignedUserIds = Array.from(
        new Set(
          (assignmentsRes.data ?? []).map((a) => a.user_id).filter(Boolean),
        ),
      );
      const missingNames = assignedUserIds.filter(
        (uid) => !foremenRows.some((f) => f.id === uid),
      );
      const extraNames = new Map<string, string>();
      if (missingNames.length > 0) {
        const namesRes = await supabase
          .from("users")
          .select("id, full_name")
          .in("id", missingNames);
        if (namesRes.error) throw namesRes.error;
        for (const u of namesRes.data ?? []) {
          if (u?.id) extraNames.set(u.id as string, (u.full_name as string) ?? "");
        }
      }

      const assignmentByJob = new Map<string, AssignmentRow>();
      for (const a of assignmentsRes.data ?? []) {
        assignmentByJob.set(a.job_id, a);
      }

      const display: JobDisplay[] = jobRows.map((job) => {
        const a = assignmentByJob.get(job.id) ?? null;
        const name = a
          ? foremenRows.find((f) => f.id === a.user_id)?.full_name ??
            extraNames.get(a.user_id) ??
            "Unknown foreman"
          : null;
        return {
          job,
          currentAssignmentId: a?.id ?? null,
          currentForemanId: a?.user_id ?? null,
          currentForemanName: name,
        };
      });

      setForemen(foremenRows);
      setJobs(display);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load jobs");
    } finally {
      setLoading(false);
    }
  }, [currentUser.companyId, currentUser.userId]);

  useEffect(() => {
    if (currentUser.loading) return;
    if (!authorized) {
      setLoading(false);
      return;
    }
    setLoading(true);
    load();
  }, [authorized, currentUser.loading, load]);

  async function changeForeman(jobId: string, nextUserId: string | null) {
    const supabase = getSupabase();
    const job = jobs.find((j) => j.job.id === jobId);
    if (!job || !currentUser.companyId || !currentUser.userId) return;
    if (job.currentForemanId === nextUserId) return;

    const previous = { ...job };
    const nextName = nextUserId
      ? foremen.find((f) => f.id === nextUserId)?.full_name ?? "Foreman"
      : null;

    setJobs((prev) =>
      prev.map((j) =>
        j.job.id === jobId
          ? {
              ...j,
              currentForemanId: nextUserId,
              currentForemanName: nextName,
            }
          : j,
      ),
    );
    setRowState((m) => ({ ...m, [jobId]: "saving" }));
    setRowError((m) => {
      const n = { ...m };
      delete n[jobId];
      return n;
    });

    try {
      if (job.currentAssignmentId) {
        const deactivate = await supabase
          .from("assignments")
          .update({ is_active: false, ends_at: new Date().toISOString() })
          .eq("id", job.currentAssignmentId);
        if (deactivate.error) throw deactivate.error;
      }

      let newAssignmentId: string | null = null;
      if (nextUserId) {
        const insert = await supabase
          .from("assignments")
          .insert({
            company_id: currentUser.companyId,
            job_id: jobId,
            user_id: nextUserId,
            assigned_role: "foreman",
            assigned_by: currentUser.userId,
            starts_at: new Date().toISOString(),
            is_active: true,
          })
          .select("id")
          .single();
        if (insert.error) throw insert.error;
        newAssignmentId = insert.data.id as string;
      }

      setJobs((prev) =>
        prev.map((j) =>
          j.job.id === jobId
            ? { ...j, currentAssignmentId: newAssignmentId }
            : j,
        ),
      );
      setRowState((m) => ({ ...m, [jobId]: "saved" }));
      setTimeout(() => {
        setRowState((m) => {
          if (m[jobId] !== "saved") return m;
          const { [jobId]: _, ...rest } = m;
          return rest;
        });
      }, 1500);
    } catch (err) {
      setJobs((prev) =>
        prev.map((j) => (j.job.id === jobId ? previous : j)),
      );
      setRowState((m) => ({ ...m, [jobId]: "error" }));
      setRowError((m) => ({
        ...m,
        [jobId]: err instanceof Error ? err.message : "Failed to save",
      }));
    }
  }

  const options = useMemo(() => foremen, [foremen]);

  if (currentUser.loading) {
    return (
      <div className="p-6">
        <SkeletonTable rows={6} cols={3} />
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
            Only admins, owners, and supervisors can manage foreman
            assignments.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="p-6">
      <header className="mb-4">
        <h1 className="text-2xl font-semibold text-stone-900">
          Foreman Assignments
        </h1>
        <p className="mt-1 text-sm text-stone-500">
          Each job may optionally have a foreman. Jobs without one still run
          normally — workers appear on supervisor views directly.
        </p>
      </header>

      {error && (
        <div className="mb-4 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
          {error}
        </div>
      )}

      {loading ? (
        <SkeletonTable rows={8} cols={3} />
      ) : jobs.length === 0 ? (
        <div className="rounded-2xl border border-stone-200 bg-card p-6 text-sm text-stone-500">
          No active jobs.
        </div>
      ) : (
        <div className="overflow-hidden rounded-2xl border border-stone-200 bg-card">
          <table className="w-full text-sm">
            <thead className="bg-stone-50 text-xs uppercase text-stone-500">
              <tr>
                <th className="p-3 text-left">Job</th>
                <th className="p-3 text-left">Status</th>
                <th className="p-3 text-left">Foreman</th>
              </tr>
            </thead>
            <tbody>
              {jobs.map((row) => {
                const status = rowState[row.job.id] ?? "idle";
                const errMsg = rowError[row.job.id];
                const currentId = row.currentForemanId ?? "";
                const showExtraOption =
                  row.currentForemanId &&
                  !options.some((o) => o.id === row.currentForemanId);
                return (
                  <tr
                    key={row.job.id}
                    className="border-t border-stone-100"
                  >
                    <td className="p-3">
                      <div className="font-medium text-stone-900">
                        {row.job.name}
                      </div>
                      <div className="text-xs text-stone-400">
                        {row.job.code}
                      </div>
                    </td>
                    <td className="p-3 text-xs uppercase text-stone-500">
                      {row.job.status}
                    </td>
                    <td className="p-3">
                      <div className="flex items-center gap-2">
                        <select
                          value={currentId}
                          onChange={(e) =>
                            void changeForeman(
                              row.job.id,
                              e.target.value || null,
                            )
                          }
                          aria-label={`Foreman for ${row.job.name}`}
                          className="rounded-lg border border-stone-300 bg-card px-3 py-1.5 text-sm text-stone-900"
                        >
                          <option value="">— None —</option>
                          {options.map((o) => (
                            <option key={o.id} value={o.id}>
                              {o.full_name}
                            </option>
                          ))}
                          {showExtraOption && row.currentForemanId && (
                            <option value={row.currentForemanId}>
                              {row.currentForemanName ?? "Current"}
                            </option>
                          )}
                        </select>
                        {status === "saving" && (
                          <span className="text-xs text-stone-400">
                            Saving…
                          </span>
                        )}
                        {status === "saved" && (
                          <span className="text-xs text-green-600">Saved</span>
                        )}
                      </div>
                      {status === "error" && errMsg && (
                        <p className="mt-1 text-xs text-red-600">{errMsg}</p>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
