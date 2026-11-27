// Envoie une notification push (Firebase Cloud Messaging, API HTTP v1) pour une
// ligne de `public.notifications`. Appelée par le déclencheur SQL
// `notifications_push` (pg_net) dès l'insertion de la notification.
//
// Déployée avec verify_jwt = false car l'appelant est la base de données.
// La fonction est sûre malgré tout : elle ne reçoit qu'un identifiant, relit
// tout (destinataire, texte) en base, et « réclame » la notification de façon
// atomique : elle ne peut être poussée qu'une seule fois, jamais rejouée.
//
// Secret requis (Supabase > Edge Functions > Secrets) :
//   FIREBASE_SERVICE_ACCOUNT = contenu JSON de la clé de compte de service.
import postgres from "npm:postgres@3.4.5";

const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, {
  max: 1,
  prepare: false,
  idle_timeout: 20,
  connect_timeout: 10,
});

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const CHANNEL_ID = "jun_alerts";
const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
};

type NotificationRow = {
  id: string;
  user_id: string;
  workspace_id: string;
  kind: string;
  title: string;
  body: string | null;
  post_id: string | null;
};

type SendResult = "sent" | "invalid_token" | "error";

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function loadServiceAccount(): ServiceAccount | null {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!raw) return null;
  try {
    const sa = JSON.parse(raw);
    if (
      typeof sa.project_id === "string" &&
      typeof sa.client_email === "string" &&
      typeof sa.private_key === "string"
    ) {
      return sa as ServiceAccount;
    }
  } catch {
    // JSON invalide
  }
  return null;
}

function base64Url(input: string | Uint8Array): string {
  const bytes = typeof input === "string"
    ? new TextEncoder().encode(input)
    : input;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const base64 = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

let cachedToken: { value: string; expiresAt: number } | null = null;

/** Jeton OAuth2 Google (valable ~1 h), mis en cache entre deux appels. */
async function accessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt - 60 > now) return cachedToken.value;

  const tokenUri = sa.token_uri ?? "https://oauth2.googleapis.com/token";
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64Url(JSON.stringify({
    iss: sa.client_email,
    scope: FCM_SCOPE,
    aud: tokenUri,
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${claims}`;
  const key = await importPrivateKey(sa.private_key);
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(unsigned),
    ),
  );

  const response = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${unsigned}.${base64Url(signature)}`,
    }),
    signal: AbortSignal.timeout(8000),
  });
  if (!response.ok) throw new Error(`oauth_${response.status}`);

  const data = await response.json();
  cachedToken = {
    value: data.access_token as string,
    expiresAt: now + Number(data.expires_in ?? 3300),
  };
  return cachedToken.value;
}

async function sendToDevice(
  sa: ServiceAccount,
  bearer: string,
  deviceToken: string,
  n: NotificationRow,
): Promise<SendResult> {
  const data: Record<string, string> = {
    notification_id: n.id,
    kind: n.kind,
  };
  if (n.post_id) data.post_id = n.post_id;

  const message = {
    message: {
      token: deviceToken,
      notification: { title: n.title, body: n.body ?? "" },
      data,
      android: {
        // Priorité haute : livraison immédiate, même en veille profonde (Doze).
        priority: "HIGH",
        ttl: "86400s",
        notification: {
          channel_id: CHANNEL_ID,
          tag: n.id,
          color: "#0F6B45",
          default_sound: true,
        },
      },
    },
  };

  try {
    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${bearer}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(message),
        signal: AbortSignal.timeout(8000),
      },
    );
    if (response.ok) return "sent";

    const detail = await response.text();
    const unregistered = response.status === 404 ||
      detail.includes("UNREGISTERED") ||
      (response.status === 400 && detail.includes("registration token"));
    console.error(`send-push: FCM ${response.status}`);
    return unregistered ? "invalid_token" : "error";
  } catch (error) {
    console.error("send-push: FCM injoignable:", (error as Error).message);
    return "error";
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let notificationId: unknown;
  try {
    notificationId = (await req.json())?.notification_id;
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  if (typeof notificationId !== "string" || !UUID.test(notificationId)) {
    return json({ error: "invalid_notification_id" }, 400);
  }

  // Avant de réclamer quoi que ce soit : le service doit être configuré.
  const sa = loadServiceAccount();
  if (!sa) {
    console.error("send-push: FIREBASE_SERVICE_ACCOUNT absent ou invalide");
    return json({ status: "not_configured" }, 503);
  }

  try {
    // Réclamation atomique : une seule exécution gagne, les autres sortent.
    const [n] = await sql<NotificationRow[]>`
      update public.notifications
         set push_claimed_at = now()
       where id = ${notificationId} and push_claimed_at is null
      returning id, user_id, workspace_id, kind, title, body, post_id
    `;
    if (!n) return json({ status: "skipped", reason: "already_handled" });

    // Respect des préférences de l'utilisateur (tout est actif par défaut).
    const [prefs] = await sql<Record<string, boolean>[]>`
      select publish_success, publish_failure, ai_draft_ready, facebook_issue
        from public.notification_preferences
       where workspace_id = ${n.workspace_id} and user_id = ${n.user_id}
    `;
    if (prefs && prefs[n.kind] === false) {
      return json({ status: "skipped", reason: "disabled_by_user" });
    }

    const devices = await sql<{ token: string }[]>`
      select token from public.device_tokens where user_id = ${n.user_id}
    `;
    if (devices.length === 0) {
      return json({ status: "skipped", reason: "no_device" });
    }

    const bearer = await accessToken(sa);
    const results = await Promise.all(
      devices.map(async (device) => ({
        token: device.token,
        result: await sendToDevice(sa, bearer, device.token, n),
      })),
    );

    // Les jetons que Firebase ne reconnaît plus sont supprimés.
    const stale = results
      .filter((r) => r.result === "invalid_token")
      .map((r) => r.token);
    if (stale.length > 0) {
      await sql`delete from public.device_tokens where token in ${sql(stale)}`;
    }

    const sent = results.filter((r) => r.result === "sent").length;
    console.log(`send-push: ${n.kind} -> ${sent}/${devices.length} appareil(s)`);
    return json({ status: "done", sent, devices: devices.length, removed: stale.length });
  } catch (error) {
    console.error("send-push:", (error as Error).message);
    return json({ error: "server_error" }, 500);
  }
});
