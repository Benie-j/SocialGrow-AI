// Connecte ou déconnecte la Page Facebook d'un espace de travail.
//
// POST { action: "connect", workspace_id, provider_token, meta_page_id }
//   -> 200 { page: { id, meta_page_id, name, category, picture_url }, long_lived: boolean }
// POST { action: "disconnect", workspace_id }
//   -> 200 { disconnected: number }
//
// La Page choisie est revérifiée auprès de Facebook : elle doit faire partie des Pages
// que l'utilisateur gère réellement. Le jeton de Page est chiffré puis stocké dans
// private.facebook_credentials, inaccessible aux clients.

import {
  adminClient,
  authenticate,
  encryptToken,
  exchangeForLongLivedToken,
  fetchManagedPages,
  handler,
  HttpError,
  json,
  requireProviderToken,
  requireUuid,
  requireWriteAccess,
} from "../_shared/common.ts";

const META_PAGE_ID = /^\d{5,30}$/;
// Sans jeton longue durée, le jeton de Page expire en quelques heures.
const SHORT_LIVED_TTL_MS = 55 * 60 * 1000;

export const handle = handler(async (req, body) => {
  const admin = adminClient();
  const user = await authenticate(req, admin);
  const workspaceId = requireUuid(body.workspace_id, "workspace_id");
  await requireWriteAccess(admin, workspaceId, user.id);

  if (body.action === "disconnect") {
    const { data, error } = await admin.rpc("disconnect_facebook_page", {
      p_workspace_id: workspaceId,
      p_user_id: user.id,
    });
    if (error) throw new Error("Déconnexion impossible");
    return json({ disconnected: data ?? 0 });
  }

  if (body.action !== "connect") {
    throw new HttpError(400, "invalid_body", "Action inconnue.");
  }

  const metaPageId = typeof body.meta_page_id === "string" ? body.meta_page_id : "";
  if (!META_PAGE_ID.test(metaPageId)) {
    throw new HttpError(400, "invalid_body", "Identifiant de Page invalide.");
  }
  let userToken = requireProviderToken(body.provider_token);

  const longLivedToken = await exchangeForLongLivedToken(userToken);
  if (longLivedToken) userToken = longLivedToken;

  const pages = await fetchManagedPages(userToken);
  const page = pages.find((p) => p.id === metaPageId);
  if (!page) {
    throw new HttpError(404, "page_not_found", "Cette Page ne fait pas partie de celles que tu gères.");
  }
  if (!page.accessToken) {
    throw new HttpError(
      403,
      "facebook_permission_missing",
      "Facebook n'a pas fourni d'accès de publication pour cette Page.",
    );
  }

  const longLived = longLivedToken !== null;
  const { data, error } = await admin.rpc("connect_facebook_page", {
    p_workspace_id: workspaceId,
    p_user_id: user.id,
    p_meta_page_id: page.id,
    p_page_name: page.name,
    p_category: page.category,
    p_picture_url: page.pictureUrl,
    p_token_ciphertext: await encryptToken(page.accessToken),
    p_token_expires_at: longLived ? null : new Date(Date.now() + SHORT_LIVED_TTL_MS).toISOString(),
  });
  if (error) {
    if (error.code === "42501") {
      throw new HttpError(403, "forbidden", "Tu n'as pas les droits pour gérer la Page de cet espace.");
    }
    throw new Error("Connexion de la Page impossible");
  }

  return json({
    page: {
      id: data,
      meta_page_id: page.id,
      name: page.name,
      category: page.category,
      picture_url: page.pictureUrl,
    },
    long_lived: longLived,
  });
});

