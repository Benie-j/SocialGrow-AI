// Utilitaires HTTP communs aux Edge Functions.

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export class HttpError extends Error {
  status: number;
  code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** Enveloppe commune : CORS, méthode POST, corps JSON, erreurs maîtrisées. */
export function handle(
  fn: (req: Request, body: Record<string, unknown>) => Promise<Response>,
): (req: Request) => Promise<Response> {
  return async (req) => {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }
    try {
      if (req.method !== "POST") {
        throw new HttpError(405, "method_not_allowed", "Méthode non autorisée.");
      }
      let body: Record<string, unknown>;
      try {
        const parsed = await req.json();
        body = parsed && typeof parsed === "object" ? parsed : {};
      } catch {
        throw new HttpError(400, "invalid_json", "Corps de requête invalide.");
      }
      return await fn(req, body);
    } catch (error) {
      if (error instanceof HttpError) {
        return json({ error: error.code, message: error.message }, error.status);
      }
      // Le détail n'est jamais renvoyé au client (il pourrait contenir un jeton).
      console.error("Erreur inattendue", error instanceof Error ? error.name : "unknown");
      return json(
        { error: "internal_error", message: "Erreur interne. Réessaie plus tard." },
        500,
      );
    }
  };
}
