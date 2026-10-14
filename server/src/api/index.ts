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
  image_url: string | null;
  original_language: string | null;
  topics: string | null;
  tags: string | null;
  importance: number | null;
}

const SELECT_ARTICLE = `
  SELECT a.id, s.country, a.source_id, s.name AS source_name, s.url AS source_url,
         a.url, a.original_title, a.published_at, a.date_only, a.headline, a.short_summary,
         a.summary, a.image_url, a.original_language, a.topics, a.tags, a.importance
  FROM articles a JOIN sources s ON s.id = a.source_id`;

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
    originalTitle: row.original_title,
    originalLanguage: row.original_language,
    topics: row.topics ? JSON.parse(row.topics) : [],
    tags: row.tags ? JSON.parse(row.tags) : [],
    importance: row.importance,
    imageUrl: row.image_url,
    originalUrl: row.url,
  };
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });

/**
 * Item 1 completes this: the 7-day window, cursor paging, `since` and
 * `top`. Kickoff version: the newest 20 news articles,
 * so the app and backend can talk to each other from day one.
 */
export async function handleApi(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  if (request.method !== "GET") return json({ error: "Method not allowed" }, 405);

  if (url.pathname === "/articles") {
    const { results } = await env.DB.prepare(
      `${SELECT_ARTICLE} WHERE a.is_news = 1 ORDER BY a.published_at DESC LIMIT 20`,
    ).all<ArticleRow>();
    return json({ items: results.map(toArticle), nextCursor: null, top: [] });
  }

  const match = url.pathname.match(/^\/articles\/([^/]+)$/);
  if (match) {
    const row = await env.DB.prepare(`${SELECT_ARTICLE} WHERE a.id = ?`).bind(match[1]).first<ArticleRow>();
    return row ? json(toArticle(row)) : json({ error: "Not found" }, 404);
  }

  if (url.pathname === "/health") {
    return json({ sources: await sourceHealth(env), lastFetcherRun: null });
  }

  return json({ error: "Not found" }, 404);
}
