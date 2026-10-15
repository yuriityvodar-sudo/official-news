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

/** An article gets this many tries with an unusable answer per language, then it stays in English. */
export const MAX_ATTEMPTS = 3;

/** A claim older than this is from a run that was cut off, so its article is free again. */
export const CLAIM_MINUTES = 10;

/** Only articles the feed can show get translated: the last 7 days (docs/contract.md). */
const FEED_DAYS = 7;

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
}

export interface TranslatorOptions {
  /** Translations per run: one per article and language, so 6 is 3 articles in 2 languages. */
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
 * the feed into each language in LANGS, newest first, and stores them in
 * `article_translations`; the API returns them for `?lang=`.
 *
 * Each language tries its providers in TRANSLATORS order. One that is down,
 * rate limited or out of quota is skipped for the rest of the run; when none
 * answers, the translation waits for a later run (claim freed, no attempt
 * counted). An unusable answer (not JSON, a field missing, cut off, too long,
 * wrong language, wrong number of paragraphs) counts an attempt; after
 * MAX_ATTEMPTS that language stays in English.
 *
 * The run claims its translations first, in one statement, so an overlapping
 * run takes other ones and nothing is translated twice.
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

  // Claim before calling any model: a new row, or one that is not finished, has
  // tries left and no live claim. The SELECT picks only those, so the upsert
  // just sets claimed_at.
  const { results: claimed } = await env.DB.prepare(
    `INSERT INTO article_translations (article_id, lang, claimed_at)
     SELECT a.id, l.value, ?1
     FROM articles a
     JOIN json_each(?2) l
     LEFT JOIN article_translations t ON t.article_id = a.id AND t.lang = l.value
     WHERE a.is_news = 1
       AND a.headline IS NOT NULL AND a.short_summary IS NOT NULL AND a.summary IS NOT NULL
       AND a.published_at >= ?3
       AND (t.article_id IS NULL
            OR (t.translated_at IS NULL AND t.attempts < ?4 AND (t.claimed_at IS NULL OR t.claimed_at < ?5)))
     ORDER BY a.published_at DESC, a.id DESC, l.key
     LIMIT ?6
     ON CONFLICT (article_id, lang) DO UPDATE SET claimed_at = excluded.claimed_at
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
    .all<{ article_id: string; lang: string }>();
  if (!claimed.length) return [];

  // Logged before any model call, so a run stopped by a limit still shows what it took.
  console.log(JSON.stringify({ message: "translator start", claimed: claimed.map((c) => `${c.article_id}:${c.lang}`) }));

  const { results: articles } = await env.DB.prepare(
    `SELECT id, headline, short_summary, summary FROM articles
     WHERE id IN (SELECT value FROM json_each(?))
     ORDER BY published_at DESC, id DESC`,
  )
    .bind(JSON.stringify([...new Set(claimed.map((c) => c.article_id))]))
    .all<{ id: string; headline: string; short_summary: string; summary: string }>();
  const jobs: Job[] = articles.flatMap((a) =>
    langs
      .filter((lang) => claimed.some((c) => c.article_id === a.id && c.lang === lang))
      .map((lang) => ({ articleId: a.id, lang, english: { headline: a.headline, shortSummary: a.short_summary, summary: a.summary } })),
  );

  const results: TranslationResult[] = [];
  /** Providers that failed in this run, with why; they are not asked again until the next run. */
  const down: Record<string, string> = {};
  const waiting: Job[] = [];
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
        const t = checked.translation;
        await env.DB.prepare(
          `UPDATE article_translations
           SET headline = ?, short_summary = ?, summary = ?, model = ?, translated_at = ?, claimed_at = NULL
           WHERE article_id = ? AND lang = ?`,
        )
          .bind(t.headline, t.shortSummary, t.summary, provider.name, toStoredTime(new Date()), job.articleId, job.lang)
          .run();
        result = { articleId: job.articleId, lang: job.lang, ok: true, provider: provider.name };
      } catch (error) {
        if (error instanceof ProviderDown) {
          down[provider.name] = error.message;
          continue;
        }
        if (!(error instanceof UnusableAnswer)) throw error;
        await env.DB.prepare(
          "UPDATE article_translations SET attempts = attempts + 1, claimed_at = NULL WHERE article_id = ? AND lang = ?",
        )
          .bind(job.articleId, job.lang)
          .run();
        result = { articleId: job.articleId, lang: job.lang, ok: false, provider: provider.name, error: error.message };
      }
      break;
    }
    if (!result) {
      // Every provider for this language is down or out of quota: it waits for a later run.
      waiting.push(job);
      result = { articleId: job.articleId, lang: job.lang, ok: false, error: "no translator answered" };
    }
    results.push(result);
  }

  if (waiting.length) {
    // Free the claims, no attempt counted.
    await env.DB.prepare(
      `UPDATE article_translations SET claimed_at = NULL
       WHERE article_id || ':' || lang IN (SELECT value FROM json_each(?))`,
    )
      .bind(JSON.stringify(waiting.map((j) => `${j.articleId}:${j.lang}`)))
      .run();
  }

  console.log(JSON.stringify({ message: "translator run", results, ...(Object.keys(down).length ? { down } : {}) }));
  return results;
}
