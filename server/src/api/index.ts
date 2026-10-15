import type { Env } from "../env";
import { sourceHealth } from "../health";
import { LANGS, type Lang, SHOWN, isLang, queueStatus } from "../translator";

/** A row of `articles` joined with its source, as stored in D1. */
interface ArticleRow {
  id: string;
  country: string;
  source_id: string;
  source_name: string;
  source_url: string;
  url: string;
  original_title: string;
  published_at: string;
  date_only: number;
  headline: string | null;
  short_summary: string | null;
  summary: string | null;
  decision_type: string | null;
  image_url: string | null;
  original_language: string | null;
  topics: string | null;
  tags: string | null;
  importance: number | null;
}

const ARTICLE_COLUMNS = `
  a.id, s.country, a.source_id, s.name AS source_name, s.url AS source_url,
  a.url, a.original_title, a.published_at, a.date_only, a.headline, a.short_summary,
  a.summary, a.decision_type, a.image_url, a.original_language, a.topics, a.tags, a.importance`;

const FROM_ARTICLES = "FROM articles a JOIN sources s ON s.id = a.source_id";

/** The feed shows official decisions from the last 7 days (docs/contract.md). */
const FEED_WINDOW = "a.published_at >= strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-7 days')";

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;

/**
 * Top today: last 24 hours, highest importance, at most 2 per country, up to 5,
 * among the articles `where` picks (the feed's, or a language's: #46).
 */
const topQuery = (columns: string, from: string, where: string) => `
  SELECT * FROM (
    SELECT ${columns},
           ROW_NUMBER() OVER (
             PARTITION BY s.country ORDER BY a.importance DESC, a.published_at DESC, a.id DESC
           ) AS country_rank
    ${from}
    WHERE ${where} AND a.importance IS NOT NULL
      AND a.published_at >= strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-24 hours')
  )
  WHERE country_rank <= 2
  ORDER BY importance DESC, published_at DESC, id DESC
  LIMIT 5`;

const TOP_QUERY = topQuery(ARTICLE_COLUMNS, FROM_ARTICLES, "a.is_news = 1");

/** A JSON array of strings stored in D1; anything else reads as empty. */
function parseStringArray(value: string | null): string[] {
  if (!value) return [];
  try {
    const parsed: unknown = JSON.parse(value);
    return Array.isArray(parsed) ? parsed.filter((item): item is string => typeof item === "string") : [];
  } catch {
    return [];
  }
}

/** Converts a row to the article format in docs/contract.md. */
export function toArticle(row: ArticleRow) {
  return {
    id: row.id,
    country: row.country,
    source: { id: row.source_id, name: row.source_name, url: row.source_url },
    publishedAt: row.published_at,
    dateOnly: row.date_only === 1,
    headline: row.headline,
    shortSummary: row.short_summary,
    summary: row.summary,
    decisionType: row.decision_type,
    originalTitle: row.original_title,
    originalLanguage: row.original_language,
    topics: parseStringArray(row.topics),
    tags: parseStringArray(row.tags),
    importance: row.importance,
    imageUrl: row.image_url,
    originalUrl: row.url,
  };
}

const json = (body: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...headers },
  });

const badRequest = (message: string) => json({ error: message }, 400);

/** Timestamps are stored as `YYYY-MM-DDTHH:MM:SSZ` (docs/contract.md), so they compare as text. */
function toStoredTime(date: Date): string {
  return `${date.toISOString().slice(0, 19)}Z`;
}

/** The position after the last article of a page: opaque to the app. */
interface Cursor {
  publishedAt: string;
  id: string;
}

function encodeCursor(cursor: Cursor): string {
  return btoa(JSON.stringify([cursor.publishedAt, cursor.id]))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");
}

function decodeCursor(value: string): Cursor | null {
  try {
    const parsed: unknown = JSON.parse(atob(value.replaceAll("-", "+").replaceAll("_", "/")));
    if (
      Array.isArray(parsed) &&
      parsed.length === 2 &&
      typeof parsed[0] === "string" &&
      typeof parsed[1] === "string"
    ) {
      return { publishedAt: parsed[0], id: parsed[1] };
    }
  } catch {
    // Falls through to null: not a cursor we issued.
  }
  return null;
}

