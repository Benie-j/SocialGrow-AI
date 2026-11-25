// Tests des Edge Functions Facebook, sans réseau : fetch est remplacé par un faux
// Supabase (auth + PostgREST) et une fausse Graph API.
//
// Lancer : deno test -A supabase/functions/tests

import { assert, assertEquals, assertNotEquals, assertStringIncludes } from "./asserts.ts";

import { decryptToken, encryptToken } from "../_shared/common.ts";
import { handle as listPages } from "../facebook-list-pages/handler.ts";
import { handle as connectPage } from "../facebook-connect-page/handler.ts";

const SUPABASE_URL = "https://fake-project.supabase.test";
const WORKSPACE = "11111111-1111-4111-8111-111111111111";
const USER_ID = "22222222-2222-4222-8222-222222222222";
const PAGE_TOKEN = "EAAB-PAGE-TOKEN-SECRET-1234567890";

Deno.env.set("SUPABASE_URL", SUPABASE_URL);
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service-role-key-used-only-in-tests");

interface World {
  role: string | null;
  graphError?: { code: number };
  rpcCalls: Array<{ name: string; args: Record<string, unknown> }>;
  graphCalls: string[];
  graphAuthHeaders: Array<string | null>;
  exchange?: boolean;
}

const GRAPH_PAGES = [
  {
    id: "100000000000001",
    name: "Boulangerie Soleil",
    category: "Bakery",
    picture: { data: { url: "https://cdn.test/soleil.jpg" } },
    access_token: PAGE_TOKEN,
  },
  { id: "100000000000002", name: "Café du Port", category: "Cafe", access_token: "EAAB-OTHER-TOKEN-0987654321" },
];

function jsonResponse(body: unknown, status = 200, headers: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...headers },
  });
}

/** Installe le faux réseau pour la durée d'un test. */
async function withWorld(world: World, run: () => Promise<void>) {
  const original = globalThis.fetch;
  globalThis.fetch = (input: string | URL | Request, init?: RequestInit) => {
    const request = input instanceof Request ? input : null;
    const url = new URL(request ? request.url : String(input));
    const headers = new Headers(init?.headers ?? request?.headers);
    const method = (init?.method ?? request?.method ?? "GET").toUpperCase();

    if (url.origin === SUPABASE_URL) {
      if (url.pathname === "/auth/v1/user") {
        if (headers.get("Authorization") === "Bearer valid-user-jwt") {
          return Promise.resolve(
            jsonResponse({ id: USER_ID, aud: "authenticated", email: "owner@test.dev", app_metadata: {}, user_metadata: {}, created_at: "2026-01-01T00:00:00Z" }),
          );
        }
        return Promise.resolve(jsonResponse({ msg: "invalid" }, 401));
      }
      if (url.pathname === "/rest/v1/workspace_members" && method === "GET") {
        const rows = world.role ? [{ role: world.role }] : [];
        if ((headers.get("Accept") ?? "").includes("vnd.pgrst.object")) {
          return Promise.resolve(rows.length ? jsonResponse(rows[0]) : jsonResponse({ code: "PGRST116" }, 406));
        }
        return Promise.resolve(jsonResponse(rows));
      }
      if (url.pathname.startsWith("/rest/v1/rpc/") && method === "POST") {
        const name = url.pathname.split("/").pop()!;
        const args = JSON.parse(String(init?.body ?? "{}"));
        world.rpcCalls.push({ name, args });
        return Promise.resolve(
          name === "connect_facebook_page" ? jsonResponse("33333333-3333-4333-8333-333333333333") : jsonResponse(1),
        );
      }
    }

    if (url.hostname === "graph.facebook.com") {
      world.graphCalls.push(url.pathname);
      world.graphAuthHeaders.push(headers.get("Authorization"));
      // Le jeton ne doit jamais apparaître dans l'URL.
      assert(!url.search.includes("access_token="), "jeton dans l'URL");
      if (world.graphError) {
        return Promise.resolve(jsonResponse({ error: { message: "x", type: "OAuthException", code: world.graphError.code } }, 400));
      }
      if (url.pathname.endsWith("/oauth/access_token")) {
        return Promise.resolve(jsonResponse({ access_token: "LONG-LIVED-USER-TOKEN-1234567890" }));
      }
      if (url.pathname.endsWith("/me/accounts")) {
        return Promise.resolve(jsonResponse({ data: GRAPH_PAGES }));
      }
    }
    return Promise.resolve(jsonResponse({ unexpected: url.toString() }, 500));
  };
  try {
    await run();
  } finally {
    globalThis.fetch = original;
  }
}

function newWorld(role: string | null = "owner"): World {
  return { role, rpcCalls: [], graphCalls: [], graphAuthHeaders: [] };
}

function post(body: unknown, auth: string | null = "Bearer valid-user-jwt") {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (auth) headers.Authorization = auth;
  return new Request("https://fn.test/", { method: "POST", headers, body: JSON.stringify(body) });
}

