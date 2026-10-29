// Firebase Cloud Messaging (#62): sends one message to a topic through the FCM
// HTTP v1 API, as the Google service account in the Worker secret
// FCM_SERVICE_ACCOUNT (the contents of its JSON key file: client_email,
// private_key, project_id). The service account has one role, Firebase Cloud
// Messaging API Admin, Google's role for sending: besides sending messages it
// can manage topic subscriptions and read FCM's delivery data, so its key is
// kept as carefully as one that can (docs/setup.md).
//
// FCM wants an OAuth2 access token, which the Worker gets with the JWT bearer
// flow: it signs a JWT (RS256, WebCrypto) with the service account's private
// key and exchanges it at Google's token endpoint. Google issues the token for
// about an hour, and it is kept in D1 (kv_cache, migration 0012) until a few
// minutes before it expires, so most runs make no token request and spend no
// CPU on signing: a run that sends reads one row (two during a pause). The key
// itself never leaves the Worker secret, and neither the key nor the token is
// ever logged.
//
// When Google gives no token, or FCM cannot take a message just then (an
// answer about the token, the permission, the quota or FCM itself), the push
// step pauses for PAUSE_MINUTES, or FCM's Retry-After when longer: one row in
// kv_cache, read with the token. So a broken key or a busy FCM is asked at most
// every 10 minutes, not every run.
import type { Env } from "../env";
import { toStoredTime } from "../fetcher/text";

export const TOKEN_URL = "https://oauth2.googleapis.com/token";
export const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
export const fcmUrl = (projectId: string) => `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`;

/** The fields of a service account's JSON key file the Worker reads; the others are ignored. */
export interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

/**
 * Reads a service account's JSON key from a Worker secret: FCM_SERVICE_ACCOUNT,
 * or another one named by `name` (the admin page's GA_SERVICE_ACCOUNT). Throws
 * when it is not JSON or misses a field; the message names only what is
 * wrong, never a value, so it can be logged.
 */
export function parseServiceAccount(secret: string, name = "FCM_SERVICE_ACCOUNT"): ServiceAccount {
  let parsed: unknown;
  try {
    parsed = JSON.parse(secret);
  } catch {
    throw new Error(`${name} is not JSON (it should be the service account's whole JSON key file)`);
  }
  const fields = ["client_email", "private_key", "project_id"] as const;
  const missing = fields.filter((field) => typeof (parsed as Record<string, unknown> | null)?.[field] !== "string");
  if (missing.length) throw new Error(`${name} has no ${missing.join(", ")}`);
  const account = parsed as ServiceAccount;
  return { client_email: account.client_email, private_key: account.private_key, project_id: account.project_id };
}

/** The kv_cache row of the access token: per service account, so a new secret never uses the old account's token. */
export const tokenKey = (account: ServiceAccount) => `fcm_token:${account.client_email}`;

/** A token is used until this long before it expires, so a run never sends with one that runs out on the way. */
export const TOKEN_MARGIN_MS = 5 * 60_000;
/** How long the signed JWT asks for: Google's maximum, one hour. */
const JWT_SECONDS = 3600;
/** A request that takes longer counts as failed, so a run never hangs on Google. */
const TIMEOUT_MS = 10_000;

const errorText = (error: unknown) => (error instanceof Error ? error.message : String(error));
const clip = (text: string, max = 300) => (text.length > max ? `${text.slice(0, max - 1)}…` : text);

/** The kv_cache row of the push step's pause: per service account, like the token. */
export const pauseKey = (account: ServiceAccount) => `fcm_pause:${account.client_email}`;
/**
 * How long the push step waits after Google gave no token or FCM could not
 * take a message, at least: 5 translator runs. FCM asks for a backoff of at
 * least a minute; one request per pause is far gentler than that.
 */
export const PAUSE_MINUTES = 10;
/** FCM's Retry-After is honoured up to this long. */
const MAX_RETRY_AFTER_SECONDS = 24 * 3600;

/** The cached token and the pause, each only while still good at ?3. Binds: ?1 token key, ?2 pause key, ?3 now. */
export const READ_CACHE = "SELECT key, value, expires_at FROM kv_cache WHERE key IN (?1, ?2) AND expires_at > ?3";
/** Stores a value until ?3. Binds: ?1 key, ?2 value, ?3 expires at. */
export const WRITE_CACHE = `INSERT INTO kv_cache (key, value, expires_at) VALUES (?1, ?2, ?3)
  ON CONFLICT (key) DO UPDATE SET value = excluded.value, expires_at = excluded.expires_at`;