/**
 * `GET /articles?limit=&cursor=&since=`: news from the last 7 days, newest
 * first. `cursor` continues from the previous page; `since` keeps only
 * articles published after that time. `top` is filled on the first page only.
 * With `lang` other than `en`, the translated feed instead (listTranslated).
 */
async function listArticles(url: URL, env: Env): Promise<Response> {
  const params = url.searchParams;

  let limit = DEFAULT_LIMIT;
  const limitParam = params.get("limit");
  if (limitParam !== null) {
    limit = Number(limitParam);
    if (!Number.isInteger(limit) || limit < 1 || limit > MAX_LIMIT) {
      return badRequest(`limit must be a whole number from 1 to ${MAX_LIMIT}`);
    }
  }

  const lang = readLang(params);
  if (lang === undefined) return badRequest(LANG_ERROR);
  if (lang !== null) return listTranslated(params, lang, limit, env);

  const where = ["a.is_news = 1", FEED_WINDOW];
  const binds: (string | number)[] = [];

  const sinceParam = params.get("since");
  if (sinceParam !== null) {
    const since = new Date(sinceParam);
    if (Number.isNaN(since.getTime())) return badRequest("since must be an ISO 8601 time");
    where.push("a.published_at > ?");
    binds.push(toStoredTime(since));
  }

  const cursorParam = params.get("cursor");
  if (cursorParam !== null) {
    const cursor = decodeCursor(cursorParam);
    if (!cursor) return badRequest("cursor is not valid");
    where.push("(a.published_at < ? OR (a.published_at = ? AND a.id < ?))");
    binds.push(cursor.publishedAt, cursor.publishedAt, cursor.id);
  }

  // One extra row tells whether there is a next page.
  const pageQuery = env.DB.prepare(
    `SELECT ${ARTICLE_COLUMNS} ${FROM_ARTICLES}
     WHERE ${where.join(" AND ")}
     ORDER BY a.published_at DESC, a.id DESC
     LIMIT ?`,
  ).bind(...binds, limit + 1);

  const firstPage = cursorParam === null && sinceParam === null;
  const [page, top] = firstPage
    ? await env.DB.batch<ArticleRow>([pageQuery, env.DB.prepare(TOP_QUERY)])
    : [await pageQuery.all<ArticleRow>(), null];

  const rows = page.results.slice(0, limit);
  const last = rows.at(-1);
  const nextCursor =
    page.results.length > limit && last ? encodeCursor({ publishedAt: last.published_at, id: last.id }) : null;

  return json({
    items: rows.map(toArticle),
    nextCursor,
    top: top ? top.results.map(toArticle) : [],
  });
}

/** `GET /articles/:id`: one article shown in the feed, or 404. */
async function getArticle(id: string, env: Env): Promise<Response> {
  const row = await env.DB.prepare(`SELECT ${ARTICLE_COLUMNS} ${FROM_ARTICLES} WHERE a.id = ? AND a.is_news = 1`)
    .bind(id)
    .first<ArticleRow>();
  return row ? json(toArticle(row)) : json({ error: "Not found" }, 404);
}

// Translated feeds (#46). With `?lang=uk` (any of LANGS) the API shows only
// articles with a finished translation into that language, in the order the
// translations were stored (`lang_seq`), never an English one mixed in.
// `lang=en`, or no `lang`, is the English feed above, unchanged.

/** A row of `article_translations` joined with its article and source. */
interface TranslatedRow extends ArticleRow {
  t_headline: string;
  t_short_summary: string;
  t_summary: string;
  lang_seq: number;
  translated_at: string;
}

const TRANSLATED_COLUMNS = `${ARTICLE_COLUMNS},
  t.headline AS t_headline, t.short_summary AS t_short_summary, t.summary AS t_summary, t.lang_seq, t.translated_at`;

const FROM_TRANSLATIONS = `FROM article_translations t
  JOIN articles a ON a.id = t.article_id
  JOIN sources s ON s.id = a.source_id`;

