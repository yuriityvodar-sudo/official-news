// The website's sitemap of one month (#88). Article pages never expire, but the
// sitemap listed only the feed's 7 days: on 30 Oct about 970 of the site's
// 3,250 pages. Now /sitemap.xml is an index of the latest file (the 7 days) and
// one file per month of every article released that month, in each language it
// is shown in. The site runs no SQL of its own (scripts/site.check.mjs), so the
// month's query lives here. Two statements in one batch: the month's released
// articles, and their shown translations (TRANSLATED_CONDITIONS, as
// GET /articles/:id?lang= answers them), both through the (added_at) range.
import { TRANSLATED_CONDITIONS } from ".";
import type { Env } from "../env";

/** What a sitemap entry needs of an article in one language: its address (articlePath) and when it came. */
export interface SitemapArticle {
  id: string;
  country: string;
  headline: string | null;
  originalTitle: string;
  addedAt: string | null;
  publishedAt: string;
}

/** `YYYY-MM` → the month's first instant and the next month's, as stored times. */
export function monthRange(month: string): [string, string] {
  const [y, m] = month.split("-").map(Number);
  const next = m === 12 ? `${y + 1}-01` : `${y}-${String(m + 1).padStart(2, "0")}`;
  return [`${month}-01T00:00:00Z`, `${next}-01T00:00:00Z`];
}

/**
 * Every article released in `month` (by added_at), in English and in each
 * language with a shown translation: `{ en: [...], uk: [...], ... }`, oldest
 * first. About 1,300 articles and 4,000 translations a month today.
 */
export async function monthArticles(env: Env, month: string): Promise<Record<string, SitemapArticle[]>> {
  const [from, to] = monthRange(month);
  const [articles, translations] = await env.DB.batch<{
    id: string;
    country: string;
    headline: string | null;
    original_title: string;
    added_at: string | null;
    published_at: string;
    lang?: string;
  }>([
    env.DB.prepare(
      `SELECT a.id, s.country, a.headline, a.original_title, a.added_at, a.published_at
       FROM articles a JOIN sources s ON s.id = a.source_id
       WHERE a.added_at >= ?1 AND a.added_at < ?2 AND a.is_news = 1 AND a.feed_seq IS NOT NULL
       ORDER BY a.added_at`,
    ).bind(from, to),
    env.DB.prepare(
      `SELECT a.id, s.country, t.headline, a.original_title, a.added_at, a.published_at, t.lang
       FROM articles a JOIN sources s ON s.id = a.source_id JOIN article_translations t ON t.article_id = a.id
       WHERE a.added_at >= ?1 AND a.added_at < ?2 AND a.is_news = 1 AND a.feed_seq IS NOT NULL
         AND ${TRANSLATED_CONDITIONS.join(" AND ")}
       ORDER BY a.added_at`,
    ).bind(from, to),
  ]);
  const out: Record<string, SitemapArticle[]> = { en: [] };
  const shape = (r: (typeof articles.results)[number]): SitemapArticle => ({
    id: r.id,
    country: r.country,
    headline: r.headline,
    originalTitle: r.original_title,
    addedAt: r.added_at,
    publishedAt: r.published_at,
  });
  for (const r of articles.results) out.en.push(shape(r));
  for (const r of translations.results) (out[r.lang!] ??= []).push(shape(r));
  return out;
}
