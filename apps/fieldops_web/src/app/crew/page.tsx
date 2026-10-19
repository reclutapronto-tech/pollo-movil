"use client";

// /crew was merged into /workers in Sprint 8.10.z to remove the redundant
// sidebar entry. The /crew edge function still exists and is useful for
// foreman-scoped roster queries — it just no longer needs its own page.
// Redirect any bookmarks / direct links to the canonical /workers page.

import { useEffect } from "react";
import { useRouter } from "next/navigation";

export default function CrewRedirect() {
  const router = useRouter();

  useEffect(() => {
    router.replace("/workers");
  }, [router]);

  return (
    <div className="flex min-h-[60vh] items-center justify-center text-sm text-slate-500 dark:text-slate-400">
      Redirecting to Workers…
    </div>
  );
}
