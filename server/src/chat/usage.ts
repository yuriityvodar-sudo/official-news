import type { Env } from "../env";
import { toStoredTime } from "../fetcher/text";

/**
 * The AI chat's limit (#146, Roman 27 Oct): what the answers really cost at
 * OpenAI, so a subscriber never costs more than a set sum. Its unit, a
 * "question", is $0.002 of that cost: a typical question is one, a question
 * about a long document two or three. Amounts are in micro-dollars.
 */
export const QUESTION_MICROS = 2000;

/** Questions a day in the subscription: $0.04 a day, so at most $1.20 a month a subscriber. Unused ones do not carry over. */
export const DAILY_QUESTIONS = 20;
export const DAILY_MICROS = DAILY_QUESTIONS * QUESTION_MICROS;

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

/** What a subscription has left: of today's budget (UTC), and in its wallet of bought questions. */
export interface Budget {
  today: number;
  wallet: number;
}

export async function readBudget(env: Env, subscription: string, day: string): Promise<Budget> {
  const row = await env.DB.prepare(
    `SELECT (SELECT spent_micros FROM chat_usage WHERE original_transaction_id = ?1 AND day = ?2) AS spent,
            (SELECT extra_micros FROM chat_wallet WHERE original_transaction_id = ?1) AS wallet`,
  )
    .bind(subscription, day)
    .first<{ spent: number | null; wallet: number | null }>();
  return { today: DAILY_MICROS - (row?.spent ?? 0), wallet: row?.wallet ?? 0 };
}

/** The questions left at `units` a question: today's, and the bought ones, which are spent after them. */
export function questionsLeft(budget: Budget, units: number): { today: number; bought: number } {
  const each = units * QUESTION_MICROS;
  return { today: Math.max(0, Math.floor(budget.today / each)), bought: Math.max(0, Math.floor(budget.wallet / each)) };
}

/**
 * Takes `micros` from today's budget first, then from the wallet; what neither
 * has left (an answer longer than its estimate) goes on today's. Returns where
 * it came from, so a later correction can give back to the same place.
 */
export async function charge(
  env: Env,
  subscription: string,
  day: string,
  micros: number,
  now: Date,
  question = false,
): Promise<{ today: number; wallet: number }> {
  const budget = await readBudget(env, subscription, day);
  const fromToday = Math.min(micros, Math.max(budget.today, 0));
  const wallet = Math.min(micros - fromToday, Math.max(budget.wallet, 0));
  const today = micros - wallet;
  await spend(env, subscription, day, today, wallet, now, question);
  return { today, wallet };
}

/** Adds to (or with negative amounts, gives back to) today's spending and the wallet. */
export async function spend(env: Env, subscription: string, day: string, today: number, wallet: number, now: Date, question = false) {
  const at = toStoredTime(now);
  const statements = [
    env.DB.prepare(
      `INSERT INTO chat_usage (original_transaction_id, day, questions, spent_micros) VALUES (?1, ?2, ?3, ?4)
       ON CONFLICT (original_transaction_id, day) DO UPDATE SET questions = questions + ?3, spent_micros = spent_micros + ?4`,
    ).bind(subscription, day, question ? 1 : 0, today),
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
