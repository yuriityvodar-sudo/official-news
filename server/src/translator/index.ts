import type { Env } from "../env";
import { toStoredTime } from "../fetcher/text";
import { LANGS, LANGUAGES, type Lang } from "./languages";
import { type Texts, systemPrompt, toTranslation, userMessage } from "./prompt";
import { type Provider, ProviderDown, UnusableAnswer, providerFor } from "./providers";
import {
  AUTO_PAUSE,
  AUTO_PAUSE_HOURS,
  CLAIM_MINUTES,
  CLAIM_WINDOW,
  CLAIMS_PER_LANGUAGE,
  COUNT_ATTEMPT,
  ENQUEUE,
  EVENT_DAYS,
  FREE_CLAIM,
  MARK_DOWN,
  MARK_UP,
  MAX_ATTEMPTS,
  OUTAGE,
  PRUNE_EVENTS,
  RELEASE_STALE,
  RETRY_OUTAGE_MINUTES,
  RETRY_UNUSABLE_MINUTES,
  type State,
  CLAIM,
  nextAttemptAt,
} from "./queue";
import { releaseReady } from "./release";

export { LANGS, LANGUAGES, type Lang, isLang } from "./languages";
export { RELEASE, RELEASES_PER_BATCH, releaseReady, releaseStatus } from "./release";
export {
  AUTO_PAUSE,
  AUTO_PAUSE_HOURS,
  AUTO_PAUSED,
  CLAIM_MINUTES,
  CLAIM_WINDOW,
  CLAIMS_PER_LANGUAGE,
  COUNT_ATTEMPT,
  ENQUEUE,
  FREE_CLAIM,
  MARK_DOWN,
  MARK_UP,
  MAX_ATTEMPTS,
  OUTAGE,
  RELEASE_STALE,
  STATES,
  CLAIM,
  queueStatus,
} from "./queue";

/**
 * The providers to try for each language, in order: the next one is used when
 * one is down, rate limited or out of its free quota. Swap or add one by
 * editing its line. Each Groq model has its own free limits, so the two Groq
 * models back each other up, and so do the two Z.ai models. Groq needs the
 * Worker secret GROQ_API_KEY, Z.ai ZAI_API_KEY; without its key a language
 * waits in the queue (and is paused automatically after AUTO_PAUSE_HOURS).
 * Spanish is on Groq's gpt-oss-20b: Z.ai answers requests from Cloudflare
 * Workers with an HTTP 405 block page (seen 15 Oct), so German, still on Z.ai,
 * is off (translation_langs, migration 0010) until another provider is chosen. `workers-ai:<model>` also works here (for example
 * `workers-ai:@cf/google/gemma-4-26b-a4b-it`), but is left out for now so the
 * Workers AI Neurons stay for the summaries (#46).
 */
export const TRANSLATORS: Record<Lang, readonly string[]> = {
  uk: ["groq:qwen/qwen3.8-27b", "groq:openai/gpt-oss-120b"],
  ru: ["groq:openai/gpt-oss-120b", "groq:qwen/qwen3.8-27b"],
  es: ["groq:openai/gpt-oss-20b", "groq:openai/gpt-oss-120b"],
  de: ["zai:glm-4.5-flash", "zai:glm-4.7-flash"],
};

/**
 * Translations for one scheduled run: one article in each language (CLAIM
 * takes CLAIMS_PER_LANGUAGE), also when other languages have nothing to do or
 * are paused. Groq counts a request's max_tokens (700) against Qwen's 1,000
 * output tokens a minute, so Qwen takes one request a run; Z.ai's free plan
 * takes one request at a time, and a run makes them one after another, at most
 * one per language.
 */
export const TRANSLATIONS_PER_RUN = LANGS.length;

/** Only articles the feed can show get translated: the last 7 days (docs/contract.md). */
const FEED_DAYS = 7;
const DAY_MS = 24 * 3_600_000;

