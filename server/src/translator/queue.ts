// The translation queue (#46): one row of `article_translations` per article
// and language, with an explicit state (migration 0008, docs/contract.md):
//
//   queued ─claim─▶ translating ─stored─▶ published ─English changes─▶ updating ─claim─▶ translating …
//                        │  ▲
//                        │  └─ due ─ retrying ◀─ unusable answer (attempt + 1), or no provider answered (no attempt)
//                        ├─ 3rd unusable answer ─▶ failed  (until the English changes)
//                        └─ claim older than 10 minutes ─▶ queued (or updating)
//   queued / updating / retrying ─article left the feed─▶ skipped
//
// The database logs every change of state with its time (`translation_events`)
// and keeps the counts per state (`translation_counts`), both by trigger.
import type { Env } from "../env";
import { toStoredTime } from "../fetcher/text";
import { LANGS, type Lang } from "./languages";

export const STATES = ["queued", "updating", "translating", "retrying", "published", "failed", "skipped"] as const;
export type State = (typeof STATES)[number];

/** Unusable answers for one article, language and English; the next one makes it `failed`. */
export const MAX_ATTEMPTS = 3;

/** A claim older than this is from a run that was cut off: it goes back to `queued`. */
export const CLAIM_MINUTES = 10;

/** The wait after the first unusable answer; it doubles with each one (10, then 20 minutes). */
export const RETRY_UNUSABLE_MINUTES = 10;

/**
 * The wait after the first try no provider answered (rate limit, quota,
 * outage); it doubles each time (2, 4, 8 … minutes), up to MAX_RETRY_MINUTES.
 * The translator runs every 2 minutes, so the first retry is the next run.
 */
export const RETRY_OUTAGE_MINUTES = 2;
export const MAX_RETRY_MINUTES = 60;

/** When a translation in `retrying` may be tried again, after `tries` earlier tries of the same kind. */
export function nextAttemptAt(now: Date, baseMinutes: number, tries: number): string {
  const minutes = Math.min(baseMinutes * 2 ** tries, MAX_RETRY_MINUTES);
  return toStoredTime(new Date(now.getTime() + minutes * 60_000));
}

/** The state log keeps this many days. */
export const EVENT_DAYS = 30;

/**
 * How far before the newest English already queued each run looks again. A
 * summary's `summarized_at` is set a moment before it is written, so one can be
 * written just after a run looked past that time.
 */
const ENQUEUE_OVERLAP = "-10 minutes";

/**
 * Puts news whose English is new or changed into the queue for one enabled
 * language (?1), as `queued`, or `updating` when it has a translation already
 * (shown until the new one is published), with fresh tries. Every news article
 * of the feed enters it once per language and English version
 * (`attempts_source`). It looks only at English written since the newest one
 * it queued for that language, through the index on `summarized_at`, so a run
 * with nothing new reads a few rows; a language with nothing queued yet (a new
 * one) queues the feed's 7 days. A paused language is still queued. Returns
 * the rows it queued (D1's `changes` also counts what the triggers write).
 * Binds: ?1 lang, ?2 now, ?3 English written from, ?4 the feed's start.
 */
export const ENQUEUE = `INSERT INTO article_translations (article_id, lang, attempts_source, queued_at, state, state_at)
  SELECT a.id, ?1, a.summarized_at, ?2, 'queued', ?2
  FROM articles a INDEXED BY articles_news_summarized
  WHERE a.is_news = 1
    AND EXISTS (SELECT 1 FROM translation_langs l WHERE l.lang = ?1 AND l.enabled = 1)
    AND a.summarized_at > MAX(?3, COALESCE((SELECT strftime('%Y-%m-%dT%H:%M:%SZ', w.attempts_source, '${ENQUEUE_OVERLAP}')
                                            FROM article_translations w INDEXED BY article_translations_source
                                            WHERE w.lang = ?1 AND w.attempts_source IS NOT NULL
                                            ORDER BY w.attempts_source DESC LIMIT 1), ''))
    AND a.published_at >= ?4
    AND a.headline IS NOT NULL AND a.short_summary IS NOT NULL AND a.summary IS NOT NULL
  ON CONFLICT (article_id, lang) DO UPDATE SET
    attempts_source = excluded.attempts_source, attempts = 0, outage_retries = 0,
    queued_at = excluded.queued_at, claimed_at = NULL, next_attempt_at = NULL, last_error = NULL,
    state = CASE WHEN lang_seq IS NULL THEN 'queued' ELSE 'updating' END, state_at = excluded.state_at
  WHERE attempts_source IS NOT excluded.attempts_source
  RETURNING article_id`;

