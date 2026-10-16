import type { Env } from "../env";
import { health } from "../health";
import { LANGS, type Lang, SHOWN, isLang, queueStatus, releaseStatus } from "../translator";

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
  feed_seq: number | null;
  added_at: string | null;
  impact: string | null;
}

/**
 * The source's name (#76): in English, `name`; in a language of LANGS, its
 * `config.names.<lang>` (loaded from docs/source-names.csv), else the English
 * name. `lang` is one of LANGS, never text from the request, so it can sit in
 * the SQL. A config that is not JSON gives the English name instead of failing
 * the whole feed.
 */
const sourceName = (lang: Lang | null) =>
  lang ? `COALESCE(CASE WHEN json_valid(s.config) THEN json_extract(s.config, '$.names.${lang}') END, s.name)` : "s.name";

const articleColumns = (lang: Lang | null) => `
  a.id, s.country, a.source_id, ${sourceName(lang)} AS source_name, s.url AS source_url,
  a.url, a.original_title, a.published_at, a.date_only, a.headline, a.short_summary,
  a.summary, a.decision_type, a.image_url, a.original_language, a.topics, a.tags, a.importance,
  a.feed_seq, a.added_at, a.impact`;

const ARTICLE_COLUMNS = articleColumns(null);

const FROM_ARTICLES = "FROM articles a JOIN sources s ON s.id = a.source_id";

/**
 * A feed page: official decisions from the last 7 days (docs/contract.md), in feed order.
 * The page walks articles_feed_seq newest first: the unary + keeps SQLite from using the
 * (is_news, published_at) index instead, which would read the whole window and sort. The
 * lower bound stops the walk at the 7-day edge (added_at >= published_at always, and
 * added_at rises with feed_seq), so even the last page reads only what it shows.
 */
export const PAGE_CONDITIONS = [
  "+a.is_news = 1",
  "a.feed_seq IS NOT NULL",
  "+a.published_at >= strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-7 days')",
  `a.feed_seq >= COALESCE((SELECT b.feed_seq FROM articles b
                           WHERE b.feed_seq IS NOT NULL
                             AND b.added_at >= strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-7 days')
                           ORDER BY b.added_at, b.feed_seq LIMIT 1), 0)`,
];

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;

/**
 * Top today: last 24 hours, highest importance, at most 2 per country, up to 5,
 * among the articles `where` picks (the feed's, or a language's: #46). Picked by
 * importance, shown newest first (feed order), so times only go down here too.
 */
const topQuery = (columns: string, from: string, where: string) => `
  SELECT * FROM (
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
  LIMIT 5
  ) ORDER BY feed_seq DESC`;

const TOP_WHERE = "a.is_news = 1 AND a.feed_seq IS NOT NULL";
const TOP_QUERY = topQuery(ARTICLE_COLUMNS, FROM_ARTICLES, TOP_WHERE);

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

