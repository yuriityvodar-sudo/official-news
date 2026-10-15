import type { Env } from "../env";
import { toStoredTime } from "../fetcher/text";
import { type Language, type Texts, systemPrompt, toTranslation, userMessage } from "./prompt";
import { type Provider, ProviderDown, UnusableAnswer, providerFor } from "./providers";

/** The languages news articles are translated into, besides English (#46). */
export const LANGS = ["uk", "ru"] as const;
export type Lang = (typeof LANGS)[number];

/** What the prompt and the answer check need for each language in LANGS. */
export const LANGUAGES: Record<Lang, Language> = {
  // Letters only one of the two uses catch an answer in the other one.
  uk: { name: "Ukrainian", letters: /\p{Script=Cyrillic}/u, own: /[іїєґ]/iu, foreign: /[ыэъё]/iu },
  ru: { name: "Russian", letters: /\p{Script=Cyrillic}/u, foreign: /[іїєґ]/iu },
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
 * language does without the article (it never shows there) until its English
 * changes.
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

/** Gives one claim back, by primary key, without counting an attempt. */
export const FREE_CLAIM = "UPDATE article_translations SET claimed_at = NULL WHERE article_id = ? AND lang = ?";

/** The next number of a language's feed: its last entry in the index on (lang, lang_seq), plus 1. */
export const NEXT_LANG_SEQ = `SELECT COALESCE(MAX(n.lang_seq), 0) + 1 FROM article_translations n
                              WHERE n.lang = ?7 AND n.lang_seq IS NOT NULL`;

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

/**
 * #46. Translates the headline, short summary and summary of news articles in
 * the feed into each language in LANGS, newest first, one article and language
 * per AI call, and stores them in `article_translations`. Consistency first,
 * speed second: an article shows in a language only once all three fields are
 * translated and checked (prompt.ts), and each language numbers its articles
 * in the order their translations are stored (`lang_seq`), so a late one lands
 * on top of that language's feed.
 *
 * Each language tries its providers in TRANSLATORS order. One that is down,
 * rate limited or out of quota is skipped for the rest of the run; when none
 * answers, the translation waits for a later run (claim freed, no attempt
 * counted). An unusable answer counts an attempt and keeps the claim, so the
 * next try waits CLAIM_MINUTES; after MAX_ATTEMPTS the article does not show in
 * that language. When the English is summarized again, the translation is made
 * again, and the old one is served until the new one is stored.
 *
 * The run claims its translations first, in one statement, so an overlapping
 * run takes other ones and nothing is translated twice.
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
    // Groq without its key: nothing can be translated, so nothing is claimed.
    console.log(JSON.stringify({ message: "translator skipped", reason: "no provider available (is GROQ_API_KEY set?)" }));
    return [];
  }

  // Claim before calling any model. A translation is due when there is none of
  // the article's current English yet (never translated, or the English changed
  // since), it has tries left for that English, and no live claim. Tries count
  // per English: the claim starts them again at 0 when the English changed.
  const { results: claimed } = await env.DB.prepare(
    `INSERT INTO article_translations (article_id, lang, claimed_at, attempts_source)
     SELECT a.id, l.value, ?1, a.summarized_at
     FROM articles a
     JOIN json_each(?2) l
     LEFT JOIN article_translations t ON t.article_id = a.id AND t.lang = l.value
     WHERE a.is_news = 1
       AND a.headline IS NOT NULL AND a.short_summary IS NOT NULL AND a.summary IS NOT NULL
       AND a.summarized_at IS NOT NULL
       AND a.published_at >= ?3
       AND (t.article_id IS NULL
            OR ((t.source_summarized_at IS NULL OR t.source_summarized_at < a.summarized_at)
                AND (t.attempts < ?4 OR t.attempts_source IS NOT a.summarized_at)
                AND (t.claimed_at IS NULL OR t.claimed_at < ?5)))
     ORDER BY a.published_at DESC, a.id DESC, l.key
     LIMIT ?6
     ON CONFLICT (article_id, lang) DO UPDATE SET
       claimed_at = excluded.claimed_at,
       attempts = CASE WHEN attempts_source IS excluded.attempts_source THEN attempts ELSE 0 END,
       attempts_source = excluded.attempts_source
     RETURNING article_id, lang`,
  )
    .bind(
      toStoredTime(now),
      JSON.stringify(langs),
      toStoredTime(new Date(now.getTime() - FEED_DAYS * 24 * 3_600_000)),
      MAX_ATTEMPTS,
      toStoredTime(new Date(now.getTime() - CLAIM_MINUTES * 60_000)),
      options.maxTranslations,
    )
    .all<{ article_id: string; lang: Lang }>();
  if (!claimed.length) return [];

  // Logged before any model call, so a run stopped by a limit still shows what it took.
  console.log(JSON.stringify({ message: "translator start", claimed: claimed.map((c) => `${c.article_id}:${c.lang}`) }));

  // The English and its version, read together: the translation is stored with that version.
  const { results: articles } = await env.DB.prepare(
    `SELECT id, headline, short_summary, summary, summarized_at FROM articles
     WHERE id IN (SELECT value FROM json_each(?))
       AND headline IS NOT NULL AND short_summary IS NOT NULL AND summary IS NOT NULL AND summarized_at IS NOT NULL
     ORDER BY published_at DESC, id DESC`,
  )
    .bind(JSON.stringify([...new Set(claimed.map((c) => c.article_id))]))
    .all<{ id: string; headline: string; short_summary: string; summary: string; summarized_at: string }>();
  const jobs: Job[] = articles.flatMap((a) =>
    langs
      .filter((lang) => claimed.some((c) => c.article_id === a.id && c.lang === lang))
      .map((lang) => ({
        articleId: a.id,
        lang,
        english: { headline: a.headline, shortSummary: a.short_summary, summary: a.summary },
        source: a.summarized_at,
      })),
  );
  /** Claims to give back without an attempt: no provider answered, or the English is being redone. */
  const free = claimed
    .filter((c) => !jobs.some((j) => j.articleId === c.article_id && j.lang === c.lang))
    .map((c) => ({ articleId: c.article_id, lang: c.lang }));

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
        // The claim stays, so the next try waits until it runs out (CLAIM_MINUTES).
        await env.DB.prepare("UPDATE article_translations SET attempts = attempts + 1 WHERE article_id = ? AND lang = ?")
          .bind(job.articleId, job.lang)
          .run();
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
    await env.DB.batch(free.map((c) => env.DB.prepare(FREE_CLAIM).bind(c.articleId, c.lang)));
  }

  console.log(JSON.stringify({ message: "translator run", results, ...(Object.keys(down).length ? { down } : {}) }));
  return results;
}