/**
 * The order in which a language's first translations were stored: its last
 * entry in the index on (lang, lang_seq), plus 1. No longer the order of the
 * language's feed (that is the article's feed_seq, release together); kept
 * because the all-or-nothing CHECK of migration 0008 reads lang_seq as "has a
 * translation".
 */
export const NEXT_LANG_SEQ = `SELECT COALESCE(MAX(n.lang_seq), 0) + 1 FROM article_translations n
                              WHERE n.lang = ?7 AND n.lang_seq IS NOT NULL`;

/**
 * SQL for the API: whether translation `t` is shown, besides having its
 * texts. An older translation is shown while the new English waits or
 * is being translated (`updating`, `translating`, `retrying`), and no longer
 * once the new English has used its tries (`failed`): it no longer matches the
 * English, and nothing will replace it. A text of the English it was asked for
 * again (requeued by hand, after a prompt change) still matches it, so it stays
 * when the redo fails.
 */
export const SHOWN = "(t.state <> 'failed' OR t.source_summarized_at IS t.attempts_source)";

/** What happened to one article and language in a run, for the log. */
export interface TranslationResult {
  articleId: string;
  lang: Lang;
  ok: boolean;
  /** The provider that answered, as in TRANSLATORS. */
  provider?: string;
  error?: string;
}

interface Job {
  articleId: string;
  lang: Lang;
  english: Texts;
  /** `articles.summarized_at` of that English, stored with the translation. */
  source: string;
  /** Unusable answers and unanswered tries so far, for the backoff. */
  attempts: number;
  outageRetries: number;
}

export interface TranslatorOptions {
  /** Translations per run in all, each one article in one language; at most CLAIMS_PER_LANGUAGE per language. */
  maxTranslations: number;
  now?: Date;
  /** The providers to try per language; TRANSLATORS by default. */
  providers?: Record<Lang, readonly string[]>;
  /** For Groq and Z.ai; tests pass their own. */
  fetch?: typeof globalThis.fetch;
}

interface Taken {
  article_id: string;
  lang: Lang;
  attempts_source: string;
  state: State;
  attempts: number;
  outage_retries: number;
}

/**
 * #46. Translates the headline, short summary and summary of news articles in
 * the feed into each language in LANGS, one article and language per AI call,
 * and stores them in `article_translations`. Consistency first, speed second:
 * an article shows in a language only once all three fields are translated and
 * checked (prompt.ts), and the feed is the same in every language (release
 * together, release.ts): an article enters it, with its feed_seq, in English
 * and every language at once, once each enabled language that is not paused
 * has published it or failed it MAX_ATTEMPTS times.
 *
 * The queue (queue.ts) has an explicit state per article and language. Each
 * run, in one batch before any AI call: drops the state log older than 30
 * days, sends claims that ran out back to `queued`, marks a language without a
 * provider key as down, queues the news whose English is new or changed for
 * every enabled language (ENQUEUE), and claims one translation in each
 * language that is enabled, not paused by hand and has a provider (CLAIM):
 * articles still waiting for release first, then the oldest English, so no
 * language waits for another's backlog or outage. So nothing is translated
 * twice, and a run with nothing to do reads a few rows.
 *
 * Each language tries its providers in TRANSLATORS order, one request at a
 * time. One that is down, rate limited or out of quota is skipped for the rest
 * of the run; when none answers, the translation is `retrying` with a growing
 * wait (2, 4, 8 … 60 minutes), no attempt counted, and the language is down
 * from then on: after AUTO_PAUSE_HOURS it is paused automatically, so the
 * release stops waiting for it, and it is still probed with one claim a run;
 * its first answer unpauses it, and it catches up at the articles' feed_seq.
 * An unusable answer counts an attempt: `retrying` after 10, then 20 minutes,
 * `failed` after MAX_ATTEMPTS, with the reason. When the English is summarized
 * again, the translation is `updating`: made again, with the old one shown
 * until the new one is published, or until the new English has used its tries.
 *
 * Every run ends with the release (also a run with nothing to translate).
 * Its own cron trigger (CRONS in ../index.ts) runs it every even minute with
 * TRANSLATIONS_PER_RUN.
 */
