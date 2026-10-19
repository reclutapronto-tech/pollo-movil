"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { usePathname } from "next/navigation";
import { getSupabase } from "@/lib/supabase";
import { signOut } from "@/lib/auth";
import { useI18n, type Locale } from "@/lib/i18n";
import { isManagementRole, isSupervisorOrAbove } from "@/lib/roles";
import {
  ChevronLeft,
  Menu,
  Search,
  X,
  Moon,
  Sun,
} from "lucide-react";
import { useTheme } from "@/lib/theme";
import { NAV_ITEMS, NAV_SECTIONS } from "@/lib/nav-items";
import { AlertBell } from "@/components/alert-bell";

const STORAGE_KEY = "sidebar_collapsed";

/* ------------------------------------------------------------------ */
/*  Sidebar Component                                                  */
/* ------------------------------------------------------------------ */

export function Sidebar() {
  const pathname = usePathname();
  const [userEmail, setUserEmail] = useState<string | null>(null);
  const [userRole, setUserRole] = useState<string | null>(null);
  const [companyLogoUrl, setCompanyLogoUrl] = useState<string | null>(null);
  const { locale, setLocale, t } = useI18n();
  const { resolved: resolvedTheme, toggle: toggleTheme } = useTheme();

  /* ---------- collapse state (persisted) ---------- */
  const [collapsed, setCollapsed] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);

  useEffect(() => {
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      if (stored === "true") setCollapsed(true);
    } catch {
      /* SSR / localStorage unavailable */
    }
  }, []);

  const toggleCollapsed = () => {
    setCollapsed((prev) => {
      const next = !prev;
      try {
        localStorage.setItem(STORAGE_KEY, String(next));
      } catch {
        /* ignore */
      }
      return next;
    });
  };

  /* ---------- search state ---------- */
  const [searchQuery, setSearchQuery] = useState("");
  const [searchFocused, setSearchFocused] = useState(false);
  const searchRef = useRef<HTMLDivElement>(null);

  // Close search dropdown on outside click
  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (searchRef.current && !searchRef.current.contains(e.target as Node)) {
        setSearchFocused(false);
      }
    }
    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, []);

  /* ---------- auth state (cached to avoid refetch on every navigation) ---------- */
  const authLoadedRef = useRef(false);

  useEffect(() => {
    if (authLoadedRef.current) return; // Already loaded — skip redundant queries
    try {
      const supabase = getSupabase();
      supabase.auth.getSession().then(async ({ data }) => {
        setUserEmail(data.session?.user?.email ?? null);
        if (data.session?.user?.id) {
          const { data: user } = await supabase
            .from("users")
            .select("role, company_id")
            .eq("id", data.session.user.id)
            .maybeSingle();
          setUserRole(user?.role ?? null);
          if (user?.company_id) {
            const { data: company } = await supabase
              .from("companies")
              .select("logo_url")
              .eq("id", user.company_id)
              .maybeSingle();
            setCompanyLogoUrl(company?.logo_url ?? null);
          }
        }
        authLoadedRef.current = true;
      });
      const { data: listener } = supabase.auth.onAuthStateChange(
        (_event, session) => {
          setUserEmail(session?.user?.email ?? null);
          // Reset cache on sign-out / sign-in so role re-fetches
          if (_event === "SIGNED_OUT" || _event === "SIGNED_IN") {
            authLoadedRef.current = false;
          }
        },
      );
      return () => listener.subscription.unsubscribe();
    } catch {
      // Not configured
    }
  }, []);

  /* ---------- derived data ---------- */
  const canManageCompany = isManagementRole(userRole);
  const canSeeSupervisor = isSupervisorOrAbove(userRole);
  const visibleItems = NAV_ITEMS.filter((item) => {
    if (item.adminOnly && !canManageCompany) return false;
    if (item.supervisorOrAbove && !canSeeSupervisor) return false;
    return true;
  });

  const searchResults = useMemo(() => {
    if (!searchQuery.trim()) return [];
    const q = searchQuery.toLowerCase();
    return visibleItems.filter((item) => {
      const label = t(item.labelKey).toLowerCase();
      return label.includes(q);
    });
  }, [searchQuery, visibleItems, t]);

  const grouped = Object.entries(NAV_SECTIONS).map(([key, label]) => ({
    sectionKey: key,
    section: t(label),
    items: visibleItems.filter((item) => item.section === key),
  }));

  /* ---------- close mobile drawer on route change ---------- */
  useEffect(() => {
    setMobileOpen(false);
  }, [pathname]);

  /* ---------- render helpers ---------- */
  const sidebarContent = (isMobile: boolean) => {
    const isExpanded = isMobile || !collapsed;

    return (
      <>
        {/* Brand + Toggle */}
        <div className="flex items-center justify-between px-3 py-4">
          <div className="flex items-center gap-3 overflow-hidden">
            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-slate-900 text-sm font-bold tracking-tight text-white shadow-sm dark:bg-slate-100 dark:text-slate-900">
              F
            </div>
            {isExpanded && (
              <div className="min-w-0">
                <div className="truncate text-sm font-bold tracking-tight text-slate-900">
                  {t("shell.appName")}
                </div>
                <div className="text-xs font-medium text-slate-500">
                  {t("shell.commandCenter")}
                </div>
              </div>
            )}
          </div>
          {/* Desktop: alert bell + collapse toggle */}
          {!isMobile && (
            <div className="flex items-center gap-1">
              {isExpanded && <AlertBell compact />}
              <button
                onClick={toggleCollapsed}
                aria-label={collapsed ? t("shell.expandSidebar") : t("shell.collapseSidebar")}
                className="flex h-7 w-7 shrink-0 items-center justify-center rounded-md text-slate-500 transition-colors hover:bg-stone-100 hover:text-slate-600 dark:hover:bg-slate-800 dark:hover:text-slate-600"
              >
                {collapsed ? <Menu size={16} /> : <ChevronLeft size={16} />}
              </button>
            </div>
          )}
          {/* Mobile: alert bell + close */}
          {isMobile && (
            <div className="flex items-center gap-1">
              <AlertBell compact />
              <button
                onClick={() => setMobileOpen(false)}
                aria-label={t("shell.closeMenu")}
                className="flex h-11 w-11 items-center justify-center rounded-md text-slate-500 hover:bg-stone-100 hover:text-slate-700 dark:hover:bg-slate-800 dark:hover:text-slate-600"
              >
                <X size={18} />
              </button>
            </div>
          )}
        </div>

        {/* Search */}
        <div ref={!isMobile ? searchRef : undefined} className="relative px-3 pb-2">
          {isExpanded ? (
            <div className="relative">
              <Search size={14} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-slate-500" />
              <input
                type="text"
                placeholder={t("shell.searchPlaceholder")}
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                onFocus={() => setSearchFocused(true)}
                className="w-full rounded-lg border border-stone-200 bg-stone-50 py-1.5 pl-8 pr-3 text-xs text-slate-600 placeholder:text-slate-500 focus:border-amber-300 focus:outline-none focus:ring-1 focus:ring-amber-200"
              />
              {/* Search dropdown */}
              {searchFocused && searchQuery.trim() && (
                <div className="absolute left-0 right-0 top-full z-50 mt-1 rounded-lg border border-stone-200 bg-white py-1 shadow-lg">
                  {searchResults.length === 0 ? (
                    <div className="px-3 py-2 text-xs text-slate-500">
                      No results
                    </div>
                  ) : (
                    searchResults.map((item) => {
                      const Icon = item.icon;
                      return (
                        <a
                          key={item.href}
                          href={item.href}
                          className="flex items-center gap-2 px-3 py-2 text-xs text-slate-600 hover:bg-stone-50"
                          onClick={() => {
                            setSearchQuery("");
                            setSearchFocused(false);
                          }}
                        >
                          <Icon size={14} className="shrink-0 text-slate-500" />
                          <span>
                            {t("shell.searchGoTo")} {t(item.labelKey)}
                          </span>
                        </a>
                      );
                    })
                  )}
                </div>
              )}
            </div>
          ) : (
            <button
              onClick={() => {
                setCollapsed(false);
                try {
                  localStorage.setItem(STORAGE_KEY, "false");
                } catch {
                  /* ignore */
                }
              }}
              aria-label={t("shell.search")}
              className="flex h-8 w-8 items-center justify-center rounded-lg text-slate-500 transition-colors hover:bg-stone-100 hover:text-slate-600"
            >
              <Search size={16} />
            </button>
          )}
        </div>

        {/* Navigation */}
        <nav className="flex-1 overflow-y-auto px-3 py-2">
          {grouped.map((group) => (
            <div key={group.sectionKey} className="mb-4">
              {isExpanded && (
                <div className="mb-1 px-2 text-xs font-semibold uppercase tracking-widest text-slate-600">
                  {group.section}
                </div>
              )}
              {group.items.map((item) => {
                const Icon = item.icon;
                const isActive = pathname === item.href;
                const label = t(item.labelKey);

                return (
                  <a
                    key={item.href}
                    href={item.href}
                    title={!isExpanded ? label : undefined}
                    className={`group relative mb-px flex items-center rounded-lg transition-all duration-150 ${
                      isExpanded ? "gap-3 px-3 py-2" : "justify-center px-0 py-2"
                    } text-[13px] font-medium ${
                      isActive
                        ? "bg-slate-900 text-white shadow-sm"
                        : "text-slate-500 hover:bg-stone-50 hover:text-slate-900"
                    }`}
                  >
                    <Icon size={16} className="shrink-0" />
                    {isExpanded && (
                      <>
                        <span className="truncate">{label}</span>
                        {isActive && (
                          <div className="ml-auto h-1.5 w-1.5 shrink-0 rounded-full bg-amber-400" />
                        )}
                      </>
                    )}
                    {/* Tooltip when collapsed */}
                    {!isExpanded && (
                      <span className="pointer-events-none absolute left-full ml-2 hidden whitespace-nowrap rounded-md bg-slate-900 px-2 py-1 text-xs font-medium text-white shadow-lg group-hover:block">
                        {label}
                      </span>
                    )}
                  </a>
                );
              })}
            </div>
          ))}
        </nav>

        {/* Footer: language, theme, logo, user, sign-out */}
        <div className="border-t border-stone-100 px-3 py-4 dark:border-slate-800">
          {isExpanded ? (
            <>
              <label className="mb-2 block text-xs font-semibold uppercase tracking-widest text-slate-600 dark:text-slate-400">
                {t("shell.language")}
              </label>
              <select
                value={locale}
                onChange={(event) => setLocale(event.target.value as Locale)}
                className="mb-3 w-full rounded-lg border border-stone-200 bg-white px-2 py-1.5 text-xs font-medium text-slate-500 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-600"
              >
                <option value="en">{t("shell.english")}</option>
                <option value="es">{t("shell.spanish")}</option>
                <option value="th">{t("shell.thai")}</option>
              </select>
              <button
                onClick={toggleTheme}
                className="mb-3 flex w-full items-center gap-2 rounded-lg border border-stone-200 bg-white px-2 py-1.5 text-xs font-medium text-slate-500 transition-colors hover:bg-stone-50 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-600 dark:hover:bg-slate-800"
                aria-label={
                  resolvedTheme === "dark"
                    ? t("shell.switchToLight")
                    : t("shell.switchToDark")
                }
              >
                {resolvedTheme === "dark" ? (
                  <Sun size={14} />
                ) : (
                  <Moon size={14} />
                )}
                <span>
                  {resolvedTheme === "dark"
                    ? t("shell.lightMode")
                    : t("shell.darkMode")}
                </span>
              </button>
              {companyLogoUrl && (
                <img
                  src={companyLogoUrl}
                  alt=""
                  className="mb-2 h-8 w-8 rounded-lg object-contain"
                />
              )}
              {userEmail && (
                <div className="mb-2 truncate text-xs text-slate-500 dark:text-slate-400">
                  {userEmail}
                </div>
              )}
              {userEmail && (
                <button
                  onClick={() => signOut()}
                  className="w-full rounded-lg py-1.5 text-xs font-medium text-slate-500 transition-colors hover:bg-red-50 hover:text-red-500 dark:text-slate-400 dark:hover:bg-red-950/40 dark:hover:text-red-400"
                >
                  {t("shell.signOut")}
                </button>
              )}
            </>
          ) : (
            <div className="flex flex-col items-center gap-2">
              <button
                onClick={toggleTheme}
                aria-label={
                  resolvedTheme === "dark"
                    ? t("shell.switchToLight")
                    : t("shell.switchToDark")
                }
                title={
                  resolvedTheme === "dark"
                    ? t("shell.switchToLight")
                    : t("shell.switchToDark")
                }
                className="flex h-11 w-11 items-center justify-center rounded-lg text-slate-500 transition-colors hover:bg-stone-100 hover:text-slate-700 dark:text-slate-400 dark:hover:bg-slate-800 dark:hover:text-slate-200"
              >
                {resolvedTheme === "dark" ? <Sun size={18} /> : <Moon size={18} />}
              </button>
              {userEmail && (
                <button
                  onClick={() => signOut()}
                  aria-label={t("shell.signOut")}
                  title={t("shell.signOut")}
                  className="flex h-11 w-11 items-center justify-center rounded-lg text-slate-500 transition-colors hover:bg-red-50 hover:text-red-600 dark:text-slate-400 dark:hover:bg-red-950/40 dark:hover:text-red-400"
                >
                  <X size={18} />
                </button>
              )}
            </div>
          )}
        </div>
      </>
    );
  };

  /* ---------- render ---------- */
  return (
    <>
      {/* Mobile hamburger (visible only on small screens) */}
      <button
        onClick={() => setMobileOpen(true)}
        aria-label={t("shell.openMenu")}
        className="fixed left-3 top-3 z-40 flex h-11 w-11 items-center justify-center rounded-lg bg-white text-slate-700 shadow-md dark:bg-slate-900 dark:text-slate-200 md:hidden"
      >
        <Menu size={20} />
      </button>

      {/* Mobile overlay */}
      {mobileOpen && (
        <div
          className="fixed inset-0 z-40 bg-black/30 md:hidden"
          onClick={() => setMobileOpen(false)}
        />
      )}

      {/* Mobile drawer */}
      <aside
        className={`fixed inset-y-0 left-0 z-50 flex w-64 flex-col border-r border-stone-200 bg-white transition-transform duration-200 md:hidden ${
          mobileOpen ? "translate-x-0" : "-translate-x-full"
        }`}
      >
        {sidebarContent(true)}
      </aside>

      {/* Desktop sidebar */}
      <aside
        className={`hidden md:flex flex-col border-r border-stone-200 bg-white dark:border-slate-800 dark:bg-slate-900 transition-[width] duration-200 ${
          collapsed ? "w-14" : "w-56"
        }`}
      >
        {sidebarContent(false)}
      </aside>
    </>
  );
}
