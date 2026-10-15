// Shared by the translator tests (#46): articles, fake providers, the API, and D1 row counts.
import { env, exports } from "cloudflare:workers";
import { vi } from "vitest";
import type { Lang } from "../src/translator";
import { GROQ_URL, ZAI_URL } from "../src/translator/providers";

export const QWEN = "groq:qwen/qwen3.8-27b";
export const GPT_OSS = "groq:openai/gpt-oss-120b";
/** Spanish's first model (TRANSLATORS.es). */
export const GPT_OSS_20B = "groq:openai/gpt-oss-20b";
export const GLM_45 = "zai:glm-4.5-flash";
export const GLM_47 = "zai:glm-4.7-flash";
export const GEMMA = "workers-ai:@cf/google/gemma-4-26b-a4b-it";

export const stored = (date: Date) => `${date.toISOString().slice(0, 19)}Z`;
export const hoursAgo = (hours: number) => stored(new Date(Date.now() - hours * 3_600_000));
export const minutesAgo = (minutes: number) => stored(new Date(Date.now() - minutes * 60_000));
/** A run's `now`, this many minutes from now. */
export const inMinutes = (minutes: number) => new Date(Date.now() + minutes * 60_000);

export const ENGLISH = {
  headline: "Germany's cabinet approves the 2027 draft budget",
  shortSummary: "The federal cabinet approved the draft budget for 2027.",
  summary: "The federal cabinet approved the draft budget for 2027.\nThe Bundestag now debates it.",
};

/** A good translation of ENGLISH into each language. */
export const TRANSLATED: Record<Lang, { headline: string; shortSummary: string; summary: string }> = {
  uk: {
    headline: "Уряд Німеччини схвалив проєкт бюджету на 2027 рік",
    shortSummary: "Федеральний уряд схвалив проєкт бюджету на 2027 рік.",
    summary: "Федеральний уряд схвалив проєкт бюджету на 2027 рік.\n\nТепер його обговорює Бундестаг.",
  },
  ru: {
    headline: "Правительство Германии одобрило проект бюджета на 2027 год",
    shortSummary: "Федеральное правительство одобрило проект бюджета на 2027 год.",
    summary: "Федеральное правительство одобрило проект бюджета на 2027 год.\n\nТеперь его обсуждает бундестаг.",
  },
  es: {
    headline: "El Gobierno alemán aprueba el proyecto de presupuesto para 2027",
    shortSummary: "El Consejo de Ministros federal aprobó el proyecto de presupuesto para 2027.",
    summary: "El Consejo de Ministros federal aprobó el proyecto de presupuesto para 2027.\n\nAhora lo debate el Bundestag.",
  },
  de: {
    headline: "Bundeskabinett billigt den Haushaltsentwurf für 2027",
    shortSummary: "Das Bundeskabinett hat den Haushaltsentwurf für 2027 gebilligt.",
    summary: "Das Bundeskabinett hat den Haushaltsentwurf für 2027 gebilligt.\n\nNun berät der Bundestag darüber.",
  },
};

/** A model's answer: the translation of ENGLISH into `lang`, with fields replaced. */
export const answer = (lang: Lang, overrides: Record<string, unknown> = {}) => JSON.stringify({ ...TRANSLATED[lang], ...overrides });
export const uk = (overrides: Record<string, unknown> = {}) => answer("uk", overrides);

/** Only the articles each test adds are news, so the runs pick exactly those. */
export const hideSeed = () => env.DB.prepare("UPDATE articles SET is_news = 0 WHERE model = 'seed'").run();

/** Turns the translation of only these languages on (translation_langs); the others are off. */
export const only = (...langs: Lang[]) =>
  env.DB.prepare("UPDATE translation_langs SET enabled = CASE WHEN lang IN (SELECT value FROM json_each(?)) THEN 1 ELSE 0 END")
    .bind(JSON.stringify(langs))
    .run();

/**
 * A news article with its English summary, as the summarizer leaves it: not
 * released yet, so in no feed until the translator releases it (seed articles
 * are hidden in these tests). With `released`, it is in the feed already, with
 * the next feed_seq, as an article released earlier.
 */
