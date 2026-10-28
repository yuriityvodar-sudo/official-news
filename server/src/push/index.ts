// Push notifications (#62, Yurii 16 Oct): breaking decisions only, each one as
// it comes (Yurii, 23 Oct, #157: no daily cap, no spacing, no top story of the
// day), never at night, each in the reader's language.
//
// Per language (English, and every language enabled in translation_langs):
//   - Breaking: a released decision (feed_seq set, in the feed's 7 days) with
//     importance 4 or 5, released in the last 24 hours and not pushed before in
//     that language. A non-English push needs that language's translation
//     published for the article, and uses its headline and short summary.
//   - Every breaking decision is pushed; a day with none has no push.
//   - Quiet hours: none from 21:00 to 08:00 in the language's main time zone
//     (TIME_ZONES); a decision released at night goes out in the morning, while
//     it is less than 24 hours old.
// A run sends at most one push per language: when several decisions qualify,
// the highest importance goes first, then the newest, and the next run (a few
// minutes later) sends the next. A push goes to the FCM topic breaking_<lang>, which the app
// subscribes to for its feed language: title the headline, a line under it on
// iOS (the subtitle) with the country's flag and name in the language and, for
// importance 5 only, "Breaking" (#157), body the short summary cut to about
// 110 characters at a word, data { articleId, lang }.
//
// Each translator run ends with runPush (../index.ts), at most one push per
// language, and so does the summarizer's while the translator is not running
// (its new trigger can take an hour to start, #50), as the release does. A run
// stays small: the clocks first (no database read at all while every language
// is in its quiet hours), then one statement for the languages that are on,
// then one per language for its best candidate (breaking news through its own
// small index): a few dozen D1 rows a run with nothing to send. Each push is
// claimed in push_log BEFORE the request to FCM (its key, article and
// language, keeps two overlapping runs from both sending one article), and
// completed after it by what FCM answered:
//   - Sent: FCM's message id.
//   - Refused (FCM refused the message itself, HTTP 400): the error, and the
//     article is never tried again in that language.
//   - No answer (a network error, the 10 s timeout): the error. FCM may have
//     sent it, so it is never tried again.
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
/** No push from this local hour … */
export const QUIET_FROM_HOUR = 21;
/** … until this one. */
export const QUIET_UNTIL_HOUR = 8;
/** A decision this important (5) says "Breaking" under the title (#157); 4 is breaking without the word. */
export const TOP_IMPORTANCE = 5;
/** Only decisions released this recently are pushed. */
export const RECENT_HOURS = 24;
/** The body: the short summary cut to about this many characters, ellipsis included. */
export const BODY_MAX = 110;

/** The FCM topic of a language, which the app subscribes to (docs/contract.md). */
export const topicFor = (lang: PushLang) => `breaking_${lang}`;

/** "Breaking" in each push language, under the title of an importance 5 decision (#157). */
export const BREAKING_WORD: Record<PushLang, string> = {
  en: "Breaking",
  uk: "Терміново",
  ru: "Срочно",
  es: "Última hora",
  de: "Eilmeldung",
};

/**
 * The languages of ?1 (a JSON array of language codes, those outside their
 * quiet hours) that can be pushed: English, and each one enabled in
 * translation_langs.
 */
export const LANGS_ON = `SELECT value AS lang FROM json_each(?1)
  WHERE value = 'en' OR EXISTS (SELECT 1 FROM translation_langs t WHERE t.lang = value AND t.enabled = 1)`;

/**
 * A language's best breaking decision (importance 4+): released since ?2
 * (RECENT_HOURS ago) and published in the feed's 7 days (?3), never pushed in
 * that language (?1), and for a language other than English with its
 * translation published (state `published`, the translation of the current
 * English). Highest importance first, then the newest feed_seq. Its headline
 * and short summary in the language, and its source's country for the line
 * under the title. Through the partial index articles_breaking (migration
 * 0012): it holds only released decisions of importance 4 or 5 (3 to 10 a
 * day), so a run checking every language reads a few rows, not the day's 50.
 * The index's condition repeats BREAKING_IMPORTANCE; if one changes without the
 * other, INDEXED BY fails the query and the tests. Each row read gets a lookup
 * in push_log, sources and, for a language, article_translations, by primary key.
 */
