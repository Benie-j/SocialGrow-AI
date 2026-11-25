// Connecte une Page Facebook à un espace de travail.
// Entrée  : { workspace_id: uuid, meta_page_id: string, provider_token: string }
// Sortie  : { page: { id, meta_page_id, page_name } }
//
// La Page n'est jamais acceptée telle que le client la décrit : on la retrouve
// chez Meta parmi les Pages que cet utilisateur gère, puis on stocke son jeton
// chiffré côté serveur. Le droit de connecter (propriétaire ou administrateur)
// est revérifié en base par public.connect_facebook_page.
import { requireUser, serviceClient } from "../_shared/auth.ts";
import { encryptToken } from "../_shared/crypto.ts";
import { canPublish, fetchManagedPages } from "../_shared/graph.ts";
import { HttpError, handle, json } from "../_shared/http.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const META_ID = /^\d{5,32}$/;

Deno.serve(handle(async (req, body) => {
  const user = await requireUser(req);

  const workspaceId = String(body.workspace_id ?? "");
  const metaPageId = String(body.meta_page_id ?? "");
  if (!UUID.test(workspaceId) || !META_ID.test(metaPageId)) {
    throw new HttpError(400, "invalid_request", "Demande invalide.");
  }

  const managed = await fetchManagedPages(String(body.provider_token ?? ""));
  const page = managed.find((p) => p.id === metaPageId);
  if (!page || !canPublish(page)) {
    throw new HttpError(
      403,
      "page_not_managed",
      "Tu ne gères pas cette Page, ou tu n'as pas le droit d'y publier.",
    );
  }
  if (!page.accessToken) {
    throw new HttpError(
      422,
      "page_token_missing",
      "Meta n'a pas fourni d'autorisation pour cette Page. Reconnecte-toi à Facebook et accepte l'accès à la Page.",
    );
  }

  const ciphertext = await encryptToken(page.accessToken);

  const { data, error } = await serviceClient().rpc("connect_facebook_page", {
    _workspace_id: workspaceId,
    _user_id: user.id,
    _meta_page_id: page.id,
    _page_name: page.name,
    _category: page.category,
    _picture_url: page.pictureUrl,
    _token_ciphertext: ciphertext,
    _token_expires_at: null,
  });

  if (error) {
    if (error.code === "42501") {
      throw new HttpError(
        403,
        "forbidden",
        "Seuls les propriétaires et administrateurs peuvent connecter une Page.",
      );
    }
    console.error("connect_facebook_page a échoué", error.code);
    throw new HttpError(500, "connect_failed", "La connexion de la Page a échoué.");
  }

  return json({
    page: { id: data, meta_page_id: page.id, page_name: page.name },
  });
}));