/**
 * A finished translation (into the language bound to `?`) of an article shown
 * in the feed, and not one of an older English whose new English used up its
 * tries (SHOWN: not `failed`).
 */
const TRANSLATED = `t.lang = ? AND t.lang_seq IS NOT NULL AND a.is_news = 1 AND ${SHOWN}`;

/**
 * A language feed page: what TRANSLATED shows, last 7 days, two binds of the language.
 * The page walks the index on (lang, lang_seq) newest first. The lower bound
 * stops the walk at the 7-day edge: translated_at >= published_at, and
 * translated_at rises with lang_seq (both are set in one statement), so the
 * first translation of the last 7 days (an hour more for clock differences)
 * bounds it, found through the index on (lang, translated_at). Even the last
 * page reads only about what it shows. The unary + keeps SQLite from switching
 * to the (is_news, published_at) index, which reads the whole window and sorts
 * (it did, without the lower bound, once the tables had statistics), as the
 * English feed does in #38.
 */
export const LANG_PAGE_CONDITIONS = [
  "t.lang = ?",
  "t.lang_seq IS NOT NULL",
  "+a.is_news = 1",
  SHOWN,
  "+a.published_at >= strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-7 days')",
  `t.lang_seq >= COALESCE((SELECT b.lang_seq FROM article_translations b
                           WHERE b.lang = ? AND b.lang_seq IS NOT NULL
                             AND b.translated_at >= strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-7 days', '-1 hour')
                           ORDER BY b.translated_at, b.lang_seq LIMIT 1), ${Number.MAX_SAFE_INTEGER})`,
];

const TRANSLATED_TOP_QUERY = topQuery(TRANSLATED_COLUMNS, FROM_TRANSLATIONS, TRANSLATED);

/** `lang`: null for English (absent or `en`), undefined when it is not a language we serve. */
function readLang(params: URLSearchParams): Lang | null | undefined {
  const value = params.get("lang");
  if (value === null || value === "en") return null;
  return isLang(value) ? value : undefined;
}

const LANG_ERROR = `lang must be one of: en, ${LANGS.join(", ")}`;

/**
 * The article in `lang`: its translated headline, short summary and summary,
 * and the language. `feedSeq` and `addedAt` are its place in that language's
 * feed (`lang_seq`) and when it appeared there (`translated_at`): the fields the
 * English feed has from #38, so the app reads every feed the same way (#51).
 */
function toTranslatedArticle(row: TranslatedRow, lang: Lang) {
  return {
    ...toArticle(row),
    headline: row.t_headline,
    shortSummary: row.t_short_summary,
    summary: row.t_summary,
    lang,
    feedSeq: row.lang_seq,
    addedAt: row.translated_at,
  };
}

