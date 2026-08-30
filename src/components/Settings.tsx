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
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Field, FieldDescription, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Spinner } from "@/components/ui/spinner";
import {
  type ConnectionInfo,
  NETWORK_LABELS,
  type ProviderCapabilities,
  type R2SettingsView,
} from "@/lib/types";
import { CircleHelpIcon, HeartPulseIcon, SaveIcon, Trash2Icon } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import type { IconType } from "react-icons";
import { SiBluesky, SiInstagram, SiThreads, SiX } from "react-icons/si";

interface ConnectionsResponse {
  connections: ConnectionInfo[];
  capabilities: ProviderCapabilities[];
  r2: R2SettingsView;
}

const networkTitleIcon = {
  x: SiX,
  bluesky: SiBluesky,
  threads: SiThreads,
  instagram: SiInstagram,
} satisfies Record<ProviderCapabilities["network"], IconType>;

async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(path, {
    ...init,
    headers: { "Content-Type": "application/json", ...(init?.headers ?? {}) },
  });
  const body = (await res.json().catch(() => ({}))) as T & { error?: string };
  if (!res.ok) throw new Error(body.error ?? `Request failed (${res.status})`);
  return body;
}

export function Settings() {
  const [data, setData] = useState<ConnectionsResponse | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [checking, setChecking] = useState(false);

  const refresh = useCallback(async (withHealth = false) => {
    const response = await api<ConnectionsResponse>(
      `/api/connections${withHealth ? "?refresh=1" : ""}`,
    );
    setData(response);
  }, []);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const error = params.get("error");
    if (error) setNotice(error);
    void refresh();
  }, [refresh]);

  const checkHealth = async () => {
    setChecking(true);
    try {
      await refresh(true);
      setNotice("Health checks completed");
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "Health checks failed");
    } finally {
      setChecking(false);
    }
  };

  const disconnect = useCallback(
    async (network: string) => {
      await api(`/api/disconnect/${network}`, { method: "POST" });
      await refresh();
    },
    [refresh],
  );

  if (!data) {
    return (
      <div className="flex items-center gap-2 text-sm text-muted-foreground">
        <Spinner />
        Loading settings
      </div>
    );
  }

  const connectionFor = (network: string) =>
    data.connections.find((connection) => connection.network === network) ?? {
      network: network as ConnectionInfo["network"],
      state: "disconnected" as const,
    };

  return (
    <section className="flex max-w-6xl flex-col gap-8">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="text-sm text-muted-foreground">Configuration</p>
          <h1 className="mt-1 text-2xl font-semibold tracking-tight">Settings</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            Connections and media staging stay on this machine.
          </p>
        </div>
        <Button
          type="button"
          variant="outline"
          disabled={checking}
          onClick={() => void checkHealth()}
        >
          {checking ? (
            <Spinner data-icon="inline-start" />
          ) : (
            <HeartPulseIcon data-icon="inline-start" />
          )}
          Run health checks
        </Button>
      </div>

      {notice && (
        <Alert>
          <AlertDescription>{notice}</AlertDescription>
        </Alert>
      )}

      <div className="grid gap-4 md:grid-cols-2">
        {data.capabilities.map((capabilities) => (
          <NetworkCard
            key={capabilities.network}
            caps={capabilities}
            conn={connectionFor(capabilities.network)}
            onDisconnect={disconnect}
            onChanged={() => void refresh()}
          />
        ))}
      </div>

      <R2Panel r2={data.r2} onChanged={() => void refresh()} />
    </section>
  );
}

function NetworkCard({
  caps,
  conn,
  onDisconnect,
  onChanged,
}: {
  caps: ProviderCapabilities;
  conn: ConnectionInfo;
  onDisconnect: (network: string) => Promise<void>;
  onChanged: () => void;
}) {
  const NetworkIcon = networkTitleIcon[caps.network];

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2" role="heading" aria-level={2}>
          <NetworkIcon aria-hidden className="size-4" />
          {NETWORK_LABELS[caps.network]}
        </CardTitle>
        <CardDescription>{conn.accountLabel ?? "No account connected"}</CardDescription>
        <CardAction>
          <StatusBadge state={conn.state} />
        </CardAction>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        {conn.error && (
          <Alert variant="destructive">
            <AlertDescription>{conn.error}</AlertDescription>
          </Alert>
        )}
        <ul className="flex list-disc flex-col gap-1 pl-4 text-sm text-muted-foreground">
          <li>
            {caps.maxChars} characters, up to {caps.maxImages} images
            {caps.allowsVideo ? ", video" : ""}
            {caps.requiresMedia ? ", media required" : ""}
          </li>
          {caps.notes.map((note) => (
            <li key={note}>{note}</li>
          ))}
        </ul>
        {conn.state === "disconnected" ? (
          <ConnectForm network={caps.network} onChanged={onChanged} />
        ) : (
          <Button
            type="button"
            variant="destructive"
            size="sm"
            className="self-start"
            onClick={() => void onDisconnect(caps.network)}
          >
            Disconnect
          </Button>
        )}
      </CardContent>
    </Card>
  );
}

