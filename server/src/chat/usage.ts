import type { Env } from "../env";
import { toStoredTime } from "../fetcher/text";

/**
 * The AI chat's limit (#146, Roman 27 Oct): what the answers really cost at
 * OpenAI, so a subscriber never costs more than a set sum. The subscription
 * gives a week's usage, which comes back every Monday at 00:00 UTC (Roman,
 * 4 Nov: «пользователь покупает weekly usage»), and the app shows how much of
 * it is used, never a count of questions (`usageOf`). Inside, a "question" is
 * still the unit of an estimate: $0.002 of that cost, a typical question one,
 * a question about a long document two or three. Amounts are in micro-dollars.
 */
export const QUESTION_MICROS = 2000;

/** A week's usage: what 20 questions a day cost, $0.28 a week, so at most about $1.20 a month a subscriber. Unused usage does not carry over. */
export const WEEKLY_MICROS = 7 * 20 * QUESTION_MICROS;

/**
 * The week of a Sandbox purchase without a team key (Roman, 5 Nov): about
 * three questions. App Review buys in the Sandbox with the `store` build, and
 * sees the packs only once the week's usage runs out, so it gets there after
 * a few questions instead of about 140.
 */
export const SANDBOX_WEEK_MICROS = 3 * QUESTION_MICROS;

/** The week a question counts in: its key in `chat_usage.day` (`weekOf`) and the usage it holds. */
export interface Week {
  key: string;
  micros: number;
}

/** The week `now` falls in, by its Monday (UTC), as `chat_usage.day` keeps it: "2026-11-02". */
export function weekOf(now: Date): string {
  const monday = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  monday.setUTCDate(monday.getUTCDate() - ((monday.getUTCDay() + 6) % 7));
  return monday.toISOString().slice(0, 10);
}

/** The next Monday at 00:00 UTC, when the week's usage comes back. */
export function nextWeek(now: Date): Date {
  const monday = new Date(`${weekOf(now)}T00:00:00Z`);
  monday.setUTCDate(monday.getUTCDate() + 7);
  return monday;
}

/** GPT-5.4 mini's prices per token, in micro-dollars ($0.75, $0.075 and $4.50 per 1M; developers.openai.com, 27 Oct). */
export const PRICES = { input: 0.75, cached: 0.075, output: 4.5 };

/** OpenAI's count of a call's tokens, as its stream ends (`stream_options.include_usage`). */
export interface Usage {
  prompt_tokens?: number;
  completion_tokens?: number;
  prompt_tokens_details?: { cached_tokens?: number };
}

export function costMicros(usage: Usage): number {
  const cached = usage.prompt_tokens_details?.cached_tokens ?? 0;
  const input = Math.max((usage.prompt_tokens ?? 0) - cached, 0);
  return Math.ceil(input * PRICES.input + cached * PRICES.cached + (usage.completion_tokens ?? 0) * PRICES.output);
}

/**
 * What a question about an official text of `chars` characters costs, before
 * it is asked: the rules, the summary and the question (about 800 tokens), the
 * text at about 3.5 characters a token, and an answer of about 250 tokens.
 */
export function estimateMicros(chars: number): number {
  return Math.ceil((800 + chars / 3.5) * PRICES.input + 250 * PRICES.output);
}

/** How many questions of the limit one question about that text takes: at least one. */
export const unitsFor = (chars: number) => Math.max(1, Math.round(estimateMicros(chars) / QUESTION_MICROS));

/** What a subscription has left: of the week's usage, and in its wallet of extra usage bought. */
export interface Budget {
  week: number;
  wallet: number;
}

export async function readBudget(env: Env, subscription: string, week: Week): Promise<Budget> {
  const row = await env.DB.prepare(
    `SELECT (SELECT spent_micros FROM chat_usage WHERE original_transaction_id = ?1 AND day = ?2) AS spent,
            (SELECT extra_micros FROM chat_wallet WHERE original_transaction_id = ?1) AS wallet`,
  )
    .bind(subscription, week.key)
    .first<{ spent: number | null; wallet: number | null }>();
  return { week: week.micros - (row?.spent ?? 0), wallet: row?.wallet ?? 0 };
}

/** The questions left at `units` a question: of the week's usage, and of the extra usage, which is spent after it. Only for the server's checks and older app builds: the app shows usage. */
export function questionsLeft(budget: Budget, units: number): { week: number; bought: number } {
  const each = units * QUESTION_MICROS;
  return { week: Math.max(0, Math.floor(budget.week / each)), bought: Math.max(0, Math.floor(budget.wallet / each)) };
}

