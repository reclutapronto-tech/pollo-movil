"use client";

import Link from "next/link";
import { type FormEvent, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabase } from "@/lib/supabase";

const inputClass = "mt-1 min-h-11 w-full rounded-lg border border-stone-300 bg-white px-3 text-sm text-slate-900 outline-none focus:border-amber-500 focus:ring-2 focus:ring-amber-100 dark:border-slate-700 dark:bg-slate-950 dark:text-slate-100";

type RecoveryStatus = "checking" | "ready" | "invalid" | "unavailable";

function callbackError(): boolean {
  const query = new URLSearchParams(window.location.search);
  const fragment = new URLSearchParams(window.location.hash.replace(/^#/, ""));
  // Supabase returns rejected/expired email links in either location depending
  // on the auth flow. Never render or log the raw URL (it can contain tokens).
  return Boolean(
    query.get("error") || query.get("error_code") ||
    fragment.get("error") || fragment.get("error_code"),
  );
}

function hasExpiredImplicitSession(): boolean {
  const fragment = new URLSearchParams(window.location.hash.replace(/^#/, ""));
  const expiresAt = Number(fragment.get("expires_at"));
  if (Number.isFinite(expiresAt) && expiresAt > 0) return expiresAt * 1000 <= Date.now();

  const expiresIn = fragment.get("expires_in");
  if (expiresIn !== null && Number.isFinite(Number(expiresIn)) && Number(expiresIn) <= 0) return true;

  // Supabase implicit callbacks may carry only a JWT and its refresh token.
  // Inspect exp only as an early-expiry hint; Auth still validates the token.
  const accessToken = fragment.get("access_token");
  const payload = accessToken?.split(".")[1];
  if (!payload) return false;
  try {
    const base64 = payload.replace(/-/g, "+").replace(/_/g, "/");
    const parsed = JSON.parse(window.atob(base64)) as { exp?: unknown };
    return typeof parsed.exp === "number" && parsed.exp * 1000 <= Date.now();
  } catch {
    return false;
  }
}

function withAuthTimeout<T>(promise: Promise<T>, timeoutMs = 10_000): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error("Auth request timed out")), timeoutMs);
  });
  return Promise.race([promise, timeout]).finally(() => {
    if (timer) clearTimeout(timer);
  });
}

export default function ResetPasswordPage() {
  const router = useRouter();
  const [status, setStatus] = useState<RecoveryStatus>("checking");
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    let active = true;

    async function resolveRecovery() {
      if (callbackError() || hasExpiredImplicitSession()) {
        if (active) {
          setStatus("invalid");
          setError("Este enlace de recuperación ya venció o fue utilizado. Solicita uno nuevo desde Pollo Móvil.");
        }
        return;
      }

      try {
        // supabase-js detectSessionInUrl processes both PKCE `?code=...`
        // callbacks and implicit `#access_token=...&type=recovery` callbacks
        // during initialization. getSession waits for that processing; do not
        // exchange the code a second time because PKCE codes are single-use.
        const supabase = getSupabase();
        const { data, error: sessionError } = await withAuthTimeout(supabase.auth.getSession());
        if (!active) return;
        if (sessionError || !data.session) {
          setStatus("invalid");
          setError("El enlace de recuperación no es válido o ya venció. Solicita uno nuevo desde Pollo Móvil.");
          return;
        }

        // getSession reads the locally stored callback session. Ask Auth to
        // validate it before exposing the password form so expired/forged
        // implicit-flow fragments do not look usable in the UI.
        const { data: userData, error: userError } = await withAuthTimeout(supabase.auth.getUser());
        if (!active) return;
        if (userError || !userData.user) {
          setStatus("invalid");
          setError("La sesión de recuperación venció o ya no es válida. Solicita un enlace nuevo.");
          return;
        }
        setStatus("ready");
      } catch (cause) {
        if (!active) return;
        if (cause instanceof Error && cause.message.includes("Missing NEXT_PUBLIC_SUPABASE_")) {
          setStatus("unavailable");
          setError("La aplicación no tiene configurada la conexión de autenticación. Inténtalo más tarde.");
        } else {
          setStatus("invalid");
          setError("La sesión de recuperación venció o no se pudo validar. Solicita un enlace nuevo desde Pollo Móvil.");
        }
      }
    }

    void resolveRecovery();
    return () => { active = false; };
  }, []);

  async function savePassword(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (saving || password.length < 8 || password !== confirmation) return;
    setSaving(true);
    setError(null);
    try {
      const supabase = getSupabase();
      const { error: updateError } = await supabase.auth.updateUser({ password });
      if (updateError) {
        setStatus("invalid");
        setError("No se pudo actualizar la contraseña. El enlace puede haber vencido; solicita uno nuevo.");
        return;
      }

      // The requested outcome is to return to login, not to leave a reset
      // session open. Local sign-out avoids depending on another network call.
      await supabase.auth.signOut({ scope: "local" });
      router.replace("/");
    } catch {
      setError("No se pudo actualizar la contraseña. Vuelve a solicitar el enlace e inténtalo otra vez.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <main className="mx-auto mt-16 max-w-md rounded-2xl border border-stone-200 bg-white p-7 shadow-sm dark:border-slate-800 dark:bg-slate-900">
      <p className="text-xs font-semibold uppercase tracking-[0.18em] text-amber-700">Pollo Móvil</p>
      <h1 className="mt-2 text-2xl font-bold">Crear una contraseña nueva</h1>
      <p className="mt-2 text-sm text-slate-500">La contraseña se actualizará en tu cuenta de Pollo Móvil.</p>
      {status === "checking" && <p role="status" className="mt-5 text-sm text-slate-500">Validando el enlace…</p>}
      {error && <p role="alert" className="mt-4 rounded-lg bg-rose-50 p-3 text-sm text-rose-700 dark:bg-rose-950/30 dark:text-rose-300">{error}</p>}
      {status === "ready" && <form className="mt-5 space-y-4" onSubmit={savePassword}>
        <label className="block text-sm font-medium">Contraseña nueva<input className={inputClass} type="password" autoComplete="new-password" minLength={8} required value={password} onChange={(event) => setPassword(event.target.value)} /></label>
        <label className="block text-sm font-medium">Confirmar contraseña<input className={inputClass} type="password" autoComplete="new-password" minLength={8} required value={confirmation} onChange={(event) => setConfirmation(event.target.value)} /></label>
        {confirmation && password !== confirmation && <p className="text-sm text-rose-600">Las contraseñas no coinciden.</p>}
        <button className="min-h-11 w-full rounded-lg bg-slate-900 px-4 text-sm font-semibold text-white disabled:opacity-50 dark:bg-amber-400 dark:text-slate-950" type="submit" disabled={saving || password.length < 8 || password !== confirmation}>{saving ? "Guardando…" : "Actualizar contraseña"}</button>
      </form>}
      {(status === "invalid" || status === "unavailable") && <Link className="mt-5 inline-block text-sm font-medium text-amber-700 hover:underline" href="/">Volver al inicio de sesión</Link>}
    </main>
  );
}
