import type { Metadata } from "next";
import "./globals.css";
import AdminShell from "@/components/admin-shell";

export const metadata: Metadata = {
  title: "FieldOps Admin",
  description: "FieldOps super-admin panel",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className="bg-stone-50 text-stone-900 antialiased">
        <AdminShell>{children}</AdminShell>
      </body>
    </html>
  );
}
