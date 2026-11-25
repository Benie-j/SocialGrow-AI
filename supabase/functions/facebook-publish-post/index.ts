import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error("server_misconfigured");
  return value;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let admin: ReturnType<typeof createClient> | null = null;
  let postId = "";
  try {
    const supabaseUrl = env("SUPABASE_URL");
    const anonKey = env("SUPABASE_ANON_KEY");
    const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY");
    const authorization = req.headers.get("Authorization") ?? "";
    const jwt = authorization.startsWith("Bearer ") ? authorization.slice(7).trim() : "";
    if (!jwt) return json({ error: "unauthenticated", message: "Connexion requise." }, 401);

    const auth = createClient(supabaseUrl, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: authData, error: authError } = await auth.auth.getUser(jwt);
    if (authError || !authData.user) return json({ error: "unauthenticated", message: "Session invalide ou expirée." }, 401);
    const userId = authData.user.id;

    let body: Record<string, unknown>;
    try {
      const parsed = await req.json();
      body = parsed && typeof parsed === "object" ? parsed : {};
    } catch {
      return json({ error: "invalid_json", message: "Corps JSON invalide." }, 400);
    }

    postId = String(body.post_id ?? "");
    const workspaceId = String(body.workspace_id ?? "");
    const pageId = String(body.facebook_page_id ?? "");
    if (!/^[0-9a-f-]{36}$/i.test(postId) || !/^[0-9a-f-]{36}$/i.test(workspaceId) || !/^[0-9a-f-]{36}$/i.test(pageId)) {
      return json({ error: "invalid_request", message: "Publication, espace ou Page invalide." }, 400);
    }

    admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: member, error: memberError } = await admin.from("workspace_members")
      .select("role").eq("workspace_id", workspaceId).eq("user_id", userId).maybeSingle();
    if (memberError || !member || !["owner", "admin", "editor"].includes(String(member.role))) {
      return json({ error: "forbidden", message: "Ton rôle ne permet pas de publier dans cet espace." }, 403);
    }

    const { data: publicationSettings, error: publicationSettingsError } = await admin.from("publication_settings")
      .select("publishing_paused").eq("workspace_id", workspaceId).maybeSingle();
    if (publicationSettingsError) return json({ error: "settings_unavailable", message: "Impossible de vérifier les paramètres de publication." }, 500);
    if (publicationSettings?.publishing_paused === true) {
      return json({ error: "publishing_paused", message: "La publication est suspendue dans les paramètres de cet espace." }, 409);
    }

    const { data: page, error: pageError } = await admin.from("facebook_pages")
      .select("id,meta_page_id,page_name,is_active,workspace_id")
      .eq("id", pageId).eq("workspace_id", workspaceId).eq("is_active", true).maybeSingle();
    if (pageError || !page) return json({ error: "page_unavailable", message: "Cette Page Facebook n'est pas connectée ou active." }, 404);

    const { data: post, error: postError } = await admin.from("posts")
      .select("id,workspace_id,facebook_page_id,body,status,content_type,meta_post_id")
      .eq("id", postId).eq("workspace_id", workspaceId).maybeSingle();
    if (postError || !post) return json({ error: "post_not_found", message: "Publication introuvable." }, 404);
    if (post.content_type !== "text") return json({ error: "unsupported_content_type", message: "Cette première version publie uniquement les textes." }, 422);
    if (typeof post.body !== "string" || !post.body.trim() || post.body.length > 63206) {
      return json({ error: "invalid_content", message: "Le texte est vide ou dépasse la limite autorisée par Facebook." }, 400);
    }
    if (post.facebook_page_id && post.facebook_page_id !== pageId) {
      return json({ error: "page_mismatch", message: "Cette publication est associée à une autre Page." }, 409);
    }
    if (post.status === "published") {
      return json({ ok: true, already_published: true, meta_post_id: post.meta_post_id, message: "Cette publication est déjà marquée comme publiée." });
    }
    if (!["draft", "failed", "scheduled"].includes(String(post.status))) {
      return json({ error: "invalid_post_state", message: "Cette publication est déjà en cours de traitement ou ne peut pas être publiée." }, 409);
    }

    // Compare-and-set : deux clics simultanés ne peuvent pas lancer deux publications.
    const { data: claimed, error: claimError } = await admin.from("posts").update({
      facebook_page_id: pageId, status: "publishing", error_message: null, updated_at: new Date().toISOString(),
    }).eq("id", postId).eq("workspace_id", workspaceId).in("status", ["draft", "failed", "scheduled"])
      .select("id").maybeSingle();
    if (claimError || !claimed) return json({ error: "publish_in_progress", message: "Cette publication est déjà en cours ou a changé d'état." }, 409);

    const { data: pageToken, error: tokenError } = await admin.rpc("get_facebook_page_token", { _facebook_page_id: pageId });
    if (tokenError || typeof pageToken !== "string" || pageToken.length < 20) {
      await admin.from("posts").update({ status: "failed", error_message: "Jeton Facebook indisponible. Reconnecte la Page.", updated_at: new Date().toISOString() }).eq("id", postId);
      return json({ error: "page_token_unavailable", message: "Autorisation Facebook indisponible. Déconnecte puis reconnecte la Page." }, 422);
    }

    const version = Deno.env.get("META_GRAPH_VERSION") ?? "v27.0";
    const endpoint = `https://graph.facebook.com/${version}/${encodeURIComponent(String(page.meta_page_id))}/feed`;
    const form = new URLSearchParams({ message: String(post.body).trim() });
    let metaResponse: Response;
    try {
      metaResponse = await fetch(endpoint, {
        method: "POST",
        headers: { Authorization: `Bearer ${pageToken}`, "Content-Type": "application/x-www-form-urlencoded" },
        body: form,
      });
    } catch {
      await admin.from("posts").update({
        status: "failed",
        error_message: "Connexion interrompue pendant la publication. Vérifie la Page Facebook avant toute nouvelle tentative.",
        updated_at: new Date().toISOString(),
      }).eq("id", postId);
      return json({ error: "meta_network_error", message: "Connexion interrompue. Vérifie d'abord la Page Facebook : Meta a peut-être reçu la demande." }, 502);
    }

    const meta = await metaResponse.json().catch(() => ({}));
    if (!metaResponse.ok || typeof meta?.id !== "string" || !meta.id) {
      const metaMessage = typeof meta?.error?.message === "string" ? meta.error.message.slice(0, 500) : "Meta a refusé la publication.";
      await admin.from("posts").update({
        status: "failed", error_message: metaMessage, updated_at: new Date().toISOString(),
      }).eq("id", postId);
      return json({ error: "meta_publish_failed", message: metaMessage }, 502);
    }

    const publishedAt = new Date().toISOString();
    const { error: updateError } = await admin.from("posts").update({
      status: "published", meta_post_id: meta.id, published_at: publishedAt,
      error_message: null, updated_at: publishedAt,
    }).eq("id", postId).eq("status", "publishing");
    if (updateError) {
      // Meta a confirmé la publication : ne pas re-déclencher automatiquement.
      console.error("meta_published_database_update_failed", updateError.code);
      return json({ ok: true, published: true, meta_post_id: meta.id, warning: "Publié sur Facebook, mais le statut local n'a pas pu être actualisé." }, 200);
    }

    return json({ ok: true, published: true, page_name: page.page_name, meta_post_id: meta.id, published_at: publishedAt });
  } catch (error) {
    console.error("facebook_publish_post_failed", error instanceof Error ? error.message : "unknown");
    if (admin && postId) {
      try {
        await admin.from("posts").update({
          status: "failed", error_message: "Erreur serveur pendant la publication.", updated_at: new Date().toISOString(),
        }).eq("id", postId).eq("status", "publishing");
      } catch { /* best effort */ }
    }
    return json({ error: "internal_error", message: "La publication a échoué côté serveur." }, 500);
  }
});
