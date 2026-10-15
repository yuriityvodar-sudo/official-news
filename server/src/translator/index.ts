import type { Env } from "../env";
import { toStoredTime } from "../fetcher/text";
import { type Language, type Texts, systemPrompt, toTranslation, userMessage } from "./prompt";
import { type Provider, ProviderDown, UnusableAnswer, providerFor } from "./providers";

/** The languages news articles are translated into, besides English (#46). */
export const LANGS = ["uk", "ru"] as const;
export type Lang = (typeof LANGS)[number];

/** What the prompt and the answer check need for each language in LANGS. */
export const LANGUAGES: Record<Lang, Language> = {
  uk: {
    name: "Ukrainian",
    letters: /\p{Script=Cyrillic}/u,
    own: /[іїєґ]/iu,
    // Russian letters, and Russian words Ukrainian does not have.
    foreign:
      /[ыэъё]|(?<!\p{L})(?:и|что|его|как|также|будет|будут|котор\p{L}*|или|из|она|они|был|была|было|были|правительств\p{L}*)(?!\p{L})/iu,
    numbers: {
      decimalComma: true,
      months: ["січня", "лютого", "березня", "квітня", "травня", "червня", "липня", "серпня", "вересня", "жовтня", "листопада", "грудня"],
    },
  },
  ru: {
    name: "Russian",
    letters: /\p{Script=Cyrillic}/u,
    // Ukrainian letters, and Ukrainian words Russian does not have.
    foreign:
      /[іїєґ]|(?<!\p{L})(?:що|це|щодо|також|буде|будуть|й|який|яка|яке|якого|яких|якому|або|але|його|вона|вони|був|була|було|були|цей|ця|цього|уряд|уряду|урядом|тепер)(?!\p{L})/iu,
    numbers: {
      decimalComma: true,
      months: ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"],
    },
  },
};

/**
 * The providers to try for each language, in order: the next one is used when
 * one is down, rate limited or out of its free quota. Swap or add one by
 * editing its line. Each Groq model has its own free limits, so the two Groq
 * models back each other up. All need the Worker secret GROQ_API_KEY; without
 * it nothing is translated. `workers-ai:<model>` also works here (for example
 * `workers-ai:@cf/google/gemma-4-26b-a4b-it`), but is left out for now so the
 * Workers AI Neurons stay for the summaries (#46).
 */
export const TRANSLATORS: Record<Lang, readonly string[]> = {
  uk: ["groq:qwen/qwen3.8-27b", "groq:openai/gpt-oss-120b"],
  ru: ["groq:openai/gpt-oss-120b", "groq:qwen/qwen3.8-27b"],
};

/**
 * Unusable answers for one article, language and English text; then that
 * English leaves the queue until the English changes. A new article never
 * shows in that language, and an older translation of a re-summarized one is
 * no longer shown (SHOWN).
 */
export const MAX_ATTEMPTS = 3;

/**
 * A claim older than this is free again: its run was cut off, or it got an
 * unusable answer and waited this long before the next try.
 */
export const CLAIM_MINUTES = 10;

/**
 * Translations for one scheduled run, for the step rotation of #50: one article
 * in both languages. Groq counts a request's max_tokens (700) against Qwen's
 * 1,000 output tokens a minute, so Qwen takes one request a minute.
 */
export const TRANSLATIONS_PER_RUN = 2;

/** Only articles the feed can show get translated: the last 7 days (docs/contract.md). */
const FEED_DAYS = 7;
const DAY_MS = 24 * 3_600_000;

/**
 * How far before the newest English already queued each run looks again. A
 * summary's `summarized_at` is set a moment before it is written, so one can be
 * written just after a run looked past that time.
 */
const ENQUEUE_OVERLAP = "-10 minutes";

/**
 * Puts news whose English is new or changed into the queue for one language
 * (?1): every news article of the feed enters it once per language and English
 * version (`attempts_source`, with fresh tries). It looks only at English
 * written since the newest one it queued for that language, through the index
 * on `summarized_at`, so a run with nothing new reads a few rows; a language
 * with nothing queued yet (a new one) queues the feed's 7 days.
 */
