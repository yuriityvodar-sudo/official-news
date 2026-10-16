// Push notifications (#62, Yurii 16 Oct): breaking decisions only. A push
// exists to bring a reader back to the app with something useful, so there are
// few of them, never at night, each in the reader's language.
//
// Per language (English, and every language enabled in translation_langs):
//   - Breaking: a released decision (feed_seq set, in the feed's 7 days) with
//     importance 4 or 5, released in the last 24 hours and not pushed before in
//     that language. A non-English push needs that language's translation
//     published for the article, and uses its headline and short summary.
//   - At most 2 a local day, and at least 1: from the daily slot (18:00 local)
//     on, a language that had no push that day gets its top story of the day,
//     whatever its importance (highest importance, then newest feed_seq, among
//     the decisions released in the last 24 hours and not pushed before).
//   - Quiet hours: none from 21:00 to 08:00 in the language's main time zone
//     (TIME_ZONES); a decision released at night goes out in the morning, while
//     it is less than 24 hours old.
//   - At least 3 hours between two pushes in the same language.
// When several decisions qualify, the highest importance goes first, then the
// newest. A push goes to the FCM topic breaking_<lang>, which the app
// subscribes to for its feed language: title the headline, body the short
// summary cut to about 110 characters at a word, data { articleId, lang }.
//
// Each translator run ends with runPush (../index.ts), at most one push per
// language, and so does the summarizer's while the translator is not running
// (its new trigger can take an hour to start, #50), as the release does. A run
// stays small: the clocks first (no database read at all while every language
// is in its quiet hours), then one statement for every language's count and
// last push, then one per language that may send for its best candidate
// (breaking news through its own small index): about 60 D1 rows a run with
// nothing to send. Each push is claimed in push_log BEFORE the request to FCM,
// in a statement that checks the cap and the spacing again (so two overlapping
// runs cannot both send), and completed after it by what FCM answered:
//   - Sent: FCM's message id.
//   - Refused (FCM refused the message itself, HTTP 400): the error, and the
//     article is never tried again in that language. The row counts for the
//     spacing, not for the daily cap (it surely did not go out), so a message
//     FCM refuses costs a language one try in 3 hours and the day's one push
//     can still go out.
//   - No answer (a network error, the 10 s timeout): the error. FCM may have
//     sent it, so it counts for the cap and the spacing, and is never tried again.
//   - Not now (401, 403, 408, 429, 5xx: the token, the permission, the quota,
//     FCM itself; nothing about the message): the run stops sending, deletes
//     its claims that were not sent, so a later run sends those articles,
//     forgets the token on a 401, and pauses the step for 10 minutes or FCM's
//     Retry-After (fcm.ts). Google giving no token pauses it the same way.
// A run cut off between the claim and its completion leaves a claim with
// neither, which counts as sent: nothing is ever sent twice.
import type { Env } from "../env";
import { toStoredTime } from "../fetcher/text";
import { LANGS, type Lang } from "../translator/languages";
import { DAY_MS, FEED_DAYS } from "../translator/release";
import { DROP_CACHE, type NotSent, type ServiceAccount, accessToken, parseServiceAccount, pause, sendMessage, tokenKey } from "./fcm";

/** The languages a push can be in: English and every language the feed is translated into. */
export type PushLang = "en" | Lang;
export const PUSH_LANGS: readonly PushLang[] = ["en", ...LANGS];

/**
 * Each language's main time zone, for the quiet hours, the daily slot and the
 * local day of the cap (Yurii, 16 Oct). Change a line to move a language;
 * adding a language to LANGS needs a line here (the type says so).
 */
export const TIME_ZONES: Record<PushLang, string> = {
  en: "Europe/London",
  uk: "Europe/Kyiv",
  ru: "Europe/Kyiv",
  es: "Europe/Madrid",
  de: "Europe/Berlin",
};

