"use client";

import { useEffect, useState } from "react";
import { getSupabase } from "@/lib/supabase";

interface CurrentUser {
  userId: string | null;
  email: string | null;
  role: string | null;
  companyId: string | null;
  companyLogoUrl: string | null;
  companyName: string | null;
  loading: boolean;
}

export function useCurrentUser(): CurrentUser {
  const [state, setState] = useState<CurrentUser>({
    userId: null,
    email: null,
    role: null,
    companyId: null,
    companyLogoUrl: null,
    companyName: null,
    loading: true,
  });

  useEffect(() => {
    let mounted = true;

    async function load() {
      try {
        const supabase = getSupabase();
        const { data: sessionData } = await supabase.auth.getSession();
        const session = sessionData.session;

        if (!session?.user) {
          if (mounted) setState((prev) => ({ ...prev, loading: false }));
          return;
        }

        const userId = session.user.id;
        const email = session.user.email ?? null;

        // Fetch user record for role + company_id
        const { data: userRow } = await supabase
          .from("users")
          .select("role, company_id")
          .eq("id", userId)
          .maybeSingle();

        if (!mounted) return;

        const role = userRow?.role ?? null;
        const companyId = userRow?.company_id ?? null;

        let companyLogoUrl: string | null = null;
        let companyName: string | null = null;

        if (companyId) {
          const { data: company } = await supabase
            .from("companies")
            .select("name, logo_url")
            .eq("id", companyId)
            .maybeSingle();

          if (company) {
            companyLogoUrl = company.logo_url ?? null;
            companyName = company.name ?? null;
          }
        }

        if (mounted) {
          setState({
            userId,
            email,
            role,
            companyId,
            companyLogoUrl,
            companyName,
            loading: false,
          });
        }
      } catch {
        if (mounted) {
          setState((prev) => ({ ...prev, loading: false }));
        }
      }
    }

    load();
    return () => {
      mounted = false;
    };
  }, []);

  return state;
}

export function useRequireRole(allowedRoles: string[]): {
  allowed: boolean;
  loading: boolean;
} {
  const { role, loading } = useCurrentUser();

  if (loading) return { allowed: false, loading: true };
  if (!role) return { allowed: false, loading: false };

  return { allowed: allowedRoles.includes(role), loading: false };
}