export const ENQUEUE = `INSERT INTO article_translations (article_id, lang, attempts_source, queued_at)
  SELECT a.id, ?1, a.summarized_at, ?2
  FROM articles a INDEXED BY articles_news_summarized
  WHERE a.is_news = 1
    AND a.summarized_at > MAX(?3, COALESCE((SELECT strftime('%Y-%m-%dT%H:%M:%SZ', w.attempts_source, '${ENQUEUE_OVERLAP}')
                                            FROM article_translations w INDEXED BY article_translations_source
                                            WHERE w.lang = ?1 AND w.attempts_source IS NOT NULL
                                            ORDER BY w.attempts_source DESC LIMIT 1), ''))
    AND a.published_at >= ?4
    AND a.headline IS NOT NULL AND a.short_summary IS NOT NULL AND a.summary IS NOT NULL
  ON CONFLICT (article_id, lang) DO UPDATE SET
    attempts_source = excluded.attempts_source, attempts = 0, queued_at = excluded.queued_at
  WHERE attempts_source IS NOT excluded.attempts_source`;

/**
 * Claims the next translations in one statement, so an overlapping run takes
 * other ones: oldest English first, the order the articles came into the
 * English feed, so a backlog comes out in each language in that order (each
 * article's languages in LANGS order). It walks
 * the index of the queue, so it reads about what it takes. A queued translation
 * whose article has left the feed (hidden, older than 7 days) or whose English
 * is being redone leaves the queue instead; it comes back with a new English.
 * Returns each row taken, with `claimed_at` NULL for one that left.
 */
export const CLAIM = `UPDATE article_translations AS t
  SET claimed_at = CASE WHEN c.ok THEN ?1 END,
      queued_at = CASE WHEN c.ok THEN t.queued_at END
  FROM (SELECT q.article_id, q.lang,
               EXISTS (SELECT 1 FROM articles a
                       WHERE a.id = q.article_id AND a.is_news = 1 AND a.published_at >= ?2
                         AND a.summarized_at IS q.attempts_source
                         AND a.headline IS NOT NULL AND a.short_summary IS NOT NULL AND a.summary IS NOT NULL) AS ok
        FROM article_translations q INDEXED BY article_translations_queue
        WHERE q.queued_at IS NOT NULL
          AND q.lang IN (SELECT value FROM json_each(?3))
          AND (q.claimed_at IS NULL OR q.claimed_at < ?4)
        ORDER BY q.attempts_source, q.article_id, (SELECT l.key FROM json_each(?3) l WHERE l.value = q.lang)
        LIMIT ?5) AS c
  WHERE t.article_id = c.article_id AND t.lang = c.lang
  RETURNING article_id, lang, attempts_source, claimed_at`;

/** Gives this run's claim back, by primary key, without counting an attempt. */
export const FREE_CLAIM = "UPDATE article_translations SET claimed_at = NULL WHERE article_id = ? AND lang = ? AND claimed_at = ?";

/**
 * Counts an unusable answer for the English it was given. The claim stays, so
 * the next try waits CLAIM_MINUTES; after the last try the translation leaves
 * the queue.
 */
const COUNT_ATTEMPT = `UPDATE article_translations
  SET attempts = attempts + 1,
      queued_at = CASE WHEN attempts + 1 >= ?4 THEN NULL ELSE queued_at END,
      claimed_at = CASE WHEN attempts + 1 >= ?4 THEN NULL ELSE claimed_at END
  WHERE article_id = ?1 AND lang = ?2 AND attempts_source IS ?3`;

/** The next number of a language's feed: its last entry in the index on (lang, lang_seq), plus 1. */
export const NEXT_LANG_SEQ = `SELECT COALESCE(MAX(n.lang_seq), 0) + 1 FROM article_translations n
                              WHERE n.lang = ?7 AND n.lang_seq IS NOT NULL`;

