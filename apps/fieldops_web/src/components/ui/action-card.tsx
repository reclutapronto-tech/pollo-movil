import * as React from "react";
import Link from "next/link";

import { cn } from "@/lib/utils";

interface ActionCardProps {
  title: string;
  description?: string;
  href: string;
  icon?: React.ReactNode;
  className?: string;
}

function ActionCard({
  title,
  description,
  href,
  icon,
  className,
}: ActionCardProps) {
  return (
    <Link
      href={href}
      data-slot="action-card"
      className={cn(
        "rounded-xl border border-stone-200 bg-white px-5 py-3 shadow-sm transition-all transition-transform hover:scale-[1.02] active:scale-[0.98] hover:border-slate-300 hover:shadow-md",
        className,
      )}
    >
      <div className="flex items-center gap-2">
        {icon && (
          <span className="shrink-0 text-slate-500">{icon}</span>
        )}
        <div>
          <span className="text-sm font-medium text-slate-600">
            {title} &rarr;
          </span>
          {description && (
            <p className="mt-0.5 text-xs text-slate-400">{description}</p>
          )}
        </div>
      </div>
    </Link>
  );
}

export { ActionCard };
export type { ActionCardProps };