export async function runTranslator(env: Env, options: TranslatorOptions): Promise<TranslationResult[]> {
  const now = options.now ?? new Date();
  const orders = options.providers ?? TRANSLATORS;

  // One Provider per name, shared by the languages, so one that fails is skipped for all of them.
  const byName = new Map<string, Provider | null>();
  for (const spec of LANGS.flatMap((lang) => orders[lang])) {
    if (!byName.has(spec)) byName.set(spec, providerFor(spec, env, options.fetch ?? globalThis.fetch));
  }
  const providersOf = (lang: Lang) => orders[lang].map((spec) => byName.get(spec)).filter((p): p is Provider => !!p);
  // A language without a provider (its key is not set) is queued but waits, and counts as down.
  const ready = LANGS.filter((lang) => providersOf(lang).length);
  const waiting = LANGS.filter((lang) => !ready.includes(lang));

  // Queue, then claim, before calling any model: one batch, one transaction.
  const claimedAt = toStoredTime(now);
  const ago = (ms: number) => toStoredTime(new Date(now.getTime() - ms));
  const feedStart = ago(FEED_DAYS * DAY_MS);
  // English written before this cannot be of an article published in the feed's 7 days (a day more for time zones).
  const writtenFrom = ago((FEED_DAYS + 1) * DAY_MS);
  const batch = await env.DB.batch<Taken>([
    env.DB.prepare(PRUNE_EVENTS).bind(ago(EVENT_DAYS * DAY_MS)),
    env.DB.prepare(RELEASE_STALE).bind(claimedAt, ago(CLAIM_MINUTES * 60_000)),
    // A language without a provider key is down too (always the 3rd statement; it changes nothing when none is missing).
    env.DB.prepare(MARK_DOWN).bind(claimedAt, JSON.stringify(waiting)),
    ...LANGS.map((lang) => env.DB.prepare(ENQUEUE).bind(lang, claimedAt, writtenFrom, feedStart)),
    ...(ready.length
      ? [env.DB.prepare(CLAIM).bind(claimedAt, feedStart, options.maxTranslations, JSON.stringify(ready), CLAIM_WINDOW, CLAIMS_PER_LANGUAGE)]
      : []),
  ]);
  // Counted from the rows returned: D1's `changes` also counts what the triggers write.
  const claimsRanOut = batch[1].results.length;
  const queued = batch.slice(3, 3 + LANGS.length).reduce((n, r) => n + r.results.length, 0);
  const taken = ready.length ? (batch.at(-1)?.results ?? []) : [];
  const skipped = taken.filter((t) => t.state === "skipped").map((t) => `${t.article_id}:${t.lang}`);
  const claimed = taken
    .filter((t) => t.state === "translating")
    .sort(
      (x, y) =>
        x.attempts_source.localeCompare(y.attempts_source) ||
        x.article_id.localeCompare(y.article_id) ||
        LANGS.indexOf(x.lang) - LANGS.indexOf(y.lang),
    );
  const queue = {
    ...(queued ? { queued } : {}),
    ...(claimsRanOut ? { claimsRanOut } : {}),
    ...(skipped.length ? { skipped } : {}),
    // Which languages have no provider key, so they wait (the names only).
    ...(waiting.length ? { waiting } : {}),
  };

  const results: TranslationResult[] = [];
  /** Providers that failed in this run, with why; they are not asked again until the next run. */
  const down: Record<string, string> = {};
  if (claimed.length) {
    // Logged before any model call, so a run stopped by a limit still shows what it took.
    console.log(JSON.stringify({ message: "translator start", claimed: claimed.map((c) => `${c.article_id}:${c.lang}`), ...queue }));
    results.push(...(await translate(env, claimed, providersOf, down, now, claimedAt)));
  }

  // Which languages' providers answered (a translation, or an unusable answer) and which
  // answered nothing; then the automatic pauses, then the release, in one batch.
  const answered = [...new Set(results.filter((r) => r.provider).map((r) => r.lang))];
  const unanswered = [...new Set(results.filter((r) => !r.provider && r.error === NO_ANSWER).map((r) => r.lang))].filter(
    (lang) => !answered.includes(lang),
  );
  const switches = await env.DB.batch<{ lang: Lang; paused?: number }>([
    ...(answered.length ? [env.DB.prepare(MARK_UP).bind(claimedAt, JSON.stringify(answered))] : []),
    ...(unanswered.length ? [env.DB.prepare(MARK_DOWN).bind(claimedAt, JSON.stringify(unanswered))] : []),
    env.DB.prepare(AUTO_PAUSE).bind(claimedAt, ago(AUTO_PAUSE_HOURS * 3_600_000)),
  ]);
  const resumed = answered.length ? switches[0].results.filter((r) => r.paused === 0).map((r) => r.lang) : [];
  const autoPaused = (switches.at(-1)?.results ?? []).map((r) => r.lang);
  const released = await releaseReady(env, claimedAt, feedStart);

  const after = {
    ...(released.length ? { released } : {}),
    ...(autoPaused.length ? { autoPaused } : {}),
    ...(resumed.length ? { resumed } : {}),
  };
  if (claimed.length) {
    console.log(JSON.stringify({ message: "translator run", results, ...(Object.keys(down).length ? { down } : {}), ...after }));
  } else if (!ready.length) {
    console.log(JSON.stringify({ message: "translator skipped", reason: "no provider available (GROQ_API_KEY, ZAI_API_KEY)", ...queue, ...after }));
  } else if (Object.keys(queue).length || Object.keys(after).length) {
    console.log(JSON.stringify({ message: "translator queue", ...queue, ...after }));
  }
  return results;
}

