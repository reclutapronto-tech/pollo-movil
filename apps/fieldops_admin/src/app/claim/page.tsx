import { Suspense } from "react";
import ClaimInviteForm from "@/components/claim-invite-form";

export default function ClaimInvitePage() {
  return (
    <div className="flex min-h-screen items-center justify-center bg-stone-50 px-4">
      <Suspense
        fallback={
          <div className="w-full max-w-md rounded-xl border border-stone-200 bg-white p-8 text-sm text-stone-500 shadow-sm">
            Loading invite...
          </div>
        }
      >
        <ClaimInviteForm />
      </Suspense>
    </div>
  );
}
