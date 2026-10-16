// Release together (#46, Yurii 15 Oct): the feed is the same in every
// language, the same posts in the same order with the same top stories; only
// the language differs. A summarized decision (is_news = 1) is not shown yet:
// it waits, queued for every enabled language, until each enabled language that
// is not paused has published its translation or failed it MAX_ATTEMPTS times.
// Then it is released: it gets its place in the feed (feed_seq, MAX + 1) and
// added_at, and appears in English and every language at once. A language feed
// shows a released article when that language's translation is published, at
// the article's feed_seq, so a language that catches up after a pause fills in
// at the English positions.
//
// The release waits for the translations only while the translator runs (Roman,
// #49 review): the translator writes its time to step_runs at the start of every
// run, and both the translator and the summarizer release. When the translator
// has not run for TRANSLATOR_ALIVE_MINUTES (its new cron trigger can take about
// an hour to start, #50, or it stopped), the summarizer's run releases each
// decision at once, and the languages fill in later at the English places.
import type { Env } from "../env";
import { toStoredTime } from "../fetcher/text";
import { LANGS } from "./languages";

/** Only articles the feed can show get translated and released: the last 7 days (docs/contract.md). */
export const FEED_DAYS = 7;
export const DAY_MS = 24 * 3_600_000;

/** The release waits for translations only while the translator ran this recently (it runs every 2 minutes). */
export const TRANSLATOR_ALIVE_MINUTES = 10;

/** When the translator last ran (step_runs, one row). */
export const TRANSLATOR_RAN_AT = "SELECT at FROM step_runs WHERE step = 'translator'";

/**
 * Whether the translator ran in the last TRANSLATOR_ALIVE_MINUTES, the same
 * rule RELEASE uses (its ?4). The summarizer's run sends the push
 * notifications only while this is false (../index.ts): one row read.
 */
export async function translatorRunning(env: Env, now: Date): Promise<boolean> {
  const at = await env.DB.prepare(TRANSLATOR_RAN_AT).first<string>("at");
  return !!at && at >= toStoredTime(new Date(now.getTime() - TRANSLATOR_ALIVE_MINUTES * 60_000));
}

/** Records that the translator runs now, for the release (?1 now). */
export const TRANSLATOR_RAN = `INSERT INTO step_runs (step, at) VALUES ('translator', ?1)
  ON CONFLICT (step) DO UPDATE SET at = excluded.at`;

/**
 * Releases the oldest summarized article that is ready, one per statement, as
 * MAX + 1 is read once per statement (a unique index refuses a number given
 * twice). Ready: every enabled, not paused language of LANGS (?3) has a row for
 * its current English that is `published` or `failed`. Also ready at once, as
 * nothing would ever be translated for them: an article published before the
 * feed's 7 days (?2), shown nowhere but numbered so it leaves the waiting list,
 * and one without an English summary (a row made visible by hand). With no
 * enabled language, or no translator run since ?4 (TRANSLATOR_ALIVE_MINUTES
 * ago), every article is ready at once. The candidates are the
 * articles waiting for release, oldest English first, through the partial
 * index articles_unreleased: a few rows, also when nothing is ready.
 * Binds: ?1 now (added_at), ?2 the feed's start, ?3 LANGS as JSON, ?4 the
 * oldest translator run that counts as running.
 */
export const RELEASE = `UPDATE articles
  SET feed_seq = (SELECT COALESCE(MAX(m.feed_seq), 0) + 1 FROM articles m WHERE m.feed_seq IS NOT NULL),
      added_at = ?1
  WHERE id = (
    SELECT u.id FROM articles u INDEXED BY articles_unreleased
    WHERE u.is_news = 1 AND u.feed_seq IS NULL
      AND (u.published_at < ?2
           OR NOT EXISTS (SELECT 1 FROM step_runs r WHERE r.step = 'translator' AND r.at >= ?4)
           OR u.summarized_at IS NULL OR u.headline IS NULL OR u.short_summary IS NULL OR u.summary IS NULL
           OR NOT EXISTS (
             SELECT 1 FROM translation_langs l
             WHERE l.enabled = 1 AND l.paused = 0 AND l.lang IN (SELECT value FROM json_each(?3))
               AND NOT EXISTS (SELECT 1 FROM article_translations t
                               WHERE t.article_id = u.id AND t.lang = l.lang AND t.attempts_source IS u.summarized_at
                                 AND t.state IN ('published', 'failed'))))
    ORDER BY u.summarized_at, u.id
    LIMIT 1)
  RETURNING id, feed_seq`;

/** RELEASE statements per D1 batch; another batch follows while each one released an article. */
export const RELEASES_PER_BATCH = 5;
/** At most this many batches a run (1 + 9 × 5 = 46 articles), so a run stays short; the next run goes on. */
const MAX_RELEASE_BATCHES = 10;

/**
 * Releases every ready article, oldest summarized first. Returns their ids in
 * the order released. Called at the end of each translator and summarizer run.
 */
export async function releaseReady(env: Env, now: Date): Promise<string[]> {
  const released: string[] = [];
  const ago = (ms: number) => toStoredTime(new Date(now.getTime() - ms));
  const statement = env.DB.prepare(RELEASE).bind(
    toStoredTime(now),
    ago(FEED_DAYS * DAY_MS),
    JSON.stringify(LANGS),
    ago(TRANSLATOR_ALIVE_MINUTES * 60_000),
  );
  // One statement first: a run usually releases nothing or one article. Then batches while each statement releases one.
  for (let i = 0, size = 1; i < MAX_RELEASE_BATCHES; i++, size = RELEASES_PER_BATCH) {
    const results = await env.DB.batch<{ id: string; feed_seq: number }>(Array.from({ length: size }, () => statement));
    const ids = results.flatMap((r) => r.results.map((row) => row.id));
    released.push(...ids);
    if (ids.length < size) break;
  }
  return released;
}

/** What GET /queue shows about the release: how many summarized decisions wait, and since when. */
export interface ReleaseStatus {
  waiting: number;
  /** Minutes since the oldest waiting article was summarized, or null when none waits. */
  oldestWaitingAgeMinutes: number | null;
  /** When the translator last ran, or null before its first run; the release waits for translations only while this is recent. */
  translatorRanAt: string | null;
}

/** Reads the articles waiting for release through their partial index (normally a handful). */
export async function releaseStatus(env: Env, now = new Date()): Promise<ReleaseStatus> {
  const row = await env.DB.prepare(
    `SELECT COUNT(*) AS n, MIN(summarized_at) AS oldest,
            (SELECT at FROM step_runs WHERE step = 'translator') AS translator_ran_at
     FROM articles INDEXED BY articles_unreleased
     WHERE is_news = 1 AND feed_seq IS NULL`,
  ).first<{ n: number; oldest: string | null; translator_ran_at: string | null }>();
  const oldest = row?.oldest ?? null;
  return {
    waiting: Number(row?.n ?? 0),
    oldestWaitingAgeMinutes: oldest ? Math.max(0, Math.floor((now.getTime() - Date.parse(oldest)) / 60_000)) : null,
    translatorRanAt: row?.translator_ran_at ?? null,
  };
}