/** The error of a translation no provider answered: an outage, a rate limit or the quota. */
const NO_ANSWER = "no translator answered";

/** Translates the claimed rows one after another, and stores each outcome while the claim holds. */
async function translate(
  env: Env,
  claimed: Taken[],
  providersOf: (lang: Lang) => Provider[],
  down: Record<string, string>,
  now: Date,
  claimedAt: string,
): Promise<TranslationResult[]> {
  // The English as it is now. A claim whose English changed since it was queued is
  // given back: the next run queues the new English.
  const { results: articles } = await env.DB.prepare(
    `SELECT id, headline, short_summary, summary, summarized_at FROM articles
     WHERE id IN (SELECT value FROM json_each(?))`,
  )
    .bind(JSON.stringify([...new Set(claimed.map((c) => c.article_id))]))
    .all<{ id: string; headline: string | null; short_summary: string | null; summary: string | null; summarized_at: string | null }>();
  const englishOf = new Map(articles.map((a) => [a.id, a]));
  const jobs: Job[] = [];
  /** Claims to give back unchanged: the English changed after the claim. */
  const free: { articleId: string; lang: Lang }[] = [];
  for (const c of claimed) {
    const a = englishOf.get(c.article_id);
    if (a?.headline && a.short_summary && a.summary && a.summarized_at === c.attempts_source) {
      const english = { headline: a.headline, shortSummary: a.short_summary, summary: a.summary };
      jobs.push({ articleId: c.article_id, lang: c.lang, english, source: c.attempts_source, attempts: c.attempts, outageRetries: c.outage_retries });
    } else {
      free.push({ articleId: c.article_id, lang: c.lang });
    }
  }

  const results: TranslationResult[] = [];
  for (const job of jobs) {
    const language = LANGUAGES[job.lang];
    const messages = [
      { role: "system" as const, content: systemPrompt(language) },
      { role: "user" as const, content: userMessage(job.english) },
    ];
    let result: TranslationResult | null = null;
    for (const provider of providersOf(job.lang)) {
      if (provider.name in down) continue;
      try {
        const checked = toTranslation(await provider.translate(messages), job.english, language);
        if ("problems" in checked) throw new UnusableAnswer(checked.problems.join("; "));
        result = { ...(await store(env, job, checked.translation, provider.name, claimedAt)), provider: provider.name };
      } catch (error) {
        if (error instanceof ProviderDown) {
          down[provider.name] = error.message;
          continue;
        }
        if (!(error instanceof UnusableAnswer)) throw error;
        const why = `${provider.name}: ${error.message}`;
        await env.DB.prepare(COUNT_ATTEMPT)
          .bind(job.articleId, job.lang, job.source, MAX_ATTEMPTS, claimedAt, nextAttemptAt(now, RETRY_UNUSABLE_MINUTES, job.attempts), why, claimedAt)
          .run();
        result = { articleId: job.articleId, lang: job.lang, ok: false, provider: provider.name, error: error.message };
      }
      break;
    }
    if (!result) {
      // Every provider for this language is down or out of quota: it waits, without an attempt.
      const why = providersOf(job.lang)
        .map((p) => `${p.name}: ${down[p.name]}`)
        .join("; ");
      await env.DB.prepare(OUTAGE)
        .bind(job.articleId, job.lang, claimedAt, nextAttemptAt(now, RETRY_OUTAGE_MINUTES, job.outageRetries), why, claimedAt)
        .run();
      result = { articleId: job.articleId, lang: job.lang, ok: false, error: NO_ANSWER };
    }
    results.push(result);
  }

  if (free.length) {
    // One statement per claim, by primary key, in one batch.
    await env.DB.batch(free.map((c) => env.DB.prepare(FREE_CLAIM).bind(c.articleId, c.lang, claimedAt, claimedAt)));
  }
  return results;
}