/** The stored impact JSON (#63), or null when there is none or it cannot be read. */
function parseImpact(value: string | null): unknown {
  if (!value) return null;
  try {
    const parsed: unknown = JSON.parse(value);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : null;
  } catch {
    return null;
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
    feedSeq: row.feed_seq,
    addedAt: row.added_at,
    impact: parseImpact(row.impact),
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

/**
 * The position after the last article of a page: opaque to the app. Today it
 * is that article's `feed_seq`; cursors from app builds before the change name
 * an article instead, and still work.
 */
type Cursor = { feedSeq: number } | { articleId: string; publishedAt: string };

function encodeCursor(feedSeq: number): string {
  return btoa(JSON.stringify([feedSeq])).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function decodeCursor(value: string): Cursor | null {
  try {
    const parsed: unknown = JSON.parse(atob(value.replaceAll("-", "+").replaceAll("_", "/")));
    if (Array.isArray(parsed) && parsed.length === 1 && Number.isInteger(parsed[0])) {
      return { feedSeq: parsed[0] as number };
    }
    // Before the feed was ordered by feed_seq: [publishedAt, id].
    if (Array.isArray(parsed) && parsed.length === 2 && typeof parsed[0] === "string" && typeof parsed[1] === "string") {
      return { articleId: parsed[1], publishedAt: parsed[0] };
    }
  } catch {
    // Falls through to null: not a cursor we issued.
  }
  return null;
}

/** A whole number of at least 0, or null. */
function nonNegativeInteger(value: string): number | null {
  const n = Number(value);
  return /^\d+$/.test(value) && Number.isSafeInteger(n) ? n : null;
}

/**
 * `GET /articles?limit=&cursor=&after=&since=&lang=`: official decisions of the
 * last 7 days in the order they appeared in the feed (`feed_seq`), newest
 * first, so one that appears late lands on top, never between ones already
 * read. `cursor` continues from the previous page; `after` keeps only articles
 * that appeared after a given `feedSeq` (the "N new" check); `since` is the
 * older check by publication time, kept for app builds before `after`. `top`
 * is filled on the first page only.
 *
 * With `lang` other than `en` (#46), the same feed in that language: the same
 * order, the same cursors and `after`, the same top stories, keeping only the
 * articles whose translation into it is shown (release together: every article
 * appears in all languages at once, except where a translation failed or the
 * language is paused). `translationsDelayed` says the language is paused or
 * off, so its newest articles may be missing for a while.
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

  const where = [...PAGE_CONDITIONS, ...(lang ? TRANSLATED_CONDITIONS : [])];
  // The language is bound in the join (FROM_TRANSLATED).
  const binds: (string | number)[] = lang ? [lang] : [];

  const afterParam = params.get("after");
  if (afterParam !== null) {
    const after = nonNegativeInteger(afterParam);
    if (after === null) return badRequest("after must be a feedSeq (a whole number)");
    where.push("a.feed_seq > ?");
    binds.push(after);
  }

  const sinceParam = params.get("since");
  if (sinceParam !== null) {
    const since = new Date(sinceParam);
    if (Number.isNaN(since.getTime())) return badRequest("since must be an ISO 8601 time");
    // Builds before #39 send the publication time of the first article they show. In
    // the feed's order that article is the newest to appear, so "new" means a higher
    // feed_seq than that article's: found as the newest published at or before `since`.
    // (Not the highest feed_seq published by then: a late article that arrived after
    // the app loaded would hide everything that came before it.)
    where.push(
      `a.feed_seq > COALESCE((SELECT b.feed_seq FROM articles b
                              WHERE b.is_news = 1 AND b.feed_seq IS NOT NULL AND b.published_at <= ?
                              ORDER BY b.published_at DESC, b.feed_seq ASC LIMIT 1), 0)`,
    );
    binds.push(toStoredTime(since));
  }

  const cursorParam = params.get("cursor");
  if (cursorParam !== null) {
    const cursor = decodeCursor(cursorParam);
    if (!cursor) return badRequest("cursor is not valid");
    if ("feedSeq" in cursor) {
      where.push("a.feed_seq < ?");
      binds.push(cursor.feedSeq);
    } else {
      // An older cursor: continue below the article it names. If that article is gone
      // or has no number, continue below what was published by the cursor's time, so the
      // page is never empty by mistake (an empty page reads as "all caught up").
      where.push(
        `a.feed_seq < COALESCE(
           (SELECT b.feed_seq FROM articles b WHERE b.id = ?),
           (SELECT MAX(b.feed_seq) + 1 FROM articles b
            WHERE b.is_news = 1 AND b.published_at <= ? AND b.feed_seq IS NOT NULL),
           0)`,
      );
      binds.push(cursor.articleId, cursor.publishedAt);
    }
  }

  // One extra row tells whether there is a next page.
  const pageQuery = env.DB.prepare(
    `SELECT ${lang ? translatedColumns(lang) : ARTICLE_COLUMNS} ${lang ? FROM_TRANSLATED : FROM_ARTICLES}
     WHERE ${where.join(" AND ")}
     ORDER BY a.feed_seq DESC
     LIMIT ?`,
  ).bind(...binds, limit + 1);

  const firstPage = cursorParam === null && sinceParam === null && afterParam === null;
  const topQuery = firstPage ? (lang ? env.DB.prepare(translatedTopQuery(lang)).bind(lang) : env.DB.prepare(TOP_QUERY)) : null;
  const switchQuery = lang ? env.DB.prepare(LANG_SWITCH).bind(lang) : null;
  const [page, ...more] = await env.DB.batch<TranslatedRow & { delayed?: number }>(
    [pageQuery, topQuery, switchQuery].filter((q): q is D1PreparedStatement => q !== null),
  );
  const top = topQuery ? more.shift() : undefined;
  const delayed = switchQuery ? more.shift() : undefined;

  const rows = page.results.slice(0, limit);
  const last = rows.at(-1);
  const nextCursor = page.results.length > limit && last?.feed_seq != null ? encodeCursor(last.feed_seq) : null;
  const shape = (row: TranslatedRow) => (lang ? toTranslatedArticle(row, lang) : toArticle(row));

  return json({
    items: rows.map(shape),
    nextCursor,
    top: top ? top.results.map(shape) : [],
    ...(lang ? { translationsDelayed: delayed?.results[0]?.delayed !== 0 } : {}),
  });
}

/** `GET /articles/:id`: one article shown in the feed (released), or 404. */
async function getArticle(id: string, env: Env): Promise<Response> {
  const row = await env.DB.prepare(`SELECT ${ARTICLE_COLUMNS} ${FROM_ARTICLES} WHERE a.id = ? AND a.is_news = 1 AND a.feed_seq IS NOT NULL`)
    .bind(id)
    .first<ArticleRow>();
  return row ? json(toArticle(row)) : json({ error: "Not found" }, 404);
}

// Translated feeds (#46). With `?lang=uk` (any of LANGS) the API shows the
// English feed's articles that have a shown translation into that language, in
// the English order (feed_seq), never an English one mixed in. `lang=en`, or no
// `lang`, is the English feed above, unchanged.

/** A row of `articles` joined with its source and, in a language feed, its translation. */
interface TranslatedRow extends ArticleRow {
  t_headline?: string;
  t_short_summary?: string;
  t_summary?: string;
}

/** The columns of a language feed: the article with its source named in `lang`, and the translation. */
const translatedColumns = (lang: Lang) => `${articleColumns(lang)},
  t.headline AS t_headline, t.short_summary AS t_short_summary, t.summary AS t_summary`;

/**
 * The feed's articles with their translation into the language bound here. CROSS
 * JOIN keeps articles the outer loop, so a page walks articles_feed_seq newest
 * first as the English feed does and finds each translation by its primary key.
 */
export const FROM_TRANSLATED = `${FROM_ARTICLES} CROSS JOIN article_translations t ON t.article_id = a.id AND t.lang = ?`;

/**
 * A translation that is shown: it has a text (the CHECK constraint of
 * migration 0008 keeps the three fields together), and not one of an older English whose
 * new English used up its tries (SHOWN: not `failed`, unless its text is of the
 * English it failed for).
 */
export const TRANSLATED_CONDITIONS = ["t.headline IS NOT NULL", SHOWN];

/**
 * A language's top stories: the English top stories (same selection, same
 * order) that have a shown translation into it, so the language never gets a
 * top story the English feed does not have. Their sources are named in `lang`.
 */
const translatedTopQuery = (lang: Lang) => `
  SELECT top.*, t.headline AS t_headline, t.short_summary AS t_short_summary, t.summary AS t_summary
  FROM (${topQuery(articleColumns(lang), FROM_ARTICLES, TOP_WHERE)}) top
  JOIN article_translations t ON t.article_id = top.id AND t.lang = ?
  WHERE ${TRANSLATED_CONDITIONS.join(" AND ")}
  ORDER BY top.feed_seq DESC`;

/** 0 while the language is translated as it should be; 1 while it is paused (by hand or automatically) or off. */
const LANG_SWITCH = "SELECT CASE WHEN enabled = 1 AND paused = 0 THEN 0 ELSE 1 END AS delayed FROM translation_langs WHERE lang = ?";

/** `lang`: null for English (absent or `en`), undefined when it is not a language we serve. */
function readLang(params: URLSearchParams): Lang | null | undefined {
  const value = params.get("lang");
  if (value === null || value === "en") return null;
  return isLang(value) ? value : undefined;
}

const LANG_ERROR = `lang must be one of: en, ${LANGS.join(", ")}`;

/**
 * The article in `lang`: its translated headline, short summary and summary,
 * and the language. `feedSeq` and `addedAt` are the English ones: every
 * language has the same feed.
 */
function toTranslatedArticle(row: TranslatedRow, lang: Lang) {
  return {
    ...toArticle(row),
    headline: row.t_headline ?? null,
    shortSummary: row.t_short_summary ?? null,
    summary: row.t_summary ?? null,
    // Not translated yet: English is never mixed into a language feed (#46).
    impact: null,
    lang,
  };
}

/** `GET /articles/:id?lang=uk`: one article shown in the feed, translated into `lang`, or 404 when it is not (yet). */
async function getTranslated(id: string, lang: Lang, env: Env): Promise<Response> {
  const row = await env.DB.prepare(
    `SELECT ${translatedColumns(lang)} ${FROM_TRANSLATED}
     WHERE a.id = ? AND a.is_news = 1 AND a.feed_seq IS NOT NULL AND ${TRANSLATED_CONDITIONS.join(" AND ")}`,
  )
    .bind(lang, id)
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
    return json(await health(env));
  }

  // The translation queue per language and the articles waiting for release (#46): read-only counts and times, no secrets.
  if (url.pathname === "/queue") {
    const [languages, release] = await Promise.all([queueStatus(env), releaseStatus(env)]);
    return json({ languages, release }, 200, { "cache-control": "no-store" });
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