export async function insertNews(id: string, publishedAt: string, isNews: number | null = 1, { released = false } = {}) {
  await env.DB.prepare(
    `INSERT INTO articles (id, source_id, url, original_title, published_at, fetched_at, headline, short_summary,
                           summary, is_news, importance, decision_type, summarized_at, topics, tags, feed_seq, added_at)
     VALUES (?1, 'de-federal-government', ?2, ?3, ?4, ?4, ?5, ?6, ?7, ?8, 4, 'cabinet-decision', ?4, '["economy"]', '[]',
             CASE WHEN ?9 THEN (SELECT COALESCE(MAX(feed_seq), 0) + 1 FROM articles WHERE feed_seq IS NOT NULL) END,
             CASE WHEN ?9 THEN strftime('%Y-%m-%dT%H:%M:%SZ', 'now') END)`,
  )
    .bind(id, `https://example.gov/${id}`, `Kabinett ${id}`, publishedAt, ENGLISH.headline, ENGLISH.shortSummary, ENGLISH.summary, isNews, released ? 1 : 0)
    .run();
}

/** The news articles released into the feed, in feed order (feed_seq), oldest first. */
export async function releasedOrder() {
  const { results } = await env.DB.prepare("SELECT id FROM articles WHERE is_news = 1 AND feed_seq IS NOT NULL ORDER BY feed_seq").all<{ id: string }>();
  return results.map((r) => r.id);
}

/** Each feed's article ids, newest feed_seq first: English and the languages given. */
export async function feeds(...langs: Lang[]) {
  const out: Record<string, string[]> = { en: await ids("/articles") };
  for (const lang of langs) out[lang] = await ids(`/articles?lang=${lang}`);
  return out;
}

/** A translation that a run has claimed at `at` (or that waits in `state`), as the translator writes it. */
export const claimRow = (id: string, lang: Lang, at: string, state = "translating") =>
  env.DB.prepare(
    `INSERT INTO article_translations (article_id, lang, attempts_source, queued_at, state, state_at, claimed_at)
     SELECT id, ?2, summarized_at, ?3, ?4, ?3, CASE WHEN ?4 = 'translating' THEN ?3 END FROM articles WHERE id = ?1`,
  ).bind(id, lang, at, state);

export async function translation(id: string, lang: Lang = "uk") {
  return env.DB.prepare("SELECT * FROM article_translations WHERE article_id = ? AND lang = ?")
    .bind(id, lang)
    .first<Record<string, unknown>>();
}

export const translationRows = async () =>
  (await env.DB.prepare("SELECT COUNT(*) AS n FROM article_translations").first<{ n: number }>())?.n;

/** The state log of one article and language, oldest first. */
export async function events(id: string, lang: Lang = "uk") {
  const { results } = await env.DB.prepare(
    "SELECT state, at, attempts, detail FROM translation_events WHERE article_id = ? AND lang = ? ORDER BY rowid",
  )
    .bind(id, lang)
    .all<{ state: string; at: string; attempts: number; detail: string | null }>();
  return results;
}

export const chat = (content: unknown, finishReason = "stop") => ({
  choices: [{ message: { role: "assistant", content }, finish_reason: finishReason }],
});

export type Reply = string | { status: number; body?: unknown } | Error;

export interface ApiRequest {
  url: string;
  authorization: string | null;
  /** As in TRANSLATORS: "groq:<model>" or "zai:<model>". */
  provider: string;
  model: string;
  lang: Lang;
  body: Record<string, unknown>;
}

const LANGUAGE_NAMES: Record<string, Lang> = { Ukrainian: "uk", Russian: "ru", Spanish: "es", German: "de" };

/**
 * A fake Groq and Z.ai. `replies` lists, per provider ("groq:<model>",
 * "zai:<model>"), what it answers to its next requests; once a list is empty it
 * answers with a good translation into the language the prompt asks for.
 * Records every request, and the most requests one host had at once.
 */
