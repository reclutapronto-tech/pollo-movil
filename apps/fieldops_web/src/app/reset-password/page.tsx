"use client";

import { type FormEvent, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabase } from "@/lib/supabase";

const inputClass = "mt-1 min-h-11 w-full rounded-lg border border-stone-300 bg-white px-3 text-sm text-slate-900 outline-none focus:border-amber-500 focus:ring-2 focus:ring-amber-100 dark:border-slate-700 dark:bg-slate-950 dark:text-slate-100";

export default function ResetPasswordPage() {
  const router = useRouter();
  const [ready, setReady] = useState(false);
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    let active = true;
    getSupabase().auth.getSession().then(({ data, error: sessionError }) => {
      if (!active) return;
      setReady(Boolean(data.session) && !sessionError);
      if (!data.session || sessionError) {
        setError("El enlace de invitación o recuperación no es válido o ya venció. Solicita uno nuevo desde Pollo Móvil.");
      }
    });
    return () => { active = false; };
  }, []);

  async function savePassword(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (saving || password.length < 8 || password !== confirmation) return;
    setSaving(true);
    setError(null);
    try {
      const { error: updateError } = await getSupabase().auth.updateUser({ password });
      if (updateError) throw updateError;
      router.replace("/restaurant");
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "No se pudo actualizar la contraseña.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <main className="mx-auto mt-16 max-w-md rounded-2xl border border-stone-200 bg-white p-7 shadow-sm dark:border-slate-800 dark:bg-slate-900">
      <p className="text-xs font-semibold uppercase tracking-[0.18em] text-amber-700">Pollo Móvil</p>
      <h1 className="mt-2 text-2xl font-bold">Crear una contraseña nueva</h1>
      <p className="mt-2 text-sm text-slate-500">La contraseña se actualizará en tu cuenta de Pollo Móvil.</p>
      {error && <p role="alert" className="mt-4 rounded-lg bg-rose-50 p-3 text-sm text-rose-700 dark:bg-rose-950/30 dark:text-rose-300">{error}</p>}
      {ready && <form className="mt-5 space-y-4" onSubmit={savePassword}>
        <label className="block text-sm font-medium">Contraseña nueva<input className={inputClass} type="password" autoComplete="new-password" minLength={8} required value={password} onChange={(event) => setPassword(event.target.value)} /></label>
        <label className="block text-sm font-medium">Confirmar contraseña<input className={inputClass} type="password" autoComplete="new-password" minLength={8} required value={confirmation} onChange={(event) => setConfirmation(event.target.value)} /></label>
        {confirmation && password !== confirmation && <p className="text-sm text-rose-600">Las contraseñas no coinciden.</p>}
        <button className="min-h-11 w-full rounded-lg bg-slate-900 px-4 text-sm font-semibold text-white disabled:opacity-50 dark:bg-amber-400 dark:text-slate-950" type="submit" disabled={saving || password.length < 8 || password !== confirmation}>{saving ? "Guardando…" : "Actualizar contraseña"}</button>
      </form>}
    </main>
  );
}
