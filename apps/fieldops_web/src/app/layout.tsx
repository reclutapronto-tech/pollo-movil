import type { Metadata } from "next";
import "./globals.css";
import { AuthGuard } from "@/components/auth-guard";
import { Sidebar } from "@/components/sidebar";
import { CommandPalette } from "@/components/command-palette";
import { KeyboardShortcutsProvider } from "@/components/keyboard-shortcuts-provider";
import { Providers } from "./providers";
import { Geist, Manrope } from "next/font/google";
import { cn } from "@/lib/utils";
import { THEME_INIT_SCRIPT } from "@/lib/theme";

// Body voice — Geist Sans (neutral, system-grade workhorse).
const geist = Geist({ subsets: ["latin"], variable: "--font-sans" });

// Display voice — Manrope (more refined character at heavier weights;
// applied to headings + KPI digits via --font-heading in globals.css).
const manrope = Manrope({
  subsets: ["latin"],
  variable: "--font-display",
  weight: ["500", "600", "700", "800"],
});

export const metadata: Metadata = {
  title: "FieldOps AI — Command Center",
  description:
    "Monitor field operations, worker activity, and proof timelines.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html
      lang="en"
      className={cn("font-sans", geist.variable, manrope.variable)}
      suppressHydrationWarning
    >
      <body
        className="bg-background text-foreground antialiased"
        suppressHydrationWarning
      >
        {/* Applies stored/system theme before hydration to avoid flash.
            Must be the first child of <body> in App Router — <head> in a layout
            collides with Next.js's metadata system in prod builds. */}
        <script dangerouslySetInnerHTML={{ __html: THEME_INIT_SCRIPT }} />
        <Providers>
          <AuthGuard>
            <div className="flex h-screen overflow-hidden">
              <Sidebar />
              <main className="flex-1 overflow-y-auto">
                <div className="mx-auto max-w-7xl px-6 py-6">{children}</div>
              </main>
            </div>
            <CommandPalette />
            <KeyboardShortcutsProvider />
          </AuthGuard>
        </Providers>
      </body>
    </html>
  );
}
