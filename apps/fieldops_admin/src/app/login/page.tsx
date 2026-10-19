"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";

export default function LoginPage() {
  const router = useRouter();

  useEffect(() => {
    // Login is handled by AdminAuthGuard; redirect to dashboard
    router.replace("/");
  }, [router]);

  return null;
}
