import type { Env } from "../env";
import { toStoredTime } from "../fetcher/text";
import { JwsError, verifyAppleJws, type VerifyOptions } from "./jws";

export { JwsError, type VerifyOptions } from "./jws";

/** The app, and the one subscription that opens the AI chat (#146; docs/setup.md). */
export const BUNDLE_ID = "com.officialnews.app";
export const CHAT_PRODUCT_ID = "com.officialnews.app.agent.monthly";

/** What the server reads of an App Store signed transaction (JWSTransactionDecodedPayload). */
export interface AppleTransaction {
  originalTransactionId: string;
  transactionId: string;
  bundleId: string;
  productId: string;
  environment: "Production" | "Sandbox";
  /** Milliseconds since 1970, as Apple writes them. */
  expiresDate: number;
  revocationDate?: number;
  appAccountToken?: string;
  signedDate?: number;
}

export interface Subscription {
  original_transaction_id: string;
  transaction_id: string;
  app_account_token: string | null;
  product_id: string;
  environment: string;
  expires_at: string;
  revoked_at: string | null;
  last_notification: string | null;
  updated_at: string;
}

/**
 * A signed transaction from the app or a notification, checked: Apple's, for
 * this app and the chat's subscription, with what the chat needs. Throws a
 * JwsError otherwise.
 */
export async function verifyTransaction(jws: string, options: VerifyOptions = {}): Promise<AppleTransaction> {
  const t = await verifyAppleJws<AppleTransaction>(jws, options);
  if (t.bundleId !== BUNDLE_ID || t.productId !== CHAT_PRODUCT_ID) throw new JwsError("another app or product");
  if (t.environment !== "Production" && t.environment !== "Sandbox") throw new JwsError("unknown environment");
  if (typeof t.originalTransactionId !== "string" || typeof t.transactionId !== "string" || typeof t.expiresDate !== "number") {
    throw new JwsError("not a subscription transaction");
  }
  return t;
}

const stored = (ms: number) => toStoredTime(new Date(ms));

/**
 * Keeps what a checked transaction says about its subscription, and returns
 * the row. The row follows the latest period known: a transaction that expires
 * later replaces it, revocation included. One of the same period can only add a
 * revocation, never take one away, so an old transaction the app still holds
 * cannot reopen a refunded month; only Apple's `REFUND_REVERSED` does
 * (`reversed`). An older one changes nothing.
 */
export async function recordTransaction(
  env: Env,
  t: AppleTransaction,
  options: { notification?: string; reversed?: boolean; now?: Date } = {},
): Promise<Subscription> {
  const now = toStoredTime(options.now ?? new Date());
  const expires = stored(t.expiresDate);
  const revoked = t.revocationDate ? stored(t.revocationDate) : null;
  const row = await env.DB.prepare("SELECT * FROM subscriptions WHERE original_transaction_id = ?")
    .bind(t.originalTransactionId)
    .first<Subscription>();
  const notification = options.notification ?? row?.last_notification ?? null;

  let next: Subscription;
  if (!row || expires > row.expires_at) {
    next = {
      original_transaction_id: t.originalTransactionId,
      transaction_id: t.transactionId,
      app_account_token: t.appAccountToken ?? row?.app_account_token ?? null,
      product_id: t.productId,
      environment: t.environment,
      expires_at: expires,
      revoked_at: revoked,
      last_notification: notification,
      updated_at: now,
    };
  } else if (t.transactionId === row.transaction_id) {
    next = { ...row, revoked_at: revoked ?? (options.reversed ? null : row.revoked_at), last_notification: notification, updated_at: now };
  } else {
    return row;
  }
  await env.DB.prepare(
    `INSERT INTO subscriptions (original_transaction_id, transaction_id, app_account_token, product_id, environment,
                                expires_at, revoked_at, last_notification, updated_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
     ON CONFLICT (original_transaction_id) DO UPDATE SET
       transaction_id = ?2, app_account_token = ?3, product_id = ?4, environment = ?5,
       expires_at = ?6, revoked_at = ?7, last_notification = ?8, updated_at = ?9`,
  )
    .bind(
      next.original_transaction_id,
      next.transaction_id,
      next.app_account_token,
      next.product_id,
      next.environment,
      next.expires_at,
      next.revoked_at,
      next.last_notification,
      next.updated_at,
    )
    .run();
  return next;
}

/** Open while not revoked and paid until later than `now`. */
export function isActive(subscription: Subscription, now = new Date()): boolean {
  return subscription.revoked_at === null && subscription.expires_at > toStoredTime(now);
}

interface Notification {
  notificationType?: string;
  data?: { bundleId?: string; signedTransactionInfo?: string };
}

/**
 * `POST /v1/appstore/notifications`: Apple's App Store Server Notifications V2
 * (docs/contract.md). Any checked notification that carries a transaction of
 * the chat's subscription updates its row as a transaction from the app would;
 * `REFUND_REVERSED` alone takes a revocation away. Everything Apple sends that
 * passes the check gets 200, so it is not sent again; a payload that fails it
 * gets 400. `CONSUMPTION_REQUEST` is only logged: answering it needs an
 * In-App Purchase key (docs/setup.md).
 */
export async function receiveNotification(
  body: unknown,
  env: Env,
  options: VerifyOptions & { now?: Date } = {},
): Promise<{ status: number; body: Record<string, string> }> {
  const signedPayload = (body as { signedPayload?: unknown } | null)?.signedPayload;
  if (typeof signedPayload !== "string") return { status: 400, body: { error: "Expected { signedPayload }" } };
  let notification: Notification;
  try {
    notification = await verifyAppleJws<Notification>(signedPayload, options);
  } catch (error) {
    console.error(JSON.stringify({ message: "appstore notification refused", error: (error as Error).message }));
    return { status: 400, body: { error: "Not a valid App Store notification" } };
  }
  const type = notification.notificationType ?? "UNKNOWN";
  const signed = notification.data?.bundleId === BUNDLE_ID ? notification.data.signedTransactionInfo : undefined;
  let subscription: Subscription | undefined;
  if (signed) {
    try {
      const t = await verifyTransaction(signed, options);
      subscription = await recordTransaction(env, t, { notification: type, reversed: type === "REFUND_REVERSED", now: options.now });
    } catch (error) {
      // Another product of the app, or a transaction that fails the check: nothing to keep.
      if (!(error instanceof JwsError)) throw error;
    }
  }
  console.log(
    JSON.stringify({
      message: "appstore notification",
      type,
      subscription: subscription?.original_transaction_id ?? null,
      active: subscription ? isActive(subscription, options.now) : null,
    }),
  );
  return { status: 200, body: {} };
}
