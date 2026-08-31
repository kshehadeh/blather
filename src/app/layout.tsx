import { AppSidebar } from "@/components/AppSidebar";
import type { Metadata } from "next";
import { Geist } from "next/font/google";
import type { ReactNode } from "react";
import "./globals.css";

const geist = Geist({
  subsets: ["latin"],
  variable: "--font-geist",
});

export const metadata: Metadata = {
  title: "Blather",
  description: "Local-only multi-network composer",
  icons: {
    icon: "/icon.svg",
  },
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" className="dark">
      <body className={geist.variable}>
        <div className="flex min-h-screen">
          <AppSidebar />
          <main className="min-w-0 flex-1 px-6 py-8 sm:px-8 sm:py-12">{children}</main>
        </div>
      </body>
    </html>
  );
}
