"use client";

import { cn } from "@/lib/utils";
import { ChartNoAxesCombinedIcon, HistoryIcon, PenLineIcon, SettingsIcon } from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";

const navigation = [
  { href: "/", label: "Dashboard", icon: ChartNoAxesCombinedIcon },
  { href: "/compose", label: "Compose", icon: PenLineIcon },
  { href: "/history", label: "History", icon: HistoryIcon },
  { href: "/settings", label: "Settings", icon: SettingsIcon },
];

export function AppSidebar() {
  const pathname = usePathname();

  return (
    <aside className="flex w-56 shrink-0 flex-col border-r bg-card" aria-label="Application">
      <header className="flex min-h-16 items-center border-b px-5">
        <Link href="/" className="flex items-center gap-2 text-sm font-medium tracking-tight">
          <img src="/icon.svg" alt="" className="size-6 invert" />
          Blather
        </Link>
      </header>
      <nav className="flex flex-1 flex-col gap-1 p-3" aria-label="Main navigation">
        {navigation.map(({ href, label, icon: Icon }) => (
          <Link
            key={href}
            href={href}
            className={cn(
              "flex items-center gap-2 rounded-md px-3 py-2 text-sm text-muted-foreground transition-colors hover:bg-muted hover:text-foreground",
              pathname === href && "bg-muted text-foreground",
            )}
          >
            <Icon aria-hidden />
            {label}
          </Link>
        ))}
      </nav>
    </aside>
  );
}