/** A language feed's cursor: the language and the last `lang_seq` of the page, opaque to the app. */
function encodeLangCursor(lang: Lang, langSeq: number): string {
  return btoa(JSON.stringify([lang, langSeq])).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

/** The `lang_seq` in a cursor of this language's feed, or null (an English cursor, another language's, or none of ours). */
function decodeLangCursor(value: string, lang: Lang): number | null {
  try {
    const parsed: unknown = JSON.parse(atob(value.replaceAll("-", "+").replaceAll("_", "/")));
    if (Array.isArray(parsed) && parsed.length === 2 && parsed[0] === lang && Number.isSafeInteger(parsed[1])) {
      return parsed[1] as number;
    }
  } catch {
    // Falls through to null: not a cursor we issued.
  }
  return null;
}

/**
 * `GET /articles?lang=uk&limit=&cursor=&after=&since=`: news of the last 7 days
 * translated into `lang`, the latest translated first (`lang_seq`), so one
 * translated late lands on top, never between ones already read. `cursor`
 * continues from the previous page; `after` keeps only articles translated
 * after a given `feedSeq` of this feed (the "N new" check); `since` keeps only articles
 * published after that time. `top` is filled on the first page only, from the
 * translated articles.
 */
async function listTranslated(params: URLSearchParams, lang: Lang, limit: number, env: Env): Promise<Response> {
  const where = [...LANG_PAGE_CONDITIONS];
  const binds: (string | number)[] = [lang, lang];

  const afterParam = params.get("after");
  if (afterParam !== null) {
    if (!/^\d+$/.test(afterParam) || !Number.isSafeInteger(Number(afterParam))) {
      return badRequest("after must be a feedSeq (a whole number)");
    }
    where.push("t.lang_seq > ?");
    binds.push(Number(afterParam));
  }

  const sinceParam = params.get("since");
  if (sinceParam !== null) {
    const since = new Date(sinceParam);
    if (Number.isNaN(since.getTime())) return badRequest("since must be an ISO 8601 time");
    where.push("a.published_at > ?");
    binds.push(toStoredTime(since));
  }

  const cursorParam = params.get("cursor");
  if (cursorParam !== null) {
    const langSeq = decodeLangCursor(cursorParam, lang);
    if (langSeq === null) return badRequest("cursor is not valid");
    where.push("t.lang_seq < ?");
    binds.push(langSeq);
  }

  // One extra row tells whether there is a next page.
  const pageQuery = env.DB.prepare(
    `SELECT ${TRANSLATED_COLUMNS} ${FROM_TRANSLATIONS}
     WHERE ${where.join(" AND ")}
     ORDER BY t.lang_seq DESC
     LIMIT ?`,
  ).bind(...binds, limit + 1);

  const firstPage = cursorParam === null && sinceParam === null && afterParam === null;
  const [page, top] = firstPage
    ? await env.DB.batch<TranslatedRow>([pageQuery, env.DB.prepare(TRANSLATED_TOP_QUERY).bind(lang)])
    : [await pageQuery.all<TranslatedRow>(), null];

  const rows = page.results.slice(0, limit);
  const last = rows.at(-1);
  const nextCursor = page.results.length > limit && last ? encodeLangCursor(lang, last.lang_seq) : null;

  return json({
    items: rows.map((row) => toTranslatedArticle(row, lang)),
    nextCursor,
    top: top ? top.results.map((row) => toTranslatedArticle(row, lang)) : [],
  });
}

/** `GET /articles/:id?lang=uk`: one article shown in the feed, translated into `lang`, or 404 when it is not (yet). */
async function getTranslated(id: string, lang: Lang, env: Env): Promise<Response> {
  const row = await env.DB.prepare(`SELECT ${TRANSLATED_COLUMNS} ${FROM_TRANSLATIONS} WHERE t.article_id = ? AND ${TRANSLATED}`)
    .bind(id, lang)
    .first<TranslatedRow>();
  return row ? json(toTranslatedArticle(row, lang)) : json({ error: "Not found" }, 404);
}

async function route(request: Request, env: Env): Promise<Response> {
  if (request.method !== "GET") return json({ error: "Method not allowed" }, 405, { allow: "GET" });

  const url = new URL(request.url);
  if (url.pathname === "/articles") return listArticles(url, env);

  const match = url.pathname.match(/^\/articles\/([^/]+)$/);
  if (match) {
    let id: string;
    try {
      id = decodeURIComponent(match[1]);
    } catch {
      return json({ error: "Not found" }, 404);
    }
    const lang = readLang(url.searchParams);
    if (lang === undefined) return badRequest(LANG_ERROR);
    return lang === null ? getArticle(id, env) : getTranslated(id, lang, env);
  }

  if (url.pathname === "/health") {
    return json({ sources: await sourceHealth(env), lastFetcherRun: null });
  }

  // The translation queue per language (#46): read-only counts and times, no secrets.
  if (url.pathname === "/queue") {
    return json({ languages: await queueStatus(env) }, 200, { "cache-control": "no-store" });
  }

  return json({ error: "Not found" }, 404);
}

/** The API router. Every response, errors included, is JSON. */
export async function handleApi(request: Request, env: Env): Promise<Response> {
  try {
    return await route(request, env);
  } catch (error) {
    console.error(
      JSON.stringify({
        message: "API request failed",
        path: new URL(request.url).pathname,
        error: error instanceof Error ? error.message : String(error),
      }),
    );
    return json({ error: "Internal error" }, 500);
  }
}