function StatusBadge({ state }: { state: ConnectionInfo["state"] }) {
  const variant =
    state === "error" ? "destructive" : state === "connected" ? "default" : "secondary";
  return <Badge variant={variant}>{state}</Badge>;
}

function ConnectForm({
  network,
  onChanged,
}: {
  network: ProviderCapabilities["network"];
  onChanged: () => void;
}) {
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const submit = async (form: HTMLFormElement) => {
    setBusy(true);
    setError(null);
    try {
      const fields = Object.fromEntries(new FormData(form).entries()) as Record<string, string>;
      const response = await api<{ url?: string }>(`/api/connect/${network}`, {
        method: "POST",
        body: JSON.stringify(fields),
      });
      if (response.url) {
        window.location.href = response.url;
        return;
      }
      onChanged();
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : "Connect failed");
    } finally {
      setBusy(false);
    }
  };

  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        void submit(event.currentTarget);
      }}
    >
      <FieldGroup>
        {network === "x" && (
          <Field>
            <FieldLabel htmlFor={`${network}-client-id`}>Client ID</FieldLabel>
            <Input
              id={`${network}-client-id`}
              name="clientId"
              required
              placeholder="X app Client ID"
            />
          </Field>
        )}
        {network === "bluesky" && (
          <>
            <Field>
              <FieldLabel htmlFor="bluesky-pds">PDS</FieldLabel>
              <Input id="bluesky-pds" name="pds" placeholder="https://bsky.social" />
            </Field>
            <Field>
              <FieldLabel htmlFor="bluesky-handle">Handle</FieldLabel>
              <Input id="bluesky-handle" name="handle" required placeholder="you.bsky.social" />
            </Field>
            <Field>
              <FieldLabel htmlFor="bluesky-password">App password</FieldLabel>
              <Input
                id="bluesky-password"
                name="appPassword"
                required
                type="password"
                placeholder="App password"
              />
            </Field>
          </>
        )}
        {(network === "threads" || network === "instagram") && (
          <>
            <Field>
              <FieldLabel htmlFor={`${network}-client-id`}>App ID</FieldLabel>
              <Input id={`${network}-client-id`} name="clientId" required placeholder="App ID" />
            </Field>
            <Field>
              <FieldLabel htmlFor={`${network}-client-secret`}>App Secret</FieldLabel>
              <Input
                id={`${network}-client-secret`}
                name="clientSecret"
                required
                type="password"
                placeholder="App Secret"
              />
            </Field>
            <MetaCredentialsHelp network={network} />
          </>
        )}
        <Button type="submit" className="self-start" disabled={busy}>
          {busy && <Spinner data-icon="inline-start" />}
          Connect
        </Button>
        {error && (
          <Alert variant="destructive">
            <AlertDescription>{error}</AlertDescription>
          </Alert>
        )}
      </FieldGroup>
    </form>
  );
}

function MetaCredentialsHelp({ network }: { network: "threads" | "instagram" }) {
  const networkName = NETWORK_LABELS[network];
  const callbackUrl = `https://127.0.0.1:3000/api/connect/${network}/callback`;

  return (
    <Dialog>
      <DialogTrigger asChild>
        <Button type="button" variant="link" size="sm" className="w-fit px-0">
          <CircleHelpIcon data-icon="inline-start" />
          Where do I find the App ID and App Secret?
        </Button>
      </DialogTrigger>
      <DialogContent aria-describedby={`${network}-credentials-description`}>
        <DialogTitle className="text-lg font-medium">
          Find your {networkName} app credentials
        </DialogTitle>
        <DialogDescription
          id={`${network}-credentials-description`}
          className="mt-2 text-sm text-muted-foreground"
        >
          These values are in the Meta for Developers console, not your {networkName} account
          settings.
        </DialogDescription>
        <ol className="mt-4 flex list-decimal flex-col gap-3 pl-5 text-sm">
          <li>
            Go to{" "}
            <a
              href="https://developers.facebook.com/apps/"
              target="_blank"
              rel="noreferrer"
              className="underline underline-offset-4 hover:text-muted-foreground"
            >
              Meta for Developers, My Apps
            </a>
            , then select the app configured for {networkName}.
          </li>
          <li>
            In the left navigation, open <strong>App settings</strong>, then <strong>Basic</strong>.
          </li>
          <li>
            Copy the value labeled <strong>App ID</strong>. For <strong>App Secret</strong>, select{" "}
            <strong>Show</strong> in the console, then copy the revealed value.
          </li>
          <li>
            Paste both values here. Also ensure this OAuth redirect URI is configured:{" "}
            <code className="break-all text-xs">{callbackUrl}</code>
          </li>
        </ol>
        <DialogClose asChild>
          <Button type="button" variant="outline" className="mt-6">
            Close
          </Button>
        </DialogClose>
      </DialogContent>
    </Dialog>
  );
}