/**
 * SQL for the API: whether translation `t` of article `a` is shown. One of an
 * older English is shown while the new English is still being tried (#46), and
 * no longer once its tries are used up: it no longer matches the English, and
 * nothing will replace it.
 */
export const SHOWN = `(t.source_summarized_at IS a.summarized_at OR t.attempts_source IS NOT a.summarized_at OR t.attempts < ${MAX_ATTEMPTS})`;

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
}

export interface TranslatorOptions {
  /** Translations per run: one per article and language, so 2 is one article in 2 languages. */
  maxTranslations: number;
  now?: Date;
  /** The providers to try per language; TRANSLATORS by default. */
  providers?: Record<Lang, readonly string[]>;
  /** For Groq; tests pass their own. */
  fetch?: typeof globalThis.fetch;
}

/** Whether `value` is one of LANGS. */
export const isLang = (value: string): value is Lang => (LANGS as readonly string[]).includes(value);

interface Taken {
  article_id: string;
  lang: Lang;
  attempts_source: string;
  claimed_at: string | null;
}

/**
 * #46. Translates the headline, short summary and summary of news articles in
 * the feed into each language in LANGS, one article and language per AI call,
 * and stores them in `article_translations`. Consistency first, speed second:
 * an article shows in a language only once all three fields are translated and
 * checked (prompt.ts), and each language numbers its articles in the order
 * their translations are stored (`lang_seq`), so a late one lands on top of
 * that language's feed.
 *
 * The queue: each run first queues the news whose English is new or changed
 * (ENQUEUE), then claims the oldest English waiting (CLAIM), both in one batch,
 * so nothing is translated twice and a run with nothing to do reads a few rows.
 *
 * Each language tries its providers in TRANSLATORS order. One that is down,
 * rate limited or out of quota is skipped for the rest of the run; when none
 * answers, the translation waits for a later run (claim freed, no attempt
 * counted). An unusable answer counts an attempt and keeps the claim, so the
 * next try waits CLAIM_MINUTES; after MAX_ATTEMPTS that English leaves the
 * queue. When the English is summarized again, the translation is made again,
 * and the old one is served until the new one is stored, or until the new
 * English has used its tries.
 *
 * Not on a cron trigger of its own: it joins the one-trigger step rotation of
 * #50 with `runTranslator(env, { maxTranslations: TRANSLATIONS_PER_RUN })`.
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
  const langs = LANGS.filter((lang) => providersOf(lang).length);
  if (!langs.length) {
    // Groq without its key: nothing can be translated, so nothing is queued or claimed.
    console.log(JSON.stringify({ message: "translator skipped", reason: "no provider available (is GROQ_API_KEY set?)" }));
    return [];
  }

  // Queue, then claim, before calling any model: one batch, one transaction.
  const claimedAt = toStoredTime(now);
  const feedStart = toStoredTime(new Date(now.getTime() - FEED_DAYS * DAY_MS));
  // English written before this cannot be of an article published in the feed's 7 days (a day more for time zones).
  const writtenFrom = toStoredTime(new Date(now.getTime() - (FEED_DAYS + 1) * DAY_MS));
  const batch = await env.DB.batch<Taken>([
    ...langs.map((lang) => env.DB.prepare(ENQUEUE).bind(lang, claimedAt, writtenFrom, feedStart)),
    env.DB.prepare(CLAIM).bind(
      claimedAt,
      feedStart,
      JSON.stringify(langs),
      toStoredTime(new Date(now.getTime() - CLAIM_MINUTES * 60_000)),
      options.maxTranslations,
    ),
  ]);
  const queued = batch.slice(0, -1).reduce((n, r) => n + (r.meta.changes ?? 0), 0);
  const taken = batch.at(-1)?.results ?? [];
  const left = taken.filter((t) => t.claimed_at !== claimedAt).map((t) => `${t.article_id}:${t.lang}`);
  const claimed = taken
    .filter((t) => t.claimed_at === claimedAt)
    .sort(
      (x, y) =>
        x.attempts_source.localeCompare(y.attempts_source) ||
        x.article_id.localeCompare(y.article_id) ||
        LANGS.indexOf(x.lang) - LANGS.indexOf(y.lang),
    );
  const queue = { ...(queued ? { queued } : {}), ...(left.length ? { left } : {}) };
  if (!claimed.length) {
    if (Object.keys(queue).length) console.log(JSON.stringify({ message: "translator queue", ...queue }));
    return [];
  }

  // Logged before any model call, so a run stopped by a limit still shows what it took.
  console.log(JSON.stringify({ message: "translator start", claimed: claimed.map((c) => `${c.article_id}:${c.lang}`), ...queue }));

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
  /** Claims to give back without an attempt: no provider answered, or the English is being redone. */
  const free: { articleId: string; lang: Lang }[] = [];
  for (const c of claimed) {
    const a = englishOf.get(c.article_id);
    if (a?.headline && a.short_summary && a.summary && a.summarized_at === c.attempts_source) {
      const english = { headline: a.headline, shortSummary: a.short_summary, summary: a.summary };
      jobs.push({ articleId: c.article_id, lang: c.lang, english, source: c.attempts_source });
    } else {
      free.push({ articleId: c.article_id, lang: c.lang });
    }
  }

  const results: TranslationResult[] = [];
  /** Providers that failed in this run, with why; they are not asked again until the next run. */
  const down: Record<string, string> = {};
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
        result = { ...(await store(env, job, checked.translation, provider.name)), provider: provider.name };
      } catch (error) {
        if (error instanceof ProviderDown) {
          down[provider.name] = error.message;
          continue;
        }
        if (!(error instanceof UnusableAnswer)) throw error;
        await env.DB.prepare(COUNT_ATTEMPT).bind(job.articleId, job.lang, job.source, MAX_ATTEMPTS).run();
        result = { articleId: job.articleId, lang: job.lang, ok: false, provider: provider.name, error: error.message };
      }
      break;
    }
    if (!result) {
      // Every provider for this language is down or out of quota: it waits for a later run.
      free.push({ articleId: job.articleId, lang: job.lang });
      result = { articleId: job.articleId, lang: job.lang, ok: false, error: "no translator answered" };
    }
    results.push(result);
  }

  if (free.length) {
    // No attempt counted. One statement per claim, by primary key, in one batch.
    await env.DB.batch(free.map((c) => env.DB.prepare(FREE_CLAIM).bind(c.articleId, c.lang, claimedAt)));
  }

  console.log(JSON.stringify({ message: "translator run", results, ...(Object.keys(down).length ? { down } : {}) }));
  return results;
}