/** Forgets a value (FCM refused its token). Binds: ?1 key. */
export const DROP_CACHE = "DELETE FROM kv_cache WHERE key = ?1";

/**
 * Pauses the push step until PAUSE_MINUTES after `now`, or `retryAfterSeconds`
 * when longer; `why` is logged by every run it pauses. Returns the statement
 * (for a batch) and when the pause ends.
 */
export function pause(env: Env, account: ServiceAccount, now: Date, why: string, retryAfterSeconds = 0) {
  const ms = Math.max(PAUSE_MINUTES * 60_000, Math.min(retryAfterSeconds, MAX_RETRY_AFTER_SECONDS) * 1000);
  const until = toStoredTime(new Date(now.getTime() + ms));
  return { until, statement: env.DB.prepare(WRITE_CACHE).bind(pauseKey(account), clip(why), until) };
}


function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
const base64urlText = (text: string) => base64url(new TextEncoder().encode(text));

/** The DER bytes of a PEM private key ("-----BEGIN PRIVATE KEY-----", PKCS #8, as in Google's key files). */
function pemToDer(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "")
    // A key pasted with its newlines still escaped.
    .replace(/\\n/g, "")
    .replace(/\s+/g, "");
  let binary: string;
  try {
    binary = atob(body);
  } catch {
    throw new Error("FCM_SERVICE_ACCOUNT's private_key is not a PEM key");
  }
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

/**
 * The JWT the token endpoint exchanges: issued by the service account, for
 * FCM only (or the scopes given, as the admin page's read-only analytics
 * ones), valid one hour from `now`.
 */
