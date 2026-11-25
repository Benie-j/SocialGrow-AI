import { createClient, type User } from "npm:@supabase/supabase-js@2";
import { HttpError } from "./http.ts";

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new HttpError(500, "server_misconfigured", "Configuration serveur incomplète.");
  }
  return value;
}

/** Vérifie le jeton Supabase de l'appelant et renvoie l'utilisateur. */
export async function requireUser(req: Request): Promise<User> {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
  if (!token) {
    throw new HttpError(401, "unauthenticated", "Connexion requise.");
  }

  const client = createClient(requireEnv("SUPABASE_URL"), requireEnv("SUPABASE_ANON_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user) {
    throw new HttpError(401, "unauthenticated", "Session invalide ou expirée.");
  }
  return data.user;
}

/** Client service_role : réservé aux écritures que le client ne doit jamais faire. */
export function serviceClient() {
  return createClient(requireEnv("SUPABASE_URL"), requireEnv("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
