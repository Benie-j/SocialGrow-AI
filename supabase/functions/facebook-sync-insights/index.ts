import { createClient } from "npm:@supabase/supabase-js@2";

// Collecte quotidienne des statistiques de Page (Graph API /{page-id}/insights).
// Appelée par pg_cron via pg_net. Sécurité : en-tête x-cron-secret vérifié dans la base.
// Mesures actuelles uniquement : Meta a retiré page_impressions*, page_fans, page_fan_adds
// (nov. 2025) et page_impressions_unique (juin 2026).

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error("server_misconfigured");
  return value;
}

type Admin = ReturnType<typeof createClient>;

// Chaque mesure est demandée séparément : une mesure refusée ne bloque pas les autres.
const METRICS = [
  "page_total_media_view_unique", // portée (remplace page_impressions_unique)
  "page_media_view", // vues (remplace page_impressions)
  "page_post_engagements", // interactions
  "page_follows", // abonnés (remplace page_fans)
  "page_daily_follows", // nouveaux abonnés du jour (remplace page_fan_adds)
];
const WINDOW_DAYS = 28;
const DAY_MS = 24 * 60 * 60 * 1000;

async function syncPage(
  admin: Admin,
  page: { id: string; workspace_id: string; meta_page_id: string },
): Promise<string> {
  const { data: token, error: tokenError } = await admin.rpc("get_facebook_page_token", { _facebook_page_id: page.id });
  if (tokenError || typeof token !== "string" || token.length < 20) {
    await record(admin, page, [], "Jeton Facebook indisponible : reconnecte la Page.");
    return "token_unavailable";
  }

  const version = Deno.env.get("META_GRAPH_VERSION") ?? "v27.0";
  const until = Math.floor(Date.now() / 1000);
  const since = until - WINDOW_DAYS * 86400;
  const rows: Record<string, unknown>[] = [];
  const ok: string[] = [];
  let blocking: string | null = null;
  let invalid = 0;

  for (const metric of METRICS) {
    const url = new URL(`https://graph.facebook.com/${version}/${encodeURIComponent(page.meta_page_id)}/insights`);
    url.searchParams.set("metric", metric);
    url.searchParams.set("period", "day");
    url.searchParams.set("since", String(since));
    url.searchParams.set("until", String(until));
    let res: Response;
    try {
      res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    } catch {
      blocking ??= "Meta est injoignable.";
      continue;
    }
    const payload = await res.json().catch(() => ({}));
    if (!res.ok) {
      const code = Number(payload?.error?.code ?? 0);
      if (code === 100) { invalid++; continue; } // mesure inconnue ou retirée
      if (code === 190) blocking ??= "L'autorisation Facebook a expiré : reconnecte la Page.";
      else if (code === 10 || code === 200) blocking ??= "Autorisation manquante : la permission « read_insights » n'est pas accordée à l'app pour cette Page.";
      else blocking ??= `Meta a refusé la demande (code ${code || res.status}).`;
      continue;
    }
    const values = payload?.data?.[0]?.values;
    if (!Array.isArray(values)) continue;
    let count = 0;
    for (const v of values) {
      const value = (v as Record<string, unknown>)?.value;
      const end = new Date(String((v as Record<string, unknown>)?.end_time ?? ""));
      if (typeof value !== "number" || Number.isNaN(end.getTime())) continue;
      // La valeur d'un jour est datée de la fin de la période : on retient le jour écoulé.
      const day = new Date(end.getTime() - DAY_MS).toISOString().slice(0, 10);
      rows.push({
        workspace_id: page.workspace_id, facebook_page_id: page.id, metric_date: day,
        metric_name: metric, metric_value: value, dimensions: {}, collected_at: new Date().toISOString(),
      });
      count++;
    }
    if (count > 0) ok.push(metric);
  }

  if (rows.length > 0) {
    const { error } = await admin.from("page_insights").upsert(rows, { onConflict: "facebook_page_id,metric_date,metric_name,dimensions" });
    if (error) { await record(admin, page, [], "Enregistrement des statistiques impossible."); return "store_failed"; }
  }
  const error = rows.length > 0 ? null
    : blocking ?? (invalid === METRICS.length ? "Meta ne fournit aucune de ces mesures pour cette Page." : "Meta n'a renvoyé aucune donnée pour le moment (Page récente ou peu active).");
  await record(admin, page, ok, error);
  return rows.length > 0 ? `ok:${rows.length}` : "no_data";
}

async function record(admin: Admin, page: { id: string; workspace_id: string }, ok: string[], error: string | null) {
  const now = new Date().toISOString();
  await admin.from("page_insights_sync").upsert({
    facebook_page_id: page.id, workspace_id: page.workspace_id, last_attempt_at: now,
    last_success_at: error === null ? now : undefined, last_error: error, metrics_ok: ok,
  }, { onConflict: "facebook_page_id" });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const admin = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: allowed, error: verifyError } = await admin.rpc("verify_cron_secret", { _secret: req.headers.get("x-cron-secret") ?? "" });
    if (verifyError || allowed !== true) return json({ error: "unauthenticated" }, 401);

    const { data: pages, error } = await admin.from("facebook_pages").select("id,workspace_id,meta_page_id").eq("is_active", true).limit(25);
    if (error) return json({ error: "query_failed" }, 500);

    const results: Record<string, string> = {};
    for (const page of pages ?? []) {
      try {
        results[String(page.id)] = await syncPage(admin, page as { id: string; workspace_id: string; meta_page_id: string });
      } catch (e) {
        console.error("insights_sync_failed", e instanceof Error ? e.message : "unknown");
        results[String(page.id)] = "failed";
      }
    }
    return json({ ok: true, results });
  } catch (error) {
    console.error("insights_sync_internal", error instanceof Error ? error.message : "unknown");
    return json({ error: "internal_error" }, 500);
  }
});
