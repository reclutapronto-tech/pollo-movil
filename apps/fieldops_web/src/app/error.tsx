"use client";

import { useEffect } from "react";
import * as Sentry from "@sentry/nextjs";

/**
 * Route-segment error boundary. Catches render/effect crashes inside any
 * page under the root layout (global-error.tsx only fires when the root
 * layout itself crashes) and reports them before offering a retry.
 */
export default function RouteError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    Sentry.captureException(error);
  }, [error]);

  return (
    <div className="flex min-h-[50vh] items-center justify-center p-6">
      <div className="max-w-md rounded-2xl border border-red-200 bg-red-50 p-6 text-center dark:border-red-900 dark:bg-red-950/30">
        <h2 className="text-lg font-semibold text-red-800 dark:text-red-300">
          Something went wrong
        </h2>
        <p className="mt-2 text-sm text-red-700 dark:text-red-400">
          The error has been reported automatically.
          {error.digest ? ` Reference: ${error.digest}` : ""}
        </p>
        <button
          onClick={reset}
          className="mt-4 rounded-lg bg-red-600 px-4 py-2 text-sm font-semibold text-white hover:bg-red-700"
        >
          Try again
        </button>
      </div>
    </div>
  );
}
