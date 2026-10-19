import {
  LayoutDashboard,
  MapPin,
  Users,
  Clock,
  Camera,
  Images,
  DollarSign,
  Calendar,
  Tag,
  Timer,
  ShieldCheck,
  FileText,
  FileSignature,
  Settings,
  UserPlus,
  Clipboard,
  AlertTriangle,
  ToggleLeft,
  type LucideIcon,
} from "lucide-react";

export interface NavItem {
  href: string;
  icon: LucideIcon;
  labelKey: string;
  section: string;
  adminOnly?: boolean;
  supervisorOrAbove?: boolean;
}

export const NAV_ITEMS: NavItem[] = [
  // Overview — what's the high-level state right now?
  { href: "/", icon: LayoutDashboard, labelKey: "shell.dashboard", section: "overview" },
  { href: "/map", icon: MapPin, labelKey: "shell.map", section: "overview" },
  { href: "/workers", icon: Users, labelKey: "shell.workers", section: "overview" },
  { href: "/projects", icon: Clipboard, labelKey: "shell.projects", section: "overview" },

  // Today — live, time-sensitive workflows.
  { href: "/schedule", icon: Calendar, labelKey: "shell.schedule", section: "today" },
  { href: "/timeline", icon: Clock, labelKey: "shell.timeline", section: "today" },
  { href: "/alerts", icon: AlertTriangle, labelKey: "shell.alerts", section: "today", supervisorOrAbove: true },

  // Proof — evidence trail (photos, signed timecards, permits).
  { href: "/photos", icon: Camera, labelKey: "shell.photos", section: "proof" },
  { href: "/galleries", icon: Images, labelKey: "shell.galleries", section: "proof" },
  { href: "/timecards", icon: FileSignature, labelKey: "shell.timecards", section: "proof" },
  { href: "/projects/permits", icon: FileText, labelKey: "shell.permits", section: "proof" },

  // Costs — money flows tied to the job.
  { href: "/expenses", icon: DollarSign, labelKey: "shell.expenses", section: "costs" },
  { href: "/cost-codes", icon: Tag, labelKey: "shell.costCodes", section: "costs" },
  { href: "/overtime", icon: Timer, labelKey: "shell.overtime", section: "costs" },
  { href: "/pto", icon: ShieldCheck, labelKey: "shell.pto", section: "costs" },

  // Reports — aggregate views.
  { href: "/reports", icon: FileText, labelKey: "shell.reports", section: "reports" },

  // Settings — admin only.
  { href: "/settings", icon: Settings, labelKey: "shell.company", section: "settings" },
  { href: "/settings/billing", icon: DollarSign, labelKey: "shell.billing", section: "settings", adminOnly: true },
  { href: "/settings/staff", icon: UserPlus, labelKey: "shell.staff", section: "settings", adminOnly: true },
  { href: "/settings/pto-allocations", icon: ShieldCheck, labelKey: "shell.ptoAllocations", section: "settings", adminOnly: true },
  { href: "/settings/job-foremen", icon: Users, labelKey: "shell.jobForemen", section: "settings", adminOnly: true },
  { href: "/settings/feature-flags", icon: ToggleLeft, labelKey: "shell.featureFlags", section: "settings", adminOnly: true },
  { href: "/onboarding", icon: Clipboard, labelKey: "shell.onboarding", section: "settings", adminOnly: true },
];

// Section render order in the sidebar. Working-memory rule: keep each group
// at 3–5 items so the eye can scan a section without effort.
export const NAV_SECTIONS: Record<string, string> = {
  overview: "shell.overview",
  today: "shell.today",
  proof: "shell.proof",
  costs: "shell.costs",
  reports: "shell.reports",
  settings: "shell.settings",
};
