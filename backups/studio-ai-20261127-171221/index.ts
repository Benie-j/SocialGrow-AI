import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const started = Date.now();
  let workspaceId = "";
  let userId = "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const groqKey = Deno.env.get("GROQ_API_KEY") ?? "";

  try {
    if (!supabaseUrl || !anonKey || !serviceKey || !groqKey) {
      return json({ error: "server_misconfigured", message: "Configuration serveur incomplète." }, 500);
    }
    const authorization = req.headers.get("Authorization") ?? "";
    const token = authorization.startsWith("Bearer ") ? authorization.slice(7).trim() : "";
    if (!token) return json({ error: "unauthenticated", message: "Connexion requise." }, 401);

    const authClient = createClient(supabaseUrl, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: authData, error: authError } = await authClient.auth.getUser(token);
    if (authError || !authData.user) return json({ error: "unauthenticated", message: "Session invalide ou expirée." }, 401);
    userId = authData.user.id;

    let body: Record<string, unknown>;
    try {
      const parsed = await req.json();
      body = parsed && typeof parsed === "object" ? parsed : {};
    } catch {
      return json({ error: "invalid_json", message: "Corps JSON invalide." }, 400);
    }

    workspaceId = String(body.workspace_id ?? "");
    const topic = String(body.topic ?? "").trim();
    if (!/^[0-9a-f-]{36}$/i.test(workspaceId)) return json({ error: "invalid_workspace", message: "Espace invalide." }, 400);
    if (topic.length < 3 || topic.length > 1200) return json({ error: "invalid_topic", message: "Le sujet doit contenir entre 3 et 1 200 caractères." }, 400);

    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: membership, error: membershipError } = await admin.from("workspace_members")
      .select("role").eq("workspace_id", workspaceId).eq("user_id", userId).maybeSingle();
    if (membershipError || !membership) return json({ error: "workspace_forbidden", message: "Tu n'as pas accès à cet espace." }, 403);
    if (!["owner", "admin", "editor"].includes(String(membership.role))) return json({ error: "role_forbidden", message: "Ton rôle ne permet pas de générer du contenu." }, 403);

    const [settingsResult, strategyResult, publicationResult] = await Promise.all([
      admin.from("groq_settings").select("model, creativity, max_output_tokens, monthly_generation_limit").eq("workspace_id", workspaceId).maybeSingle(),
      admin.from("editorial_strategy").select("business_description, brand_tagline, pillar_weights, voice_formality, voice_warmth, banned_phrases").eq("workspace_id", workspaceId).maybeSingle(),
      admin.from("publication_settings").select("language, default_tone, default_length, writing_style, allowed_categories, preferred_content_type, hashtags_enabled, max_hashtags, cta_enabled, primary_goal, target_audience, preferred_topics, avoided_topics, format_text_enabled").eq("workspace_id", workspaceId).maybeSingle(),
    ]);
    if (settingsResult.error || strategyResult.error || publicationResult.error) throw new Error("workspace_settings_read_failed");

    const gs = settingsResult.data ?? {};
    const strategy = strategyResult.data ?? {};
    const pub = publicationResult.data ?? {};
    const limit = Math.max(1, Math.min(10000, Number(gs.monthly_generation_limit ?? 300)));
    const monthStart = new Date();
    monthStart.setUTCDate(1);
    monthStart.setUTCHours(0, 0, 0, 0);
    const { count, error: countError } = await admin.from("ai_generation_logs")
      .select("id", { count: "exact", head: true })
      .eq("workspace_id", workspaceId).eq("task_type", "social_post")
      .gte("created_at", monthStart.toISOString());
    if (countError) throw new Error("usage_read_failed");
    if ((count ?? 0) >= limit) return json({ error: "monthly_limit_reached", message: "La limite mensuelle de génération de cet espace est atteinte." }, 429);
    if (pub.format_text_enabled === false) return json({ error: "text_format_disabled", message: "Le format texte est désactivé dans les paramètres." }, 409);

    const model = String(gs.model ?? "openai/gpt-oss-120b");
    const banned = Array.isArray(strategy.banned_phrases) ? strategy.banned_phrases.join(", ") : "";
    const avoided = Array.isArray(pub.avoided_topics) ? pub.avoided_topics.join(", ") : "";
    const preferred = Array.isArray(pub.preferred_topics) ? pub.preferred_topics.join(", ") : "";
    const categories = Array.isArray(pub.allowed_categories) ? pub.allowed_categories.join(", ") : "";
    const language = String(pub.language ?? "fr");
    const objective = String(pub.primary_goal ?? "engagement");
    const tone = String(pub.default_tone ?? "professional");
    const pillars = strategy.pillar_weights && typeof strategy.pillar_weights === "object" ? JSON.stringify(strategy.pillar_weights) : "{}";
    const formality = Math.max(1, Math.min(10, Number(strategy.voice_formality ?? 5)));
    const warmth = Math.max(1, Math.min(10, Number(strategy.voice_warmth ?? 5)));

    const systemPrompt = [
      "Tu es le rédacteur social media de JUN AI. Rédige une publication prête à relire, pas une analyse.",
      "Réponds dans la langue demandée. N'invente aucun chiffre, témoignage, résultat ou caractéristique produit.",
      "Respecte strictement le sujet et l'objectif. N'ajoute pas de faits non fournis.",
      `Réseau : Facebook. Objectif enregistré : ${objective}. Ton enregistré : ${tone}. Langue : ${language}.`,
      `Activité : ${String(strategy.business_description ?? "")}. Signature : ${String(strategy.brand_tagline ?? "")}.`,
      `Public cible : ${String(pub.target_audience ?? "")}.`,
      `Style : ${String(pub.writing_style ?? "conversational")}. Longueur : ${String(pub.default_length ?? "medium")}.`,
      `Catégories autorisées : ${categories || "aucune restriction enregistrée"}.`,
      `Type de contenu préféré : ${String(pub.preferred_content_type ?? "texte")}.`,
      `Thèmes privilégiés : ${preferred}. Thèmes à éviter : ${avoided}.`,
      `Pondération des piliers éditoriaux : ${pillars}. Favorise les piliers les plus pondérés.`,
      `Voix de marque : formalité ${formality}/10, chaleur ${warmth}/10.`,
      `Formules interdites : ${banned}.`,
      `Hashtags : ${pub.hashtags_enabled === false ? "ne pas ajouter" : "oui, maximum " + String(pub.max_hashtags ?? 3)}.`,
      `Appel à l'action : ${pub.cta_enabled === false ? "non" : "oui si pertinent"}.`,
      "Format de sortie : uniquement le texte de la publication, avec paragraphes et hashtags si adaptés.",
    ].join("\n");

    const groqResponse = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: { Authorization: `Bearer ${groqKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        messages: [{ role: "system", content: systemPrompt }, { role: "user", content: topic }],
        temperature: Math.max(0, Math.min(1.5, Number(gs.creativity ?? 7) / 10)),
        max_completion_tokens: Math.max(100, Math.min(2000, Number(gs.max_output_tokens ?? 500))),
      }),
    });
    const payload = await groqResponse.json().catch(() => ({}));
    if (!groqResponse.ok) {
      const code = groqResponse.status === 429 ? "groq_rate_limited" : "groq_request_failed";
      await admin.from("ai_generation_logs").insert({
        workspace_id: workspaceId, user_id: userId, provider: "groq", model,
        task_type: "social_post", input_tokens: Number(payload?.usage?.prompt_tokens ?? 0),
        output_tokens: Number(payload?.usage?.completion_tokens ?? 0),
        latency_ms: Date.now() - started, success: false, error_code: code,
      });
      return json({ error: code, message: groqResponse.status === 429 ? "Groq est temporairement saturé. Réessaie dans un instant." : "La génération a échoué côté fournisseur." }, groqResponse.status === 429 ? 429 : 502);
    }

    const content = payload?.choices?.[0]?.message?.content;
    if (typeof content !== "string" || !content.trim()) throw new Error("empty_model_response");
    const usage = payload?.usage ?? {};
    const { error: logError } = await admin.from("ai_generation_logs").insert({
      workspace_id: workspaceId, user_id: userId, provider: "groq", model,
      task_type: "social_post", input_tokens: Number(usage.prompt_tokens ?? usage.input_tokens ?? 0),
      output_tokens: Number(usage.completion_tokens ?? usage.output_tokens ?? 0),
      latency_ms: Date.now() - started, success: true, error_code: null,
    });
    if (logError) console.error("generation_log_insert_failed", logError.message);
    return json({
      content: content.trim(),
      usage: {
        input_tokens: Number(usage.prompt_tokens ?? usage.input_tokens ?? 0),
        output_tokens: Number(usage.completion_tokens ?? usage.output_tokens ?? 0),
      },
      remaining_this_month: Math.max(0, limit - (count ?? 0) - 1),
    });
  } catch (error) {
    console.error("groq_generate_content_failed", error instanceof Error ? error.message : "unknown");
    if (workspaceId && userId) {
      try {
        const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
        await admin.from("ai_generation_logs").insert({
          workspace_id: workspaceId, user_id: userId, provider: "groq",
          task_type: "social_post", input_tokens: 0, output_tokens: 0,
          latency_ms: Date.now() - started, success: false, error_code: "generation_internal_error",
        });
      } catch { /* best effort logging */ }
    }
    return json({ error: "generation_failed", message: "La génération a échoué. Vérifie les paramètres et réessaie." }, 500);
  }
});