const test = (name: string, fn: () => Promise<void>) =>
  Deno.test({ name, fn, sanitizeOps: false, sanitizeResources: false });

const USER_TOKEN = "EAAB-USER-TOKEN-ABCDEFGHIJ-123456";

// --- facebook-list-pages -------------------------------------------------------

test("list : refuse une requête sans connexion", async () => {
  await withWorld(newWorld(), async () => {
    const res = await listPages(post({ workspace_id: WORKSPACE, provider_token: USER_TOKEN }, null));
    assertEquals(res.status, 401);
    assertEquals((await res.json()).error.code, "unauthenticated");
  });
});

test("list : refuse un jeton Supabase invalide", async () => {
  await withWorld(newWorld(), async () => {
    const res = await listPages(post({ workspace_id: WORKSPACE, provider_token: USER_TOKEN }, "Bearer nope"));
    assertEquals(res.status, 401);
  });
});

test("list : refuse un lecteur (viewer) ou un non-membre", async () => {
  for (const role of ["viewer", null]) {
    await withWorld(newWorld(role), async () => {
      const res = await listPages(post({ workspace_id: WORKSPACE, provider_token: USER_TOKEN }));
      assertEquals(res.status, 403);
      assertEquals((await res.json()).error.code, "forbidden");
    });
  }
});

test("list : renvoie les Pages sans jamais exposer leur jeton", async () => {
  const world = newWorld("editor");
  await withWorld(world, async () => {
    const res = await listPages(post({ workspace_id: WORKSPACE, provider_token: USER_TOKEN }));
    assertEquals(res.status, 200);
    const text = await res.text();
    assert(!text.includes(PAGE_TOKEN), "le jeton de Page a fuité");
    assert(!text.includes("access_token"), "champ access_token dans la réponse");
    const body = JSON.parse(text);
    assertEquals(body.pages.length, 2);
    assertEquals(body.pages[0], {
      id: "100000000000001",
      name: "Boulangerie Soleil",
      category: "Bakery",
      picture_url: "https://cdn.test/soleil.jpg",
    });
    assertEquals(body.pages[1].picture_url, null);
    assertEquals(world.graphAuthHeaders[0], `Bearer ${USER_TOKEN}`);
  });
});

test("list : jeton Facebook expiré -> 401 facebook_token_invalid", async () => {
  const world = newWorld();
  world.graphError = { code: 190 };
  await withWorld(world, async () => {
    const res = await listPages(post({ workspace_id: WORKSPACE, provider_token: USER_TOKEN }));
    assertEquals(res.status, 401);
    assertEquals((await res.json()).error.code, "facebook_token_invalid");
  });
});

test("list : permission Pages refusée -> 403 facebook_permission_missing", async () => {
  const world = newWorld();
  world.graphError = { code: 200 };
  await withWorld(world, async () => {
    const res = await listPages(post({ workspace_id: WORKSPACE, provider_token: USER_TOKEN }));
    assertEquals(res.status, 403);
    assertEquals((await res.json()).error.code, "facebook_permission_missing");
  });
});

test("list : jeton Facebook absent -> 401 facebook_token_missing", async () => {
  await withWorld(newWorld(), async () => {
    const res = await listPages(post({ workspace_id: WORKSPACE }));
    assertEquals(res.status, 401);
    assertEquals((await res.json()).error.code, "facebook_token_missing");
  });
});

test("list : workspace_id invalide -> 400", async () => {
  await withWorld(newWorld(), async () => {
    const res = await listPages(post({ workspace_id: "pas-un-uuid", provider_token: USER_TOKEN }));
    assertEquals(res.status, 400);
  });
});

test("list : méthode GET refusée", async () => {
  await withWorld(newWorld(), async () => {
    const res = await listPages(new Request("https://fn.test/", { method: "GET" }));
    assertEquals(res.status, 405);
  });
});

// --- facebook-connect-page -----------------------------------------------------

test("connect : une Page qui n'appartient pas à l'utilisateur est refusée (anti-faux)", async () => {
  const world = newWorld();
  await withWorld(world, async () => {
    const res = await connectPage(
      post({ action: "connect", workspace_id: WORKSPACE, provider_token: USER_TOKEN, meta_page_id: "999999999999" }),
    );
    assertEquals(res.status, 404);
    assertEquals((await res.json()).error.code, "page_not_found");
    assertEquals(world.rpcCalls.length, 0, "aucune écriture ne doit avoir lieu");
  });
});

test("connect : un lecteur ne peut pas connecter", async () => {
  const world = newWorld("viewer");
  await withWorld(world, async () => {
    const res = await connectPage(
      post({ action: "connect", workspace_id: WORKSPACE, provider_token: USER_TOKEN, meta_page_id: "100000000000001" }),
    );
    assertEquals(res.status, 403);
    assertEquals(world.rpcCalls.length, 0);
    assertEquals(world.graphCalls.length, 0, "Facebook ne doit même pas être appelé");
  });
});

