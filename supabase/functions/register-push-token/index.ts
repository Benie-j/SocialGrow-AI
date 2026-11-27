// Enregistre ou retire le jeton Firebase (FCM) d'un téléphone pour l'utilisateur
// connecté. Déployée avec verify_jwt = true : la passerelle Supabase a déjà
// vérifié la signature du JWT, on n'en lit ici que l'identité.
//
// Pourquoi une fonction plutôt qu'une écriture directe : un jeton est unique
// et peut changer de compte (téléphone partagé, déconnexion hors ligne) ;
// seul le serveur peut le déplacer proprement d'un utilisateur à l'autre.
import postgres from "npm:postgres@3.4.5";

const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, {
  max: 1,
  prepare: false,
  idle_timeout: 20,
  connect_timeout: 10,
});

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TOKEN = /^[A-Za-z0-9_\-:.]{20,4096}$/;
const MAX_DEVICES_PER_USER = 10;

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function decodeBase64Url(value: string): Uint8Array {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/")
    .padEnd(Math.ceil(value.length / 4) * 4, "=");
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}

/** Identifiant de l'utilisateur connecté (jamais celui de la clé anonyme). */
function userIdFrom(req: Request): string | null {
  const match = /^Bearer\s+(.+)$/i.exec(req.headers.get("Authorization") ?? "");
  if (!match) return null;
  const parts = match[1].split(".");
  if (parts.length !== 3) return null;
  try {
    const payload = JSON.parse(
      new TextDecoder().decode(decodeBase64Url(parts[1])),
    );
    if (
      payload?.role === "authenticated" &&
      typeof payload.sub === "string" &&
      UUID.test(payload.sub)
    ) {
      return payload.sub;
    }
  } catch {
    // jeton illisible
  }
  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const userId = userIdFrom(req);
  if (!userId) return json({ error: "unauthorized" }, 401);

  let body: { action?: unknown; token?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const { action, token } = body;
  if (typeof token !== "string" || !TOKEN.test(token)) {
    return json({ error: "invalid_token" }, 400);
  }

  try {
    if (action === "register") {
      await sql`
        insert into public.device_tokens (user_id, token, platform)
        values (${userId}, ${token}, 'android')
        on conflict (token)
        do update set user_id = excluded.user_id, updated_at = now()
      `;
      // On garde les appareils les plus récents seulement.
      await sql`
        delete from public.device_tokens
        where user_id = ${userId}
          and id not in (
            select id from public.device_tokens
            where user_id = ${userId}
            order by updated_at desc
            limit ${MAX_DEVICES_PER_USER}
          )
      `;
      return json({ status: "registered" });
    }

    if (action === "unregister") {
      await sql`
        delete from public.device_tokens
        where token = ${token} and user_id = ${userId}
      `;
      return json({ status: "unregistered" });
    }

    return json({ error: "invalid_action" }, 400);
  } catch (error) {
    console.error("register-push-token:", (error as Error).message);
    return json({ error: "server_error" }, 500);
  }
});