/**
 * Stores a checked translation: all three fields, the model and the English
 * version in one statement. The first one of an article in a language also gets
 * that language's next number (`lang_seq`, MAX + 1) and `translated_at`, in the
 * same statement; a translation of a newer English keeps both, so the article
 * keeps its place in the feed. One row per statement, and the unique index
 * refuses a duplicate number. A translation of an older English than the one
 * already stored (a run that was cut off and came back late) is not stored.
 */
async function store(env: Env, job: Job, t: Texts, model: string): Promise<Omit<TranslationResult, "provider">> {
  const { meta } = await env.DB.prepare(
    `UPDATE article_translations
     SET headline = ?1, short_summary = ?2, summary = ?3, model = ?4, source_summarized_at = ?5,
         lang_seq = COALESCE(lang_seq, (${NEXT_LANG_SEQ})),
         translated_at = COALESCE(translated_at, strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
         claimed_at = NULL
     WHERE article_id = ?6 AND lang = ?7
       AND (source_summarized_at IS NULL OR source_summarized_at <= ?5)`,
  )
    .bind(t.headline, t.shortSummary, t.summary, model, job.source, job.articleId, job.lang)
    .run();
  return meta.changes
    ? { articleId: job.articleId, lang: job.lang, ok: true }
    : { articleId: job.articleId, lang: job.lang, ok: false, error: "a translation of a newer English is already stored" };
}
