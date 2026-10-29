// The second lock (#60): Cloudflare Access lets only Yurii and Roman reach
// admin.outernews.app, and the Worker checks the sign-in token Access adds to
// every request too, so the page never answers without it (a request that
// reached the Worker some other way, or a misconfigured Access app).
import type { AdminEnv } from "./env";

interface Jwk extends JsonWebKey {
  kid?: string;
}

let keys: { team: string; at: number; keys: Jwk[] } | undefined;
const KEYS_MS = 60 * 60_000;

const b64urlBytes = (part: string) => Uint8Array.from(atob(part.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(part.length / 4) * 4, "=")), (c) => c.charCodeAt(0));
const b64urlJson = (part: string) => JSON.parse(new TextDecoder().decode(b64urlBytes(part))) as Record<string, unknown>;

/** The team's signing keys, kept an hour; fetched again at once when a token names a key not in them (Access rotates its keys). */
async function teamKeys(team: string, fetcher: typeof fetch, kid?: unknown): Promise<Jwk[]> {
  const fresh = keys && keys.team === team && Date.now() - keys.at < KEYS_MS;
  if (fresh && keys!.keys.some((k) => k.kid === kid)) return keys!.keys;
  const response = await fetcher(`https://${team}.cloudflareaccess.com/cdn-cgi/access/certs`);
  if (!response.ok) throw new Error(`Access keys: HTTP ${response.status}`);
  const body = (await response.json()) as { keys?: Jwk[] };
  keys = { team, at: Date.now(), keys: body.keys ?? [] };
  return keys.keys;
}

/** The signed-in person's e-mail when the token is Access's, unexpired and for one of ADMIN_EMAILS; otherwise null. */
export async function signedInEmail(request: Request, env: AdminEnv, fetcher: typeof fetch = fetch, now = Date.now()): Promise<string | null> {
  const token = request.headers.get("cf-access-jwt-assertion");
  if (!token) return null;
  const [head, body, sig] = token.split(".");
  if (!head || !body || !sig) return null;
  let header: Record<string, unknown>;
  let claims: Record<string, unknown>;
  try {
    header = b64urlJson(head);
    claims = b64urlJson(body);
  } catch {
    return null;
  }
  if (header.alg !== "RS256") return null;
  if (claims.iss !== `https://${env.ACCESS_TEAM}.cloudflareaccess.com`) return null;
  if (typeof claims.exp !== "number" || claims.exp * 1000 <= now) return null;
  const email = typeof claims.email === "string" ? claims.email.toLowerCase() : "";
  const allowed = env.ADMIN_EMAILS.split(",").map((e) => e.trim().toLowerCase()).filter(Boolean);
  if (!allowed.includes(email)) return null;
  const jwk = (await teamKeys(env.ACCESS_TEAM, fetcher, header.kid)).find((k) => k.kid === header.kid);
  if (!jwk) return null;
  const key = await crypto.subtle.importKey("jwk", jwk, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
  const ok = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, b64urlBytes(sig), new TextEncoder().encode(`${head}.${body}`));
  return ok ? email : null;
}
