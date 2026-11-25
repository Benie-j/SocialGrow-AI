import { HttpError } from "./http.ts";

function toBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary);
}

function fromBase64(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

async function loadKey(): Promise<CryptoKey> {
  const raw = Deno.env.get("TOKEN_ENCRYPTION_KEY");
  let bytes: Uint8Array | null = null;
  try {
    bytes = raw ? fromBase64(raw.trim()) : null;
  } catch {
    bytes = null;
  }
  if (!bytes || bytes.length !== 32) {
    throw new HttpError(
      500,
      "server_misconfigured",
      "Clé de chiffrement absente ou invalide (32 octets en base64 attendus).",
    );
  }
  return await crypto.subtle.importKey("raw", bytes, "AES-GCM", false, ["encrypt", "decrypt"]);
}

/** Chiffre un jeton (AES-256-GCM). Format : v1.<iv base64>.<données base64>. */
export async function encryptToken(plain: string): Promise<string> {
  const key = await loadKey();
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const data = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    key,
    new TextEncoder().encode(plain),
  );
  return `v1.${toBase64(iv)}.${toBase64(new Uint8Array(data))}`;
}

/** Déchiffre un jeton produit par encryptToken (pour les futures publications). */
export async function decryptToken(ciphertext: string): Promise<string> {
  const [version, iv, data] = ciphertext.split(".");
  if (version !== "v1" || !iv || !data) {
    throw new HttpError(500, "invalid_ciphertext", "Jeton stocké illisible.");
  }
  const key = await loadKey();
  const plain = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: fromBase64(iv) },
    key,
    fromBase64(data),
  );
  return new TextDecoder().decode(plain);
}
