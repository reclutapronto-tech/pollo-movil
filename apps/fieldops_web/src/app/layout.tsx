import type { Metadata } from "next";
import "./globals.css";
import { AppShell } from "@/components/app-shell";
import { Providers } from "./providers";
import { THEME_INIT_SCRIPT } from "@/lib/theme";

export const metadata: Metadata = {
  title: "Pollo Móvil — Operación del restaurante",
  description: "Coordinación de turnos, actividades, inspecciones e incidencias de restaurante.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html
      lang="es-MX"
      className="font-sans"
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
          <AppShell>{children}</AppShell>
        </Providers>
      </body>
    </html>
  );
}
