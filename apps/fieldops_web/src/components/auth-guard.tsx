"use client";

import { useEffect, useState } from "react";
import { getSupabase } from "@/lib/supabase";
import { signIn } from "@/lib/auth";
import type { Session } from "@supabase/supabase-js";
import { BrandLogo } from "@/components/brand-logo";
import { useI18n } from "@/lib/i18n";
import { usePathname, useRouter } from "next/navigation";

export function AuthGuard({ children }: { children: React.ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [platformAdmin, setPlatformAdmin] = useState(false);
  const [roleLoading, setRoleLoading] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [signingIn, setSigningIn] = useState(false);
  const [resetSent, setResetSent] = useState(false);
  const [sendingReset, setSendingReset] = useState(false);
  const { t } = useI18n();
  const pathname = usePathname();
  const router = useRouter();
  const isPasswordResetRoute = pathname === "/reset-password";
  const isPublicGalleryRoute = pathname.startsWith("/g/");
  const isPlatformRoute = pathname === "/platform" || pathname.startsWith("/platform/");
  const isPolloRoute =
    pathname === "/restaurant" ||
    pathname.startsWith("/restaurant/") ||
    isPlatformRoute ||
    isPasswordResetRoute ||
    isPublicGalleryRoute;

  useEffect(() => {
    let mounted = true;
    const supabase = getSupabase();

    supabase.auth.getSession().then(({ data, error: sessionError }) => {
      if (!mounted) return; // component unmounted before promise resolved
      if (sessionError) {
        setError(sessionError.message);
      } else {
        setSession(data.session);
      }
      setLoading(false);
    });

    const { data: listener } = supabase.auth.onAuthStateChange(
      (_event, session) => {
        if (mounted) setSession(session);
      },
    );

    return () => {
      mounted = false;
      listener.subscription.unsubscribe();
    };
  }, []);

  useEffect(() => {
    let active = true;
    async function resolveAccess() {
      if (!session || isPasswordResetRoute || isPublicGalleryRoute) {
        setPlatformAdmin(false);
        setRoleLoading(false);
        return;
      }
      setRoleLoading(true);
      const { data, error } = await getSupabase().rpc("is_platform_admin");
      if (!active) return;
      const isAdmin = !error && data === true;
      setPlatformAdmin(isAdmin);
      setRoleLoading(false);
      if (isAdmin && !isPlatformRoute) router.replace("/platform");
      if (!isAdmin && isPlatformRoute) router.replace("/restaurant");
      else if (!isAdmin && !isPolloRoute) router.replace("/restaurant");
    }
    void resolveAccess();
    return () => { active = false; };
  }, [isPasswordResetRoute, isPlatformRoute, isPolloRoute, isPublicGalleryRoute, router, session]);

  async function handleSignIn(e: React.FormEvent) {
    e.preventDefault();
    setSigningIn(true);
    setError(null);
    try {
      await signIn(email, password);
    } catch (err) {
      setError(err instanceof Error ? err.message : t("auth.signInFailed"));
    } finally {
      setSigningIn(false);
    }
  }

  async function handleForgotPassword() {
    if (!email.trim()) {
      setError("Enter your email address above, then click Forgot password.");
      return;
    }
    setSendingReset(true);
    setError(null);
    try {
      const supabase = getSupabase();
      const { error: resetError } = await supabase.auth.resetPasswordForEmail(email.trim(), {
        redirectTo: `${window.location.origin}/reset-password`,
      });
      if (resetError) throw resetError;
      setResetSent(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to send reset email");
    } finally {
      setSendingReset(false);
    }
  }

  if (loading || (session && roleLoading)) {
    return (
      <div className="flex min-h-[60vh] items-center justify-center text-slate-500">
        <div className="h-5 w-5 animate-spin rounded-full border-2 border-slate-300 border-t-amber-500" />
        <span className="ml-3">{t("common.loading")}</span>
      </div>
    );
  }

  if (!session && !isPasswordResetRoute && !isPublicGalleryRoute) {
    return (
      <div className="mx-auto mt-20 max-w-md">
        <div className="rounded-2xl border border-stone-200 bg-card p-8 shadow-sm">
          <div className="mb-5 flex justify-center">
            <BrandLogo
              width={192}
              height={192}
              alt="Logotipo oficial de El Pollo Móvil"
              priority
              className="h-40 w-40 object-contain"
            />
          </div>
          <h2 className="text-xl font-bold text-slate-900">
            {t("auth.title")}
          </h2>
          <p className="mt-1 text-sm text-slate-500">
            {t("auth.subtitle")}
          </p>

          <form onSubmit={handleSignIn} className="mt-6 space-y-4">
            <div>
              <label
                htmlFor="email"
                className="block text-sm font-medium text-slate-700"
              >
                {t("auth.email")}
              </label>
              <input
                id="email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="mt-1 w-full rounded-xl border border-stone-300 px-4 py-2.5 text-sm focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30"
                required
              />
            </div>
            <div>
              <label
                htmlFor="password"
                className="block text-sm font-medium text-slate-700"
              >
                {t("auth.password")}
              </label>
              <input
                id="password"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="mt-1 w-full rounded-xl border border-stone-300 px-4 py-2.5 text-sm focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30"
                required
              />
            </div>

            {error && (
              <div className="rounded-lg bg-red-50 p-3 text-sm text-red-700">
                {error}
              </div>
            )}

            {resetSent && (
              <div className="rounded-lg bg-green-50 p-3 text-sm text-green-700">
                Password reset email sent. Check your inbox.
              </div>
            )}

            <button
              type="submit"
              disabled={signingIn}
              className="w-full rounded-xl bg-amber-500 px-4 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-amber-600 disabled:bg-stone-100 disabled:text-slate-400"
            >
              {signingIn ? t("auth.signingIn") : t("auth.signIn")}
            </button>

            <div className="text-center">
              <button
                type="button"
                onClick={handleForgotPassword}
                disabled={sendingReset}
                className="text-xs text-slate-500 hover:text-slate-600 disabled:bg-stone-100 disabled:text-slate-400"
              >
                {sendingReset ? "Sending…" : "Forgot password?"}
              </button>
            </div>
          </form>
        </div>
      </div>
    );
  }

  if (!isPolloRoute) {
    return (
      <div className="flex min-h-[60vh] items-center justify-center text-sm text-slate-500">
        Abriendo Pollo Móvil…
      </div>
    );
  }

  if (isPlatformRoute && !platformAdmin) {
    return <div className="p-8 text-sm text-slate-500">Validando acceso administrativo…</div>;
  }

  return <>{children}</>;
}
