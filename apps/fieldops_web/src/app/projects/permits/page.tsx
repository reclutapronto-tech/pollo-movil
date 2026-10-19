"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useCurrentUser } from "@/lib/use-role";
import { isManagementRole, SUPERVISOR_ROLE } from "@/lib/roles";
import { callFunctionJson } from "@/lib/function-client";
import { getSupabase } from "@/lib/supabase";
import { SkeletonTable } from "@/components/ui/skeleton";

const PERMIT_TYPES = [
  "hv_electrical",
  "confined_space",
  "hot_work",
  "working_at_heights",
  "lockout_tagout",
  "excavation",
  "general",
  "other",
] as const;

type PermitType = (typeof PERMIT_TYPES)[number];

const PERMIT_TYPE_LABELS: Record<PermitType, string> = {
  hv_electrical: "HV Electrical",
  confined_space: "Confined Space",
  hot_work: "Hot Work",
  working_at_heights: "Working at Heights",
  lockout_tagout: "Lockout/Tagout",
  excavation: "Excavation",
  general: "General",
  other: "Other",
};

type PermitStatus = "draft" | "issued" | "expired" | "revoked";

const STATUS_PILL: Record<PermitStatus, string> = {
  draft: "bg-stone-100 text-stone-600",
  issued: "bg-blue-100 text-blue-700",
  expired: "bg-red-100 text-red-700",
  revoked: "bg-stone-700 text-white",
};

// Matches public.job_status enum: draft | active | in_progress | review | completed | archived.
// Excludes completed + archived so permits are only attached to open jobs.
const ACTIVE_JOB_STATUSES = [
  "draft",
  "active",
  "in_progress",
  "review",
] as const;

interface Permit {
  id: string;
  permit_number: string;
  permit_type: PermitType;
  status: PermitStatus;
  job_id: string;
  job_name: string;
  issued_by: string | null;
  issuer_name: string | null;
  issued_at: string | null;
  expires_at: string | null;
  revoked_by: string | null;
  revoker_name: string | null;
  revoked_at: string | null;
  revocation_reason: string | null;
  description: string | null;
  created_at: string;
}

interface PermitsListResponse {
  permits?: Permit[];
}

interface JobOption {
  id: string;
  name: string;
  code: string;
  requires_permit?: boolean | null;
}

type StatusFilter = "all" | PermitStatus;

