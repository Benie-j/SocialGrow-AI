// Connecte une Page Facebook à un espace de travail.
// Entrée  : { workspace_id: uuid, meta_page_id: string, provider_token: string }
// Sortie  : { page: { id, meta_page_id, page_name } }
//
// La Page n'est jamais acceptée telle que le client la décrit : on la retrouve
// chez Meta parmi les Pages que cet utilisateur gère. Son jeton est chiffré par
// la base (public.encrypt_facebook_token, clé dans le Vault) puis enregistré par
// public.connect_facebook_page, qui revérifie le rôle (owner, admin ou editor)
// et ne garde qu'une Page active par espace.
import { requireUser, serviceClient } from "../_shared/auth.ts";
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

  const db = serviceClient();

  const encrypted = await db.rpc("encrypt_facebook_token", { _plain: page.accessToken });
  if (encrypted.error || typeof encrypted.data !== "string") {
    console.error("encrypt_facebook_token a échoué", encrypted.error?.code);
    throw new HttpError(500, "encryption_failed", "La connexion de la Page a échoué.");
  }

  const { data, error } = await db.rpc("connect_facebook_page", {
    p_workspace_id: workspaceId,
    p_user_id: user.id,
    p_meta_page_id: page.id,
    p_page_name: page.name,
    p_category: page.category,
    p_picture_url: page.pictureUrl,
    p_token_ciphertext: encrypted.data,
    p_token_expires_at: null,
  });

  if (error) {
    if (error.code === "42501") {
      throw new HttpError(
        403,
        "forbidden",
        "Tu n'as pas le droit de connecter une Page à cet espace.",
      );
    }
    console.error("connect_facebook_page a échoué", error.code);
    throw new HttpError(500, "connect_failed", "La connexion de la Page a échoué.");
  }

  return json({
    page: { id: data, meta_page_id: page.id, page_name: page.name },
  });
}));
