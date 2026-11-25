// Liste les Pages Facebook que l'utilisateur connecté peut gérer.
//
// POST { workspace_id: uuid, provider_token: string }
//   -> 200 { pages: [{ id, name, category, picture_url }] }
// Le jeton de Page n'est jamais renvoyé à l'application.

import {
  adminClient,
  authenticate,
  fetchManagedPages,
  handler,
  json,
  requireProviderToken,
  requireUuid,
  requireWriteAccess,
} from "../_shared/common.ts";

export const handle = handler(async (req, body) => {
  const admin = adminClient();
  const user = await authenticate(req, admin);
  const workspaceId = requireUuid(body.workspace_id, "workspace_id");
  const providerToken = requireProviderToken(body.provider_token);

  await requireWriteAccess(admin, workspaceId, user.id);

  const pages = await fetchManagedPages(providerToken);
  return json({
    pages: pages.map((p) => ({
      id: p.id,
      name: p.name,
      category: p.category,
      picture_url: p.pictureUrl,
    })),
  });
});

