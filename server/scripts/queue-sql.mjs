// The SQL of scripts/queue.mjs (#46): managing the translation queue. Kept apart
// from the command line, without Node imports, so the Worker tests run every
// statement against the real schema (test/queue-script.test.ts). wrangler d1
// execute takes no bound values, so each value is checked first and then quoted.
// Every write returns the rows it changed (RETURNING): D1's `changes` also
// counts what the triggers write.

/** As LANGS in src/translator/languages.ts (a test checks they match). */
export const LANGS = ["uk", "ru", "es", "de"];

/** As STATES in src/translator/queue.ts (a test checks they match). */
export const STATES = ["queued", "updating", "translating", "retrying", "published", "failed", "skipped"];

const NOW = "strftime('%Y-%m-%dT%H:%M:%SZ', 'now')";
/** The feed's 7 days (docs/contract.md): only these articles are translated. */
const FEED_START = "strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-7 days')";

/** A string as an SQL literal. */
const quote = (value) => `'${String(value).replaceAll("'", "''")}'`;

export function checkLang(value) {
  if (!LANGS.includes(value)) throw new Error(`language must be one of: ${LANGS.join(", ")} (got ${JSON.stringify(value ?? null)})`);
  return value;
}

export function checkState(value) {
  if (!STATES.includes(value)) throw new Error(`state must be one of: ${STATES.join(", ")} (got ${JSON.stringify(value ?? null)})`);
  return value;
}

export function checkArticleId(value) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{1,64}$/.test(value)) {
    throw new Error(`article id must be letters, digits, - or _ (got ${JSON.stringify(value ?? null)})`);
  }
  return value;
}

/** News in the feed with an English summary, as the translator queues it. */
const IN_FEED = `a.is_news = 1 AND a.published_at >= ${FEED_START} AND a.summarized_at IS NOT NULL
    AND a.headline IS NOT NULL AND a.short_summary IS NOT NULL AND a.summary IS NOT NULL`;

/**
 * Puts the articles `where` picks into the queue for `lang`, for their current
 * English, with fresh tries: `queued`, or `updating` when a translation is
 * shown (it stays until the new one is published). With `onlyNew`, only those
 * not queued yet for their current English (what the translator itself does).
 */
function enqueue(lang, where, why, { onlyNew = false } = {}) {
  return `INSERT INTO article_translations (article_id, lang, attempts_source, queued_at, state, state_at, last_error)
  SELECT a.id, ${quote(lang)}, a.summarized_at, ${NOW}, 'queued', ${NOW}, ${why === null ? "NULL" : quote(why)}
  FROM articles a
  WHERE ${IN_FEED} AND ${where}
  ON CONFLICT (article_id, lang) DO UPDATE SET
    attempts_source = excluded.attempts_source, attempts = 0, outage_retries = 0, queued_at = excluded.queued_at,
    claimed_at = NULL, next_attempt_at = NULL, last_error = excluded.last_error,
    state = CASE WHEN lang_seq IS NULL THEN 'queued' ELSE 'updating' END, state_at = excluded.state_at${
      onlyNew ? "\n  WHERE attempts_source IS NOT excluded.attempts_source" : ""
    }
  RETURNING article_id, lang, state`;
}

/** Each language's switch (why it is paused, since when its provider is down) and how many translations it has in each state. */
export const status = () => [
  `SELECT l.lang, l.enabled, l.paused, l.paused_reason, l.down_since, l.updated_at, c.state, c.n
   FROM translation_langs l LEFT JOIN translation_counts c ON c.lang = l.lang AND c.n > 0
   ORDER BY l.lang, c.state`,
];

/**
 * Translations by state and language, the latest change first.
 * @param {{ state?: string, lang?: string, limit?: number | string }} [options]
 */
export function list({ state, lang, limit = 50 } = {}) {
  const where = [state === undefined ? null : `state = ${quote(checkState(state))}`, lang === undefined ? null : `lang = ${quote(checkLang(lang))}`].filter(Boolean);
  const n = Number(limit);
  if (!Number.isInteger(n) || n < 1 || n > 1000) throw new Error("limit must be a whole number from 1 to 1000");
  return [
    `SELECT article_id, lang, state, state_at, attempts, outage_retries, next_attempt_at, last_error
     FROM article_translations ${where.length ? `WHERE ${where.join(" AND ")}` : ""}
     ORDER BY state_at DESC LIMIT ${n}`,
  ];
}

/**
 * Every state change of one article (in one language), oldest first.
 * @param {string} articleId
 * @param {string} [lang]
 */
export function history(articleId, lang) {
  const where = [`article_id = ${quote(checkArticleId(articleId))}`, lang === undefined ? null : `lang = ${quote(checkLang(lang))}`].filter(Boolean);
  return [`SELECT lang, state, at, attempts, detail FROM translation_events WHERE ${where.join(" AND ")} ORDER BY at, rowid`];
}

/** One article in one language again, with fresh tries: a failed one, a stuck one, or a published one to redo. */
export function requeue(articleId, lang) {
  return [enqueue(checkLang(lang), `a.id = ${quote(checkArticleId(articleId))}`, "requeued by hand")];
}

/**
 * Every article of the feed in one language again (after a prompt change), or
 * with `failed` only the failed ones. Published ones become `updating`: their
 * text stays until the new one is published.
 */
/** @param {string} lang @param {{ failed?: boolean }} [options] */
export function requeueLang(lang, { failed = false } = {}) {
  checkLang(lang);
  const where = failed
    ? `EXISTS (SELECT 1 FROM article_translations t WHERE t.article_id = a.id AND t.lang = ${quote(lang)} AND t.state = 'failed')`
    : "1 = 1";
  return [enqueue(lang, where, failed ? "requeued by hand (failed)" : "requeued by hand (whole language)")];
}

/** The feed's 7 days for a language that was just enabled: every article not queued yet for its English. */
export function backlog(lang) {
  return [enqueue(checkLang(lang), "1 = 1", null, { onlyNew: true })];
}

const setLang = (lang, values, change) =>
  `INSERT INTO translation_langs (lang, enabled, paused, paused_reason, down_since, updated_at)
  VALUES (${quote(checkLang(lang))}, ${values}, ${NOW})
  ON CONFLICT (lang) DO UPDATE SET ${change}, updated_at = excluded.updated_at
  RETURNING lang, enabled, paused, paused_reason, down_since, updated_at`;

/**
 * A paused language is still queued, but nothing of it is claimed, and the
 * release no longer waits for it. Paused by hand ('manual'), it stays paused
 * until resume; the translator pauses a language whose provider is down for 2
 * hours by itself ('auto: …') and unpauses it on the first answer.
 */
export const pause = (lang) => [setLang(lang, "0, 1, 'manual', NULL", "paused = 1, paused_reason = 'manual'")];
/** Resumes a language paused by hand or automatically, with a fresh 2 hours before an outage pauses it again. */
export const resume = (lang) => [setLang(lang, "0, 0, NULL, NULL", "paused = 0, paused_reason = NULL, down_since = NULL")];
/** Enabling also queues the feed's 7 days (backlog). */
export const enable = (lang) => [setLang(lang, "1, 0, NULL, NULL", "enabled = 1"), ...backlog(lang)];
/** A disabled language is no longer queued, nor waited for; what it has stays, and the API still shows what is published. */
export const disable = (lang) => [setLang(lang, "0, 0, NULL, NULL", "enabled = 0")];