/** A decision this important (1 to 5) is breaking. */
export const BREAKING_IMPORTANCE = 4;
/** Pushes per language and local day, at most. */
export const MAX_PER_DAY = 2;
/** Hours between two pushes in the same language, at least. */
export const SPACING_HOURS = 3;
/** No push from this local hour … */
export const QUIET_FROM_HOUR = 21;
/** … until this one. */
export const QUIET_UNTIL_HOUR = 8;
/** From this local hour, a language without a push that day gets its top story. */
export const DAILY_SLOT_HOUR = 18;
/** Only decisions released this recently are pushed. */
export const RECENT_HOURS = 24;
/** The body: the short summary cut to about this many characters, ellipsis included. */
export const BODY_MAX = 110;

/** The FCM topic of a language, which the app subscribes to (docs/contract.md). */
export const topicFor = (lang: PushLang) => `breaking_${lang}`;

/**
 * For each language of ?1 (a JSON array of { lang, dayStart }, the languages
 * outside their quiet hours) that is English or enabled in translation_langs:
 * its pushes since the start of its local day that FCM did not refuse (sent,
 * sent without an answer, or claimed by a run that did not finish: each may
 * have reached readers), and its last push of any kind. Through
 * push_log_lang_time: a few rows per language.
 */
export const PUSH_STATE = `SELECT l.lang,
    (SELECT COUNT(*) FROM push_log p INDEXED BY push_log_lang_time
     WHERE p.lang = l.lang AND p.sent_at >= l.day_start AND p.refused = 0) AS sent_today,
    (SELECT MAX(p.sent_at) FROM push_log p INDEXED BY push_log_lang_time WHERE p.lang = l.lang) AS last_sent_at
  FROM (SELECT json_extract(value, '$.lang') AS lang, json_extract(value, '$.dayStart') AS day_start FROM json_each(?1)) l
  WHERE l.lang = 'en' OR EXISTS (SELECT 1 FROM translation_langs t WHERE t.lang = l.lang AND t.enabled = 1)`;

/**
 * A language's best decision to push: released since ?2 (RECENT_HOURS ago) and
 * published in the feed's 7 days (?3), never pushed in that language (?1), and
 * for a language other than English with its translation published (state
 * `published`, the translation of the current English). Highest importance
 * first, then the newest feed_seq. Its headline and short summary in the
 * language. Each row read gets a lookup in push_log and, for a language,
 * article_translations, by primary key.
 */
const candidate = (index: string, importance: string) => `SELECT a.id, a.importance,
    CASE WHEN ?1 = 'en' THEN a.headline ELSE t.headline END AS headline,
    CASE WHEN ?1 = 'en' THEN a.short_summary ELSE t.short_summary END AS short_summary
  FROM articles a INDEXED BY ${index}
  LEFT JOIN article_translations t ON t.article_id = a.id AND t.lang = ?1 AND t.state = 'published'
  WHERE a.feed_seq IS NOT NULL${importance} AND a.added_at >= ?2 AND a.is_news = 1 AND a.published_at >= ?3
    AND (CASE WHEN ?1 = 'en' THEN a.headline <> '' AND a.short_summary <> '' ELSE t.article_id IS NOT NULL END)
    AND NOT EXISTS (SELECT 1 FROM push_log p WHERE p.article_id = a.id AND p.lang = ?1)
  ORDER BY a.importance DESC, a.feed_seq DESC
  LIMIT 1`;

/**
 * The best breaking decision (importance 4+), through the partial index
 * articles_breaking (migration 0012): it holds only released decisions of
 * importance 4 or 5 (3 to 5 a day), so a run checking every language reads a
 * few rows, not the day's 50. The index's condition repeats
 * BREAKING_IMPORTANCE; if one changes without the other, INDEXED BY fails the
 * query and the tests. Binds: ?1 lang, ?2 released since, ?3 the feed's start.
 */
export const BREAKING_CANDIDATE = candidate("articles_breaking", ` AND a.importance >= ${BREAKING_IMPORTANCE}`);

/**
 * The day's top story, of any importance, for the daily slot (from 18:00, a
 * language without a push that day): reads the released decisions of the last
 * 24 hours (about 50) through articles_added_at. The last 24 hours, not the
 * local day: a decision from the evening before that got no push can be it.
 * Binds as BREAKING_CANDIDATE.
 */
