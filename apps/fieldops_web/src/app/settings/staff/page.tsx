"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useI18n } from "@/lib/i18n";
import { ADMIN_ROLE, isManagementRole, isOwnerRole, OWNER_ROLE } from "@/lib/roles";
import { getSupabase } from "@/lib/supabase";
import { useToast } from "@/components/ui/toast";

interface StaffMember {
  id: string;
  full_name: string;
  email: string | null;
  phone: string | null;
  role: string;
  is_active: boolean;
  metadata: Record<string, unknown>;
}

interface EditingStaff {
  id: string;
  fullName: string;
  email: string;
  phone: string;
  role: string;
  driverLicense: string;
  address: string;
  notes: string;
  isActive: boolean;
}

const ROLE_DEFINITIONS = [
  { value: "owner", labelKey: "staffPage.roles.owner.label", descriptionKey: "staffPage.roles.owner.description" },
  { value: "worker", labelKey: "staffPage.roles.worker.label", descriptionKey: "staffPage.roles.worker.description" },
  { value: "foreman", labelKey: "staffPage.roles.foreman.label", descriptionKey: "staffPage.roles.foreman.description" },
  { value: "supervisor", labelKey: "staffPage.roles.supervisor.label", descriptionKey: "staffPage.roles.supervisor.description" },
  { value: "admin", labelKey: "staffPage.roles.admin.label", descriptionKey: "staffPage.roles.admin.description" },
] as const;

type RoleTab = "all" | "owner" | "admin" | "supervisor" | "crew";

const ROLE_TABS: { key: RoleTab; label: string; roles: string[] }[] = [
  { key: "all", label: "All", roles: [] },
  { key: "owner", label: "Owner", roles: ["owner"] },
  { key: "admin", label: "Admin", roles: ["admin"] },
  { key: "supervisor", label: "Supervisor", roles: ["supervisor"] },
  { key: "crew", label: "Team Crew", roles: ["worker", "foreman"] },
];

