import type { Draft, MediaItem, Network, ResolvedContent } from "@/lib/types";

/**
 * Resolve the effective content for one network from a draft: per-network
 * overrides replace individual fields; everything else inherits the base.
 * No content is duplicated at rest: overrides store only the differing fields.
 */
export function resolveContent(
  draft: Pick<Draft, "text" | "mediaIds" | "overrides">,
  network: Network,
  mediaById: Map<string, MediaItem>,
): ResolvedContent {
  const override = draft.overrides?.[network];
  const text = override?.text ?? draft.text;
  const mediaIds = override?.mediaIds ?? draft.mediaIds;
  const media = mediaIds.map((id) => mediaById.get(id)).filter((m): m is MediaItem => Boolean(m));
  return { text, media };
}