export const TOP_CANDIDATE = candidate("articles_added_at", "");

/**
 * Claims one push before it is sent: writes its push_log row only if the
 * article was never pushed in that language, no push of the language is newer
 * than ?5 (SPACING_HOURS ago) and fewer than ?7 that FCM did not refuse went
 * out since ?6 (the start of its local day; counted as in PUSH_STATE), all in
 * one statement, so an overlapping run cannot claim a second one. Returns the
 * row when it was written.
 * Binds: ?1 article, ?2 lang, ?3 now, ?4 topic, ?5 spacing cutoff, ?6 day start, ?7 MAX_PER_DAY.
 */
export const CLAIM_PUSH = `INSERT OR IGNORE INTO push_log (article_id, lang, sent_at, topic)
  SELECT ?1, ?2, ?3, ?4
  WHERE NOT EXISTS (SELECT 1 FROM push_log p INDEXED BY push_log_lang_time WHERE p.lang = ?2 AND p.sent_at > ?5)
    AND (SELECT COUNT(*) FROM push_log p INDEXED BY push_log_lang_time
         WHERE p.lang = ?2 AND p.sent_at >= ?6 AND p.refused = 0) < ?7
  RETURNING article_id`;

/**
 * Completes a claim with FCM's answer. Binds: ?1 article, ?2 lang, ?3 message
 * id or NULL, ?4 error or NULL, ?5 1 when FCM refused the message, else 0.
 */
export const COMPLETE_PUSH = "UPDATE push_log SET message_id = ?3, error = ?4, refused = ?5 WHERE article_id = ?1 AND lang = ?2";

/**
 * Gives a claim back when FCM could not take the message just then, or the run
 * stopped before sending it: a later run can claim that article again. Only a
 * claim not yet completed. Binds: ?1 article, ?2 lang.
 */
export const RELEASE_CLAIM = "DELETE FROM push_log WHERE article_id = ?1 AND lang = ?2 AND message_id IS NULL AND error IS NULL";

/** The time in a language's zone: the hour and minute, and when its local day began. */
export interface LocalClock {
  hour: number;
  minute: number;
  dayStart: Date;
}

/** One formatter per time zone for the isolate's life: making one costs more CPU than using it. */
const formatters = new Map<string, Intl.DateTimeFormat>();

/**
 * The local time of `now` in `timeZone`, with Intl.DateTimeFormat. The day's
 * start is local midnight at the offset of `now`: on the night of a clock
 * change it is an hour off, which changes nothing, as midnight is inside the
 * quiet hours either way.
 */
export function localClock(now: Date, timeZone: string): LocalClock {
  let format = formatters.get(timeZone);
  if (!format) {
    format = new Intl.DateTimeFormat("en-GB", {
      timeZone,
      hourCycle: "h23",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });
    formatters.set(timeZone, format);
  }
  const part: Record<string, number> = {};
  for (const { type, value } of format.formatToParts(now)) part[type] = Number(value);
  const local = Date.UTC(part.year, part.month - 1, part.day, part.hour, part.minute, part.second);
  const offset = local - Math.floor(now.getTime() / 1000) * 1000;
  return { hour: part.hour, minute: part.minute, dayStart: new Date(Date.UTC(part.year, part.month - 1, part.day) - offset) };
}

/** Whether a local hour is in the quiet hours (21:00 to 08:00). */
export const isQuiet = (hour: number) => hour >= QUIET_FROM_HOUR || hour < QUIET_UNTIL_HOUR;

/**
 * The push body: the short summary on one line, cut to at most `max`
 * characters at the end of a word, with an ellipsis; unchanged when it fits.
 */
export function shorten(text: string, max = BODY_MAX): string {
  const clean = text.replace(/\s+/g, " ").trim();
  const chars = [...clean];
  if (chars.length <= max) return clean;
  // Room for the ellipsis; a word that ends exactly there stays whole.
  const head = chars.slice(0, max - 1).join("");
  const space = head.lastIndexOf(" ");
  const words = chars[max - 1] === " " || space < 0 ? head : head.slice(0, space);
  return `${words.replace(/[\s,;:.\-–—(]+$/u, "")}…`;
}

