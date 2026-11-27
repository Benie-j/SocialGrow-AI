import { createClient } from "npm:@supabase/supabase-js@2";

// Appelée chaque minute par pg_cron (via pg_net) quand une publication est échue.
// Sécurité : en-tête x-cron-secret vérifié dans la base (verify_cron_secret).
// Cette fonction doit être déployée SANS vérification JWT (appel sans session).

const MAX_PER_RUN = 10;
const MAX_LATE_MS = 6 * 60 * 60 * 1000; // au-delà, on ne publie plus : à reprogrammer
const STUCK_MS = 15 * 60 * 1000;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error("server_misconfigured");
  return value;
}

type Admin = ReturnType<typeof createClient>;
type Outcome = "published" | "failed" | "skipped";

async function fail(admin: Admin, postId: string, message: string, expected: string): Promise<Outcome> {
  await admin.from("posts").update({
    status: "failed", error_message: message, updated_at: new Date().toISOString(),
  }).eq("id", postId).eq("status", expected);
  return "failed";
}

async function processPost(
  admin: Admin,
  post: Record<string, unknown>,
  paused: Map<string, boolean>,
): Promise<Outcome> {
  const postId = String(post.id);
  const workspaceId = String(post.workspace_id);

  if (!paused.has(workspaceId)) {
    const { data, error } = await admin.from("publication_settings")
      .select("publishing_paused").eq("workspace_id", workspaceId).maybeSingle();
    if (error) return "skipped";
    paused.set(workspaceId, data?.publishing_paused === true);
  }
  if (paused.get(workspaceId)) return "skipped";

  const lateMs = Date.now() - new Date(String(post.scheduled_at)).getTime();
  if (lateMs > MAX_LATE_MS) {
    return fail(admin, postId, "L'heure prévue est dépassée de plus de 6 h : la publication n'est pas partie. Reprogramme-la.", "scheduled");
  }
  const imageUrl = typeof post.image_url === "string" ? post.image_url : "";
  const withPhoto = post.content_type === "image" && imageUrl.startsWith("https://");
  if (post.content_type !== "text" && !withPhoto) {
    return fail(admin, postId, "Ce type de publication n'est pas pris en charge.", "scheduled");
  }
  const text = typeof post.body === "string" ? post.body.trim() : "";
  if (!text || text.length > 63206) {
    return fail(admin, postId, "Le texte est vide ou dépasse la limite autorisée par Facebook.", "scheduled");
  }
  const pageId = typeof post.facebook_page_id === "string" ? post.facebook_page_id : "";
  if (!/^[0-9a-f-]{36}$/i.test(pageId)) {
    return fail(admin, postId, "Aucune Page Facebook n'est associée à cette publication.", "scheduled");
  }

  const { data: page } = await admin.from("facebook_pages")
    .select("id,meta_page_id,is_active").eq("id", pageId).eq("workspace_id", workspaceId).eq("is_active", true).maybeSingle();
  if (!page) return fail(admin, postId, "La Page Facebook n'est plus connectée ou active.", "scheduled");

  // Compare-and-set : annulation ou autre exécution en parallèle => on n'envoie rien.
  const { data: claimed, error: claimError } = await admin.from("posts").update({
    status: "publishing", error_message: null, updated_at: new Date().toISOString(),
  }).eq("id", postId).eq("workspace_id", workspaceId).eq("status", "scheduled").select("id").maybeSingle();
  if (claimError || !claimed) return "skipped";

  const { data: pageToken, error: tokenError } = await admin.rpc("get_facebook_page_token", { _facebook_page_id: pageId });
  if (tokenError || typeof pageToken !== "string" || pageToken.length < 20) {
    return fail(admin, postId, "Jeton Facebook indisponible. Reconnecte la Page.", "publishing");
  }

  const version = Deno.env.get("META_GRAPH_VERSION") ?? "v27.0";
  const endpoint = `https://graph.facebook.com/${version}/${encodeURIComponent(String(page.meta_page_id))}/${withPhoto ? "photos" : "feed"}`;
  let response: Response;
  try {
    response = await fetch(endpoint, {
      method: "POST",
      headers: { Authorization: `Bearer ${pageToken}`, "Content-Type": "application/x-www-form-urlencoded" },
      body: withPhoto ? new URLSearchParams({ url: imageUrl, caption: text }) : new URLSearchParams({ message: text }),
    });
  } catch {
    // Pas de nouvel essai automatique : Meta a peut-être reçu la demande (risque de doublon).
    return fail(admin, postId, "Connexion interrompue pendant la publication. Vérifie la Page Facebook avant toute nouvelle tentative.", "publishing");
  }

  const meta = await response.json().catch(() => ({}));
  const metaPostId = typeof meta?.post_id === "string" && meta.post_id ? meta.post_id : meta?.id;
  if (!response.ok || typeof metaPostId !== "string" || !metaPostId) {
    const message = typeof meta?.error?.message === "string" ? meta.error.message.slice(0, 500) : "Meta a refusé la publication.";
    return fail(admin, postId, message, "publishing");
  }

  const now = new Date().toISOString();
  const { error: updateError } = await admin.from("posts").update({
    status: "published", meta_post_id: metaPostId, published_at: now, error_message: null, updated_at: now,
  }).eq("id", postId).eq("status", "publishing");
  if (updateError) console.error("scheduled_published_database_update_failed", updateError.code);
  return "published";
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const admin = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const secret = req.headers.get("x-cron-secret") ?? "";
    const { data: allowed, error: verifyError } = await admin.rpc("verify_cron_secret", { _secret: secret });
    if (verifyError || allowed !== true) return json({ error: "unauthenticated" }, 401);

    // Publications restées « en cours » : on ne les relance jamais seules.
    await admin.from("posts").update({
      status: "failed",
      error_message: "Publication interrompue. Vérifie la Page Facebook avant de réessayer.",
      updated_at: new Date().toISOString(),
    }).eq("status", "publishing").lt("updated_at", new Date(Date.now() - STUCK_MS).toISOString());

    const { data: due, error: dueError } = await admin.from("posts")
      .select("id,workspace_id,facebook_page_id,body,content_type,image_url,scheduled_at")
      .eq("status", "scheduled").lte("scheduled_at", new Date().toISOString())
      .order("scheduled_at", { ascending: true }).limit(MAX_PER_RUN);
    if (dueError) return json({ error: "query_failed" }, 500);

    const counts = { published: 0, failed: 0, skipped: 0 };
    const paused = new Map<string, boolean>();
    for (const post of due ?? []) {
      try {
        counts[await processPost(admin, post as Record<string, unknown>, paused)]++;
      } catch (error) {
        console.error("scheduled_post_failed", error instanceof Error ? error.message : "unknown");
        await admin.from("posts").update({
          status: "failed", error_message: "Erreur serveur pendant la publication.", updated_at: new Date().toISOString(),
        }).eq("id", String((post as Record<string, unknown>).id)).eq("status", "publishing");
        counts.failed++;
      }
    }
    return json({ ok: true, processed: (due ?? []).length, ...counts });
  } catch (error) {
    console.error("publish_scheduled_posts_failed", error instanceof Error ? error.message : "unknown");
    return json({ error: "internal_error" }, 500);
  }
});
