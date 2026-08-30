"use client";

import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Field, FieldLabel, FieldLegend, FieldSet } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Spinner } from "@/components/ui/spinner";
import { Textarea } from "@/components/ui/textarea";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { CAPABILITIES } from "@/lib/capabilities";
import {
  type Draft,
  type MediaItem,
  NETWORKS,
  NETWORK_LABELS,
  type Network,
  type NetworkOverride,
  type PublishAttempt,
} from "@/lib/types";
import {
  ArrowDownIcon,
  ArrowUpIcon,
  ImagePlusIcon,
  SaveIcon,
  SendIcon,
  Trash2Icon,
  XIcon,
} from "lucide-react";
import { useCallback, useEffect, useState } from "react";

async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(path, {
    ...init,
    headers: { "Content-Type": "application/json", ...(init?.headers ?? {}) },
  });
  const body = (await res.json().catch(() => ({}))) as T & { error?: string };
  if (!res.ok) throw new Error(body.error ?? `Request failed (${res.status})`);
  return body;
}

export function Composer() {
  const [draftId, setDraftId] = useState<string | null>(null);
  const [drafts, setDrafts] = useState<Draft[]>([]);
  const [text, setText] = useState("");
  const [media, setMedia] = useState<MediaItem[]>([]);
  const [networks, setNetworks] = useState<Network[]>([]);
  const [overrides, setOverrides] = useState<Partial<Record<Network, NetworkOverride>>>({});
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [lastAttempts, setLastAttempts] = useState<PublishAttempt[] | null>(null);

  const refreshDrafts = useCallback(async () => {
    const { drafts } = await api<{ drafts: Draft[] }>("/api/drafts");
    setDrafts(drafts);
  }, []);

  useEffect(() => {
    void refreshDrafts();
  }, [refreshDrafts]);

  const resolvedFor = useCallback(
    (network: Network) => {
      const override = overrides[network];
      const ids = override?.mediaIds ?? media.map((item) => item.id);
      return {
        text: override?.text ?? text,
        media: ids
          .map((id) => media.find((item) => item.id === id))
          .filter((item): item is MediaItem => Boolean(item)),
      };
    },
    [media, overrides, text],
  );

  const warningsFor = useCallback(
    (network: Network): string[] => {
      const caps = CAPABILITIES[network];
      const resolved = resolvedFor(network);
      const warnings: string[] = [];
      if (resolved.text.length > caps.maxChars)
        warnings.push(`Text over limit: ${resolved.text.length}/${caps.maxChars}`);
      const images = resolved.media.filter((item) => item.kind === "image");
      const videos = resolved.media.filter((item) => item.kind === "video");
      for (const image of images) {
        if (caps.maxImageBytes && image.size > caps.maxImageBytes) {
          warnings.push(
            caps.autoOptimizeImages
              ? `${image.name} will be converted to a JPEG under the ${Math.round(caps.maxImageBytes / 1_000_000)}MB image limit`
              : `${image.name} exceeds the ${Math.round(caps.maxImageBytes / 1_000_000)}MB image limit`,
          );
        }
      }
      if (caps.requiresMedia && resolved.media.length === 0) warnings.push("Media required");
      if (images.length > caps.maxImages) warnings.push(`Too many images (max ${caps.maxImages})`);
      if (videos.length > 1) warnings.push("Only one video allowed");
      if (images.length > 0 && videos.length > 0 && !caps.allowsMixedMedia)
        warnings.push("Cannot mix images and video");
      return warnings;
    },
    [resolvedFor],
  );

  const loadDraft = useCallback((draft: Draft, mediaItems: MediaItem[]) => {
    setDraftId(draft.id);
    setText(draft.text);
    setNetworks(draft.networks);
    setOverrides(draft.overrides ?? {});
    setMedia(mediaItems);
    setLastAttempts(null);
    setMessage(`Loaded draft ${draft.id.slice(0, 8)}`);
  }, []);

  const openDraft = useCallback(
    async (id: string) => {
      const { draft } = await api<{ draft: Draft }>(`/api/drafts/${id}`);
      const allIds = new Set(draft.mediaIds);
      for (const override of Object.values(draft.overrides ?? {})) {
        for (const mediaId of override?.mediaIds ?? []) allIds.add(mediaId);
      }
      const items: MediaItem[] =
        allIds.size === 0
          ? []
          : (await api<{ media: MediaItem[] }>(`/api/media?ids=${[...allIds].join(",")}`)).media;
      const byId = new Map(items.map((item) => [item.id, item]));
      loadDraft(
        draft,
        draft.mediaIds
          .map((mediaId) => byId.get(mediaId))
          .filter((item): item is MediaItem => Boolean(item)),
      );
    },
    [loadDraft],
  );

  const save = useCallback(async () => {
    setBusy(true);
    setMessage(null);
    try {
      const payload = { text, mediaIds: media.map((item) => item.id), networks, overrides };
      if (draftId) {
        await api(`/api/drafts/${draftId}`, { method: "PUT", body: JSON.stringify(payload) });
        setMessage("Draft updated");
      } else {
        const { draft } = await api<{ draft: Draft }>("/api/drafts", {
          method: "POST",
          body: JSON.stringify(payload),
        });
        setDraftId(draft.id);
        setMessage("Draft saved");
      }
      await refreshDrafts();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Save failed");
    } finally {
      setBusy(false);
    }
  }, [draftId, media, networks, overrides, refreshDrafts, text]);

  const publish = useCallback(async () => {
    setBusy(true);
    setMessage(null);
    try {
      const payload = { text, mediaIds: media.map((item) => item.id), networks, overrides };
      let id = draftId;
      if (id) {
        await api(`/api/drafts/${id}`, { method: "PUT", body: JSON.stringify(payload) });
      } else {
        const { draft } = await api<{ draft: Draft }>("/api/drafts", {
          method: "POST",
          body: JSON.stringify(payload),
        });
        id = draft.id;
        setDraftId(id);
      }
      const { attempts } = await api<{ attempts: PublishAttempt[] }>("/api/publish", {
        method: "POST",
        body: JSON.stringify({ draftId: id }),
      });
      setLastAttempts(attempts);
      const failed = attempts.filter((attempt) => attempt.status === "failed").length;
      setMessage(
        failed === 0
          ? "Published everywhere"
          : `${attempts.length - failed} succeeded, ${failed} failed (see History to retry)`,
      );
      await refreshDrafts();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Publish failed");
    } finally {
      setBusy(false);
    }
  }, [draftId, media, networks, overrides, refreshDrafts, text]);

  const discard = useCallback(async () => {
    if (draftId) await api(`/api/drafts/${draftId}`, { method: "DELETE" }).catch(() => {});
    setDraftId(null);
    setText("");
    setMedia([]);
    setNetworks([]);
    setOverrides({});
    setLastAttempts(null);
    setMessage("Discarded");
    await refreshDrafts();
  }, [draftId, refreshDrafts]);

  const upload = useCallback(async (files: FileList | null) => {
    if (!files) return;
    setBusy(true);
    try {
      for (const file of Array.from(files)) {
        const form = new FormData();
        form.set("file", file);
        const res = await fetch("/api/media", { method: "POST", body: form });
        const body = (await res.json()) as { media?: MediaItem; error?: string };
        if (!res.ok || !body.media) throw new Error(body.error ?? "Upload failed");
        setMedia((previous) => [...previous, body.media as MediaItem]);
      }
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Upload failed");
    } finally {
      setBusy(false);
    }
  }, []);

  const move = useCallback((index: number, direction: -1 | 1) => {
    setMedia((previous) => {
      const next = [...previous];
      const target = index + direction;
      if (target < 0 || target >= next.length) return previous;
      [next[index], next[target]] = [next[target], next[index]];
      return next;
    });
  }, []);

  const removeMedia = useCallback(async (id: string) => {
    await fetch(`/api/media/${id}`, { method: "DELETE" }).catch(() => {});
    setMedia((previous) => previous.filter((item) => item.id !== id));
    setOverrides((previous) => {
      const next = { ...previous };
      for (const network of NETWORKS) {
        if (next[network]?.mediaIds) {
          next[network] = {
            ...next[network],
            mediaIds: next[network].mediaIds?.filter((mediaId) => mediaId !== id),
          };
        }
      }
      return next;
    });
  }, []);

  const setOverrideText = useCallback((network: Network, value: string | undefined) => {
    setOverrides((previous) => {
      const next = { ...previous };
      if (value === undefined) {
        if (next[network]) {
          const { text: _text, ...rest } = next[network] as NetworkOverride;
          void _text;
          if (Object.keys(rest).length === 0) delete next[network];
          else next[network] = rest;
        }
      } else {
        next[network] = { ...next[network], text: value };
      }
      return next;
    });
  }, []);

  return (
    <div className="grid gap-8 xl:grid-cols-[minmax(0,1fr)_22rem]">
      <section className="flex min-w-0 flex-col gap-6">
        <div className="flex flex-wrap items-end justify-between gap-3">
          <div>
            <p className="text-sm text-muted-foreground">Workspace</p>
            <h1 className="mt-1 text-2xl font-semibold tracking-tight">Compose</h1>
          </div>
          <select
            aria-label="Open saved draft"
            className="h-8 rounded-lg border border-input bg-transparent px-2.5 text-sm text-foreground outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50"
            value=""
            onChange={(event) => event.target.value && void openDraft(event.target.value)}
          >
            <option value="">Open saved draft</option>
            {drafts.map((draft) => (
              <option key={draft.id} value={draft.id}>
                {draft.text.slice(0, 40) || "(no text)"} ·{" "}
                {new Date(draft.updatedAt).toLocaleString()}
              </option>
            ))}
          </select>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Your post</CardTitle>
            <CardDescription>
              Write once, then tailor it for each destination if needed.
            </CardDescription>
            <CardAction>
              <Badge variant="outline">{text.length} characters</Badge>
            </CardAction>
          </CardHeader>
          <CardContent>
            <Textarea
              aria-label="Post text"
              className="min-h-48 resize-y"
              placeholder="What's happening everywhere?"
              value={text}
              onChange={(event) => setText(event.target.value)}
            />
          </CardContent>
          <CardFooter className="flex-col items-stretch gap-4 sm:flex-row sm:items-center sm:justify-between">
            <Field className="max-w-md">
              <FieldLabel htmlFor="media">Add media</FieldLabel>
              <Input
                id="media"
                aria-label="Add media"
                type="file"
                multiple
                accept="image/jpeg,image/png,image/webp,image/gif,video/mp4,video/quicktime,video/webm"
                onChange={(event) => void upload(event.target.files)}
              />
            </Field>
            <span className="text-xs text-muted-foreground">
              Images and video are uploaded locally.
            </span>
          </CardFooter>
        </Card>

        {media.length > 0 && (
          <Card size="sm">
            <CardHeader>
              <CardTitle>Media</CardTitle>
              <CardDescription>Set the order used where it is supported.</CardDescription>
            </CardHeader>
            <CardContent>
              <ul className="flex flex-col gap-2" data-testid="media-list">
                {media.map((item, index) => (
                  <li
                    key={item.id}
                    className="flex items-center gap-3 rounded-lg border bg-muted/30 p-2"
                  >
                    <Badge variant="outline">{index + 1}</Badge>
                    {item.kind === "image" ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={`/api/media/${item.id}`}
                        alt={item.name}
                        className="size-11 rounded-md object-cover"
                      />
                    ) : (
                      <video
                        src={`/api/media/${item.id}`}
                        className="h-11 w-16 rounded-md bg-muted object-cover"
                        muted
                      />
                    )}
                    <span className="min-w-0 flex-1 truncate text-sm">{item.name}</span>
                    <div className="flex items-center gap-1">
                      <Button
                        type="button"
                        variant="ghost"
                        size="icon-sm"
                        aria-label={`move ${item.name} up`}
                        onClick={() => move(index, -1)}
                      >
                        <ArrowUpIcon />
                      </Button>
                      <Button
                        type="button"
                        variant="ghost"
                        size="icon-sm"
                        aria-label={`move ${item.name} down`}
                        onClick={() => move(index, 1)}
                      >
                        <ArrowDownIcon />
                      </Button>
                      <Button
                        type="button"
                        variant="ghost"
                        size="icon-sm"
                        aria-label={`remove ${item.name}`}
                        onClick={() => void removeMedia(item.id)}
                      >
                        <XIcon />
                      </Button>
                    </div>
                  </li>
                ))}
              </ul>
            </CardContent>
          </Card>
        )}

        <Card>
          <CardHeader>
            <CardTitle>Destinations</CardTitle>
            <CardDescription>
              Select the networks where this post will be published.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <FieldSet>
              <FieldLegend className="sr-only">Networks</FieldLegend>
              <ToggleGroup
                type="multiple"
                variant="outline"
                className="flex w-full flex-wrap"
                value={networks}
                onValueChange={(value) => setNetworks(value as Network[])}
              >
                {NETWORKS.map((network) => (
                  <ToggleGroupItem key={network} value={network}>
                    {NETWORK_LABELS[network]}
                  </ToggleGroupItem>
                ))}
              </ToggleGroup>
            </FieldSet>
          </CardContent>
        </Card>

        {networks.length > 0 && (
          <Card>
            <CardHeader>
              <CardTitle>Destination overrides</CardTitle>
              <CardDescription>
                Optional copy changes apply only to the chosen network.
              </CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col gap-4">
              {networks.map((network) => (
                <Field key={network}>
                  <FieldLabel htmlFor={`${network}-override`}>
                    {NETWORK_LABELS[network]} override (optional)
                  </FieldLabel>
                  <Textarea
                    id={`${network}-override`}
                    aria-label={`${NETWORK_LABELS[network]} override text`}
                    className="min-h-24"
                    placeholder={text || "Override text, leave empty to inherit"}
                    value={overrides[network]?.text ?? ""}
                    onChange={(event) =>
                      setOverrideText(
                        network,
                        event.target.value === "" ? undefined : event.target.value,
                      )
                    }
                  />
                </Field>
              ))}
            </CardContent>
          </Card>
        )}

        <div className="flex flex-wrap items-center gap-2">
          <Button type="button" variant="outline" disabled={busy} onClick={() => void save()}>
            {busy ? <Spinner data-icon="inline-start" /> : <SaveIcon data-icon="inline-start" />}
            Save draft
          </Button>
          <Button
            type="button"
            disabled={busy || networks.length === 0}
            onClick={() => void publish()}
          >
            {busy ? <Spinner data-icon="inline-start" /> : <SendIcon data-icon="inline-start" />}
            Publish now
          </Button>
          <Button
            type="button"
            variant="destructive"
            disabled={busy}
            onClick={() => void discard()}
          >
            <Trash2Icon data-icon="inline-start" />
            Discard
          </Button>
        </div>

        {message && (
          <Alert role="status">
            <AlertDescription>{message}</AlertDescription>
          </Alert>
        )}

        {lastAttempts && (
          <Card size="sm">
            <CardHeader>
              <CardTitle>Publish results</CardTitle>
            </CardHeader>
            <CardContent>
              <ul className="flex flex-col gap-2" data-testid="publish-results">
                {lastAttempts.map((attempt) => (
                  <li key={attempt.id} className="flex flex-wrap items-center gap-2 text-sm">
                    <StatusBadge status={attempt.status} />
                    <span>{NETWORK_LABELS[attempt.network]}</span>
                    {attempt.providerPostUrl && (
                      <a
                        className="text-muted-foreground underline underline-offset-4 hover:text-foreground"
                        href={attempt.providerPostUrl}
                      >
                        View post
                      </a>
                    )}
                    {attempt.error && (
                      <span className="text-muted-foreground">{attempt.error}</span>
                    )}
                  </li>
                ))}
              </ul>
            </CardContent>
          </Card>
        )}
      </section>

      <aside className="flex flex-col gap-4">
        <div>
          <p className="text-sm text-muted-foreground">Live preview</p>
          <h2 className="mt-1 text-base font-medium">Per destination</h2>
        </div>
        {networks.length === 0 && (
          <Card size="sm">
            <CardContent className="flex items-center gap-3 pt-0 text-sm text-muted-foreground">
              <ImagePlusIcon />
              Select one or more destinations to preview your post.
            </CardContent>
          </Card>
        )}
        {networks.map((network) => {
          const caps = CAPABILITIES[network];
          const resolved = resolvedFor(network);
          const warnings = warningsFor(network);
          return (
            <Card key={network} size="sm" data-testid={`preview-${network}`}>
              <CardHeader>
                <CardTitle>{NETWORK_LABELS[network]}</CardTitle>
                <CardAction>
                  <Badge variant={resolved.text.length > caps.maxChars ? "destructive" : "outline"}>
                    {resolved.text.length}/{caps.maxChars}
                  </Badge>
                </CardAction>
              </CardHeader>
              <CardContent className="flex flex-col gap-3">
                <p className="whitespace-pre-wrap text-sm leading-6">
                  {resolved.text || <span className="text-muted-foreground">No text yet.</span>}
                </p>
                {resolved.media.length > 0 && (
                  <div className="flex flex-wrap gap-2">
                    {resolved.media.map((item) =>
                      item.kind === "image" ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          key={item.id}
                          src={`/api/media/${item.id}`}
                          alt={item.name}
                          className="size-14 rounded-md object-cover"
                        />
                      ) : (
                        <Badge key={item.id} variant="secondary">
                          Video
                        </Badge>
                      ),
                    )}
                  </div>
                )}
                {warnings.map((warning) => (
                  <Alert key={warning} variant="destructive">
                    <AlertDescription>{warning}</AlertDescription>
                  </Alert>
                ))}
              </CardContent>
            </Card>
          );
        })}
      </aside>
    </div>
  );
}

function StatusBadge({ status }: { status: PublishAttempt["status"] }) {
  const variant =
    status === "failed" ? "destructive" : status === "success" ? "default" : "outline";
  return <Badge variant={variant}>{status}</Badge>;
}
