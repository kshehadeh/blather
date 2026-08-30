"use client";

import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Spinner } from "@/components/ui/spinner";
import { NETWORK_LABELS, type PublishAttempt } from "@/lib/types";
import { HistoryIcon, RotateCwIcon } from "lucide-react";
import { useCallback, useEffect, useState } from "react";

export function History() {
  const [attempts, setAttempts] = useState<PublishAttempt[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    try {
      const res = await fetch("/api/history");
      const body = (await res.json()) as { attempts?: PublishAttempt[]; error?: string };
      if (!res.ok) throw new Error(body.error ?? "Failed to load history");
      setAttempts(body.attempts ?? []);
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : "Failed to load history");
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const retry = useCallback(
    async (id: string) => {
      setBusyId(id);
      try {
        await fetch(`/api/attempts/${id}/retry`, { method: "POST" });
        await refresh();
      } finally {
        setBusyId(null);
      }
    },
    [refresh],
  );

  return (
    <section className="flex max-w-4xl flex-col gap-6">
      <div>
        <p className="text-sm text-muted-foreground">Activity</p>
        <h1 className="mt-1 text-2xl font-semibold tracking-tight">Publish history</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Track recent publishing attempts and retry failed destinations.
        </p>
      </div>

      {error && (
        <Alert variant="destructive">
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}

      {attempts.length === 0 && !error ? (
        <Empty className="min-h-64 border">
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <HistoryIcon />
            </EmptyMedia>
            <EmptyTitle>Nothing published yet</EmptyTitle>
            <EmptyDescription>
              Publishing activity will appear here after your first post.
            </EmptyDescription>
          </EmptyHeader>
        </Empty>
      ) : (
        <ul className="flex flex-col gap-3" data-testid="history-list">
          {attempts.map((attempt) => (
            <li key={attempt.id}>
              <Card size="sm">
                <CardHeader>
                  <CardTitle className="flex items-center gap-2">
                    <StatusBadge status={attempt.status} />
                    {NETWORK_LABELS[attempt.network]}
                  </CardTitle>
                  <CardDescription>
                    <time>{new Date(attempt.createdAt).toLocaleString()}</time>
                  </CardDescription>
                  {attempt.status === "failed" && (
                    <CardAction>
                      <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        disabled={busyId === attempt.id}
                        onClick={() => void retry(attempt.id)}
                      >
                        {busyId === attempt.id ? (
                          <Spinner data-icon="inline-start" />
                        ) : (
                          <RotateCwIcon data-icon="inline-start" />
                        )}
                        Retry
                      </Button>
                    </CardAction>
                  )}
                </CardHeader>
                {(attempt.providerPostUrl || attempt.providerPostId || attempt.error) && (
                  <CardContent className="flex flex-wrap gap-x-4 gap-y-2 text-sm text-muted-foreground">
                    {attempt.providerPostUrl ? (
                      <a
                        href={attempt.providerPostUrl}
                        className="underline underline-offset-4 hover:text-foreground"
                      >
                        {attempt.providerPostId ?? "View post"}
                      </a>
                    ) : attempt.providerPostId ? (
                      <span>{attempt.providerPostId}</span>
                    ) : null}
                    {attempt.error && <span>{attempt.error}</span>}
                  </CardContent>
                )}
              </Card>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function StatusBadge({ status }: { status: PublishAttempt["status"] }) {
  const variant =
    status === "failed" ? "destructive" : status === "success" ? "default" : "outline";
  return <Badge variant={variant}>{status}</Badge>;
}