function formatDateTime(value: string | null): string {
  if (!value) return "—";
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return "—";
  return d.toLocaleString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function isFuture(value: string | null): boolean {
  if (!value) return false;
  const t = new Date(value).getTime();
  return Number.isFinite(t) && t > Date.now();
}

export default function WorkPermitsPage() {
  const currentUser = useCurrentUser();
  const authorized =
    isManagementRole(currentUser.role) || currentUser.role === SUPERVISOR_ROLE;

  const [jobs, setJobs] = useState<JobOption[]>([]);
  const [permits, setPermits] = useState<Permit[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [jobFilter, setJobFilter] = useState<string>("");
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("all");

  const [createOpen, setCreateOpen] = useState(false);
  const [revokingPermit, setRevokingPermit] = useState<Permit | null>(null);
  const [rowBusy, setRowBusy] = useState<Record<string, boolean>>({});
  const [rowError, setRowError] = useState<Record<string, string>>({});

  const loadJobs = useCallback(async () => {
    if (!currentUser.companyId) return;
    const supabase = getSupabase();
    const res = await supabase
      .from("jobs")
      .select("id, name, code, requires_permit")
      .eq("company_id", currentUser.companyId)
      .in("status", ACTIVE_JOB_STATUSES as unknown as string[])
      .order("name", { ascending: true });
    if (res.error) {
      setError(res.error.message);
      return;
    }
    setJobs((res.data ?? []) as JobOption[]);
  }, [currentUser.companyId]);

  const loadPermits = useCallback(async () => {
    setError(null);
    try {
      const payload = await callFunctionJson<PermitsListResponse>("permits", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "list",
          job_id: jobFilter || undefined,
          status: statusFilter === "all" ? undefined : statusFilter,
        }),
      });
      setPermits(payload.permits ?? []);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load permits");
      setPermits([]);
    } finally {
      setLoading(false);
    }
  }, [jobFilter, statusFilter]);

  useEffect(() => {
    if (currentUser.loading) return;
    if (!authorized) {
      setLoading(false);
      return;
    }
    void loadJobs();
  }, [authorized, currentUser.loading, loadJobs]);

  useEffect(() => {
    if (currentUser.loading || !authorized) return;
    setLoading(true);
    void loadPermits();
  }, [authorized, currentUser.loading, loadPermits]);

  const blockingJobIds = useMemo(() => {
    const requiredIds = new Set(
      jobs.filter((j) => j.requires_permit).map((j) => j.id),
    );
    const jobsWithActive = new Set(
      permits
        .filter((p) => p.status === "issued" && (!p.expires_at || isFuture(p.expires_at)))
        .map((p) => p.job_id),
    );
    const blocking = new Set<string>();
    for (const id of requiredIds) if (!jobsWithActive.has(id)) blocking.add(id);
    return blocking;
  }, [jobs, permits]);

  async function performAction(
    permitId: string,
    body: Record<string, unknown>,
  ): Promise<boolean> {
    setRowBusy((m) => ({ ...m, [permitId]: true }));
    setRowError((m) => {
      const n = { ...m };
      delete n[permitId];
      return n;
    });
    try {
      await callFunctionJson("permits", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Idempotency-Key": crypto.randomUUID(),
        },
        body: JSON.stringify(body),
      });
      await loadPermits();
      return true;
    } catch (err) {
      setRowError((m) => ({
        ...m,
        [permitId]: err instanceof Error ? err.message : "Action failed",
      }));
      return false;
    } finally {
      setRowBusy((m) => {
        const n = { ...m };
        delete n[permitId];
        return n;
      });
    }
  }

  if (currentUser.loading) {
    return (
      <div className="p-6">
        <SkeletonTable rows={6} cols={7} />
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
            Only supervisors, admins, and owners can manage work permits.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="p-6">
      <header className="mb-4">
        <h1 className="text-2xl font-semibold text-stone-900">Work Permits</h1>
        <p className="mt-1 text-sm text-stone-500">
          Issue, revoke, and track work permits per job. Jobs that require a
          permit will block clock-in until an active permit is attached.
        </p>
      </header>

      <div className="mb-4 flex flex-wrap items-end justify-between gap-3">
        <div className="flex flex-wrap items-end gap-3">
          <label className="flex flex-col text-xs font-medium text-stone-500">
            Job
            <select
              value={jobFilter}
              onChange={(e) => setJobFilter(e.target.value)}
              className="mt-1 min-w-[200px] rounded-lg border border-stone-300 bg-card px-3 py-2 text-sm text-stone-900"
            >
              <option value="">All jobs</option>
              {jobs.map((j) => (
                <option key={j.id} value={j.id}>
                  {j.name} ({j.code})
                </option>
              ))}
            </select>
          </label>
          <label className="flex flex-col text-xs font-medium text-stone-500">
            Status
            <select
              value={statusFilter}
              onChange={(e) =>
                setStatusFilter(e.target.value as StatusFilter)
              }
              className="mt-1 rounded-lg border border-stone-300 bg-card px-3 py-2 text-sm text-stone-900"
            >
              <option value="all">All</option>
              <option value="draft">Draft</option>
              <option value="issued">Issued</option>
              <option value="expired">Expired</option>
              <option value="revoked">Revoked</option>
            </select>
          </label>
        </div>
        <button
          type="button"
          onClick={() => setCreateOpen(true)}
          className="rounded-xl bg-amber-500 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-amber-600"
        >
          + New Permit
        </button>
      </div>

      {error && (
        <div className="mb-4 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
          Failed to load: {error}
        </div>
      )}

      {blockingJobIds.size > 0 && (
        <div className="mb-4 rounded-lg border border-amber-200 bg-amber-50 p-3 text-xs text-amber-800">
          {blockingJobIds.size} job{blockingJobIds.size === 1 ? "" : "s"} require
          a permit but have no active permit — clock-in is blocked.
        </div>
      )}

      {loading ? (
        <SkeletonTable rows={8} cols={7} />
      ) : permits.length === 0 ? (
        <div className="rounded-2xl border border-stone-200 bg-card p-6 text-sm text-stone-500">
          No permits found.
        </div>
      ) : (
        <div className="overflow-hidden rounded-2xl border border-stone-200 bg-card">
          <table className="w-full text-sm">
            <thead className="bg-stone-50 text-xs uppercase text-stone-500">
              <tr>
                <th className="p-3 text-left">Permit #</th>
                <th className="p-3 text-left">Type</th>
                <th className="p-3 text-left">Job</th>
                <th className="p-3 text-left">Status</th>
                <th className="p-3 text-left">Issued</th>
                <th className="p-3 text-left">Expires</th>
                <th className="p-3 text-left">Actions</th>
              </tr>
            </thead>
            <tbody>
              {permits.map((p) => {
                const busy = rowBusy[p.id] === true;
                const errMsg = rowError[p.id];
                const closed = p.status === "expired" || p.status === "revoked";
                const expiryFuture = isFuture(p.expires_at);
                const jobBlocking = blockingJobIds.has(p.job_id);
                return (
                  <tr key={p.id} className="border-t border-stone-100 align-top">
                    <td className="p-3 font-medium text-stone-900">
                      {p.permit_number}
                    </td>
                    <td className="p-3 text-stone-700">
                      {PERMIT_TYPE_LABELS[p.permit_type] ?? p.permit_type}
                    </td>
                    <td className="p-3 text-stone-700">
                      <div>{p.job_name}</div>
                      {jobBlocking && (
                        <span className="mt-1 inline-block rounded-full bg-amber-100 px-2 py-0.5 text-xs font-semibold uppercase text-amber-800">
                          Blocking clock-in
                        </span>
                      )}
                    </td>
                    <td className="p-3">
                      <span
                        className={`rounded-full px-2 py-0.5 text-xs font-bold uppercase ${STATUS_PILL[p.status]}`}
                      >
                        {p.status}
                      </span>
                    </td>
                    <td className="p-3 text-stone-600">
                      <div>{formatDateTime(p.issued_at)}</div>
                      {p.issuer_name && (
                        <div className="text-xs text-stone-400">
                          {p.issuer_name}
                        </div>
                      )}
                    </td>
                    <td className="p-3 text-stone-600">
                      {p.expires_at ? formatDateTime(p.expires_at) : "Never"}
                    </td>
                    <td className="p-3">
                      <div className="flex flex-wrap items-center gap-2">
                        {p.status === "draft" && (
                          <>
                            <button
                              type="button"
                              disabled={busy}
                              aria-disabled={busy}
                              onClick={() =>
                                void performAction(p.id, {
                                  action: "issue",
                                  permit_id: p.id,
                                })
                              }
                              className="rounded-lg bg-blue-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-blue-700 disabled:bg-stone-100 disabled:text-slate-400"
                            >
                              Issue
                            </button>
                            <button
                              type="button"
                              disabled={busy}
                              aria-disabled={busy}
                              onClick={() => setRevokingPermit(p)}
                              className="rounded-lg border border-stone-300 px-3 py-1.5 text-xs font-semibold text-stone-700 hover:bg-stone-50 disabled:bg-stone-100 disabled:text-slate-400"
                            >
                              Revoke
                            </button>
                          </>
                        )}
                        {p.status === "issued" && (
                          <>
                            <button
                              type="button"
                              disabled={busy}
                              aria-disabled={busy}
                              onClick={() => setRevokingPermit(p)}
                              className="rounded-lg bg-red-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-red-700 disabled:bg-stone-100 disabled:text-slate-400"
                            >
                              Revoke
                            </button>
                            {expiryFuture && (
                              <span className="text-xs text-stone-400">
                                Active
                              </span>
                            )}
                          </>
                        )}
                        {closed && (
                          <span className="text-xs text-stone-400">
                            {p.status === "revoked" && p.revocation_reason
                              ? p.revocation_reason
                              : "—"}
                          </span>
                        )}
                        {busy && (
                          <span className="text-xs text-stone-400">
                            Working…
                          </span>
                        )}
                      </div>
                      {errMsg && (
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

      {createOpen && (
        <NewPermitModal
          jobs={jobs}
          onClose={() => setCreateOpen(false)}
          onCreated={() => {
            setCreateOpen(false);
            void loadPermits();
          }}
        />
      )}

      {revokingPermit && (
        <RevokeModal
          permit={revokingPermit}
          onClose={() => setRevokingPermit(null)}
          onRevoked={() => {
            setRevokingPermit(null);
            void loadPermits();
          }}
        />
      )}
    </div>
  );
}

/* --------------------------- Modals --------------------------- */

function useEscapeClose(onClose: () => void) {
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [onClose]);
}

interface NewPermitModalProps {
  jobs: JobOption[];
  onClose: () => void;
  onCreated: () => void;
}

function NewPermitModal({ jobs, onClose, onCreated }: NewPermitModalProps) {
  useEscapeClose(onClose);
  const [jobId, setJobId] = useState("");
  const [permitNumber, setPermitNumber] = useState("");
  const [permitType, setPermitType] = useState<PermitType | "">("");
  const [description, setDescription] = useState("");
  const [expiresAt, setExpiresAt] = useState("");
  const [issueNow, setIssueNow] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setErr(null);
    if (!jobId || !permitNumber.trim() || !permitType) {
      setErr("Job, permit number, and type are required.");
      return;
    }
    if (expiresAt) {
      const t = new Date(expiresAt).getTime();
      if (!Number.isFinite(t) || t <= Date.now()) {
        setErr("Expiry must be in the future.");
        return;
      }
    }
    setSubmitting(true);
    try {
      await callFunctionJson("permits", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Idempotency-Key": crypto.randomUUID(),
        },
        body: JSON.stringify({
          action: "create",
          job_id: jobId,
          permit_number: permitNumber.trim(),
          permit_type: permitType,
          description: description.trim() || undefined,
          expires_at: expiresAt
            ? new Date(expiresAt).toISOString()
            : undefined,
          issue_immediately: issueNow,
        }),
      });
      onCreated();
    } catch (e2) {
      setErr(e2 instanceof Error ? e2.message : "Failed to create permit");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
      role="dialog"
      aria-modal="true"
      aria-label="New work permit"
    >
      <div className="w-full max-w-lg rounded-2xl bg-card shadow-xl">
        <div className="flex items-center justify-between border-b border-stone-100 px-5 py-4">
          <h2 className="text-lg font-semibold text-stone-900">New Permit</h2>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close"
            className="rounded-md p-1 text-stone-400 hover:bg-stone-100 hover:text-stone-700"
          >
            ✕
          </button>
        </div>
        <form onSubmit={submit} className="space-y-3 px-5 py-4">
          <label className="block text-xs font-semibold text-stone-600">
            Job
            <select
              value={jobId}
              onChange={(e) => setJobId(e.target.value)}
              required
              className="mt-1 w-full rounded-lg border border-stone-300 bg-card px-3 py-2 text-sm text-stone-900"
            >
              <option value="">Select a job…</option>
              {jobs.map((j) => (
                <option key={j.id} value={j.id}>
                  {j.name} ({j.code})
                </option>
              ))}
            </select>
          </label>
          <label className="block text-xs font-semibold text-stone-600">
            Permit #
            <input
              type="text"
              value={permitNumber}
              onChange={(e) => setPermitNumber(e.target.value)}
              required
              className="mt-1 w-full rounded-lg border border-stone-300 bg-card px-3 py-2 text-sm text-stone-900"
            />
          </label>
          <label className="block text-xs font-semibold text-stone-600">
            Permit Type
            <select
              value={permitType}
              onChange={(e) => setPermitType(e.target.value as PermitType)}
              required
              className="mt-1 w-full rounded-lg border border-stone-300 bg-card px-3 py-2 text-sm text-stone-900"
            >
              <option value="">Select a type…</option>
              {PERMIT_TYPES.map((t) => (
                <option key={t} value={t}>
                  {PERMIT_TYPE_LABELS[t]}
                </option>
              ))}
            </select>
          </label>
          <label className="block text-xs font-semibold text-stone-600">
            Description (optional)
            <textarea
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              rows={2}
              className="mt-1 w-full rounded-lg border border-stone-300 bg-card px-3 py-2 text-sm text-stone-900"
            />
          </label>
          <label className="block text-xs font-semibold text-stone-600">
            Expires at (optional — empty means never)
            <input
              type="datetime-local"
              value={expiresAt}
              onChange={(e) => setExpiresAt(e.target.value)}
              className="mt-1 w-full rounded-lg border border-stone-300 bg-card px-3 py-2 text-sm text-stone-900"
            />
          </label>
          <label className="flex items-center gap-2 text-xs font-semibold text-stone-600">
            <input
              type="checkbox"
              checked={issueNow}
              onChange={(e) => setIssueNow(e.target.checked)}
            />
            Issue immediately
          </label>

          {err && (
            <div className="rounded-lg border border-red-200 bg-red-50 p-2 text-xs text-red-700">
              {err}
            </div>
          )}

          <div className="flex justify-end gap-2 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="rounded-xl px-4 py-2 text-sm font-semibold text-stone-600 hover:bg-stone-100"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={submitting}
              aria-disabled={submitting}
              className="inline-flex min-h-11 items-center rounded-xl bg-slate-900 px-4 text-sm font-semibold text-white transition-colors hover:bg-slate-800 disabled:bg-stone-100 disabled:text-slate-400 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-white"
            >
              {submitting ? "Saving…" : "Create"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

interface RevokeModalProps {
  permit: Permit;
  onClose: () => void;
  onRevoked: () => void;
}

function RevokeModal({ permit, onClose, onRevoked }: RevokeModalProps) {
  useEscapeClose(onClose);
  const [reason, setReason] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setErr(null);
    if (reason.trim().length < 5) {
      setErr("Reason must be at least 5 characters.");
      return;
    }
    setSubmitting(true);
    try {
      await callFunctionJson("permits", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Idempotency-Key": crypto.randomUUID(),
        },
        body: JSON.stringify({
          action: "revoke",
          permit_id: permit.id,
          reason: reason.trim(),
        }),
      });
      onRevoked();
    } catch (e2) {
      setErr(e2 instanceof Error ? e2.message : "Failed to revoke permit");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
      role="dialog"
      aria-modal="true"
      aria-label={`Revoke permit ${permit.permit_number}`}
    >
      <div className="w-full max-w-md rounded-2xl bg-card shadow-xl">
        <div className="flex items-center justify-between border-b border-stone-100 px-5 py-4">
          <h2 className="text-lg font-semibold text-stone-900">
            Revoke {permit.permit_number}
          </h2>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close"
            className="rounded-md p-1 text-stone-400 hover:bg-stone-100 hover:text-stone-700"
          >
            ✕
          </button>
        </div>
        <form onSubmit={submit} className="space-y-3 px-5 py-4">
          <label className="block text-xs font-semibold text-stone-600">
            Reason (required)
            <textarea
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              rows={3}
              required
              minLength={5}
              className="mt-1 w-full rounded-lg border border-stone-300 bg-card px-3 py-2 text-sm text-stone-900"
            />
          </label>

          {err && (
            <div className="rounded-lg border border-red-200 bg-red-50 p-2 text-xs text-red-700">
              {err}
            </div>
          )}

          <div className="flex justify-end gap-2 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="rounded-xl px-4 py-2 text-sm font-semibold text-stone-600 hover:bg-stone-100"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={submitting}
              aria-disabled={submitting}
              className="rounded-xl bg-red-600 px-4 py-2 text-sm font-semibold text-white hover:bg-red-700 disabled:bg-stone-100 disabled:text-slate-400"
            >
              {submitting ? "Revoking…" : "Revoke permit"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
