import * as React from "react";

import { cn } from "@/lib/utils";

interface PhotoStampCardProps {
  photoUrl: string;
  workerName: string;
  jobName?: string;
  timestamp: string;
  verificationCode?: string;
  onClick?: () => void;
  className?: string;
}

function formatTimestamp(iso: string): string {
  return new Date(iso).toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
}

function PhotoStampCard({
  photoUrl,
  workerName,
  jobName,
  timestamp,
  verificationCode,
  onClick,
  className,
}: PhotoStampCardProps) {
  return (
    <div
      data-slot="photo-stamp-card"
      role={onClick ? "button" : undefined}
      tabIndex={onClick ? 0 : undefined}
      onClick={onClick}
      onKeyDown={
        onClick
          ? (e: React.KeyboardEvent) => {
              if (e.key === "Enter" || e.key === " ") {
                e.preventDefault();
                onClick();
              }
            }
          : undefined
      }
      className={cn(
        "overflow-hidden rounded-2xl border border-stone-200 bg-white shadow-sm transition-shadow hover:shadow-md",
        onClick && "cursor-pointer",
        className,
      )}
    >
      {/* Photo thumbnail with metadata overlay */}
      <div className="relative bg-slate-100">
        {photoUrl ? (
          <img
            src={photoUrl}
            alt={`Photo by ${workerName}`}
            className="w-full object-cover"
            loading="lazy"
          />
        ) : (
          <div className="flex h-48 items-center justify-center text-4xl text-slate-300">
            <svg
              className="h-10 w-10"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={1.5}
                d="M2.25 15.75l5.159-5.159a2.25 2.25 0 013.182 0l5.159 5.159m-1.5-1.5l1.409-1.409a2.25 2.25 0 013.182 0l2.909 2.909M3.75 21h16.5A2.25 2.25 0 0022.5 18.75V5.25A2.25 2.25 0 0020.25 3H3.75A2.25 2.25 0 001.5 5.25v13.5A2.25 2.25 0 003.75 21z"
              />
            </svg>
          </div>
        )}

        {/* Bottom overlay with metadata */}
        <div className="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/60 to-transparent px-3 pb-2 pt-6">
          <p className="text-xs font-semibold text-white">{workerName}</p>
          {jobName && (
            <p className="text-[10px] text-white/80">{jobName}</p>
          )}
          <p className="text-[10px] text-white/70">
            {formatTimestamp(timestamp)}
          </p>
        </div>
      </div>

      {/* Verification code footer */}
      {verificationCode && (
        <div className="flex items-center gap-2 border-t border-stone-100 px-3 py-2">
          <svg
            className="h-3.5 w-3.5 text-emerald-600"
            fill="currentColor"
            viewBox="0 0 20 20"
          >
            <path
              fillRule="evenodd"
              d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
              clipRule="evenodd"
            />
          </svg>
          <code className="truncate rounded bg-slate-100 px-2 py-0.5 text-[10px] font-mono text-slate-600">
            {verificationCode}
          </code>
        </div>
      )}
    </div>
  );
}

export { PhotoStampCard };
export type { PhotoStampCardProps };