export const BREAKING_CANDIDATE = `SELECT a.id, a.importance, s.country,
    CASE WHEN ?1 = 'en' THEN a.headline ELSE t.headline END AS headline,
    CASE WHEN ?1 = 'en' THEN a.short_summary ELSE t.short_summary END AS short_summary
  FROM articles a INDEXED BY articles_breaking
  LEFT JOIN sources s ON s.id = a.source_id
  LEFT JOIN article_translations t ON t.article_id = a.id AND t.lang = ?1 AND t.state = 'published'
  WHERE a.feed_seq IS NOT NULL AND a.importance >= ${BREAKING_IMPORTANCE} AND a.added_at >= ?2 AND a.is_news = 1 AND a.published_at >= ?3
    AND (CASE WHEN ?1 = 'en' THEN a.headline <> '' AND a.short_summary <> '' ELSE t.article_id IS NOT NULL END)
    AND NOT EXISTS (SELECT 1 FROM push_log p WHERE p.article_id = a.id AND p.lang = ?1)
  ORDER BY a.importance DESC, a.feed_seq DESC
  LIMIT 1`;

/**
 * Claims one push before it is sent: writes its push_log row only if the
 * article was never pushed (nor claimed) in that language, so an overlapping
 * run cannot send it too. Returns the row when it was written.
 * Binds: ?1 article, ?2 lang, ?3 now, ?4 topic.
 */
export const CLAIM_PUSH = `INSERT OR IGNORE INTO push_log (article_id, lang, sent_at, topic) VALUES (?1, ?2, ?3, ?4)
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

/** A country's flag: its two letters as regional indicator symbols (the EU and the UN have one too). */
export function flag(country: string): string {
  if (!/^[A-Z]{2}$/.test(country)) return "";
  return String.fromCodePoint(...[...country].map((letter) => 0x1f1e6 + letter.charCodeAt(0) - 65));
}

/** One Intl.DisplayNames per language for the isolate's life, like the time zones' formatters. */
const regionNames = new Map<PushLang, Intl.DisplayNames>();

/** A country's name in the push's language ("Brazil", "Бразилія", "Brasilien"), or its code when Intl has none. */
export function countryName(country: string, lang: PushLang): string {
  let names = regionNames.get(lang);
  if (!names) {
    names = new Intl.DisplayNames([lang], { type: "region", fallback: "code" });
    regionNames.set(lang, names);
  }
  try {
    return names.of(country) ?? country;
  } catch {
    return country;
  }
}

/**
 * The line under the title on iOS (#157): the flag and the country in the
 * push's language, and "Breaking" for importance 5 only, so the word keeps
 * its meaning: "🇧🇷 Brazil · Breaking", "🇮🇹 Italy". Empty without either.
 */
export function subtitleFor(country: string | null, importance: number | null, lang: PushLang): string {
  const where = country ? [flag(country), countryName(country, lang)].filter(Boolean).join(" ") : "";
  const breaking = (importance ?? 0) >= TOP_IMPORTANCE ? BREAKING_WORD[lang] : "";
  return [where, breaking].filter(Boolean).join(" · ");
}

/** What a run did for one language it sent to: sent (with FCM's id), or not, with why. */
export interface PushResult {
  lang: PushLang;
  articleId: string;
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
  title: string;
  subtitle: string;
  body: string;
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
  const { results: on } = await env.DB.prepare(LANGS_ON)
    .bind(JSON.stringify(open.map(({ lang }) => lang)))
    .all<{ lang: PushLang }>();
  const ready: PushLang[] = [];
  for (const { lang } of open) {
    if (on.some((row) => row.lang === lang)) ready.push(lang);
    else run.skipped[lang] = "language off";
  }
  if (!ready.length) return log();

  const since = ago(RECENT_HOURS * 3_600_000);
  const feedStart = ago(FEED_DAYS * DAY_MS);
  const candidates = await env.DB.batch<{ id: string; importance: number | null; country: string | null; headline: string; short_summary: string }>(
    ready.map((lang) => env.DB.prepare(BREAKING_CANDIDATE).bind(lang, since, feedStart)),
  );
  const picks: Pick[] = [];
  ready.forEach((lang, i) => {
    const row = candidates[i].results[0];
    if (!row) {
      run.skipped[lang] = `nothing breaking (importance ${BREAKING_IMPORTANCE}+) in the last 24 hours`;
      return;
    }
    picks.push({
      lang,
      articleId: row.id,
      title: row.headline,
      subtitle: subtitleFor(row.country, row.importance, lang),
      body: shorten(row.short_summary),
    });
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
      env.DB.prepare(CLAIM_PUSH).bind(p.articleId, p.lang, sentAt, topicFor(p.lang)),
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
      {
        topic: topicFor(pick.lang),
        title: pick.title,
        subtitle: pick.subtitle,
        body: pick.body,
        data: { articleId: pick.articleId, lang: pick.lang },
      },
      fetch,
    );
    const result: PushResult = { lang: pick.lang, articleId: pick.articleId, ok: sent.ok };
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
