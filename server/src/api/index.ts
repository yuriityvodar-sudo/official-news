import type { Env } from "../env";
import { sourceHealth } from "../health";

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
}

const ARTICLE_COLUMNS = `
  a.id, s.country, a.source_id, s.name AS source_name, s.url AS source_url,
  a.url, a.original_title, a.published_at, a.date_only, a.headline, a.short_summary,
  a.summary, a.decision_type, a.image_url, a.original_language, a.topics, a.tags, a.importance,
  a.feed_seq, a.added_at`;

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

/** Top today: last 24 hours, highest importance, at most 2 per country, up to 5. */
const TOP_QUERY = `
  SELECT * FROM (
    SELECT ${ARTICLE_COLUMNS},
           ROW_NUMBER() OVER (
             PARTITION BY s.country ORDER BY a.importance DESC, a.published_at DESC, a.id DESC
           ) AS country_rank
    ${FROM_ARTICLES}
    WHERE a.is_news = 1 AND a.feed_seq IS NOT NULL AND a.importance IS NOT NULL
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
    feedSeq: row.feed_seq,
    addedAt: row.added_at,
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
 * `GET /articles?limit=&cursor=&after=&since=`: official decisions of the last
 * 7 days in the order they appeared in the feed (`feed_seq`), newest first, so
 * one that appears late lands on top, never between ones already read.
 * `cursor` continues from the previous page; `after` keeps only articles that
 * appeared after a given `feedSeq` (the "N new" check); `since` is the older
 * check by publication time, kept for app builds before `after`. `top` is
 * filled on the first page only.
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

  const where = [...PAGE_CONDITIONS];
  const binds: (string | number)[] = [];

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
    `SELECT ${ARTICLE_COLUMNS} ${FROM_ARTICLES}
     WHERE ${where.join(" AND ")}
     ORDER BY a.feed_seq DESC
     LIMIT ?`,
  ).bind(...binds, limit + 1);

  const firstPage = cursorParam === null && sinceParam === null && afterParam === null;
  const [page, top] = firstPage
    ? await env.DB.batch<ArticleRow>([pageQuery, env.DB.prepare(TOP_QUERY)])
    : [await pageQuery.all<ArticleRow>(), null];

  const rows = page.results.slice(0, limit);
  const last = rows.at(-1);
  const nextCursor = page.results.length > limit && last?.feed_seq != null ? encodeCursor(last.feed_seq) : null;

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
    return getArticle(id, env);
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
