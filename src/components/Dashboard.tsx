"use client";

import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { type ConnectionInfo, NETWORK_LABELS, type RecentPost } from "@/lib/types";
import { HistoryIcon, PlugZapIcon } from "lucide-react";
import Link from "next/link";
import { useEffect, useState } from "react";
import { SiBluesky, SiInstagram, SiThreads, SiX } from "react-icons/si";

interface DashboardData {
  posts: RecentPost[];
  platforms: ConnectionInfo[];
}

const networkIcons = { x: SiX, bluesky: SiBluesky, threads: SiThreads, instagram: SiInstagram };

export function Dashboard() {
  const [data, setData] = useState<DashboardData | null>(null);

  useEffect(() => {
    void fetch("/api/dashboard")
      .then(async (response) => {
        if (!response.ok) throw new Error("Failed to load dashboard");
        return (await response.json()) as DashboardData;
      })
      .then(setData)
      .catch(() => setData({ posts: [], platforms: [] }));
  }, []);

  const posts = data?.posts ?? [];
  const platforms = data?.platforms ?? [];

  return (
    <section className="flex max-w-6xl flex-col gap-8">
      <div>
        <p className="text-sm text-muted-foreground">Overview</p>
        <h1 className="mt-1 text-2xl font-semibold tracking-tight">Dashboard</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Your recent publishing activity and active connections.
        </p>
      </div>
      <div className="grid gap-4 lg:grid-cols-[minmax(0,2fr)_minmax(18rem,1fr)]">
        <Card>
          <CardHeader>
            <CardTitle>Recent posts</CardTitle>
            <CardDescription>Your five most recent publish operations.</CardDescription>
          </CardHeader>
          <CardContent>
            {posts.length === 0 ? (
              <Empty className="min-h-48 border">
                <EmptyHeader>
                  <EmptyMedia variant="icon">
                    <HistoryIcon />
                  </EmptyMedia>
                  <EmptyTitle>Nothing published yet</EmptyTitle>
                  <EmptyDescription>Published posts will appear here.</EmptyDescription>
                </EmptyHeader>
              </Empty>
            ) : (
              <ul className="flex flex-col divide-y">
                {posts.map((post) => (
                  <PostRow key={post.draftId} post={post} />
                ))}
              </ul>
            )}
            <Link
              href="/history"
              className="mt-4 inline-block text-sm text-muted-foreground underline underline-offset-4 hover:text-foreground"
            >
              View full history
            </Link>
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>Connected platforms</CardTitle>
            <CardDescription>Accounts available to publish now.</CardDescription>
          </CardHeader>
          <CardContent>
            {platforms.length === 0 ? (
              <Empty className="min-h-48 border">
                <EmptyHeader>
                  <EmptyMedia variant="icon">
                    <PlugZapIcon />
                  </EmptyMedia>
                  <EmptyTitle>No connections</EmptyTitle>
                  <EmptyDescription>Connect an account to start publishing.</EmptyDescription>
                </EmptyHeader>
              </Empty>
            ) : (
              <ul className="flex flex-col gap-3">
                {platforms.map((platform) => (
                  <PlatformRow key={platform.network} platform={platform} />
                ))}
              </ul>
            )}
            <Link
              href="/settings"
              className="mt-4 inline-block text-sm text-muted-foreground underline underline-offset-4 hover:text-foreground"
            >
              Manage connections
            </Link>
          </CardContent>
        </Card>
      </div>
    </section>
  );
}

function PostRow({ post }: { post: RecentPost }) {
  const failed = post.attempts.some((attempt) => attempt.status === "failed");
  return (
    <li className="flex flex-col gap-2 py-3 first:pt-0 last:pb-0">
      <p className="line-clamp-2 text-sm">{post.text || "Media post"}</p>
      <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
        <time>{new Date(post.createdAt).toLocaleString()}</time>
        {post.attempts.map((attempt) => (
          <Badge
            key={attempt.id}
            variant={attempt.status === "failed" ? "destructive" : "secondary"}
          >
            {NETWORK_LABELS[attempt.network]}
          </Badge>
        ))}
        {failed && <Badge variant="destructive">needs attention</Badge>}
      </div>
    </li>
  );
}

function PlatformRow({ platform }: { platform: ConnectionInfo }) {
  const Icon = networkIcons[platform.network];
  return (
    <li className="flex items-center gap-3">
      <Icon aria-hidden className="size-4" />
      <div className="min-w-0 flex-1">
        <p className="text-sm font-medium">{NETWORK_LABELS[platform.network]}</p>
        <p className="truncate text-xs text-muted-foreground">
          {platform.accountLabel ?? "Connection requires attention"}
        </p>
      </div>
      <Badge variant={platform.state === "error" ? "destructive" : "secondary"}>
        {platform.state}
      </Badge>
    </li>
  );
}