export async function signedJwt(account: ServiceAccount, now: Date, scope = FCM_SCOPE, name = "FCM_SERVICE_ACCOUNT"): Promise<string> {
  const iat = Math.floor(now.getTime() / 1000);
  const header = base64urlText(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64urlText(JSON.stringify({ iss: account.client_email, scope, aud: TOKEN_URL, iat, exp: iat + JWT_SECONDS }));
  let key: CryptoKey;
  try {
    key = await crypto.subtle.importKey("pkcs8", pemToDer(account.private_key), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  } catch (error) {
    throw new Error(`${name}'s private_key cannot be read: ${errorText(error)}`);
  }
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`));
  return `${header}.${claims}.${base64url(new Uint8Array(signature))}`;
}

/** An access token to send with, or why the run sends nothing (for its log; no token or key in it). */
export type TokenResult = { token: string } | { error: string };

/**
 * An access token for FCM: the one in kv_cache while it is good for at least
 * TOKEN_MARGIN_MS more, otherwise a new one from Google (a signed JWT
 * exchanged at TOKEN_URL), stored until TOKEN_MARGIN_MS before it expires.
 * None while the push step is paused (the same read, so no signing and no
 * request); when Google gives none (it refused the key, or did not answer),
 * it pauses the step for PAUSE_MINUTES. Never throws for Google's answer.
 */
export async function accessToken(env: Env, account: ServiceAccount, now: Date, fetch: typeof globalThis.fetch): Promise<TokenResult> {
  const key = tokenKey(account);
  const { results: rows } = await env.DB.prepare(READ_CACHE)
    .bind(key, pauseKey(account), toStoredTime(now))
    .all<{ key: string; value: string; expires_at: string }>();
  const paused = rows.find((row) => row.key !== key);
  if (paused) return { error: `paused until ${paused.expires_at} (${paused.value})` };
  const cached = rows.find((row) => row.key === key);
  if (cached) return { token: cached.value };

  const fail = async (why: string) => {
    const error = clip(`no access token: ${why}`);
    await pause(env, account, now, error).statement.run();
    return { error };
  };
  let assertion: string;
  try {
    assertion = await signedJwt(account, now);
  } catch (error) {
    // A private_key that is not a key: the message says so, never the value.
    return fail(errorText(error));
  }
  let response: Response;
  try {
    response = await fetch(TOKEN_URL, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }).toString(),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch (error) {
    return fail(`token request failed: ${errorText(error)}`);
  }
  const body = (await response.json().catch(() => null)) as
    | { access_token?: unknown; expires_in?: unknown; error?: unknown; error_description?: unknown }
    | null;
  if (!response.ok || typeof body?.access_token !== "string" || !body.access_token) {
    const why = [body?.error, body?.error_description].filter((part) => typeof part === "string").join(": ");
    return fail(`token request: HTTP ${response.status}${why ? ` ${why}` : ""}`);
  }
  const seconds = typeof body.expires_in === "number" && body.expires_in > 0 ? body.expires_in : JWT_SECONDS;
  const expiresAt = new Date(now.getTime() + seconds * 1000 - TOKEN_MARGIN_MS);
  if (expiresAt > now) await env.DB.prepare(WRITE_CACHE).bind(key, body.access_token, toStoredTime(expiresAt)).run();
  return { token: body.access_token };
}

/** One push: where it goes and what it says. FCM wants every data value as a string. */
export interface PushMessage {
  /** An FCM topic (breaking news), or one phone's FCM token (a reply to its message, #220). */
  topic?: string;
  token?: string;
  title: string;
  /** The line under the title on iOS (#157); none when empty. */
  subtitle?: string;
  body: string;
  data: Record<string, string>;
}

/**
 * What became of a message that was not sent:
 *   - `refused`: FCM refused the message itself (HTTP 400 INVALID_ARGUMENT, and
 *     any other 4xx below): it surely did not go out, and it is never tried again.
 *   - `retry`: FCM or the setup could not take it just then (401: the access
 *     token; 403: the service account's permission; 408; 429: the quota; 5xx:
 *     FCM itself), nothing about the message: it can be tried again later.
 *   - `unknown`: no answer (a network error, the 10 s timeout): FCM may have
 *     sent it, so it counts as sent and is never tried again.
 */
export type NotSent = "refused" | "retry" | "unknown";

/** The HTTP statuses after which a message can be tried again (FCM's error codes: UNAVAILABLE, INTERNAL, QUOTA_EXCEEDED). */
export const retryLater = (status: number) => status === 401 || status === 403 || status === 408 || status === 429 || status >= 500;

/** What FCM did with a message: its name, or why not (with the HTTP status and Retry-After, when it answered). */
export type SendResult =
  | { ok: true; messageId: string }
  | { ok: false; outcome: NotSent; error: string; status?: number; retryAfterSeconds?: number };

/**
 * The FCM HTTP v1 request body: a notification with a sound on iOS, and the
 * data the app opens the article with. A subtitle goes in the APNs alert, which
 * repeats the title and body so iOS shows all three; Android has no subtitle.
 */
export const fcmBody = (message: PushMessage) => ({
  message: {
    ...(message.token ? { token: message.token } : { topic: message.topic }),
    notification: { title: message.title, body: message.body },
    data: message.data,
    apns: {
      payload: {
        aps: message.subtitle
          ? { alert: { title: message.title, subtitle: message.subtitle, body: message.body }, sound: "default" }
          : { sound: "default" },
      },
    },
  },
});

/** Sends one message. Never throws: a refusal or a failed request is a result, for push_log. */
export async function sendMessage(
  account: ServiceAccount,
  token: string,
  message: PushMessage,
  fetch: typeof globalThis.fetch,
): Promise<SendResult> {
  let response: Response;
  try {
    response = await fetch(fcmUrl(account.project_id), {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify(fcmBody(message)),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch (error) {
    return { ok: false, outcome: "unknown", error: clip(`request failed: ${errorText(error)}`) };
  }
  const body = (await response.json().catch(() => null)) as { name?: unknown; error?: { status?: unknown; message?: unknown } } | null;
  if (response.ok && typeof body?.name === "string") return { ok: true, messageId: body.name };
  const status = typeof body?.error?.status === "string" ? ` ${body.error.status}` : "";
  const why = typeof body?.error?.message === "string" ? `: ${body.error.message}` : "";
  const error = clip(`HTTP ${response.status}${status}${why}`);
  // A 2xx without a message name: FCM took the request, so the message may be out.
  if (response.ok) return { ok: false, outcome: "unknown", status: response.status, error };
  if (!retryLater(response.status)) return { ok: false, outcome: "refused", status: response.status, error };
  // Retry-After in seconds (the date form is not used by FCM's API).
  const header = response.headers.get("retry-after")?.trim() ?? "";
  const retryAfter = /^\d+$/.test(header) ? Number(header) : 0;
  return { ok: false, outcome: "retry", status: response.status, error, ...(retryAfter ? { retryAfterSeconds: retryAfter } : {}) };
}
