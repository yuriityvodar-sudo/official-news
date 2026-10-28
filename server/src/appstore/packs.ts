import { QUESTION_MICROS } from "../chat/usage";
import type { Env } from "../env";
import { toStoredTime } from "../fetcher/text";
import { JwsError, verifyAppleJws, type VerifyOptions } from "./jws";
import { BUNDLE_ID, PACK_QUESTIONS } from "./products";

/**
 * The packs of questions (#146, Roman 27 Oct): consumables, which StoreKit does
 * not restore and we have no account to keep, so the server keeps them, in the
 * wallet of the subscription they were bought for. Each pack is credited once
 * (`chat_credits`, by its transaction), and a refund takes it back out.
 */
export interface PackTransaction {
  transactionId: string;
  bundleId: string;
  productId: string;
  environment: "Production" | "Sandbox";
  revocationDate?: number;
  signedDate?: number;
}

/** A pack's transaction, Apple's signature already checked: this app's, one of the packs. Throws a JwsError otherwise. */
export function checkPack(t: PackTransaction): PackTransaction {
  if (t.bundleId !== BUNDLE_ID || !(t.productId in PACK_QUESTIONS)) throw new JwsError("not a pack of this app");
  if ((t.environment !== "Production" && t.environment !== "Sandbox") || typeof t.transactionId !== "string") {
    throw new JwsError("not a pack transaction");
  }
  return t;
}

/** A pack's signed transaction from the app, checked. */
export const verifyPack = async (jws: string, options: VerifyOptions = {}) => checkPack(await verifyAppleJws<PackTransaction>(jws, options));

const packMicros = (productId: string) => PACK_QUESTIONS[productId] * QUESTION_MICROS;

/** The wallet's balance, in micro-dollars. */
export async function walletMicros(env: Env, subscription: string): Promise<number> {
  return (await env.DB.prepare("SELECT extra_micros FROM chat_wallet WHERE original_transaction_id = ?").bind(subscription).first<number>("extra_micros")) ?? 0;
}

const addToWallet = (env: Env, subscription: string, micros: number, at: string) =>
  env.DB.prepare(
    `INSERT INTO chat_wallet (original_transaction_id, extra_micros, updated_at) VALUES (?1, ?2, ?3)
     ON CONFLICT (original_transaction_id) DO UPDATE SET extra_micros = extra_micros + ?2, updated_at = ?3`,
  ).bind(subscription, micros, at);

/**
 * Credits a pack to a subscription's wallet, once: the app sends it again
 * until this answers, and StoreKit gives the app an unfinished pack again
 * after a restart, so the same pack must never count twice. A pack already
 * refunded is not credited. Returns whether it was new.
 */
export async function creditPack(env: Env, subscription: string, pack: PackTransaction, now = new Date()): Promise<boolean> {
  if (pack.revocationDate) return false;
  const at = toStoredTime(now);
  const micros = packMicros(pack.productId);
  const { meta } = await env.DB.prepare(
    `INSERT INTO chat_credits (transaction_id, original_transaction_id, product_id, micros, environment, created_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6) ON CONFLICT (transaction_id) DO NOTHING`,
  )
    .bind(pack.transactionId, subscription, pack.productId, micros, pack.environment, at)
    .run();
  if (!meta.changes) return false;
  await addToWallet(env, subscription, micros, at).run();
  return true;
}

/**
 * Apple's notification about a pack: a refund or a revocation takes it out of
 * its wallet (which may go below zero: the bought questions were already
 * asked), and `REFUND_REVERSED` puts it back. A pack refunded before the app
 * sent it leaves a row with no subscription (''), so the transaction the app
 * still holds, signed before the refund, can never be credited (Yurii's
 * review of #184); `REFUND_REVERSED` removes that row.
 */
export async function packNotification(env: Env, pack: PackTransaction, type: string, now = new Date()): Promise<void> {
  const at = toStoredTime(now);
  const refunded = type === "REFUND" || type === "REVOKE";
  if (!refunded && type !== "REFUND_REVERSED") return;
  const revokedAt = toStoredTime(pack.revocationDate ? new Date(pack.revocationDate) : now);
  if (!refunded) await env.DB.prepare("DELETE FROM chat_credits WHERE transaction_id = ? AND original_transaction_id = ''").bind(pack.transactionId).run();
  const statement = refunded
    ? env.DB.prepare(
        "UPDATE chat_credits SET revoked_at = ?2 WHERE transaction_id = ?1 AND revoked_at IS NULL RETURNING original_transaction_id, micros",
      ).bind(pack.transactionId, revokedAt)
    : env.DB.prepare(
        "UPDATE chat_credits SET revoked_at = NULL WHERE transaction_id = ?1 AND revoked_at IS NOT NULL RETURNING original_transaction_id, micros",
      ).bind(pack.transactionId);
  const row = await statement.first<{ original_transaction_id: string; micros: number }>();
  if (row) {
    await addToWallet(env, row.original_transaction_id, refunded ? -row.micros : row.micros, at).run();
  } else if (refunded) {
    // Not credited yet (or refunded again): the row keeps it from being credited later.
    await env.DB.prepare(
      `INSERT INTO chat_credits (transaction_id, original_transaction_id, product_id, micros, environment, revoked_at, created_at)
       VALUES (?1, '', ?2, ?3, ?4, ?5, ?6) ON CONFLICT (transaction_id) DO NOTHING`,
    )
      .bind(pack.transactionId, pack.productId, packMicros(pack.productId), pack.environment, revokedAt, at)
      .run();
  }
}
