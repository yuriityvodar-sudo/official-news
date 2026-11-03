import type { Env } from "../env";
import { LIMITS } from "../fetcher";
import { type OutletHeadline, parseHeadlines } from "../fetcher/types";

/** Headlines a reply gives at most (GET /headlines). */
export const HEADLINES_PER_REPLY = 200;

/**
 * GET /headlines?country=XX (#230, the aggregator): the newest headlines of
 * XX's news outlets (`WW` the world's, `EU` the Union's) from the last day
 * (LIMITS.headlineHours, as they are kept), newest first, each with its outlet
 * and its link: their headlines and links only, never their text. Reads one
 * row per outlet of the country.
 */
export async function countryHeadlines(env: Env, country: string, now = new Date()): Promise<OutletHeadline[]> {
  const { results } = await env.DB.prepare("SELECT id, name, site, headlines FROM outlets WHERE country = ? AND status != 'blocked'")
    .bind(country)
    .all<{ id: string; name: string; site: string; headlines: string }>();
  const cutoff = `${new Date(now.getTime() - LIMITS.headlineHours * 3_600_000).toISOString().slice(0, 19)}Z`;
  return results
    .flatMap((o) =>
      parseHeadlines(o.headlines)
        .filter((h) => h.publishedAt >= cutoff)
        .map((h) => ({ title: h.title, url: h.url, publishedAt: h.publishedAt, outlet: { id: o.id, name: o.name, site: o.site } })),
    )
    .sort((a, b) => b.publishedAt.localeCompare(a.publishedAt) || a.outlet.id.localeCompare(b.outlet.id))
    .slice(0, HEADLINES_PER_REPLY);
}
