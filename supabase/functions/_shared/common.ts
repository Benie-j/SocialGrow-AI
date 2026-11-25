// Utilitaires partagés des Edge Functions Facebook.
// Aucun secret n'est écrit ici : tout vient des variables d'environnement Supabase.

import { createClient, type SupabaseClient, type User } from "npm:@supabase/supabase-js@2";

export type Admin = SupabaseClient;

/** Version de la Graph API. Surchargeable avec le secret GRAPH_API_VERSION. */
export const GRAPH_VERSION = Deno.env.get("GRAPH_API_VERSION") ?? "v25.0";
const GRAPH = `https://graph.facebook.com/${GRAPH_VERSION}`;

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json; charset=utf-8" },
  });
}

/** Erreur métier : code stable lisible par l'application, message en français. */
export class HttpError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}

/** Enveloppe commune : CORS, méthode POST, corps JSON, erreurs homogènes. */
export function handler(
  run: (req: Request, body: Record<string, unknown>) => Promise<Response>,
): (req: Request) => Promise<Response> {
  return async (req) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
    try {
      if (req.method !== "POST") {
        throw new HttpError(405, "method_not_allowed", "Méthode non autorisée.");
      }
      let body: Record<string, unknown>;
      try {
        const parsed = await req.json();
        if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
          throw new Error("not an object");
        }
        body = parsed as Record<string, unknown>;
      } catch {
        throw new HttpError(400, "invalid_body", "Corps de requête invalide.");
      }
      return await run(req, body);
    } catch (error) {
      if (error instanceof HttpError) {
        return json({ error: { code: error.code, message: error.message } }, error.status);
      }
      // Les détails internes restent dans les journaux, jamais dans la réponse.
      console.error("Erreur inattendue :", error instanceof Error ? error.message : "inconnue");
      return json(
        { error: { code: "internal_error", message: "Erreur interne. Réessaie dans un instant." } },
        500,
      );
    }
  };
}

export function adminClient(): Admin {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new HttpError(500, "server_misconfigured", "Configuration serveur incomplète.");
  }
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

