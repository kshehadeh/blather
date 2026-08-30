import type { Metadata } from "next";
import { Geist } from "next/font/google";
import Link from "next/link";
import type { ReactNode } from "react";
import "./globals.css";

const geist = Geist({
  subsets: ["latin"],
  variable: "--font-geist",
});

export const metadata: Metadata = {
  title: "Blather",
  description: "Local-only multi-network composer",
};

const navigation = [
  { href: "/", label: "Compose" },
  { href: "/history", label: "History" },
  { href: "/settings", label: "Settings" },
];

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" className="dark">
      <body className={geist.variable}>
        <div className="mx-auto flex min-h-screen max-w-7xl flex-col px-4 sm:px-6">
          <header className="flex min-h-16 items-center justify-between border-b">
            <Link href="/" className="flex items-center gap-2 text-sm font-medium tracking-tight">
              <span className="size-2 rounded-full bg-foreground" aria-hidden />
              Blather
            </Link>
            <nav aria-label="Main navigation" className="flex items-center gap-1">
              {navigation.map((item) => (
                <Link
                  key={item.href}
                  href={item.href}
                  className="rounded-md px-2.5 py-1.5 text-sm text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
                >
                  {item.label}
                </Link>
              ))}
            </nav>
          </header>
          <main className="flex-1 py-8 sm:py-12">{children}</main>
        </div>
      </body>
    </html>
  );
}