/** Claims that ran out (?2: older than CLAIM_MINUTES) go back to `queued`, or `updating`. Binds: ?1 now, ?2 cutoff. */
export const RELEASE_STALE = `UPDATE article_translations INDEXED BY article_translations_claims
  SET state = CASE WHEN lang_seq IS NULL THEN 'queued' ELSE 'updating' END, state_at = ?1, claimed_at = NULL,
      last_error = 'claim ran out: the run that took it did not finish within ${CLAIM_MINUTES} minutes'
  WHERE state = 'translating' AND claimed_at < ?2
  RETURNING article_id`;

/**
 * Claims the next translations in one statement, so an overlapping run takes
 * other ones. For each language in ?4 (a JSON array, in LANGS order) that is
 * enabled and not paused, it reads at most ?3 rows of `queued` and `updating`
 * (oldest English first) and of `retrying` that are due, each through its own
 * partial index, so it reads about what it takes, also when another language
 * has a backlog. Of those it takes the oldest English first, each article's
 * languages in LANGS order, so a backlog comes out in each language in the
 * English feed's order. One whose article has left the feed (hidden, older
 * than 7 days) or whose English is being redone becomes `skipped` instead,
 * with why; it comes back with a new English. (Two parts of a compound SELECT,
 * whatever the number of languages: D1 allows only a few.)
 * Binds: ?1 now (the claim), ?2 the feed's start, ?3 limit, ?4 the languages.
 */
const OPEN = "EXISTS (SELECT 1 FROM translation_langs s WHERE s.lang = l.value AND s.enabled = 1 AND s.paused = 0)";
export const CLAIM = `UPDATE article_translations AS t
  SET state = CASE WHEN c.why = '' THEN 'translating' ELSE 'skipped' END,
      state_at = ?1,
      claimed_at = CASE WHEN c.why = '' THEN ?1 END,
      queued_at = CASE WHEN c.why = '' THEN t.queued_at END,
      next_attempt_at = NULL,
      last_error = CASE WHEN c.why = '' THEN t.last_error ELSE c.why END
  FROM (SELECT p.article_id, p.lang,
               COALESCE((SELECT CASE WHEN a.is_news IS NOT 1 THEN 'the article is hidden'
                                     WHEN a.published_at < ?2 THEN 'the article is older than 7 days'
                                     WHEN a.summarized_at IS NOT p.attempts_source OR a.headline IS NULL
                                          OR a.short_summary IS NULL OR a.summary IS NULL THEN 'its English is being redone'
                                     ELSE '' END
                         FROM articles a WHERE a.id = p.article_id), 'the article is gone') AS why
        FROM (SELECT r.article_id, r.lang, r.attempts_source, l.key AS rank
              FROM json_each(?4) l, article_translations r
              WHERE ${OPEN}
                AND r.rowid IN (SELECT x.rowid FROM article_translations x INDEXED BY article_translations_ready
                                WHERE x.lang = l.value AND x.state IN ('queued', 'updating')
                                ORDER BY x.attempts_source, x.article_id LIMIT ?3)
              UNION ALL
              SELECT r.article_id, r.lang, r.attempts_source, l.key AS rank
              FROM json_each(?4) l, article_translations r
              WHERE ${OPEN}
                AND r.rowid IN (SELECT x.rowid FROM article_translations x INDEXED BY article_translations_retry
                                WHERE x.lang = l.value AND x.state = 'retrying' AND x.next_attempt_at <= ?1
                                ORDER BY x.next_attempt_at LIMIT ?3)) p
        ORDER BY p.attempts_source, p.article_id, p.rank
        LIMIT ?3) AS c
  WHERE t.article_id = c.article_id AND t.lang = c.lang
  RETURNING article_id, lang, attempts_source, state, attempts, outage_retries`;

/**
 * An unusable answer: one attempt more for the English it was given, then
 * `retrying` until ?6, or `failed` after the last one, with why (?7). Only for
 * this run's claim (?8), so a run that was cut off and came back late changes
 * nothing. Binds: ?1 article, ?2 lang, ?3 English, ?4 MAX_ATTEMPTS, ?5 now, ?6 next try, ?7 why, ?8 claim.
 */
