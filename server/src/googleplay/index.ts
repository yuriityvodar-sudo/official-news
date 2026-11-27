// Google Play purchases of the AI chat (#349, Android part of #146; Yurii's
// Play account, Yurii the seller, #345). The app sends what Google Play gave it
// as the same `transaction` / `pack` fields the iPhone sends Apple's signed
// transactions in, marked `gp:` so the two never mix:
//   - the subscription: `gp:<purchaseToken>`;
//   - a pack:           `gp:<productId>:<purchaseToken>`.
// Google's purchase tokens are not signed for us, so each one is asked of the
// Play Developer API (purchases.subscriptionsv2, purchases.products) with the
// read-only robot of PLAY_SERVICE_ACCOUNT, and then kept in the same tables as
// Apple's (appstore/index.ts, appstore/packs.ts): one subscription row per
// Google subscription (its first order id, which stays the same across
// renewals), so the weekly usage, the packs and the Sandbox cap work unchanged.
// Google's test purchases (license testers, the closed test) count as Sandbox.
import type { AppleTransaction } from "../appstore";
import { BUNDLE_ID, CHAT_PRODUCT_ID, PACK_WEEKS } from "../appstore/products";
import type { PackTransaction } from "../appstore/packs";
import type { Env } from "../env";
import { toStoredTime } from "../fetcher/text";
import { parseServiceAccount, signedJwt, TOKEN_URL, type ServiceAccount } from "../push/fcm";