test("connect : identifiant de Page invalide -> 400", async () => {
  await withWorld(newWorld(), async () => {
    const res = await connectPage(
      post({ action: "connect", workspace_id: WORKSPACE, provider_token: USER_TOKEN, meta_page_id: "1; drop table" }),
    );
    assertEquals(res.status, 400);
  });
});

test("connect : connexion réussie, jeton de Page chiffré et non renvoyé", async () => {
  const world = newWorld("owner");
  await withWorld(world, async () => {
    const res = await connectPage(
      post({ action: "connect", workspace_id: WORKSPACE, provider_token: USER_TOKEN, meta_page_id: "100000000000001" }),
    );
    assertEquals(res.status, 200);
    const text = await res.text();
    assert(!text.includes(PAGE_TOKEN), "le jeton de Page a fuité dans la réponse");
    const body = JSON.parse(text);
    assertEquals(body.page.name, "Boulangerie Soleil");
    assertEquals(body.long_lived, false);

    assertEquals(world.rpcCalls.length, 1);
    const { name, args } = world.rpcCalls[0];
    assertEquals(name, "connect_facebook_page");
    assertEquals(args.p_workspace_id, WORKSPACE);
    assertEquals(args.p_user_id, USER_ID);
    assertEquals(args.p_meta_page_id, "100000000000001");
    const cipher = String(args.p_token_ciphertext);
    assertNotEquals(cipher, PAGE_TOKEN);
    assert(!cipher.includes(PAGE_TOKEN), "jeton stocké en clair");
    assertStringIncludes(cipher, "v1.");
    assertEquals(await decryptToken(cipher), PAGE_TOKEN);
    // Sans secrets Meta : pas d'échange, le jeton expire bientôt.
    assert(typeof args.p_token_expires_at === "string");
    assert(!world.graphCalls.some((p) => p.endsWith("/oauth/access_token")));
  });
});

test("connect : avec les secrets Meta, jeton longue durée et sans expiration", async () => {
  Deno.env.set("FACEBOOK_APP_ID", "123456789");
  Deno.env.set("FACEBOOK_APP_SECRET", "app-secret-for-tests");
  const world = newWorld("admin");
  try {
    await withWorld(world, async () => {
      const res = await connectPage(
        post({ action: "connect", workspace_id: WORKSPACE, provider_token: USER_TOKEN, meta_page_id: "100000000000001" }),
      );
      assertEquals(res.status, 200);
      assertEquals((await res.json()).long_lived, true);
      assertEquals(world.rpcCalls[0].args.p_token_expires_at, null);
      assert(world.graphCalls.some((p) => p.endsWith("/oauth/access_token")));
      // Les appels suivants utilisent le jeton longue durée.
      assertEquals(world.graphAuthHeaders.at(-1), "Bearer LONG-LIVED-USER-TOKEN-1234567890");
    });
  } finally {
    Deno.env.delete("FACEBOOK_APP_ID");
    Deno.env.delete("FACEBOOK_APP_SECRET");
  }
});

test("connect : déconnexion", async () => {
  const world = newWorld("editor");
  await withWorld(world, async () => {
    const res = await connectPage(post({ action: "disconnect", workspace_id: WORKSPACE }));
    assertEquals(res.status, 200);
    assertEquals((await res.json()).disconnected, 1);
    assertEquals(world.rpcCalls[0].name, "disconnect_facebook_page");
    assertEquals(world.graphCalls.length, 0);
  });
});

test("connect : déconnexion refusée à un lecteur", async () => {
  const world = newWorld("viewer");
  await withWorld(world, async () => {
    const res = await connectPage(post({ action: "disconnect", workspace_id: WORKSPACE }));
    assertEquals(res.status, 403);
    assertEquals(world.rpcCalls.length, 0);
  });
});

test("connect : action inconnue -> 400", async () => {
  await withWorld(newWorld(), async () => {
    const res = await connectPage(post({ action: "delete-everything", workspace_id: WORKSPACE }));
    assertEquals(res.status, 400);
  });
});

// --- chiffrement ---------------------------------------------------------------

test("chiffrement : aller-retour, IV aléatoire, falsification détectée", async () => {
  const a = await encryptToken("secret-token");
  const b = await encryptToken("secret-token");
  assertNotEquals(a, b);
  assertEquals(await decryptToken(a), "secret-token");
  const parts = a.split(".");
  parts[2] = parts[2].slice(0, -4) + (parts[2].endsWith("AAAA") ? "BBBB" : "AAAA");
  let failed = false;
  try {
    await decryptToken(parts.join("."));
  } catch {
    failed = true;
  }
  assert(failed, "un jeton modifié doit être rejeté");
});