/** Why a checked translation was not stored: the queue no longer holds this run's claim for that English. */
export const NOT_STORED = "not stored: requeued, claimed again or a newer English meanwhile";

/**
 * Publishes a checked translation: all three fields, the model and the English
 * version in one statement, which also makes it `published`. The first one of
 * an article in a language also gets `lang_seq` (MAX + 1, the order of first
 * translations; not the feed's order, which is the article's feed_seq) and
 * `translated_at`, in the same statement; a translation of a newer English
 * keeps both. One row per statement, and the unique index refuses a duplicate
 * number. It is stored only
 * while this run's claim (?8) holds, as COUNT_ATTEMPT, OUTAGE and FREE_CLAIM
 * are: not over a requeue made meanwhile (queue.mjs, after a prompt change),
 * nor once the claim ran out and another run may be translating it too; and
 * only for the English the queue holds, never over a translation of a newer
 * English.
 */
async function store(env: Env, job: Job, t: Texts, model: string, claim: string): Promise<Omit<TranslationResult, "provider">> {
  const { results } = await env.DB.prepare(
    `UPDATE article_translations
     SET headline = ?1, short_summary = ?2, summary = ?3, model = ?4, source_summarized_at = ?5,
         lang_seq = COALESCE(lang_seq, (${NEXT_LANG_SEQ})),
         translated_at = COALESCE(translated_at, strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
         published_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
         state = 'published', state_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
         claimed_at = NULL, queued_at = NULL, next_attempt_at = NULL, last_error = NULL, outage_retries = 0
     WHERE article_id = ?6 AND lang = ?7 AND attempts_source IS ?5 AND state = 'translating' AND claimed_at = ?8
       AND (source_summarized_at IS NULL OR source_summarized_at <= ?5)
     RETURNING lang_seq`,
  )
    .bind(t.headline, t.shortSummary, t.summary, model, job.source, job.articleId, job.lang, claim)
    .all();
  return results.length
    ? { articleId: job.articleId, lang: job.lang, ok: true }
    : { articleId: job.articleId, lang: job.lang, ok: false, error: NOT_STORED };
}
