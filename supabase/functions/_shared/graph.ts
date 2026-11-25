import { HttpError } from "./http.ts";

const GRAPH_VERSION = Deno.env.get("META_GRAPH_VERSION") ?? "v23.0";
const MAX_PAGES_OF_RESULTS = 5;

export interface ManagedPage {
  id: string;
  name: string;
  category: string | null;
  pictureUrl: string | null;
  accessToken: string | null;
  tasks: string[] | null;
}

/** Une Page est exploitable pour publier si Meta indique au moins une de ces tâches. */
export function canPublish(page: ManagedPage): boolean {
  if (page.tasks === null) return true;
  return page.tasks.includes("CREATE_CONTENT") || page.tasks.includes("MANAGE");
}

/**
 * Pages que l'utilisateur Facebook gère réellement (GET /me/accounts).
 * Le jeton utilisateur est envoyé en en-tête, jamais dans l'URL.
 */
export async function fetchManagedPages(userToken: string): Promise<ManagedPage[]> {
  if (typeof userToken !== "string" || userToken.length < 20 || userToken.length > 4096) {
    throw new HttpError(
      400,
      "missing_facebook_token",
      "Autorisation Facebook manquante. Reconnecte-toi à Facebook puis réessaie.",
    );
  }

  const pages: ManagedPage[] = [];
  let after: string | null = null;

  for (let i = 0; i < MAX_PAGES_OF_RESULTS; i++) {
    const url = new URL(`https://graph.facebook.com/${GRAPH_VERSION}/me/accounts`);
    url.searchParams.set("fields", "id,name,category,picture.type(large){url},tasks,access_token");
    url.searchParams.set("limit", "100");
    if (after) url.searchParams.set("after", after);

    let res: Response;
    try {
      res = await fetch(url, { headers: { Authorization: `Bearer ${userToken}` } });
    } catch {
      throw new HttpError(502, "meta_unreachable", "Meta est injoignable. Réessaie plus tard.");
    }

    if (res.status === 400 || res.status === 401 || res.status === 403) {
      throw new HttpError(
        401,
        "facebook_token_invalid",
        "L'autorisation Facebook a expiré. Reconnecte-toi à Facebook puis réessaie.",
      );
    }
    if (!res.ok) {
      throw new HttpError(502, "meta_error", "Meta a refusé la demande. Réessaie plus tard.");
    }

    const payload = await res.json();
    const rows: unknown[] = Array.isArray(payload?.data) ? payload.data : [];
    for (const row of rows) {
      const r = row as Record<string, unknown>;
      if (typeof r.id !== "string" || typeof r.name !== "string") continue;
      const picture = r.picture as { data?: { url?: unknown } } | undefined;
      pages.push({
        id: r.id,
        name: r.name,
        category: typeof r.category === "string" ? r.category : null,
        pictureUrl: typeof picture?.data?.url === "string" ? picture.data.url : null,
        accessToken: typeof r.access_token === "string" ? r.access_token : null,
        tasks: Array.isArray(r.tasks) ? r.tasks.filter((t): t is string => typeof t === "string") : null,
      });
    }

    after = payload?.paging?.next ? (payload?.paging?.cursors?.after ?? null) : null;
    if (!after) break;
  }

  return pages;
}
