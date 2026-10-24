"use client";

import { useEffect, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { getSupabase } from "@/lib/supabase";

type ViewState = "loading" | "ready" | "invalid" | "done";

export default function AcceptCompanyInvitePage() {
  const router = useRouter();
  const [state, setState] = useState<ViewState>("loading");
  const [email, setEmail] = useState("");
  const [invitationId, setInvitationId] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [message, setMessage] = useState("");
  const [working, setWorking] = useState(false);

  useEffect(() => {
    let cancelled = false;
    async function initialize() {
      try {
        const supabase = getSupabase();
        const url = new URL(window.location.href);
        const id = url.searchParams.get("invitation") || "";
        setInvitationId(id);
        if (!/^[0-9a-f-]{36}$/i.test(id)) throw new Error("invalid_invitation")

        const fragment = new URLSearchParams(url.hash.replace(/^#/, ""));
        if (fragment.has("error") || fragment.has("error_code")) throw new Error("invalid_link")
        const code = url.searchParams.get("code");
        const tokenHash = url.searchParams.get("token_hash");
        const tokenType = url.searchParams.get("type");

        if (code) {
          const { error } = await supabase.auth.exchangeCodeForSession(code);
          if (error) throw new Error("invalid_link");
        } else if (fragment.has("access_token") && fragment.has("refresh_token")) {
          const { error } = await supabase.auth.setSession({
            access_token: fragment.get("access_token")!,
            refresh_token: fragment.get("refresh_token")!,
          });
          if (error) throw new Error("invalid_link");
        } else if (tokenHash && (tokenType === "invite" || tokenType === "recovery")) {
          const { error } = await supabase.auth.verifyOtp({
            token_hash: tokenHash, type: tokenType === "invite" ? "invite" : "recovery",
          });
          if (error) throw new Error("invalid_link");
        }

        // Remove one-time credentials from browser history immediately after
        // Supabase consumes them; retain only the non-secret invitation ID.
        window.history.replaceState({}, document.title, `${url.pathname}?invitation=${encodeURIComponent(id)}`);
        const { data: userResult, error: userError } = await supabase.auth.getUser();
        if (userError || !userResult.user?.email) throw new Error("authentication_required");
        if (cancelled) return;
        setEmail(userResult.user.email);
        setState("ready");
      } catch {
        if (cancelled) return;
        setMessage("El enlace no es válido, ya venció o no pudo verificarse. Solicita una nueva invitación al administrador de la plataforma.");
        setState("invalid");
      }
    }
    void initialize();
    return () => { cancelled = true; };
  }, []);

  async function accept(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (password.length < 8) { setMessage("La contraseña debe tener al menos 8 caracteres."); return; }
    if (password !== confirmPassword) { setMessage("Las contraseñas no coinciden."); return; }
    setWorking(true); setMessage("");
    try {
      const supabase = getSupabase();
      const { error: passwordError } = await supabase.auth.updateUser({ password });
      if (passwordError) throw new Error("No se pudo guardar la contraseña. Vuelve a solicitar el enlace si ya venció.");
      const { data: sessionData } = await supabase.auth.getSession();
      const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
      const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
      if (!sessionData.session || !supabaseUrl || !anonKey) throw new Error("La sesión verificada ya no está disponible.");

      const response = await fetch(`${supabaseUrl}/functions/v1/platform_admin`, {
        method: "POST",
        headers: { Authorization: `Bearer ${sessionData.session.access_token}`, apikey: anonKey, "Content-Type": "application/json" },
        body: JSON.stringify({ action: "claim_company_admin_invite", invitation_id: invitationId }),
      });
      const result = await response.json().catch(() => null);
      if (!response.ok) throw new Error(result?.message || "No se pudo activar el acceso. Contacta al administrador de la plataforma.");
      if (result?.status !== "success") throw new Error("La invitación no pudo ser confirmada.");
      setState("done");
      setMessage(`La cuenta ${email} quedó vinculada a la empresa. Inicia sesión para continuar.`);
      await supabase.auth.signOut();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "No se pudo aceptar la invitación.");
    } finally { setWorking(false); }
  }

  return <main className="flex min-h-screen items-center justify-center bg-stone-50 px-4 py-8 text-slate-900">
    <section className="w-full max-w-lg rounded-2xl border border-stone-200 bg-white p-6 shadow-sm sm:p-8">
      <p className="text-sm font-bold uppercase tracking-wide text-amber-700">Pollo Móvil</p>
      <h1 className="mt-2 text-2xl font-bold">Activar acceso corporativo</h1>
      {state === "loading" && <p role="status" className="mt-4 text-sm text-slate-600">Validando el enlace seguro…</p>}
      {state === "ready" && <>
        <p className="mt-3 text-sm text-slate-600">Correo verificado: <strong>{email}</strong>. Establece tu propia contraseña para aceptar la invitación. La cuenta se asignará únicamente a la empresa que emitió este enlace.</p>
        <form className="mt-5 space-y-4" onSubmit={(event) => void accept(event)}>
          <label className="block text-sm font-medium">Nueva contraseña<input required minLength={8} type="password" autoComplete="new-password" className="mt-1 min-h-11 w-full rounded-lg border border-stone-300 px-3" value={password} onChange={(event) => setPassword(event.target.value)} /></label>
          <label className="block text-sm font-medium">Confirmar contraseña<input required minLength={8} type="password" autoComplete="new-password" className="mt-1 min-h-11 w-full rounded-lg border border-stone-300 px-3" value={confirmPassword} onChange={(event) => setConfirmPassword(event.target.value)} /></label>
          <button disabled={working} className="min-h-11 w-full rounded-lg bg-amber-600 px-4 py-2 font-semibold text-white disabled:opacity-50">{working ? "Activando…" : "Establecer contraseña y aceptar"}</button>
        </form>
      </>}
      {(state === "invalid" || state === "done") && <div className={`mt-4 rounded-xl p-3 text-sm ${state === "done" ? "bg-emerald-50 text-emerald-800" : "bg-amber-50 text-amber-900"}`} role={state === "done" ? "status" : "alert"}>{message}</div>}
      {state === "invalid" && <button onClick={() => router.replace("/")} className="mt-4 min-h-10 rounded-lg border px-4 text-sm font-semibold">Ir al inicio de sesión</button>}
      {state === "ready" && message && <p role="alert" className="mt-4 rounded-lg bg-red-50 p-3 text-sm text-red-800">{message}</p>}
      {state === "done" && <button onClick={() => router.replace("/")} className="mt-4 min-h-10 rounded-lg border px-4 text-sm font-semibold">Volver al acceso</button>}
    </section>
  </main>;
}