export function fakeApis(replies: Record<string, Reply[]> = {}, { delayMs = 0 } = {}) {
  const requests: ApiRequest[] = [];
  const inFlight: Record<string, number> = {};
  const mostAtOnce: Record<string, number> = {};
  const fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    const kind = url === GROQ_URL ? "groq" : url === ZAI_URL ? "zai" : "unknown";
    const body = JSON.parse(String(init?.body)) as Record<string, unknown>;
    const model = String(body.model);
    const [system] = body.messages as { content: string }[];
    const name = /into (\w+)/.exec(system.content)?.[1] ?? "";
    const lang = LANGUAGE_NAMES[name] ?? "uk";
    const provider = `${kind}:${model}`;
    requests.push({ url, authorization: new Headers(init?.headers).get("authorization"), provider, model, lang, body });
    inFlight[kind] = (inFlight[kind] ?? 0) + 1;
    mostAtOnce[kind] = Math.max(mostAtOnce[kind] ?? 0, inFlight[kind]);
    try {
      if (delayMs) await new Promise((resolve) => setTimeout(resolve, delayMs));
      const reply = replies[provider]?.shift() ?? answer(lang);
      if (reply instanceof Error) throw reply;
      const { status, body: out } = typeof reply === "string" ? { status: 200, body: chat(reply) } : reply;
      return new Response(JSON.stringify(out ?? {}), { status, headers: { "content-type": "application/json" } });
    } finally {
      inFlight[kind]--;
    }
  }) as typeof globalThis.fetch;
  return { fetch, requests, mostAtOnce };
}

/** A fake Workers AI binding: answers from a list (a Ukrainian translation once it is empty) and records the calls. */
export function fakeAi(...replies: (unknown | Error)[]) {
  const calls: { model: string; inputs: Record<string, unknown> }[] = [];
  const ai = {
    run: async (model: string, inputs: Record<string, unknown>) => {
      calls.push({ model, inputs });
      const reply = replies.length ? replies.shift() : chat(uk());
      if (reply instanceof Error) throw reply;
      return reply;
    },
  } as unknown as Ai;
  return { ai, calls };
}

/** The Worker's env with a fake AI binding, a Groq key unless `groqKey` is null, and a Z.ai key unless `zaiKey` is null. */
export function testEnv(groqKey: string | null = "test-key", ai: Ai = fakeAi().ai, zaiKey: string | null = "zai-test-key") {
  return { ...env, AI: ai, GROQ_API_KEY: groqKey ?? undefined, ZAI_API_KEY: zaiKey ?? undefined };
}

export const outcome = (results: { articleId: string; lang: string; ok: boolean; provider?: string }[]) =>
  results.map((r) => `${r.articleId} ${r.lang} ${r.ok ? r.provider : "failed"}`);

export interface Article {
  id: string;
  headline: string;
  shortSummary: string;
  summary: string;
  lang?: string;
  feedSeq?: number;
  addedAt?: string;
}

export interface ArticlesPage {
  items: Article[];
  nextCursor: string | null;
  top: Article[];
  /** Language feeds only: the language is paused or off (#46). */
  translationsDelayed?: boolean;
}

export async function get(path: string) {
  const response = await exports.default.fetch(`https://api.test${path}`);
  return { status: response.status, body: (await response.json()) as unknown };
}

export const ids = async (path: string) => ((await get(path)).body as ArticlesPage).items.map((a) => a.id);

/**
 * The D1 rows `work` reads and writes (`meta.rows_read` and `meta.rows_written`
 * of every statement it runs), what D1's free plan counts.
 */
export async function d1Rows(work: () => Promise<unknown>): Promise<{ read: number; written: number }> {
  type Meta = { meta?: { rows_read?: number; rows_written?: number } };
  const statement = Object.getPrototypeOf(env.DB.prepare("SELECT 1"));
  const database = Object.getPrototypeOf(env.DB);
  const rows = { read: 0, written: 0 };
  const count = (result: Meta) => {
    rows.read += result?.meta?.rows_read ?? 0;
    rows.written += result?.meta?.rows_written ?? 0;
    return result;
  };
  for (const method of ["all", "run"] as const) {
    const original = statement[method];
    vi.spyOn(statement, method).mockImplementation(async function (this: unknown, ...args: unknown[]) {
      return count(await original.apply(this, args));
    });
  }
  const batch = database.batch;
  vi.spyOn(database, "batch").mockImplementation(async function (this: unknown, ...args: unknown[]) {
    const results = await batch.apply(this, args);
    for (const result of results) count(result);
    return results;
  });
  try {
    await work();
  } finally {
    vi.restoreAllMocks();
  }
  return rows;
}

/** The D1 rows `work` reads. */
export const rowsRead = async (work: () => Promise<unknown>) => (await d1Rows(work)).read;
