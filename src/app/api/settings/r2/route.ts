import { deleteSecret, makeCredentialRef, storeSecret } from "@/server/credentials";
import { r2Repo } from "@/server/db/repositories";
import { withGuard } from "@/server/http";
import { __setStagerForTests } from "@/server/r2";
import type { NextRequest } from "next/server";

export const runtime = "nodejs";

export const GET = withGuard(async () => {
  return Response.json({ r2: r2Repo().view() });
});

export const PUT = withGuard(async (req: NextRequest) => {
  const body = (await req.json()) as {
    accountId?: string;
    bucket?: string;
    accessKeyId?: string;
    secretAccessKey?: string;
    publicUrlStrategy?: "public" | "presigned";
    publicBaseUrl?: string;
  };
  if (!body.accountId || !body.bucket) {
    return Response.json({ error: "account ID and bucket are required" }, { status: 400 });
  }
  if (body.publicUrlStrategy === "public" && !body.publicBaseUrl) {
    return Response.json(
      { error: "a public R2 bucket URL is required when using public media URLs" },
      { status: 400 },
    );
  }

  const repo = r2Repo();
  const existing = repo.get();
  let credentialRef = existing?.credentialRef;

  // Only rotate credentials when new ones are provided.
  if (body.accessKeyId || body.secretAccessKey) {
    if (!body.accessKeyId || !body.secretAccessKey) {
      return Response.json(
        { error: "accessKeyId and secretAccessKey must be provided together" },
        { status: 400 },
      );
    }
    if (credentialRef) deleteSecret(credentialRef);
    credentialRef = makeCredentialRef("r2", "staging");
    storeSecret(credentialRef, {
      accessKeyId: body.accessKeyId,
      secretAccessKey: body.secretAccessKey,
    });
  }
  if (!credentialRef) {
    return Response.json({ error: "credentials required on first setup" }, { status: 400 });
  }

  repo.save({
    accountId: body.accountId.trim(),
    bucket: body.bucket,
    publicUrlStrategy: body.publicUrlStrategy ?? "presigned",
    publicBaseUrl: body.publicBaseUrl,
    credentialRef,
  });
  // drop any cached stager so new settings take effect
  __setStagerForTests(null);
  return Response.json({ r2: repo.view() });
});

export const DELETE = withGuard(async () => {
  const repo = r2Repo();
  const existing = repo.get();
  if (existing?.credentialRef) deleteSecret(existing.credentialRef);
  repo.clear();
  __setStagerForTests(null);
  return Response.json({ ok: true });
});