/** What a run did for one language it sent to: sent (with FCM's id), or not, with why. */
export interface PushResult {
  lang: PushLang;
  articleId: string;
  /** `breaking`: importance 4 or more; `daily`: the day's top story at the daily slot. */
  kind: "breaking" | "daily";
  ok: boolean;
  messageId?: string;
  error?: string;
  /** Not sent: `refused` and `unknown` are never tried again, `retry` is tried by a later run (fcm.ts, NotSent). */
  outcome?: NotSent;
}

export interface PushRun {
  pushes: PushResult[];
  /** Why each language without a push sent none. */
  skipped: Partial<Record<PushLang, string>>;
}

export interface PushOptions {
  now?: Date;
  /** For Google's token endpoint and FCM; tests pass their own. */
  fetch?: typeof globalThis.fetch;
}

interface Pick {
  lang: PushLang;
  articleId: string;
  kind: PushResult["kind"];
  title: string;
  body: string;
  dayStart: Date;
}

/**
 * #62. Sends at most one push per language, by the rules at the top of this
 * file, and logs one `push run` line: what was sent, what FCM refused, and why
 * each other language sent nothing. Without the Worker secret
 * FCM_SERVICE_ACCOUNT it does nothing and logs `push skipped`. Called at the
 * end of each translator run (../index.ts).
 */
