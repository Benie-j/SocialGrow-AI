// Liste les Pages Facebook que l'utilisateur connecté gère.
// Entrée  : { provider_token: string }  (jeton Facebook de la session)
// Sortie  : { pages: [{ id, name, category, picture_url }], diagnostic? }
//           `diagnostic` n'est présent que si la liste est vide : il dit pourquoi
//           (raison + permissions accordées par Meta), sans aucun jeton.
// Aucun jeton de Page n'est jamais renvoyé au client.
import { requireUser } from "../_shared/auth.ts";
import { canPublish, fetchGrantedPermissions, fetchManagedPages } from "../_shared/graph.ts";
import { handle, json } from "../_shared/http.ts";

Deno.serve(handle(async (req, body) => {
  await requireUser(req);

  const providerToken = String(body.provider_token ?? "");
  const pages = await fetchManagedPages(providerToken);
  const publishable = pages.filter(canPublish);

  const result = publishable.map((p) => ({
    id: p.id,
    name: p.name,
    category: p.category,
    picture_url: p.pictureUrl,
  }));

  if (result.length > 0) return json({ pages: result });

  // Liste vide : on explique pourquoi pour que l'app puisse guider l'utilisateur.
  const permissions = await fetchGrantedPermissions(providerToken);
  let reason: string;
  if (pages.length > 0) {
    reason = "no_publish_rights";
  } else if (permissions && !permissions.granted.includes("pages_show_list")) {
    reason = "missing_pages_permission";
  } else {
    reason = "no_pages_shared";
  }

  return json({
    pages: [],
    diagnostic: {
      reason,
      total_pages: pages.length,
      granted_permissions: permissions?.granted ?? null,
      declined_permissions: permissions?.declined ?? null,
    },
  });
}));