/** What the app shows (Roman, 4 Nov): how much of the week's usage is used, 0 to 100, and whether extra usage is left. */
export function usageOf(budget: Budget, week: Week): { usedPercent: number; extraUsage: boolean } {
  const used = (week.micros - budget.week) / week.micros;
  return { usedPercent: Math.min(100, Math.max(0, Math.floor(used * 100))), extraUsage: budget.wallet > 0 };
}

/** Where a share of the limit came from, in micro-dollars: the week's usage and the wallet. */
export interface Taken {
  week: number;
  wallet: number;
}

/**
 * Takes `micros` from the week's usage first, then from the wallet; what
 * neither has left (an answer longer than its estimate) goes on the week's.
 * Returns where it came from, so a later correction can give back to the
 * same place.
 */
export async function charge(env: Env, subscription: string, week: Week, micros: number, now: Date, questions = 0): Promise<Taken> {
  const budget = await readBudget(env, subscription, week);
  const fromWeek = Math.min(micros, Math.max(budget.week, 0));
  const wallet = Math.min(micros - fromWeek, Math.max(budget.wallet, 0));
  const spentOfWeek = micros - wallet;
  await spend(env, subscription, week.key, spentOfWeek, wallet, now, questions);
  return { week: spentOfWeek, wallet };
}

/** Adds to (or with negative amounts, gives back to) the spending of the week `key` (`Week`), its questions and the wallet. */
export async function spend(env: Env, subscription: string, key: string, ofWeek: number, wallet: number, now: Date, questions = 0) {
  const at = toStoredTime(now);
  const statements = [
    env.DB.prepare(
      `INSERT INTO chat_usage (original_transaction_id, day, questions, spent_micros) VALUES (?1, ?2, ?3, ?4)
       ON CONFLICT (original_transaction_id, day) DO UPDATE SET questions = questions + ?3, spent_micros = spent_micros + ?4`,
    ).bind(subscription, key, questions, ofWeek),
  ];
  if (wallet) {
    statements.push(
      env.DB.prepare(
        `INSERT INTO chat_wallet (original_transaction_id, extra_micros, updated_at) VALUES (?1, ?2, ?3)
         ON CONFLICT (original_transaction_id) DO UPDATE SET extra_micros = extra_micros + ?2, updated_at = ?3`,
      ).bind(subscription, -wallet, at),
    );
  }
  await env.DB.batch(statements);
}

/** How long a subscription's limit stays locked at most, should a Worker stop before it unlocks it. */
const LOCK_MS = 10_000;
/** How long a question waits while another question of the same subscription takes its share. */
const WAIT_MS = 2_000;

/**
 * A question's share of the limit, taken before OpenAI is asked (#219): its
 * estimate at `units`, if a question at that many is left (`questionsLeft`).
 * Reading the budget and writing it are two steps, so one question of a
 * subscription at a time takes its share (`chat_locks`), and questions sent
 * together never both pass the check. Returns what was taken and what was left
 * before; "none" with no question left; "busy" when another question held the
 * lock for over WAIT_MS (a lock left behind ends after LOCK_MS). The budget
 * before is returned too, for the usage the app shows after the question.
 */
export async function reserve(
  env: Env,
  subscription: string,
  week: Week,
  units: number,
  now: Date,
): Promise<{ taken: Taken; left: { week: number; bought: number }; budget: Budget } | "none" | "busy"> {
  const token = crypto.randomUUID();
  const started = Date.now();
  for (;;) {
    // `now`, moved on by the time spent waiting, so a lock left behind ends while this one waits too.
    const at = new Date(now.getTime() + Date.now() - started);
    const { meta } = await env.DB.prepare(
      `INSERT INTO chat_locks (original_transaction_id, token, until) VALUES (?1, ?2, ?3)
       ON CONFLICT (original_transaction_id) DO UPDATE SET token = ?2, until = ?3 WHERE until < ?4`,
    )
      .bind(subscription, token, toStoredTime(new Date(at.getTime() + LOCK_MS)), toStoredTime(at))
      .run();
    if (meta.changes) break;
    if (Date.now() - started > WAIT_MS) return "busy";
    // Each try is a D1 write: ten a second at most (Yurii's review of #223).
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  try {
    const budget = await readBudget(env, subscription, week);
    const left = questionsLeft(budget, units);
    if (left.week + left.bought < 1) return "none";
    return { taken: await charge(env, subscription, week, units * QUESTION_MICROS, now, 1), left, budget };
  } finally {
    await env.DB.prepare("DELETE FROM chat_locks WHERE original_transaction_id = ? AND token = ?").bind(subscription, token).run();
  }
}