export const COUNT_ATTEMPT = `UPDATE article_translations
  SET attempts = attempts + 1,
      state = CASE WHEN attempts + 1 >= ?4 THEN 'failed' ELSE 'retrying' END,
      state_at = ?5,
      next_attempt_at = CASE WHEN attempts + 1 >= ?4 THEN NULL ELSE ?6 END,
      queued_at = CASE WHEN attempts + 1 >= ?4 THEN NULL ELSE queued_at END,
      claimed_at = NULL,
      last_error = ?7
  WHERE article_id = ?1 AND lang = ?2 AND attempts_source IS ?3 AND state = 'translating' AND claimed_at = ?8`;

/**
 * No provider answered (rate limit, quota, outage): `retrying` until ?4, with
 * why, and no attempt counted. Only for this run's claim (?6).
 * Binds: ?1 article, ?2 lang, ?3 now, ?4 next try, ?5 why, ?6 claim.
 */
export const OUTAGE = `UPDATE article_translations
  SET state = 'retrying', state_at = ?3, next_attempt_at = ?4, outage_retries = outage_retries + 1,
      claimed_at = NULL, last_error = ?5
  WHERE article_id = ?1 AND lang = ?2 AND state = 'translating' AND claimed_at = ?6`;

/**
 * Gives this run's claim back unchanged, by primary key, without counting an
 * attempt: its English changed between the claim and the run reading it.
 * Binds: ?1 article, ?2 lang, ?3 claim, ?4 now.
 */
export const FREE_CLAIM = `UPDATE article_translations
  SET state = CASE WHEN lang_seq IS NULL THEN 'queued' ELSE 'updating' END, state_at = ?4, claimed_at = NULL
  WHERE article_id = ?1 AND lang = ?2 AND state = 'translating' AND claimed_at = ?3`;

/** The state log older than EVENT_DAYS. Binds: ?1 cutoff. */
export const PRUNE_EVENTS = "DELETE FROM translation_events WHERE at < ?1";

/** What GET /queue shows for one language. */
export interface LanguageQueue extends Record<State, number> {
  enabled: boolean;
  paused: boolean;
  publishedLast24h: number;
  /** Minutes since the oldest translation still waiting (queued, updating, translating or retrying) was queued. */
  oldestWaitingAgeMinutes: number | null;
  lastPublishedAt: string | null;
}

/**
 * GET /queue: per language, how many translations are in each state, how many
 * were published in the last 24 hours, how long the oldest waiting one has
 * waited and when the last one was published. Read-only and cheap: the counts
 * come from `translation_counts`, the rest through partial indexes, about 4 rows
 * per language plus one per translation of the last 24 hours.
 */
export async function queueStatus(env: Env, now = new Date()): Promise<Record<Lang, LanguageQueue>> {
  const [langs, counts, times] = await env.DB.batch<Record<string, string | number | null>>([
    env.DB.prepare("SELECT lang, enabled, paused FROM translation_langs"),
    env.DB.prepare("SELECT lang, state, n FROM translation_counts"),
    env.DB.prepare(
      `SELECT l.value AS lang,
              (SELECT MIN(w.queued_at) FROM article_translations w INDEXED BY article_translations_waiting
               WHERE w.lang = l.value AND w.queued_at IS NOT NULL) AS oldest_waiting,
              (SELECT MAX(p.published_at) FROM article_translations p INDEXED BY article_translations_published
               WHERE p.lang = l.value AND p.published_at IS NOT NULL) AS last_published,
              (SELECT COUNT(*) FROM article_translations d INDEXED BY article_translations_published
               WHERE d.lang = l.value AND d.published_at >= ?2) AS published_24h
       FROM json_each(?1) l`,
    ).bind(JSON.stringify(LANGS), toStoredTime(new Date(now.getTime() - 24 * 3_600_000))),
  ]);
  const status = {} as Record<Lang, LanguageQueue>;
  for (const lang of LANGS) {
    const switches = langs.results.find((r) => r.lang === lang);
    const time = times.results.find((r) => r.lang === lang);
    const oldest = time?.oldest_waiting as string | null | undefined;
    const entry = {
      enabled: switches?.enabled === 1,
      paused: switches?.paused === 1,
      ...(Object.fromEntries(STATES.map((state) => [state, 0])) as Record<State, number>),
      publishedLast24h: Number(time?.published_24h ?? 0),
      oldestWaitingAgeMinutes: oldest ? Math.max(0, Math.floor((now.getTime() - Date.parse(oldest)) / 60_000)) : null,
      lastPublishedAt: (time?.last_published as string | null | undefined) ?? null,
    };
    for (const row of counts.results) if (row.lang === lang && (STATES as readonly unknown[]).includes(row.state)) entry[row.state as State] = Number(row.n);
    status[lang] = entry;
  }
  return status;
}
