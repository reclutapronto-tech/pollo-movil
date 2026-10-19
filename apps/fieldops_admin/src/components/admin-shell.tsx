"use client";

import type { ReactNode } from "react";
import { usePathname } from "next/navigation";
import AdminAuthGuard from "@/components/admin-auth-guard";
import AdminSidebar from "@/components/admin-sidebar";

export default function AdminShell({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const isPublicRoute = pathname === "/login" || pathname === "/claim";

  if (isPublicRoute) {
    return <main className="min-h-screen">{children}</main>;
  }

  return (
    <AdminAuthGuard>
      <div className="flex h-screen">
        <AdminSidebar />
        <main className="flex-1 overflow-y-auto p-8">{children}</main>
      </div>
    </AdminAuthGuard>
  );
}