/**
 * Stores a checked translation: all three fields, the model and the English
 * version in one statement, which also takes it out of the queue. The first one
 * of an article in a language also gets that language's next number
 * (`lang_seq`, MAX + 1) and `translated_at`, in the same statement; a
 * translation of a newer English keeps both, so the article keeps its place in
 * the feed. One row per statement, and the unique index refuses a duplicate
 * number. It is stored only for the English the queue holds, and never over a
 * translation of a newer English (a run that was cut off and came back late).
 */
async function store(env: Env, job: Job, t: Texts, model: string): Promise<Omit<TranslationResult, "provider">> {
  const { meta } = await env.DB.prepare(
    `UPDATE article_translations
     SET headline = ?1, short_summary = ?2, summary = ?3, model = ?4, source_summarized_at = ?5,
         lang_seq = COALESCE(lang_seq, (${NEXT_LANG_SEQ})),
         translated_at = COALESCE(translated_at, strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
         claimed_at = NULL, queued_at = NULL
     WHERE article_id = ?6 AND lang = ?7 AND attempts_source IS ?5
       AND (source_summarized_at IS NULL OR source_summarized_at <= ?5)`,
  )
    .bind(t.headline, t.shortSummary, t.summary, model, job.source, job.articleId, job.lang)
    .run();
  return meta.changes
    ? { articleId: job.articleId, lang: job.lang, ok: true }
    : { articleId: job.articleId, lang: job.lang, ok: false, error: "not stored: a newer English is queued or translated" };
}
