import { createWriteStream } from "node:fs";
import { unlink } from "node:fs/promises";
import { join } from "node:path";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { MEDIA_LIMITS } from "@/lib/capabilities";
import type { MediaItem, MediaKind } from "@/lib/types";
import { mediaRepo } from "./db/repositories";
import { mediaDir } from "./env";
import { HttpError } from "./security";

/**
 * Local media storage. Uploads are streamed to disk with an explicit byte cap
 * so large videos are never buffered in memory.
 */

export function kindForMime(mime: string): MediaKind | null {
  if ((MEDIA_LIMITS.image.mimeTypes as readonly string[]).includes(mime)) return "image";
  if ((MEDIA_LIMITS.video.mimeTypes as readonly string[]).includes(mime)) return "video";
  return null;
}

export async function saveUpload(file: File): Promise<MediaItem> {
  const kind = kindForMime(file.type);
  if (!kind) {
    throw new HttpError(415, `Unsupported media type: ${file.type || "unknown"}`);
  }
  const limit = MEDIA_LIMITS.uploadMaxBytes;
  if (file.size > limit) {
    throw new HttpError(413, `File exceeds the ${Math.round(limit / 1024 / 1024)}MB upload limit`);
  }

  const repo = mediaRepo();
  const ext = extensionFor(file.type);
  // Reserve the id first so the filename matches the DB row.
  const tmpName = `${crypto.randomUUID()}${ext}`;
  // The local media directory is intentionally runtime-configurable.
  const absPath = join(/* turbopackIgnore: true */ mediaDir(), tmpName);

  // Stream with a hard byte cap.
  let written = 0;
  const counting = new TransformStream<Uint8Array, Uint8Array>({
    transform(chunk, controller) {
      written += chunk.byteLength;
      if (written > limit) {
        controller.error(new HttpError(413, "Upload exceeded size limit"));
        return;
      }
      controller.enqueue(chunk);
    },
  });

  try {
    await pipeline(
      Readable.fromWeb(file.stream().pipeThrough(counting) as never),
      createWriteStream(absPath, { mode: 0o600 }),
    );
  } catch (err) {
    await unlink(absPath).catch(() => {});
    throw err;
  }

  return repo.create({
    kind,
    mimeType: file.type,
    name: file.name || tmpName,
    size: written,
    path: tmpName,
  });
}

export async function deleteMedia(id: string): Promise<void> {
  const repo = mediaRepo();
  const relPath = repo.remove(id);
  if (relPath) {
    await unlink(join(mediaDir(), relPath)).catch(() => {});
  }
}

function extensionFor(mime: string): string {
  const map: Record<string, string> = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "image/gif": ".gif",
    "video/mp4": ".mp4",
    "video/quicktime": ".mov",
    "video/webm": ".webm",
  };
  return map[mime] ?? ".bin";
}