/** Identifie l'utilisateur à partir du jeton d'accès Supabase de la requête. */
export async function authenticate(req: Request, admin: Admin): Promise<User> {
  const header = req.headers.get("Authorization") ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(header);
  if (!match) throw new HttpError(401, "unauthenticated", "Connexion requise.");
  const { data, error } = await admin.auth.getUser(match[1]);
  if (error || !data.user) throw new HttpError(401, "unauthenticated", "Session invalide ou expirée.");
  return data.user;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function requireUuid(value: unknown, field: string): string {
  if (typeof value !== "string" || !UUID.test(value)) {
    throw new HttpError(400, "invalid_body", `Champ « ${field} » invalide.`);
  }
  return value;
}

export function requireProviderToken(value: unknown): string {
  if (typeof value !== "string" || value.trim().length < 20 || value.length > 4096) {
    throw new HttpError(
      401,
      "facebook_token_missing",
      "Session Facebook introuvable. Reconnecte-toi avec Facebook.",
    );
  }
  return value.trim();
}

const WRITE_ROLES = ["owner", "admin", "editor"];

/** L'utilisateur doit être propriétaire, admin ou éditeur de l'espace. */
export async function requireWriteAccess(
  admin: Admin,
  workspaceId: string,
  userId: string,
): Promise<void> {
  const { data, error } = await admin
    .from("workspace_members")
    .select("role")
    .eq("workspace_id", workspaceId)
    .eq("user_id", userId)
    .maybeSingle();
  if (error) throw new Error("Lecture de l'appartenance impossible");
  if (!data || !WRITE_ROLES.includes(data.role as string)) {
    throw new HttpError(403, "forbidden", "Tu n'as pas les droits pour gérer la Page de cet espace.");
  }
}

export interface ManagedPage {
  id: string;
  name: string;
  category: string | null;
  pictureUrl: string | null;
  /** Jeton de la Page : ne doit JAMAIS être renvoyé à l'application. */
  accessToken: string | null;
}

interface GraphErrorBody {
  error?: { message?: string; type?: string; code?: number };
}

function graphError(body: GraphErrorBody, status: number): HttpError {
  const code = body.error?.code;
  // 190 : jeton expiré ou invalide. 102 : session invalide.
  if (code === 190 || code === 102) {
    return new HttpError(
      401,
      "facebook_token_invalid",
      "La session Facebook a expiré. Reconnecte-toi avec Facebook.",
    );
  }
  // 10 et 200-299 : permission manquante.
  if (code === 10 || (typeof code === "number" && code >= 200 && code < 300)) {
    return new HttpError(
      403,
      "facebook_permission_missing",
      "Facebook n'a pas accordé l'accès à tes Pages. Reconnecte-toi et accepte l'accès aux Pages.",
    );
  }
  console.error("Erreur Graph API", status, code, body.error?.type);
  return new HttpError(502, "facebook_unavailable", "Facebook est indisponible. Réessaie plus tard.");
}

async function graphGet(path: string, params: Record<string, string>, token: string) {
  const url = new URL(`${GRAPH}${path}`);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
  let response: Response;
  try {
    // Le jeton voyage dans l'en-tête, jamais dans l'URL (qui finit dans les journaux).
    response = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  } catch {
    throw new HttpError(502, "facebook_unreachable", "Impossible de joindre Facebook.");
  }
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw graphError(body as GraphErrorBody, response.status);
  return body as Record<string, unknown>;
}

/** Pages Facebook que l'utilisateur gère (GET /me/accounts), toutes pages confondues. */
export async function fetchManagedPages(userToken: string): Promise<ManagedPage[]> {
  const pages: ManagedPage[] = [];
  let after: string | undefined;
  for (let i = 0; i < 5; i++) {
    const params: Record<string, string> = {
      fields: "id,name,category,picture.type(large){url},access_token",
      limit: "100",
    };
    if (after) params.after = after;
    const body = await graphGet("/me/accounts", params, userToken);
    const data = Array.isArray(body.data) ? body.data : [];
    for (const raw of data as Array<Record<string, unknown>>) {
      if (typeof raw.id !== "string" || typeof raw.name !== "string") continue;
      const picture = raw.picture as { data?: { url?: unknown } } | undefined;
      pages.push({
        id: raw.id,
        name: raw.name,
        category: typeof raw.category === "string" ? raw.category : null,
        pictureUrl: typeof picture?.data?.url === "string" ? picture.data.url : null,
        accessToken: typeof raw.access_token === "string" ? raw.access_token : null,
      });
    }
    const paging = body.paging as { cursors?: { after?: string }; next?: string } | undefined;
    if (!paging?.next || !paging.cursors?.after) break;
    after = paging.cursors.after;
  }
  return pages;
}

/**
 * Échange le jeton utilisateur court contre un jeton longue durée.
 * Les jetons de Page obtenus ensuite n'expirent pas.
 * Nécessite les secrets FACEBOOK_APP_ID et FACEBOOK_APP_SECRET ; sinon renvoie null.
 */
export async function exchangeForLongLivedToken(userToken: string): Promise<string | null> {
  const appId = Deno.env.get("FACEBOOK_APP_ID");
  const appSecret = Deno.env.get("FACEBOOK_APP_SECRET");
  if (!appId || !appSecret) return null;
  try {
    const body = await graphGet(
      "/oauth/access_token",
      {
        grant_type: "fb_exchange_token",
        client_id: appId,
        client_secret: appSecret,
        fb_exchange_token: userToken,
      },
      userToken,
    );
    return typeof body.access_token === "string" ? body.access_token : null;
  } catch (error) {
    // L'échange est une amélioration : sa panne ne bloque pas la connexion.
    if (error instanceof HttpError && error.status === 401) throw error;
    console.error("Échange de jeton longue durée impossible");
    return null;
  }
}

// --- Chiffrement des jetons de Page (AES-256-GCM) ---------------------------------

function toBase64(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
}

function fromBase64(value: string): Uint8Array<ArrayBuffer> {
  const binary = atob(value);
  const bytes = new Uint8Array(new ArrayBuffer(binary.length));
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

async function encryptionKey(usage: KeyUsage): Promise<CryptoKey> {
  // Secret dédié si défini ; sinon dérivé de la clé service_role (jamais exposée).
  const material = Deno.env.get("TOKEN_ENCRYPTION_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!material) throw new HttpError(500, "server_misconfigured", "Configuration serveur incomplète.");
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`socialgrow-ai:facebook-token:v1:${material}`),
  );
  return crypto.subtle.importKey("raw", digest, "AES-GCM", false, [usage]);
}

export async function encryptToken(plain: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const key = await encryptionKey("encrypt");
  const cipher = new Uint8Array(
    await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, new TextEncoder().encode(plain)),
  );
  return `v1.${toBase64(iv)}.${toBase64(cipher)}`;
}

export async function decryptToken(ciphertext: string): Promise<string> {
  const [version, iv, data] = ciphertext.split(".");
  if (version !== "v1" || !iv || !data) throw new Error("Format de jeton inconnu");
  const key = await encryptionKey("decrypt");
  const plain = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: fromBase64(iv) },
    key,
    fromBase64(data),
  );
  return new TextDecoder().decode(plain);
}
