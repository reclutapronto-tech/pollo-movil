"use client";

import type { ReactNode } from "react";
import { AuthGuard } from "@/components/auth-guard";
import { Sidebar } from "@/components/sidebar";
import { usePathname } from "next/navigation";

export function AppShell({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const isPlatformRoute = pathname === "/platform" || pathname.startsWith("/platform/");
  return (
    <AuthGuard>
      <div className="flex h-screen overflow-hidden">
        {!isPlatformRoute && <Sidebar />}
        <main className="flex-1 overflow-y-auto">
          <div className="mx-auto max-w-7xl px-6 py-6">{children}</div>
        </main>
      </div>
    </AuthGuard>
  );
}
