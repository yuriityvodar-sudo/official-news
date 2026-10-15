import type { Env } from "../env";
import { sourceHealth } from "../health";
import { LANGS, type Lang, isLang } from "../translator";

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

/** `lang`: English, or a language the translator writes (#46). */
type Language = "en" | Lang;

/** The translated fields a query adds when `lang` asks for a translation. */
interface TranslationColumns {
  t_headline?: string | null;
  t_short_summary?: string | null;
  t_summary?: string | null;
}

/**
 * The columns and join that read an article's finished translation into `lang`,
 * and the value to bind first. Nothing for English or no `lang`, so those
 * queries stay as they were.
 */
function translationJoin(lang: Language | null): { columns: string; join: string; binds: string[] } {
  if (lang === null || lang === "en") return { columns: "", join: "", binds: [] };
  return {
    columns: ", t.headline AS t_headline, t.short_summary AS t_short_summary, t.summary AS t_summary",
    join: "LEFT JOIN article_translations t ON t.article_id = a.id AND t.lang = ? AND t.translated_at IS NOT NULL",
    binds: [lang],
  };
}

/** Top today: last 24 hours, highest importance, at most 2 per country, up to 5. */
const topQuery = (tr: ReturnType<typeof translationJoin>) => `
  SELECT * FROM (
    SELECT ${ARTICLE_COLUMNS}${tr.columns},
           ROW_NUMBER() OVER (
             PARTITION BY s.country ORDER BY a.importance DESC, a.published_at DESC, a.id DESC
           ) AS country_rank
    ${FROM_ARTICLES} ${tr.join}
    WHERE a.is_news = 1 AND a.importance IS NOT NULL
      AND a.published_at >= strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-24 hours')
  )
  WHERE country_rank <= 2
  ORDER BY importance DESC, published_at DESC, id DESC
  LIMIT 5`;

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

/**
 * The article for a request with `lang` (#46): the translated headline, short
 * summary and summary where a translation exists, with `lang` saying which
 * language they are in; English with `lang: "en"` otherwise. Without `lang`,
 * the article exactly as before.
 */
function toArticleIn(lang: Language | null) {
  return (row: ArticleRow & TranslationColumns) => {
    const article = toArticle(row);
    if (lang === null) return article;
    if (row.t_headline && row.t_short_summary && row.t_summary) {
      return { ...article, headline: row.t_headline, shortSummary: row.t_short_summary, summary: row.t_summary, lang };
    }
    return { ...article, lang: "en" };
  };
}

/** Reads `lang`: null when absent, undefined when it is not a language we serve. */
function readLang(params: URLSearchParams): Language | null | undefined {
  const value = params.get("lang");
  if (value === null) return null;
  return value === "en" || isLang(value) ? value : undefined;
}

const LANG_ERROR = `lang must be one of: en, ${LANGS.join(", ")}`;

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
 * `GET /articles?limit=&cursor=&since=&lang=`: news from the last 7 days, newest
 * first. `cursor` continues from the previous page; `since` keeps only
 * articles published after that time. `top` is filled on the first page only.
 * `lang` returns translations where there are some (#46); see toArticleIn.
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
  const tr = translationJoin(lang);

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
    `SELECT ${ARTICLE_COLUMNS}${tr.columns} ${FROM_ARTICLES} ${tr.join}
     WHERE ${where.join(" AND ")}
     ORDER BY a.published_at DESC, a.id DESC
     LIMIT ?`,
  ).bind(...tr.binds, ...binds, limit + 1);

  const firstPage = cursorParam === null && sinceParam === null;
  const [page, top] = firstPage
    ? await env.DB.batch<ArticleRow & TranslationColumns>([pageQuery, env.DB.prepare(topQuery(tr)).bind(...tr.binds)])
    : [await pageQuery.all<ArticleRow & TranslationColumns>(), null];

  const rows = page.results.slice(0, limit);
  const last = rows.at(-1);
  const nextCursor =
    page.results.length > limit && last ? encodeCursor({ publishedAt: last.published_at, id: last.id }) : null;

  const toResult = toArticleIn(lang);
  return json({
    items: rows.map(toResult),
    nextCursor,
    top: top ? top.results.map(toResult) : [],
  });
}

/** `GET /articles/:id?lang=`: one article shown in the feed, or 404. */
async function getArticle(id: string, params: URLSearchParams, env: Env): Promise<Response> {
  const lang = readLang(params);
  if (lang === undefined) return badRequest(LANG_ERROR);
  const tr = translationJoin(lang);
  const row = await env.DB.prepare(
    `SELECT ${ARTICLE_COLUMNS}${tr.columns} ${FROM_ARTICLES} ${tr.join} WHERE a.id = ? AND a.is_news = 1`,
  )
    .bind(...tr.binds, id)
    .first<ArticleRow & TranslationColumns>();
  return row ? json(toArticleIn(lang)(row)) : json({ error: "Not found" }, 404);
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
    return getArticle(id, url.searchParams, env);
  }

  if (url.pathname === "/health") {
    return json({ sources: await sourceHealth(env), lastFetcherRun: null });
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
