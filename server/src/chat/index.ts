import { JwsError, isActive, recordTransaction, verifyTransaction, type Subscription, type VerifyOptions } from "../appstore";
import { creditPack, verifyPack, walletMicros } from "../appstore/packs";
import type { Env } from "../env";
import { toStoredTime } from "../fetcher/text";
import { QUESTION_MICROS, questionsLeft, readBudget, unitsFor } from "./usage";

export { DAILY_QUESTIONS, QUESTION_MICROS } from "./usage";

/**
 * The AI chat about one decision, for subscribers only (#146, docs/contract.md),
 * its first part: what a subscriber has left (`/v1/chat/status`) and the packs
 * of questions bought (`/v1/chat/credits`), within the limit of `./usage.ts`.
 * `POST /v1/chat`, the one OpenAI call per question, comes next.
 */

/** The most of a decision's official text the agent reads, so a longer one takes no more of the limit. */
const MAX_TEXT = 20_000;

/** Anything but an answer: JSON with a status. */
export interface Refusal {
  status: number;
  body: Record<string, string | number | boolean>;
}

export interface ChatOptions extends VerifyOptions {
  now?: Date;
}

const error = (status: number, message: string, extra: Record<string, string | number> = {}): Refusal => ({
  status,
  body: { error: message, ...extra },
});

/** Midnight UTC after `now`, when the day's questions come back. */
const nextDay = (now: Date) => toStoredTime(new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1)));

/** The subscription a signed transaction belongs to, kept up to date; null unless it is paid now. */
async function activeSubscription(transaction: string, env: Env, options: VerifyOptions, now: Date): Promise<Subscription | null> {
  try {
    const subscription = await recordTransaction(env, await verifyTransaction(transaction, options), { now });
    return isActive(subscription, now) ? subscription : null;
  } catch (e) {
    if (!(e instanceof JwsError)) throw e;
    return null;
  }
}

const IN_FEED = "a.is_news = 1 AND a.feed_seq IS NOT NULL";
const today = (now: Date) => toStoredTime(now).slice(0, 10);

/**
 * `POST /v1/chat/status`: what a subscriber has left for questions about one
 * article, before asking: today's, the bought ones, how many of the limit one
 * question about it takes (a long document more than one), and when today's
 * come back.
 */
export async function chatStatus(body: unknown, env: Env, options: ChatOptions = {}): Promise<Refusal> {
  const now = options.now ?? new Date();
  const b = body as { articleId?: unknown; transaction?: unknown } | null;
  if (!b || typeof b.articleId !== "string" || typeof b.transaction !== "string") return error(400, "Expected { articleId, transaction }");
  const subscription = await activeSubscription(b.transaction, env, options, now);
  if (!subscription) return error(402, "Subscription required");
  const article = await env.DB.prepare(`SELECT LENGTH(a.text) AS chars FROM articles a WHERE a.id = ? AND ${IN_FEED}`)
    .bind(b.articleId)
    .first<{ chars: number | null }>();
  if (!article) return error(404, "Not found");
  const units = unitsFor(Math.min(article.chars ?? 0, MAX_TEXT));
  const left = questionsLeft(await readBudget(env, subscription.original_transaction_id, today(now)), units);
  return { status: 200, body: { questionsLeft: left.today, boughtQuestions: left.bought, units, resetsAt: nextDay(now) } };
}

/**
 * `POST /v1/chat/credits`: a pack of questions bought in the app, with the
 * subscription it is for: credited to that subscription's wallet once (a
 * second call changes nothing), so the app can send it until this answers
 * and only then finish the purchase. 400 for anything but a pack of this app,
 * 402 without a subscription's transaction to credit it to.
 */
export async function creditChatPack(body: unknown, env: Env, options: ChatOptions = {}): Promise<Refusal> {
  const now = options.now ?? new Date();
  const b = body as { pack?: unknown; transaction?: unknown } | null;
  if (!b || typeof b.pack !== "string" || typeof b.transaction !== "string") return error(400, "Expected { pack, transaction }");
  let pack;
  try {
    pack = await verifyPack(b.pack, options);
  } catch (e) {
    if (!(e instanceof JwsError)) throw e;
    return error(400, "Not a pack of this app");
  }
  let subscription;
  try {
    subscription = await recordTransaction(env, await verifyTransaction(b.transaction, options), { now });
  } catch (e) {
    if (!(e instanceof JwsError)) throw e;
    return error(402, "Subscription required");
  }
  const id = subscription.original_transaction_id;
  const credited = await creditPack(env, id, pack, now);
  const wallet = await walletMicros(env, id);
  console.log(JSON.stringify({ message: "chat pack", subscription: id, product: pack.productId, credited }));
  return { status: 200, body: { credited, boughtQuestions: Math.max(0, Math.floor(wallet / QUESTION_MICROS)) } };
}
