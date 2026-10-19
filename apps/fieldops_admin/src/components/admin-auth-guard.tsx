"use client";

import { useEffect, useState, useCallback, type ReactNode } from "react";
import { getSupabase } from "@/lib/supabase";
import type { Session } from "@supabase/supabase-js";

type AuthState = "loading" | "unauthenticated" | "denied" | "authorized";

export default function AdminAuthGuard({ children }: { children: ReactNode }) {
  const [state, setState] = useState<AuthState>("loading");
  const [session, setSession] = useState<Session | null>(null);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loginError, setLoginError] = useState("");
  const [loginLoading, setLoginLoading] = useState(false);

  const checkAuth = useCallback(async () => {
    const sb = getSupabase();
    const {
      data: { session: s },
    } = await sb.auth.getSession();

    if (!s) {
      setState("unauthenticated");
      return;
    }

    setSession(s);

    try {
      const baseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
      const res = await fetch(
        `${baseUrl}/functions/v1/platform_admin?action=list_admins`,
        {
          headers: { Authorization: `Bearer ${s.access_token}` },
        }
      );

      if (!res.ok) {
        setState("denied");
        return;
      }

      const data = await res.json();
      const admins = data.admins ?? data;
      const callerEmail = s.user.email?.toLowerCase();
      const isAdmin = Array.isArray(admins)
        ? admins.some(
            (a: { email: string }) => a.email.toLowerCase() === callerEmail
          )
        : false;

      setState(isAdmin ? "authorized" : "denied");
    } catch {
      setState("denied");
    }
  }, []);

  useEffect(() => {
    checkAuth();

    const {
      data: { subscription },
    } = getSupabase().auth.onAuthStateChange((_event, s) => {
      if (s) {
        setSession(s);
        checkAuth();
      } else {
        setState("unauthenticated");
        setSession(null);
      }
    });

    return () => subscription.unsubscribe();
  }, [checkAuth]);

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoginError("");
    setLoginLoading(true);

    try {
      const { error } = await getSupabase().auth.signInWithPassword({
        email,
        password,
      });
      if (error) {
        setLoginError(error.message);
      }
    } catch {
      setLoginError("An unexpected error occurred");
    } finally {
      setLoginLoading(false);
    }
  };

  const handleSignOut = async () => {
    await getSupabase().auth.signOut();
    setState("unauthenticated");
    setSession(null);
  };

  if (state === "loading") {
    return (
      <div className="flex h-screen items-center justify-center bg-stone-50">
        <div className="text-stone-400">Loading...</div>
      </div>
    );
  }

  if (state === "unauthenticated") {
    return (
      <div className="flex h-screen items-center justify-center bg-stone-50">
        <div className="w-full max-w-sm rounded-lg border border-stone-200 bg-white p-8 shadow-sm">
          <h1 className="mb-1 text-xl font-semibold text-stone-900">
            FieldOps Admin
          </h1>
          <p className="mb-6 text-sm text-stone-500">
            Sign in to continue
          </p>

          <form onSubmit={handleLogin} className="space-y-4">
            <div>
              <label className="mb-1 block text-sm font-medium text-stone-700">
                Email
              </label>
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                className="w-full rounded-md border border-stone-300 px-3 py-2 text-sm text-stone-900 placeholder-stone-400 focus:border-amber-500 focus:outline-none focus:ring-1 focus:ring-amber-500"
                placeholder="admin@fieldops.ai"
              />
            </div>

            <div>
              <label className="mb-1 block text-sm font-medium text-stone-700">
                Password
              </label>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                className="w-full rounded-md border border-stone-300 px-3 py-2 text-sm text-stone-900 placeholder-stone-400 focus:border-amber-500 focus:outline-none focus:ring-1 focus:ring-amber-500"
                placeholder="********"
              />
            </div>

            {loginError && (
              <p className="text-sm text-red-600">{loginError}</p>
            )}

            <button
              type="submit"
              disabled={loginLoading}
              className="w-full rounded-md bg-amber-500 px-4 py-2 text-sm font-medium text-white hover:bg-amber-600 disabled:opacity-50"
            >
              {loginLoading ? "Signing in..." : "Sign in"}
            </button>
          </form>
        </div>
      </div>
    );
  }

  if (state === "denied") {
    return (
      <div className="flex h-screen flex-col items-center justify-center gap-4 bg-stone-50">
        <div className="rounded-lg border border-red-200 bg-red-50 p-8 text-center">
          <h1 className="mb-2 text-lg font-semibold text-red-900">
            Access Denied
          </h1>
          <p className="mb-4 text-sm text-red-700">
            {session?.user.email} is not a platform administrator.
          </p>
          <button
            onClick={handleSignOut}
            className="rounded-md bg-stone-800 px-4 py-2 text-sm font-medium text-white hover:bg-stone-700"
          >
            Sign out
          </button>
        </div>
      </div>
    );
  }

  return <>{children}</>;
}