export default function StaffPage() {
  const { t } = useI18n();
  const [staff, setStaff] = useState<StaffMember[]>([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState<EditingStaff | null>(null);
  const [showAdd, setShowAdd] = useState(false);
  const [saved, setSaved] = useState(false);
  const [inviteLink, setInviteLink] = useState<string | null>(null);
  const [emailSent, setEmailSent] = useState(false);
  const [inviteError, setInviteError] = useState<string | null>(null);
  const [accessDenied, setAccessDenied] = useState(false);
  const [viewerRole, setViewerRole] = useState<string | null>(null);
  const [selectedStaff, setSelectedStaff] = useState<Set<string>>(new Set());
  const [activeRoleTab, setActiveRoleTab] = useState<RoleTab>("all");

  // Role gate: only admin users can access staff management
  useEffect(() => {
    let mounted = true;
    const supabase = getSupabase();
    supabase.auth.getSession().then(async ({ data }) => {
      if (!mounted || !data.session) return;
      const { data: user } = await supabase
        .from("users")
        .select("role")
        .eq("id", data.session.user.id)
        .maybeSingle();
      if (mounted) {
        setViewerRole(user?.role ?? null);
      }
      if (mounted && !isManagementRole(user?.role)) {
        setAccessDenied(true);
        setLoading(false);
      }
    });
    return () => { mounted = false; };
  }, []);

  const roles = useMemo(
    () =>
      ROLE_DEFINITIONS.map((role) => ({
        value: role.value,
        label: t(role.labelKey),
        description: t(role.descriptionKey),
      })),
    [t],
  );

  const assignableRoles = useMemo(() => {
    if (isOwnerRole(viewerRole)) {
      return roles;
    }
    return roles.filter((role) => role.value !== OWNER_ROLE);
  }, [roles, viewerRole]);

  const { toast, showToast } = useToast();

  const loadStaff = useCallback(async () => {
    setLoading(true);
    try {
      const supabase = getSupabase();
      const { data } = await supabase
        .from("users")
        .select("id, full_name, email, phone, role, is_active, metadata")
        .order("full_name");
      setStaff((data as StaffMember[]) ?? []);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadStaff();
  }, [loadStaff]);

  function startEdit(member: StaffMember) {
    if (member.role === OWNER_ROLE && !isOwnerRole(viewerRole)) {
      setInviteError("Only the company owner can edit ownership.");
      return;
    }

    const metadata = (member.metadata ?? {}) as Record<string, string>;
    setEditing({
      id: member.id,
      fullName: member.full_name,
      email: member.email ?? "",
      phone: member.phone ?? "",
      role: member.role,
      driverLicense: metadata.driver_license ?? "",
      address: metadata.address ?? "",
      notes: metadata.notes ?? "",
      isActive: member.is_active,
    });
    setShowAdd(false);
  }

  function startAdd() {
    setEditing({
      id: "",
      fullName: "",
      email: "",
      phone: "",
      role: "worker",
      driverLicense: "",
      address: "",
      notes: "",
      isActive: true,
    });
    setShowAdd(true);
  }

  async function saveStaff() {
    if (!editing) return;
    setInviteError(null);

    if (editing.role === OWNER_ROLE && !isOwnerRole(viewerRole)) {
      setInviteError("Only the company owner can assign or edit the owner role.");
      return;
    }

    if (showAdd) {
      // New staff: call invites edge function
      try {
        const supabase = getSupabase();
        const { data: sessionData } = await supabase.auth.getSession();
        const token = sessionData.session?.access_token;
        if (!token) {
          setInviteError("Not authenticated.");
          return;
        }

        const response = await fetch(
          `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/invites`,
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${token}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              action: "create",
              email: editing.email,
              full_name: editing.fullName,
              role: editing.role,
            }),
          },
        );

        if (!response.ok) {
          const body = await response.text();
          let message = "Failed to send invite.";
          try {
            const parsed = JSON.parse(body);
            // Edge functions return { status: "error", message, error_code, ... }
            // via errorResponse() — earlier code read `parsed.error` which never
            // exists, so the real cause (SMTP down, rate limit, etc.) was hidden.
            message =
              parsed.message ||
              parsed.error_description ||
              parsed.error ||
              message;
          } catch {
            // Non-JSON body (e.g. proxy-level HTML error page) — fall through.
          }
          setInviteError(message);
          return;
        }

        // Parse response — if email_sent is false but invite_link exists,
        // surface the link to the admin so they can share it manually.
        let parsedResp: {
          invite_link?: string | null;
          email_sent?: boolean;
          email_error?: string | null;
        } = {};
        try {
          parsedResp = await response.json();
        } catch {
          /* ignore */
        }

        setEmailSent(parsedResp.email_sent ?? true);
        if (parsedResp.invite_link && !parsedResp.email_sent) {
          // Show the copyable link and keep the form open so the admin
          // can send it before closing.
          setInviteLink(parsedResp.invite_link);
          loadStaff();
          return;
        }

        setSaved(true);
        setTimeout(() => {
          setSaved(false);
          setEditing(null);
          setShowAdd(false);
          setInviteLink(null);
          loadStaff();
        }, 1500);
      } catch {
        setInviteError("Failed to send invite. Please try again.");
      }
    } else {
      // Edit existing staff: update via supabase
      try {
        const supabase = getSupabase();
        const { error } = await supabase
          .from("users")
          .update({
            full_name: editing.fullName,
            email: editing.email || null,
            phone: editing.phone || null,
            role: editing.role,
            is_active: editing.isActive,
            metadata: {
              driver_license: editing.driverLicense || undefined,
              address: editing.address || undefined,
              notes: editing.notes || undefined,
            },
          })
          .eq("id", editing.id);

        if (error) {
          setInviteError("Failed to update staff member.");
          return;
        }

        setSaved(true);
        setTimeout(() => {
          setSaved(false);
          setEditing(null);
          setShowAdd(false);
          loadStaff();
        }, 1500);
      } catch {
        setInviteError("Failed to update. Please try again.");
      }
    }
  }

  const activeCount = staff.filter((member) => member.is_active).length;
  const roleLabel = (role: string) => roles.find((entry) => entry.value === role)?.label ?? role;

  const tabFilteredStaff = useMemo(() => {
    const tab = ROLE_TABS.find((t) => t.key === activeRoleTab);
    if (!tab || tab.roles.length === 0) return staff;
    return staff.filter((m) => tab.roles.includes(m.role));
  }, [staff, activeRoleTab]);

  const ROLE_TOOLTIPS: Record<string, string> = {
    owner: t("staff.ownerRole"),
    worker: t("staff.workerRole"),
    supervisor: t("staff.supervisorRole"),
    admin: t("staff.adminRole"),
    foreman: t("staff.foremanRole"),
  };

  function toggleStaffSelection(id: string) {
    setSelectedStaff((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  function toggleSelectAll() {
    if (selectedStaff.size === tabFilteredStaff.length && tabFilteredStaff.length > 0) {
      setSelectedStaff(new Set());
    } else {
      setSelectedStaff(new Set(tabFilteredStaff.map((m) => m.id)));
    }
  }

  async function suspendSelected() {
    // Deactivation locks workers out of the app immediately — never on a
    // bare mis-click, and never silently-partially on a mid-loop failure.
    const confirmed = window.confirm(
      `Deactivate ${selectedStaff.size} team member${selectedStaff.size === 1 ? "" : "s"}? ` +
        "They will lose access to the app until reactivated.",
    );
    if (!confirmed) return;

    const supabase = getSupabase();
    let done = 0;
    try {
      for (const id of selectedStaff) {
        const member = staff.find((entry) => entry.id === id);
        if (!member || (!isOwnerRole(viewerRole) && member.role === OWNER_ROLE)) continue;
        const { error: updateError } = await supabase
          .from("users")
          .update({ is_active: false })
          .eq("id", id);
        if (updateError) throw new Error(updateError.message);
        done += 1;
      }
      showToast(`Deactivated ${done} team member${done === 1 ? "" : "s"}`);
    } catch (err) {
      showToast(
        `Deactivated ${done} of ${selectedStaff.size} — ${err instanceof Error ? err.message : "then failed"}`,
        "error",
      );
    } finally {
      setSelectedStaff(new Set());
      loadStaff();
    }
  }

  function exportStaffCsv() {
    const header = "id,name,email,role,active";
    const rows = staff.map(
      (m) => `${m.id},"${m.full_name}","${m.email ?? ""}",${m.role},${m.is_active}`,
    );
    const csv = [header, ...rows].join("\n");
    const blob = new Blob([csv], { type: "text/csv" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "staff_export.csv";
    a.click();
    URL.revokeObjectURL(url);
  }

  if (accessDenied) {
    return (
      <div className="mt-20 text-center">
        <h2 className="text-xl font-bold text-slate-900">{t("common.accessDenied") || "Access denied"}</h2>
        <p className="mt-2 text-sm text-slate-500">
          {t("staffPage.adminOnly") || "Only owners and administrators can manage staff."}
        </p>
        <a href="/" className="mt-4 inline-block text-sm font-medium text-amber-600 hover:text-amber-700">
          &larr; {t("common.backToDashboard") || "Back to dashboard"}
        </a>
      </div>
    );
  }

  return (
    <div>
      {toast}
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">{t("staffPage.title")}</h1>
          <p className="mt-1 text-sm text-slate-500">
            {t("staffPage.summary", { active: activeCount, total: staff.length })}
          </p>
        </div>
        <button
          onClick={startAdd}
          className="rounded-xl bg-slate-900 px-5 py-2.5 text-sm font-semibold text-white shadow-sm hover:bg-slate-800"
        >
          + {t("staffPage.addStaff")}
        </button>
      </div>

      {/* Role tab bar */}
      <div className="mb-5 flex gap-1 rounded-xl bg-stone-100 p-1">
        {ROLE_TABS.map((tab) => {
          const count = tab.roles.length === 0
            ? staff.length
            : staff.filter((m) => tab.roles.includes(m.role)).length;
          return (
            <button
              key={tab.key}
              onClick={() => setActiveRoleTab(tab.key)}
              className={`flex-1 rounded-lg px-3 py-2 text-sm font-semibold transition-all ${
                activeRoleTab === tab.key
                  ? "bg-card text-slate-900 shadow-sm"
                  : "text-slate-500 hover:text-slate-700"
              }`}
            >
              {tab.label}
              <span className={`ml-1.5 rounded-full px-1.5 py-0.5 text-xs font-bold ${
                activeRoleTab === tab.key ? "bg-amber-100 text-amber-700" : "bg-stone-200 text-slate-500"
              }`}>
                {count}
              </span>
            </button>
          );
        })}
      </div>

      {/* Bulk action bar */}
      {selectedStaff.size > 0 && (
        <div className="mb-4 flex items-center gap-3 rounded-xl border border-amber-200 bg-amber-50 p-3">
          <button
            onClick={suspendSelected}
            className="rounded-lg bg-red-500 px-4 py-2 text-xs font-semibold text-white hover:bg-red-600"
          >
            {t("staff.suspendSelected")} ({selectedStaff.size})
          </button>
          <button
            onClick={exportStaffCsv}
            className="rounded-lg border border-stone-300 bg-card px-4 py-2 text-xs font-semibold text-slate-700 hover:bg-stone-50"
          >
            {t("staff.exportList")}
          </button>
        </div>
      )}

      <div className="flex gap-6">
        <div className="flex-1">
          {loading && (
            <div className="flex items-center gap-2 text-sm text-slate-500">
              <div className="h-4 w-4 animate-spin rounded-full border-2 border-stone-200 border-t-slate-900" />
              {t("staffPage.loading")}
            </div>
          )}

          {!loading && tabFilteredStaff.length === 0 && (
            <div className="rounded-2xl border-2 border-dashed border-stone-200 bg-card p-10 text-center">
              <p className="text-sm text-slate-500">
                {staff.length === 0 ? t("staffPage.noStaff") : `No ${ROLE_TABS.find(t => t.key === activeRoleTab)?.label ?? ""} members yet.`}
              </p>
              {staff.length === 0 && (
                <button
                  onClick={startAdd}
                  className="mt-3 rounded-lg bg-slate-900 px-5 py-2 text-sm font-semibold text-white"
                >
                  + {t("staffPage.addFirstStaff")}
                </button>
              )}
            </div>
          )}

          {/* Select all header */}
          {tabFilteredStaff.length > 0 && (
            <div className="mb-2 flex items-center gap-2 px-1">
              <input
                type="checkbox"
                checked={selectedStaff.size === tabFilteredStaff.length && tabFilteredStaff.length > 0}
                onChange={toggleSelectAll}
                className="h-4 w-4 rounded border-stone-300 accent-slate-900"
              />
              <span className="text-xs font-medium text-slate-500">{t("staff.selectAll")}</span>
            </div>
          )}

          <div className="space-y-2">
            {tabFilteredStaff.map((member) => {
              const isEditing = editing?.id === member.id;
              const isChecked = selectedStaff.has(member.id);
              return (
                <div key={member.id} className="flex items-center gap-2">
                  <input
                    type="checkbox"
                    checked={isChecked}
                    onChange={() => toggleStaffSelection(member.id)}
                    className="h-4 w-4 flex-shrink-0 rounded border-stone-300 accent-slate-900"
                  />
                  <button
                    onClick={() => startEdit(member)}
                    className={`w-full rounded-xl border p-4 text-left transition-all ${
                      isEditing
                        ? "border-slate-900 bg-slate-50 shadow-sm"
                        : "border-stone-200 bg-card hover:border-stone-300 hover:shadow-sm"
                    }`}
                  >
                    <div className="flex items-center justify-between">
                      <div>
                        <div className="flex items-center gap-2">
                          <span className="font-semibold text-slate-900">{member.full_name}</span>
                          {!member.is_active && (
                            <span className="rounded-full bg-red-50 px-2 py-0.5 text-xs font-bold text-red-500">
                              {t("staffPage.inactive")}
                            </span>
                          )}
                        </div>
                        <div className="mt-0.5 text-xs text-slate-500">
                          {member.email ?? member.phone ?? t("staffPage.noContact")}
                        </div>
                      </div>
                      {/* Role badge with tooltip */}
                      <div className="group relative">
                        <span
                          className={`rounded-full px-2.5 py-1 text-xs font-bold uppercase tracking-wide ${
                            member.role === OWNER_ROLE
                              ? "bg-amber-100 text-amber-800"
                              : member.role === ADMIN_ROLE
                              ? "bg-purple-50 text-purple-600"
                              : member.role === "supervisor"
                                ? "bg-blue-50 text-blue-600"
                                : member.role === "foreman"
                                  ? "bg-amber-50 text-amber-600"
                                  : "bg-stone-100 text-slate-500"
                          }`}
                        >
                          {roleLabel(member.role)}
                        </span>
                        <div className="absolute bottom-full right-0 z-10 mb-2 hidden w-56 rounded-lg border border-stone-200 bg-card p-2.5 text-xs text-slate-600 shadow-lg group-hover:block">
                          {ROLE_TOOLTIPS[member.role] ?? member.role}
                        </div>
                      </div>
                    </div>
                  </button>
                </div>
              );
            })}
          </div>
        </div>

        {editing && (
          <div className="w-96 flex-shrink-0">
            <div className="sticky top-6 rounded-2xl border border-stone-200 bg-card p-6 shadow-sm">
              <div className="mb-5 flex items-center justify-between">
                <h2 className="text-sm font-bold uppercase tracking-wider text-slate-500">
                  {showAdd ? t("staffPage.addStaffPanel") : t("staffPage.editStaffPanel")}
                </h2>
                <button
                  onClick={() => {
                    setEditing(null);
                    setShowAdd(false);
                  }}
                  className="text-xs text-slate-500 hover:text-slate-600"
                >
                  {t("staffPage.close")}
                </button>
              </div>

              <div className="space-y-4">
                <EditField
                  label={t("staffPage.fullName")}
                  value={editing.fullName}
                  onChange={(value) => setEditing({ ...editing, fullName: value })}
                  required
                />
                <EditField
                  label={t("staffPage.email")}
                  value={editing.email}
                  onChange={(value) => setEditing({ ...editing, email: value })}
                  type="email"
                />
                <EditField
                  label={t("staffPage.phone")}
                  value={editing.phone}
                  onChange={(value) => setEditing({ ...editing, phone: value })}
                  type="tel"
                />
                <EditField
                  label={t("staffPage.address")}
                  value={editing.address}
                  onChange={(value) => setEditing({ ...editing, address: value })}
                  placeholder={t("staffPage.optional")}
                />
                <EditField
                  label={t("staffPage.driverLicense")}
                  value={editing.driverLicense}
                  onChange={(value) => setEditing({ ...editing, driverLicense: value })}
                  placeholder={t("staffPage.optional")}
                />
                <EditField
                  label={t("staffPage.notes")}
                  value={editing.notes}
                  onChange={(value) => setEditing({ ...editing, notes: value })}
                  placeholder={t("staffPage.placeholders.notes")}
                />

                <div>
                  <label className="mb-2 block text-xs font-semibold text-slate-600">
                    {t("staffPage.permissionLevel")}
                  </label>
                  <div className="space-y-2">
                    {assignableRoles.map((role) => (
                      <button
                        key={role.value}
                        onClick={() => setEditing({ ...editing, role: role.value })}
                        disabled={editing.role === OWNER_ROLE && !isOwnerRole(viewerRole)}
                        className={`w-full rounded-lg border p-3 text-left transition-all ${
                          editing.role === role.value
                            ? "border-slate-900 bg-slate-50"
                            : "border-stone-200 hover:border-stone-300"
                        } ${editing.role === OWNER_ROLE && !isOwnerRole(viewerRole) ? "cursor-not-allowed opacity-60" : ""}`}
                      >
                        <div className="flex items-center justify-between">
                          <span className="text-sm font-semibold text-slate-900">{role.label}</span>
                          {editing.role === role.value && (
                            <span className="text-xs font-bold text-slate-900">✓</span>
                          )}
                        </div>
                        <p className="mt-0.5 text-xs text-slate-500">{role.description}</p>
                      </button>
                    ))}
                  </div>
                </div>

                {!showAdd && (
                  <div className="flex items-center justify-between rounded-lg border border-stone-200 p-3">
                    <div>
                      <span className="text-sm font-medium text-slate-700">{t("staffPage.activeStatus")}</span>
                      <p className="text-xs text-slate-500">{t("staffPage.activeStatusHint")}</p>
                    </div>
                    <button
                      onClick={() => setEditing({ ...editing, isActive: !editing.isActive })}
                      className={`relative h-6 w-11 rounded-full transition-colors ${
                        editing.isActive ? "bg-green-500" : "bg-stone-300"
                      }`}
                    >
                      <span
                        className={`absolute top-0.5 h-5 w-5 rounded-full bg-card shadow-sm transition-transform ${
                          editing.isActive ? "translate-x-5" : "translate-x-0.5"
                        }`}
                      />
                    </button>
                  </div>
                )}

                <div className="pt-2">
                  {inviteError && (
                    <p className="mb-2 text-center text-sm font-medium text-red-500">
                      {inviteError}
                    </p>
                  )}
                  {saved && (
                    <p className="mb-2 text-center text-sm font-medium text-green-600">
                      {showAdd
                        ? emailSent
                          ? `Invite emailed to ${editing.email}`
                          : `Member created — share the activation link below.`
                        : t("staffPage.saved")}
                    </p>
                  )}
                  {inviteLink && (
                    <div className="mb-3 rounded-xl border border-amber-200 bg-amber-50 p-3 text-xs dark:border-amber-900/40 dark:bg-amber-950/30">
                      <p className="mb-2 font-semibold text-amber-800 dark:text-amber-300">
                        Email couldn&apos;t be delivered. Copy this link and
                        share it with {editing.fullName} (SMS, WhatsApp, or
                        your own email):
                      </p>
                      <div className="flex items-center gap-2">
                        <input
                          readOnly
                          value={inviteLink}
                          onFocus={(e) => e.currentTarget.select()}
                          className="flex-1 rounded-md border border-amber-300 bg-card px-2 py-1.5 font-mono text-xs text-slate-700 dark:border-amber-900/60 dark:bg-slate-900 dark:text-slate-200"
                        />
                        <button
                          type="button"
                          onClick={async () => {
                            try {
                              await navigator.clipboard.writeText(inviteLink);
                              setSaved(true);
                              setTimeout(() => setSaved(false), 1500);
                            } catch {
                              /* ignore */
                            }
                          }}
                          className="rounded-md bg-amber-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-amber-700"
                        >
                          Copy
                        </button>
                      </div>
                      <button
                        type="button"
                        onClick={() => {
                          setInviteLink(null);
                          setEditing(null);
                          setShowAdd(false);
                          loadStaff();
                        }}
                        className="mt-2 w-full rounded-md bg-card px-3 py-1.5 text-xs font-semibold text-slate-700 hover:bg-stone-50 dark:bg-slate-900 dark:text-slate-200 dark:hover:bg-slate-800"
                      >
                        Done
                      </button>
                    </div>
                  )}
                  {!inviteLink && (
                    <button
                      onClick={saveStaff}
                      disabled={!editing.fullName.trim()}
                      className="w-full rounded-xl bg-slate-900 py-3 text-sm font-semibold text-white shadow-sm hover:bg-slate-800 disabled:bg-stone-100 disabled:text-slate-400 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-card"
                    >
                      {showAdd ? t("staffPage.addStaffMember") : t("staffPage.saveChanges")}
                    </button>
                  )}
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function EditField({
  label,
  value,
  onChange,
  placeholder,
  type = "text",
  required = false,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  type?: string;
  required?: boolean;
}) {
  return (
    <div>
      <label className="mb-1 block text-xs font-semibold text-slate-600">
        {label}
        {required && <span className="text-red-400"> *</span>}
      </label>
      <input
        type={type}
        value={value}
        onChange={(event) => onChange(event.target.value)}
        placeholder={placeholder}
        className="w-full rounded-lg border border-stone-200 bg-stone-50 px-3 py-2.5 text-sm transition-colors focus:border-slate-900 focus:bg-card focus:outline-none"
      />
    </div>
  );
}