export const PLAY_SCOPE = "https://www.googleapis.com/auth/androidpublisher";
const API = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${BUNDLE_ID}/purchases`;
const TIMEOUT_MS = 10_000;

/** What the app sends marks a Google Play purchase. */
export const isPlay = (value: string) => value.startsWith("gp:");

/** A purchase Google does not confirm for this app (or no robot to ask): the chat answers 402 / 400. */
export class PlayError extends Error {}

/** Google's answer could not be had (the robot, Google itself): the chat answers 503, the app tries again. */
export class PlayUnavailable extends Error {}

const tokenKey = (account: ServiceAccount) => `play_token:${account.client_email}`;

/** An access token for the Play Developer API, kept in kv_cache until 5 minutes before it expires. */
async function accessToken(env: Env, now: Date, fetch: typeof globalThis.fetch): Promise<string> {
  if (!env.PLAY_SERVICE_ACCOUNT) throw new PlayUnavailable("no PLAY_SERVICE_ACCOUNT");
  const account = parseServiceAccount(env.PLAY_SERVICE_ACCOUNT, "PLAY_SERVICE_ACCOUNT");
  const key = tokenKey(account);
  const cached = await env.DB.prepare("SELECT value FROM kv_cache WHERE key = ? AND expires_at > ?").bind(key, toStoredTime(now)).first<string>("value");
  if (cached) return cached;
  const assertion = await signedJwt(account, now, PLAY_SCOPE, "PLAY_SERVICE_ACCOUNT");
  const response = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }).toString(),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  }).catch((e) => {
    throw new PlayUnavailable(`token request failed: ${e instanceof Error ? e.message : String(e)}`);
  });
  const body = (await response.json().catch(() => null)) as { access_token?: string; expires_in?: number } | null;
  if (!response.ok || !body?.access_token) throw new PlayUnavailable(`token request: HTTP ${response.status}`);
  const expires = new Date(now.getTime() + ((body.expires_in ?? 3600) - 300) * 1000);
  await env.DB.prepare(
    "INSERT INTO kv_cache (key, value, expires_at) VALUES (?1, ?2, ?3) ON CONFLICT (key) DO UPDATE SET value = ?2, expires_at = ?3",
  )
    .bind(key, body.access_token, toStoredTime(expires))
    .run();
  return body.access_token;
}

/** One call to the Play Developer API: the JSON, `null` for a token Google does not know (404/410), or PlayUnavailable. */
async function play<T>(env: Env, path: string, now: Date, fetch: typeof globalThis.fetch, method = "GET"): Promise<T | null> {
  const token = await accessToken(env, now, fetch);
  const response = await fetch(`${API}${path}`, {
    method,
    headers: { authorization: `Bearer ${token}`, ...(method === "POST" ? { "content-type": "application/json" } : {}) },
    body: method === "POST" ? "{}" : undefined,
    signal: AbortSignal.timeout(TIMEOUT_MS),
  }).catch((e) => {
    throw new PlayUnavailable(`Play API failed: ${e instanceof Error ? e.message : String(e)}`);
  });
  // 400 too: Google answers it for a token that is not a purchase of this product.
  if (response.status === 404 || response.status === 410 || response.status === 400) return null;
  if (!response.ok) throw new PlayUnavailable(`Play API: HTTP ${response.status}`);
  const text = await response.text();
  return (text ? JSON.parse(text) : {}) as T;
}

/** An order id without its renewal suffix: `GPA.1234-5678-9012-34567..3` → `GPA.1234-5678-9012-34567`. */
export const firstOrder = (orderId: string) => orderId.replace(/\.\.\d+$/, "");

interface SubscriptionPurchaseV2 {
  subscriptionState?: string;
  latestOrderId?: string;
  testPurchase?: object;
  acknowledgementState?: string;
  lineItems?: { productId?: string; expiryTime?: string; latestSuccessfulOrderId?: string }[];
}

/**
 * A Google Play subscription token, asked of Google, as the chat's transaction
 * record: `originalTransactionId` is `gp:` and the subscription's first order,
 * `transactionId` its latest order, `expiresDate` when the paid time ends.
 * Acknowledged on the way when Google still waits for it (otherwise Google
 * refunds it after 3 days). Throws PlayError when it is not the chat's
 * subscription of this app.
 */
export async function verifyPlaySubscription(
  value: string,
  env: Env,
  now: Date,
  fetch: typeof globalThis.fetch = globalThis.fetch,
): Promise<AppleTransaction> {
  const token = value.slice(3);
  if (!token || token.includes(":")) throw new PlayError("not a subscription token");
  const p = await play<SubscriptionPurchaseV2>(env, `/subscriptionsv2/tokens/${encodeURIComponent(token)}`, now, fetch);
  const item = p?.lineItems?.find((i) => i.productId === CHAT_PRODUCT_ID);
  const order = item?.latestSuccessfulOrderId ?? p?.latestOrderId;
  const expires = item?.expiryTime ? Date.parse(item.expiryTime) : NaN;
  if (!p || !item || !order || Number.isNaN(expires) || p.subscriptionState === "SUBSCRIPTION_STATE_PENDING") {
    throw new PlayError("not the chat's subscription");
  }
  if (p.acknowledgementState === "ACKNOWLEDGEMENT_STATE_PENDING") {
    await play(env, `/subscriptions/${encodeURIComponent(CHAT_PRODUCT_ID)}/tokens/${encodeURIComponent(token)}:acknowledge`, now, fetch, "POST");
  }
  return {
    originalTransactionId: `gp:${firstOrder(order)}`,
    transactionId: `gp:${order}`,
    bundleId: BUNDLE_ID,
    productId: CHAT_PRODUCT_ID,
    environment: p.testPurchase ? "Sandbox" : "Production",
    expiresDate: expires,
    // Refunded and taken back: Google may leave the end of the paid time where it was, so it is a revocation here.
    ...(p.subscriptionState === "SUBSCRIPTION_STATE_REVOKED" ? { revocationDate: now.getTime() } : {}),
  };
}

interface ProductPurchase {
  purchaseState?: number;
  consumptionState?: number;
  orderId?: string;
  purchaseType?: number;
}

/** A pack bought on Google Play, asked of Google, as the chat's pack record; throws PlayError when it is not one (or not paid). */
export async function verifyPlayPack(
  value: string,
  env: Env,
  now: Date,
  fetch: typeof globalThis.fetch = globalThis.fetch,
): Promise<PackTransaction & { token: string }> {
  const [, productId, token] = value.split(":");
  if (!productId || !token || !(productId in PACK_WEEKS)) throw new PlayError("not a pack of this app");
  const p = await play<ProductPurchase>(env, `/products/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(token)}`, now, fetch);
  // purchaseState: 0 purchased, 1 canceled, 2 pending; purchaseType 0 is a test purchase.
  if (!p || p.purchaseState !== 0 || !p.orderId) throw new PlayError("not a paid pack");
  return { transactionId: `gp:${p.orderId}`, bundleId: BUNDLE_ID, productId, environment: p.purchaseType === 0 ? "Sandbox" : "Production", token };
}

/** Consumes a pack on Google Play once it is in the wallet, so it can be bought again; a failure is only logged (the credit stays once). */
export async function consumePlayPack(pack: { productId: string; token: string }, env: Env, now: Date, fetch: typeof globalThis.fetch = globalThis.fetch) {
  try {
    await play(env, `/products/${encodeURIComponent(pack.productId)}/tokens/${encodeURIComponent(pack.token)}:consume`, now, fetch, "POST");
  } catch (e) {
    console.error(JSON.stringify({ message: "play consume failed", product: pack.productId, error: e instanceof Error ? e.message : String(e) }));
  }
}
