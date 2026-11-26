import { createClient } from "npm:@supabase/supabase-js@2";

// Brouillons automatiques (3 par jour au plus). Appelée par pg_cron via pg_net.
// Sécurité : en-tête x-cron-secret vérifié dans la base (verify_cron_secret).
// Garde-fous : sources vérifiées contre les résultats réels de la recherche web,
// aucun nom de particulier, texte brut (pas de Markdown), image libre de droits
// avec crédit, et TOUJOURS un brouillon : jamais de publication sans validation.

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error("server_misconfigured");
  return value;
}

type Admin = ReturnType<typeof createClient>;
type Source = { title: string; url: string };
type Draft = { title: string; body: string; imageKeywords: string; sources: Source[]; topic: string };

// groq/compound a été retiré par Groq le 21/09/2026 : la recherche web passe par browser_search.
const MODEL = Deno.env.get("AUTOPOST_MODEL") ?? "openai/gpt-oss-120b";

// ---------- Texte brut : Facebook affiche tout tel quel, sans Markdown ----------

/** Retire tout balisage Markdown/HTML : « ***Salut*** » deviendrait sinon visible tel quel. */
export function toPlainText(input: string): string {
  return input
    .replace(/\r\n?/g, "\n")
    .replace(/```[\s\S]*?```/g, "")
    .replace(/<[^>]+>/g, "")
    .replace(/!\[[^\]]*\]\([^)]*\)/g, "")
    .replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g, "$1 ($2)")
    .replace(/^\s{0,3}#{1,6}\s+/gm, "")
    .replace(/^\s{0,3}>\s?/gm, "")
    .replace(/^\s*[-*+]\s+/gm, "• ")
    .replace(/(\*{1,3}|_{2,3})(\S(?:[^*_\n]*\S)?)\1/g, "$2")
    .replace(/[*`~]+/g, "")
    .replace(/(^|\s)_+|_+(?=\s|$)/g, "$1")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

/**
 * Facebook n'offre aucun gras/grande taille via l'API des Pages (le Markdown n'y est pas
 * interprété). Seule astuce répandue : les lettres « gras » Unicode (𝗟𝗶𝗸𝗲 𝗰𝗲𝗹𝗮). Réservé à un
 * titre court ; les accents passent en caractères combinants pour rester lisibles.
 */
export function toUnicodeBold(input: string): string {
  const out: string[] = [];
  for (const ch of input.normalize("NFD")) {
    const c = ch.codePointAt(0)!;
    if (c >= 0x41 && c <= 0x5a) out.push(String.fromCodePoint(0x1d5d4 + (c - 0x41)));
    else if (c >= 0x61 && c <= 0x7a) out.push(String.fromCodePoint(0x1d5ee + (c - 0x61)));
    else if (c >= 0x30 && c <= 0x39) out.push(String.fromCodePoint(0x1d7ec + (c - 0x30)));
    else out.push(ch);
  }
  return out.join("").normalize("NFC");
}

// ---------- Recherche + rédaction (Groq gpt-oss + browser_search) ----------

function normUrl(raw: string): string {
  try {
    const u = new URL(raw.trim());
    return (u.hostname.replace(/^www\./, "") + u.pathname.replace(/\/+$/, "")).toLowerCase();
  } catch {
    return "";
  }
}

function extractJson(text: string): Record<string, unknown> | null {
  const cleaned = text.replace(/```json|```/g, "");
  const start = cleaned.indexOf("{");
  const end = cleaned.lastIndexOf("}");
  if (start < 0 || end <= start) return null;
  try {
    const parsed = JSON.parse(cleaned.slice(start, end + 1));
    return parsed && typeof parsed === "object" ? parsed as Record<string, unknown> : null;
  } catch {
    return null;
  }
}

async function researchAndWrite(ctx: {
  groqKey: string; strategy: Record<string, unknown>; pub: Record<string, unknown>;
  recentTopics: string[]; maxHashtags: number;
}): Promise<{ draft: Draft | null; reason?: string; usage: { input: number; output: number } }> {
  const { strategy, pub } = ctx;
  const list = (v: unknown) => (Array.isArray(v) ? v.join(", ") : "");
  const system = [
    "Tu es le rédacteur d'une Page Facebook. Tu fais d'abord des recherches web, puis tu rédiges UNE publication.",
    "Choisis un thème pertinent pour la Page : fait divers, histoire, actualité, fait marquant ou anecdote récente et vérifiable.",
    "RÈGLE ABSOLUE : n'écris que des faits présents dans les pages trouvées. N'invente rien : ni chiffre, ni date, ni citation, ni lieu, ni nom.",
    "Si tu ne trouves pas un sujet fiable confirmé par au moins deux sources distinctes, réponds {\"skip\":true,\"reason\":\"...\"}.",
    "Interdits : nommer des particuliers (victimes, suspects, mineurs), accuser, spéculer, conseils médicaux ou juridiques, sujets violents ou choquants dans le détail.",
    "Le texte est du TEXTE BRUT. Facebook affiche tout tel quel : n'utilise AUCUN astérisque, dièse de titre, soulignement, backtick ni balisage Markdown. Pas de listes avec tirets : écris des paragraphes courts séparés par une ligne vide.",
    `Langue : ${String(pub.language ?? "fr")}. Ton : ${String(pub.default_tone ?? "professional")}. Style : ${String(pub.writing_style ?? "conversational")}. Public : ${String(pub.target_audience ?? "")}.`,
    `Activité de la Page : ${String(strategy.business_description ?? "")}. Signature : ${String(strategy.brand_tagline ?? "")}.`,
    `Piliers éditoriaux (pondération) : ${JSON.stringify(strategy.pillar_weights ?? {})}. Thèmes privilégiés : ${list(pub.preferred_topics)}. Thèmes à éviter : ${list(pub.avoided_topics)}.`,
    `Formules interdites : ${list(strategy.banned_phrases)}.`,
    `Hashtags : ${pub.hashtags_enabled === false ? "aucun" : "au plus " + ctx.maxHashtags + ", en fin de texte"}.`,
    "Longueur du corps : 500 à 900 caractères. Le titre fait 90 caractères maximum, sans point final.",
    "image_keywords : 2 à 4 mots-clés EN ANGLAIS décrivant un lieu, un objet ou une scène générique pour illustrer (jamais une personne identifiable).",
    "Réponds UNIQUEMENT avec un objet JSON : {\"topic\":\"...\",\"title\":\"...\",\"body\":\"...\",\"image_keywords\":\"...\",\"sources\":[{\"title\":\"...\",\"url\":\"https://...\"}]}",
  ].join("\n");
  const user = [
    "Trouve maintenant un thème du jour et rédige la publication.",
    ctx.recentTopics.length ? `Sujets déjà traités récemment, à ne pas répéter : ${ctx.recentTopics.join(" | ")}.` : "",
  ].filter(Boolean).join("\n");

  const res = await fetch("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: `Bearer ${ctx.groqKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: MODEL, temperature: 0.4, max_completion_tokens: 3500, reasoning_effort: "medium",
      tools: [{ type: "browser_search" }], tool_choice: "required",
      messages: [{ role: "system", content: system }, { role: "user", content: user }],
    }),
  });
  const payload = await res.json().catch(() => ({}));
  const usage = { input: Number(payload?.usage?.prompt_tokens ?? 0), output: Number(payload?.usage?.completion_tokens ?? 0) };
  if (!res.ok) {
    console.error("groq_error", res.status, String(payload?.error?.message ?? "").slice(0, 300));
    throw new Error(res.status === 429 ? "groq_rate_limited" : `groq_http_${res.status}`);
  }

  const message = payload?.choices?.[0]?.message ?? {};
  const parsed = extractJson(String(message.content ?? ""));
  if (!parsed) return { draft: null, reason: "invalid_output", usage };
  if (parsed.skip === true) return { draft: null, reason: "no_reliable_topic", usage };

  // Sources : on ne garde que les liens réellement renvoyés par la recherche web.
  const seen = new Set<string>();
  // Jamais le texte rédigé par le modèle : seulement ce que l'outil de recherche a renvoyé.
  const haystack = JSON.stringify({ t: message.executed_tools ?? [], a: message.annotations ?? [] });
  for (const m of haystack.matchAll(/https?:\/\/[^\s"'\\<>)\]]+/g)) seen.add(normUrl(m[0]));
  const claimed = Array.isArray(parsed.sources) ? parsed.sources : [];
  const sources: Source[] = [];
  for (const s of claimed) {
    const r = s as Record<string, unknown>;
    const url = typeof r?.url === "string" ? r.url.trim() : "";
    if (!/^https:\/\//.test(url) || !seen.has(normUrl(url))) continue;
    if (sources.some((x) => normUrl(x.url) === normUrl(url))) continue;
    sources.push({ title: String(r.title ?? "").slice(0, 150), url: url.slice(0, 500) });
  }
  const domains = new Set(sources.map((s) => normUrl(s.url).split("/")[0]));
  if (domains.size < 2) {
    console.error("autopost_sources", JSON.stringify({ keys: Object.keys(message), seen: seen.size, claimed: claimed.length, kept: sources.length }));
    return { draft: null, reason: "sources_not_verified", usage };
  }

  const title = toPlainText(String(parsed.title ?? "")).replace(/\s+/g, " ").slice(0, 90);
  const body = toPlainText(String(parsed.body ?? ""));
  if (title.length < 5 || body.length < 200 || body.length > 1500) return { draft: null, reason: "invalid_length", usage };
  return {
    draft: {
      title, body, sources: sources.slice(0, 3),
      topic: toPlainText(String(parsed.topic ?? title)).slice(0, 200),
      imageKeywords: String(parsed.image_keywords ?? "").replace(/[^\p{L}\p{N} ]/gu, " ").replace(/\s+/g, " ").trim().slice(0, 80),
    },
    usage,
  };
}

// ---------- Image libre de droits (Wikimedia Commons, crédit obligatoire) ----------

const FREE_LICENSES = /^(cc0|public domain|pd|cc[ -]by(-sa)?[ -]\d)/i;

async function findFreeImage(keywords: string): Promise<{ url: string; credit: string } | null> {
  if (keywords.length < 3) return null;
  const api = new URL("https://commons.wikimedia.org/w/api.php");
  for (const [k, v] of Object.entries({
    action: "query", format: "json", generator: "search", gsrnamespace: "6", gsrlimit: "10",
    gsrsearch: `${keywords} filetype:bitmap`, prop: "imageinfo",
    iiprop: "url|mime|size|extmetadata", iiurlwidth: "1200",
  })) api.searchParams.set(k, v);
  try {
    const res = await fetch(api, { headers: { "User-Agent": "SocialGrowAI/1.0 (contact: app owner)" } });
    if (!res.ok) return null;
    const pages = Object.values((await res.json())?.query?.pages ?? {}) as Record<string, unknown>[];
    pages.sort((a, b) => Number(a.index ?? 99) - Number(b.index ?? 99));
    for (const page of pages) {
      const info = (page.imageinfo as Record<string, unknown>[] | undefined)?.[0];
      if (!info) continue;
      const meta = (info.extmetadata ?? {}) as Record<string, { value?: string }>;
      const license = String(meta.LicenseShortName?.value ?? "");
      const thumb = String(info.thumburl ?? "");
      if (!FREE_LICENSES.test(license) || !["image/jpeg", "image/png"].includes(String(info.mime))) continue;
      if (Number(info.width ?? 0) < 800 || new URL(thumb).hostname !== "upload.wikimedia.org") continue;
      const artist = toPlainText(String(meta.Artist?.value ?? "")).replace(/\s+/g, " ").slice(0, 120) || "auteur inconnu";
      return { url: thumb, credit: `Photo : ${artist} (${license}), Wikimedia Commons` };
    }
  } catch { /* image facultative */ }
  return null;
}

// ---------- Une exécution pour un espace ----------

async function runWorkspace(admin: Admin, groqKey: string, workspaceId: string, boldTitles: boolean): Promise<string> {
  const { data: runId } = await admin.rpc("claim_ai_autopost_run", { _workspace_id: workspaceId });
  if (typeof runId !== "string") return "daily_limit_reached";
  const finish = (status: string, extra: Record<string, unknown> = {}) =>
    admin.from("ai_autopost_runs").update({ status, ...extra }).eq("id", runId);

  try {
    const [gsR, stratR, pubR, pageR, recentR, runsR] = await Promise.all([
      admin.from("groq_settings").select("monthly_generation_limit").eq("workspace_id", workspaceId).maybeSingle(),
      admin.from("editorial_strategy").select("business_description, brand_tagline, pillar_weights, banned_phrases").eq("workspace_id", workspaceId).maybeSingle(),
      admin.from("publication_settings").select("language, default_tone, writing_style, target_audience, preferred_topics, avoided_topics, hashtags_enabled, max_hashtags").eq("workspace_id", workspaceId).maybeSingle(),
      admin.from("facebook_pages").select("id").eq("workspace_id", workspaceId).eq("is_active", true).order("connected_at", { ascending: true }).limit(1).maybeSingle(),
      admin.from("posts").select("title").eq("workspace_id", workspaceId).order("created_at", { ascending: false }).limit(20),
      admin.from("ai_autopost_runs").select("topic").eq("workspace_id", workspaceId).not("topic", "is", null).order("created_at", { ascending: false }).limit(20),
    ]);
    const strategy = stratR.data as Record<string, unknown> | null;
    if (!strategy || !String(strategy.business_description ?? "").trim()) { await finish("rejected", { error_code: "no_strategy" }); return "no_strategy"; }
    if (!pageR.data) { await finish("rejected", { error_code: "no_page" }); return "no_page"; }

    const monthStart = new Date(); monthStart.setUTCDate(1); monthStart.setUTCHours(0, 0, 0, 0);
    const { count } = await admin.from("ai_generation_logs").select("id", { count: "exact", head: true })
      .eq("workspace_id", workspaceId).gte("created_at", monthStart.toISOString());
    if ((count ?? 0) >= Number(gsR.data?.monthly_generation_limit ?? 300)) { await finish("rejected", { error_code: "monthly_limit_reached" }); return "monthly_limit_reached"; }

    const started = Date.now();
    const pub = (pubR.data ?? {}) as Record<string, unknown>;
    const recentTopics = [...(recentR.data ?? []).map((r) => String(r.title ?? "")), ...(runsR.data ?? []).map((r) => String(r.topic ?? ""))]
      .filter(Boolean).slice(0, 25);
    const result = await researchAndWrite({
      groqKey, strategy, pub, recentTopics, maxHashtags: Math.max(0, Math.min(5, Number(pub.max_hashtags ?? 3))),
    });
    await admin.from("ai_generation_logs").insert({
      workspace_id: workspaceId, provider: "groq", model: MODEL, task_type: "autopost",
      input_tokens: result.usage.input, output_tokens: result.usage.output,
      latency_ms: Date.now() - started, success: result.draft !== null, error_code: result.reason ?? null,
    });
    if (!result.draft) { await finish("rejected", { error_code: result.reason ?? "rejected" }); return result.reason ?? "rejected"; }

    const d = result.draft;
    const image = await findFreeImage(d.imageKeywords);
    const head = boldTitles ? toUnicodeBold(d.title) : d.title;
    const sourceLines = d.sources.map((s) => s.url).join("\n");
    const text = [head, d.body, `Sources :\n${sourceLines}`, image ? image.credit : ""].filter(Boolean).join("\n\n");

    const { data: post, error: insertError } = await admin.from("posts").insert({
      workspace_id: workspaceId, facebook_page_id: pageR.data.id, title: d.title, body: text,
      content_type: image ? "image" : "text", status: "draft", source: "ai",
      image_url: image?.url ?? null, image_credit: image?.credit ?? null, source_urls: d.sources,
    }).select("id").single();
    if (insertError || !post) { await finish("failed", { error_code: "insert_failed" }); return "insert_failed"; }
    await finish("drafted", { topic: d.topic, post_id: post.id });
    return "drafted";
  } catch (error) {
    const code = error instanceof Error ? error.message.slice(0, 60) : "unknown";
    console.error("ai_autopost_failed", code);
    await finish("failed", { error_code: code });
    return "failed";
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const admin = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: allowed, error: verifyError } = await admin.rpc("verify_cron_secret", { _secret: req.headers.get("x-cron-secret") ?? "" });
    if (verifyError || allowed !== true) return json({ error: "unauthenticated" }, 401);

    const groqKey = env("GROQ_API_KEY");
    const { data: rows, error } = await admin.from("ai_autopost_settings").select("workspace_id, bold_titles").eq("enabled", true).limit(10);
    if (error) return json({ error: "query_failed" }, 500);

    const results: Record<string, string> = {};
    for (const row of rows ?? []) results[String(row.workspace_id)] = await runWorkspace(admin, groqKey, String(row.workspace_id), row.bold_titles !== false);
    return json({ ok: true, results });
  } catch (error) {
    console.error("ai_autopost_internal", error instanceof Error ? error.message : "unknown");
    return json({ error: "internal_error" }, 500);
  }
});
