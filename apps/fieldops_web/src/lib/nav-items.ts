import {
  Bell,
  CalendarDays,
  ArrowRightLeft,
  ClipboardCheck,
  ClipboardList,
  Settings2,
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
  { href: "/restaurant", icon: ClipboardCheck, labelKey: "shell.restaurantOperations", section: "restaurant" },
  { href: "/restaurant/calendar", icon: CalendarDays, labelKey: "shell.restaurantCalendar", section: "restaurant" },
  { href: "/restaurant/coverage", icon: ArrowRightLeft, labelKey: "shell.restaurantCoverage", section: "restaurant" },
  { href: "/restaurant/notifications", icon: Bell, labelKey: "shell.restaurantNotifications", section: "restaurant" },
  { href: "/restaurant/inspections", icon: ClipboardList, labelKey: "shell.restaurantInspections", section: "restaurant" },
  { href: "/restaurant/configuration", icon: Settings2, labelKey: "shell.restaurantConfig", section: "restaurant", supervisorOrAbove: true },
];

export const NAV_SECTIONS: Record<string, string> = {
  restaurant: "shell.operations",
};