function R2Panel({ r2, onChanged }: { r2: R2SettingsView; onChanged: () => void }) {
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const submit = async (form: HTMLFormElement) => {
    setBusy(true);
    setMessage(null);
    try {
      const fields = Object.fromEntries(new FormData(form).entries()) as Record<string, string>;
      await api("/api/settings/r2", { method: "PUT", body: JSON.stringify(fields) });
      setMessage("R2 settings saved");
      onChanged();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Save failed");
    } finally {
      setBusy(false);
    }
  };

  const test = async () => {
    setBusy(true);
    setMessage(null);
    try {
      await api("/api/settings/r2/test", { method: "POST" });
      setMessage("Connection OK");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Test failed");
    } finally {
      setBusy(false);
    }
  };

  const remove = async () => {
    setBusy(true);
    await api("/api/settings/r2", { method: "DELETE" }).catch(() => {});
    setMessage("R2 settings removed");
    setBusy(false);
    onChanged();
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle role="heading" aria-level={2}>
          Cloudflare R2 staging
        </CardTitle>
        <CardDescription>
          Required for Threads and Instagram media. R2 API credentials are stored in Keychain.
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-5">
        <Alert>
          <AlertDescription>
            Meta fetches media over HTTPS. Uploaded files are staged in R2 while publishing, then
            removed.
          </AlertDescription>
        </Alert>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            void submit(event.currentTarget);
          }}
        >
          <FieldGroup>
            <Field>
              <FieldLabel htmlFor="r2-account-id">Account ID</FieldLabel>
              <Input
                id="r2-account-id"
                name="accountId"
                required
                placeholder="Cloudflare account ID"
                defaultValue={r2.accountId}
              />
            </Field>
            <Field>
              <FieldLabel htmlFor="r2-bucket">Bucket</FieldLabel>
              <Input
                id="r2-bucket"
                name="bucket"
                required
                placeholder="Bucket"
                defaultValue={r2.bucket}
              />
            </Field>
            <Field>
              <FieldLabel htmlFor="r2-strategy">Media URL strategy</FieldLabel>
              <select
                id="r2-strategy"
                name="publicUrlStrategy"
                defaultValue={r2.publicUrlStrategy ?? "presigned"}
                className="h-8 w-full rounded-lg border border-input bg-transparent px-2.5 text-sm outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50"
              >
                <option value="presigned">Presigned URLs, bucket stays private</option>
                <option value="public">Public R2 bucket URL</option>
              </select>
            </Field>
            <Field>
              <FieldLabel htmlFor="r2-public-base-url">Public R2 bucket URL</FieldLabel>
              <Input
                id="r2-public-base-url"
                name="publicBaseUrl"
                placeholder="https://media.example.com"
                defaultValue={r2.publicBaseUrl}
              />
            </Field>
            <Field>
              <FieldLabel htmlFor="r2-access-key">R2 access key ID</FieldLabel>
              <Input
                id="r2-access-key"
                name="accessKeyId"
                placeholder={
                  r2.hasCredentials ? "Configured, leave blank to keep" : "R2 access key ID"
                }
              />
            </Field>
            <Field>
              <FieldLabel htmlFor="r2-secret-key">R2 secret access key</FieldLabel>
              <Input
                id="r2-secret-key"
                name="secretAccessKey"
                type="password"
                placeholder={
                  r2.hasCredentials ? "Configured, leave blank to keep" : "R2 secret access key"
                }
              />
              <FieldDescription>Never stored in the local database.</FieldDescription>
            </Field>
            <div className="flex flex-wrap gap-2">
              <Button type="submit" disabled={busy}>
                {busy && <Spinner data-icon="inline-start" />}
                <SaveIcon data-icon="inline-start" />
                Save
              </Button>
              <Button
                type="button"
                variant="outline"
                disabled={busy || !r2.configured}
                onClick={() => void test()}
              >
                Test connection
              </Button>
              <Button
                type="button"
                variant="destructive"
                disabled={busy || !r2.configured}
                onClick={() => void remove()}
              >
                <Trash2Icon data-icon="inline-start" />
                Remove
              </Button>
            </div>
          </FieldGroup>
        </form>
        {message && (
          <Alert>
            <AlertDescription>{message}</AlertDescription>
          </Alert>
        )}
      </CardContent>
      <CardFooter>
        <p className="text-xs text-muted-foreground">
          R2 staging objects older than 24 hours are swept at startup.
        </p>
      </CardFooter>
    </Card>
  );
}
