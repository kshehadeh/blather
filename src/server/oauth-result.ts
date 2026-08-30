function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (character) => {
    const entities: Record<string, string> = {
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#039;",
    };
    return entities[character] ?? character;
  });
}

/** Completion document shown in the system browser after an OAuth callback. */
export function oauthResultPage(network: string, error: string | null): Response {
  const title = error ? "Connection failed" : "Connection complete";
  const detail = error
    ? `${network}: ${error}`
    : `${network} is connected. Return to Blather to continue.`;
  return new Response(
    `<!doctype html>
<html lang="en">
  <head><meta charset="utf-8"><title>${escapeHtml(title)}</title></head>
  <body><main><h1>${escapeHtml(title)}</h1><p>${escapeHtml(detail)}</p></main></body>
</html>`,
    { headers: { "Content-Type": "text/html; charset=utf-8" } },
  );
}
