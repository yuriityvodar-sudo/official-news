import type { Env } from "../env";
import { MAX_ATTEMPTS } from "../summarizer";

/** Non-seed sources: the Kickoff seed rows are never fetched (docs/contract.md). */
const REAL_SOURCE = "(config IS NULL OR json_extract(config, '$.seed') IS NOT 1)";

export interface Health {
  /** Real sources per status (active, stale, moved, broken, blocked). */
  sources: Record<string, number>;
  /** The latest time the fetcher checked a source, or null before its first run. */
  lastFetcherRun: string | null;
  articles: {
    /** Fetched in the last 24 hours. */
    fetchedLast24h: number;
    /** Fetched but not yet read by the AI (articles it gave up on after MAX_ATTEMPTS tries not counted). */
    waitingForSummary: number;
    /** Hidden for good: MAX_ATTEMPTS unusable answers (#99). */
    gaveUpOnSummary: number;
    /** Shown in the feed now (official decisions of the last 7 days). */
    inFeed: number;
  };
}

/** `GET /health`: whether the fetcher and the AI step are running, readable in a browser. */
export async function health(env: Env): Promise<Health> {
  const [statuses, lastRun, articles] = await env.DB.batch<Record<string, unknown>>([
    env.DB.prepare(`SELECT status, COUNT(*) AS n FROM sources WHERE ${REAL_SOURCE} GROUP BY status`),
    env.DB.prepare(`SELECT MAX(last_checked_at) AS at FROM sources WHERE ${REAL_SOURCE}`),
    env.DB.prepare(
      `SELECT
         SUM(fetched_at >= strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-24 hours')) AS fetched,
         SUM(summarized_at IS NULL AND summary_attempts < ?1) AS waiting,
         SUM(summarized_at IS NULL AND summary_attempts >= ?1) AS gave_up,
         SUM(is_news = 1 AND feed_seq IS NOT NULL AND published_at >= strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-7 days')) AS in_feed
       FROM articles`,
    ).bind(MAX_ATTEMPTS),
  ]);
  const totals = articles.results[0] ?? {};
  return {
    sources: Object.fromEntries(statuses.results.map((r) => [String(r.status), Number(r.n)])),
    lastFetcherRun: (lastRun.results[0]?.at as string | null | undefined) ?? null,
    articles: {
      fetchedLast24h: Number(totals.fetched ?? 0),
      waitingForSummary: Number(totals.waiting ?? 0),
      gaveUpOnSummary: Number(totals.gave_up ?? 0),
      inFeed: Number(totals.in_feed ?? 0),
    },
  };
}
