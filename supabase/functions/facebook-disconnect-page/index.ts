// Déconnecte la Page Facebook active d'un espace de travail.
// Entrée  : { workspace_id: uuid }
// Sortie  : { disconnected: number }
// La Page est désactivée (historique conservé) et son jeton supprimé par
// public.disconnect_facebook_page, qui revérifie le rôle de l'appelant.
import { requireUser, serviceClient } from "../_shared/auth.ts";
import { HttpError, handle, json } from "../_shared/http.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(handle(async (req, body) => {
  const user = await requireUser(req);

  const workspaceId = String(body.workspace_id ?? "");
  if (!UUID.test(workspaceId)) {
    throw new HttpError(400, "invalid_request", "Demande invalide.");
  }

  const { data, error } = await serviceClient().rpc("disconnect_facebook_page", {
    p_workspace_id: workspaceId,
    p_user_id: user.id,
  });

  if (error) {
    if (error.code === "42501") {
      throw new HttpError(
        403,
        "forbidden",
        "Tu n'as pas le droit de déconnecter la Page de cet espace.",
      );
    }
    console.error("disconnect_facebook_page a échoué", error.code);
    throw new HttpError(500, "disconnect_failed", "La déconnexion a échoué.");
  }

  return json({ disconnected: data ?? 0 });
}));