export async function runPush(env: Env, options: PushOptions = {}): Promise<PushRun> {
  const now = options.now ?? new Date();
  const fetch = options.fetch ?? globalThis.fetch;
  const run: PushRun = { pushes: [], skipped: {} };
  if (!env.FCM_SERVICE_ACCOUNT) {
    console.log(JSON.stringify({ message: "push skipped: FCM_SERVICE_ACCOUNT not set" }));
    return run;
  }
  let account: ServiceAccount;
  try {
    account = parseServiceAccount(env.FCM_SERVICE_ACCOUNT);
  } catch (error) {
    console.log(JSON.stringify({ message: "push skipped", reason: error instanceof Error ? error.message : String(error) }));
    return run;
  }
  const log = () => {
    console.log(JSON.stringify({ message: "push run", ...run }));
    return run;
  };

  // The clocks first: while every language is in its quiet hours, the run reads nothing.
  const open: { lang: PushLang; clock: LocalClock }[] = [];
  for (const lang of PUSH_LANGS) {
    const clock = localClock(now, TIME_ZONES[lang]);
    const time = `${String(clock.hour).padStart(2, "0")}:${String(clock.minute).padStart(2, "0")}`;
    if (isQuiet(clock.hour)) run.skipped[lang] = `quiet hours (${time} in ${TIME_ZONES[lang]})`;
    else open.push({ lang, clock });
  }
  if (!open.length) return log();

  const ago = (ms: number) => toStoredTime(new Date(now.getTime() - ms));
  const spacingCutoff = ago(SPACING_HOURS * 3_600_000);
  const { results: states } = await env.DB.prepare(PUSH_STATE)
    .bind(JSON.stringify(open.map(({ lang, clock }) => ({ lang, dayStart: toStoredTime(clock.dayStart) }))))
    .all<{ lang: PushLang; sent_today: number; last_sent_at: string | null }>();

  // The languages that may send now, and whether it is their daily slot.
  const ready: { lang: PushLang; clock: LocalClock; slot: boolean }[] = [];
  for (const { lang, clock } of open) {
    const state = states.find((s) => s.lang === lang);
    if (!state) run.skipped[lang] = "language off";
    else if (state.sent_today >= MAX_PER_DAY) run.skipped[lang] = `daily cap (${MAX_PER_DAY} today)`;
    else if (state.last_sent_at && state.last_sent_at > spacingCutoff) run.skipped[lang] = `spacing (last push ${state.last_sent_at})`;
    else ready.push({ lang, clock, slot: clock.hour >= DAILY_SLOT_HOUR && state.sent_today === 0 });
  }
  if (!ready.length) return log();

  const since = ago(RECENT_HOURS * 3_600_000);
  const feedStart = ago(FEED_DAYS * DAY_MS);
  const candidates = await env.DB.batch<{ id: string; importance: number | null; headline: string; short_summary: string }>(
    ready.map(({ lang, slot }) => env.DB.prepare(slot ? TOP_CANDIDATE : BREAKING_CANDIDATE).bind(lang, since, feedStart)),
  );
  const picks: Pick[] = [];
  ready.forEach(({ lang, clock, slot }, i) => {
    const row = candidates[i].results[0];
    if (!row) {
      run.skipped[lang] = slot ? "no decision released in the last 24 hours" : `nothing breaking (importance ${BREAKING_IMPORTANCE}+) in the last 24 hours`;
      return;
    }
    const kind = (row.importance ?? 0) >= BREAKING_IMPORTANCE ? "breaking" : "daily";
    picks.push({ lang, articleId: row.id, kind, title: row.headline, body: shorten(row.short_summary), dayStart: clock.dayStart });
  });
  if (!picks.length) return log();

  // The token before any claim: without one (or while the step is paused) nothing is claimed, so nothing is lost.
  const got = await accessToken(env, account, now, fetch);
  if ("error" in got) {
    for (const pick of picks) run.skipped[pick.lang] = got.error;
    return log();
  }
  const { token } = got;

  const sentAt = toStoredTime(now);
  const claims = await env.DB.batch(
    picks.map((p) =>
      env.DB.prepare(CLAIM_PUSH).bind(p.articleId, p.lang, sentAt, topicFor(p.lang), spacingCutoff, toStoredTime(p.dayStart), MAX_PER_DAY),
    ),
  );
  const claimed = picks.filter((pick, i) => {
    if (claims[i].results.length) return true;
    run.skipped[pick.lang] = "claimed by another run";
    return false;
  });

  // One request at a time, at most one per language (6 with the token: far below the 50 a run may make).
  // Every answer is written in one batch at the end: completions, claims given back, the pause.
  const writes: D1PreparedStatement[] = [];
  let paused: { until: string; why: string } | undefined;
  for (const pick of claimed) {
    if (paused) {
      // FCM could not take an earlier message: the same token and FCM would fail this one too.
      writes.push(env.DB.prepare(RELEASE_CLAIM).bind(pick.articleId, pick.lang));
      run.skipped[pick.lang] = `paused until ${paused.until} (${paused.why})`;
      continue;
    }
    const sent = await sendMessage(
      account,
      token,
      { topic: topicFor(pick.lang), title: pick.title, body: pick.body, data: { articleId: pick.articleId, lang: pick.lang } },
      fetch,
    );
    const result: PushResult = { lang: pick.lang, articleId: pick.articleId, kind: pick.kind, ok: sent.ok };
    run.pushes.push(sent.ok ? { ...result, messageId: sent.messageId } : { ...result, error: sent.error, outcome: sent.outcome });
    if (sent.ok) {
      writes.push(env.DB.prepare(COMPLETE_PUSH).bind(pick.articleId, pick.lang, sent.messageId, null, 0));
    } else if (sent.outcome !== "retry") {
      writes.push(env.DB.prepare(COMPLETE_PUSH).bind(pick.articleId, pick.lang, null, sent.error, sent.outcome === "refused" ? 1 : 0));
    } else {
      writes.push(env.DB.prepare(RELEASE_CLAIM).bind(pick.articleId, pick.lang));
      // FCM refused the token: the run after the pause asks Google for a new one.
      if (sent.status === 401) writes.push(env.DB.prepare(DROP_CACHE).bind(tokenKey(account)));
      const why = `FCM: ${sent.error}`;
      const step = pause(env, account, now, why, sent.retryAfterSeconds);
      writes.push(step.statement);
      paused = { until: step.until, why };
    }
  }
  if (writes.length) await env.DB.batch(writes);
  return log();
}
