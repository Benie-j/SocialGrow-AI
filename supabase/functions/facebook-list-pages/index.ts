// Liste les Pages Facebook que l'utilisateur connecté gère.
// Entrée  : { provider_token: string }  (jeton Facebook de la session)
// Sortie  : { pages: [{ id, name, category, picture_url }] }
// Aucun jeton de Page n'est jamais renvoyé au client.
import { requireUser } from "../_shared/auth.ts";
import { canPublish, fetchManagedPages } from "../_shared/graph.ts";
import { handle, json } from "../_shared/http.ts";

Deno.serve(handle(async (req, body) => {
  await requireUser(req);

  const pages = await fetchManagedPages(String(body.provider_token ?? ""));

  return json({
    pages: pages.filter(canPublish).map((p) => ({
      id: p.id,
      name: p.name,
      category: p.category,
      picture_url: p.pictureUrl,
    })),
  });
}));
