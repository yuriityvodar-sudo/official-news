import { receiveNotification } from "../appstore";
import { chatStatus, creditChatPack } from "../chat";
import type { Env } from "../env";
import { REAL_SOURCE, health } from "../health";
import { TOPICS, type Topic } from "../summarizer/schema";
import { LANGS, type Lang, SHOWN, isLang, queueStatus, releaseStatus } from "../translator";
import {
  EU,
  EU_MEMBERS,
  GROUPS,
  TOPIC_ERROR,
  TOPIC_NAMES,
  type Where,
  byName,
  countryName,
  groupCountries,
  groupName,
  readTopic,
  readWhere,
  whereCountries,
} from "./filters";

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
  headline_type: string | null;
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
  impact: string | null;
}

/**
 * The source's name (#76): in English, `name`; in a language of LANGS, its
 * `config.names.<lang>` (loaded from docs/source-names.csv), else the English
 * name. `lang` is one of LANGS, never text from the request, so it can sit in
 * the SQL. A config that is not JSON gives the English name instead of failing
 * the whole feed.
 */
const sourceName = (lang: Lang | null) =>
  lang ? `COALESCE(CASE WHEN json_valid(s.config) THEN json_extract(s.config, '$.names.${lang}') END, s.name)` : "s.name";

const articleColumns = (lang: Lang | null) => `
  a.id, s.country, a.source_id, ${sourceName(lang)} AS source_name, s.url AS source_url,
  a.url, a.original_title, a.published_at, a.date_only, a.headline, a.headline_type, a.short_summary,
  a.summary, a.decision_type, a.image_url, a.original_language, a.topics, a.tags, a.importance,
  a.feed_seq, a.added_at, a.impact`;

const ARTICLE_COLUMNS = articleColumns(null);

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

/** How many top stories the first page sends (#164). */
const TOP_SIZE = 3;

/**
 * A top story's score (#164): the AI's importance (1 to 5) less half a point
 * for each day since it was published, so a 4 from yesterday beats a fresh 3.
 */
const TOP_SCORE = "a.importance - 0.5 * (julianday('now') - julianday(a.published_at))";

/**
 * The score in For you (#170): the reader's own country gets a point more,
 * and the EU institutions half a point for a reader in an EU member, so the
 * block becomes "Top stories for you".
 */
function topScore(filters: Filters): string {
  if (filters.home === null) return TOP_SCORE;
  const [home, union] = homeCountries(filters.home);
  return `${TOP_SCORE} + CASE s.country WHEN '${home}' THEN 1${union ? ` WHEN '${union}' THEN 0.5` : ""} ELSE 0 END`;
}

/**
 * Top stories: the highest scores of the last 72 hours, TOP_SIZE in all, at
 * most 1 from one country so one gazette cannot fill the block (a one-country
 * view has only its own), among the articles `where` picks (the feed's, or a
 * language's: #46). Best first; on equal scores the newer. Within a country
 * the For you bonus is the same for all, so the plain score ranks them.
 */
const topQuery = (columns: string, from: string, where: string, filters: Filters) => `
  SELECT * FROM (
    SELECT ${columns}, ${topScore(filters)} AS score,
           ROW_NUMBER() OVER (
             PARTITION BY s.country ORDER BY ${TOP_SCORE} DESC, a.published_at DESC, a.id DESC
           ) AS country_rank
    ${from}
    WHERE ${where} AND a.importance IS NOT NULL
      AND a.published_at >= strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-72 hours')
  )
  WHERE country_rank <= ${filters.oneCountry ? TOP_SIZE : 1}
  ORDER BY score DESC, published_at DESC, id DESC
  LIMIT ${TOP_SIZE}`;

/**
 * The top stories read the last 72 hours through the (is_news, published_at)
 * index. The unary + keeps SQLite from walking articles_feed_seq instead, over
 * every released article, which it picks once the table has statistics
 * (ANALYZE; test/filters.test.ts checks both).
 */
const TOP_WHERE = "a.is_news = 1 AND +a.feed_seq IS NOT NULL";
/** The top-story conditions plus `filters` (their values are bound first). */
const topWhere = (filters: Filters) => [TOP_WHERE, ...filters.where].join(" AND ");
/** The top stories among the feed's articles that pass `filters`. */
const englishTop = (filters: Filters) => topQuery(ARTICLE_COLUMNS, FROM_ARTICLES, topWhere(filters), filters);

/** The top stories' query among the articles that pass `filters`, in English (`lang` null) or in `lang`, with the values it binds. */
export const topStories = (filters: Filters, lang: Lang | null) => ({
  sql: lang ? translatedTop(filters, lang) : englishTop(filters),
  binds: lang ? [...filters.binds, lang] : filters.binds,
});

// Filters (#67, #68): Where (`country` or `group`) and `topic`, the same on every
// page, in `after=`, in top and in every language, so a cursor continues within its filter.

/** The feed's filters as conditions on the article (`a`), with the values they bind, in order. */
export interface Filters {
  where: string[];
  binds: string[];
  /** Where is one country: the top stories may all be its own. */
  oneCountry: boolean;
  /** For you (#170): the reader's country, whose decisions get a bonus in the top stories. */
  home: string | null;
}

/** For you (#170): from the rest of the world only decisions of this importance or more… */
const FOR_YOU_MIN_IMPORTANCE = 3;
/** …and at most this many a day (by publication date, UTC) from one country, so a gazette cannot fill the feed. */
const FOR_YOU_PER_DAY = 2;

/** The source countries a reader in `home` gets every decision of: its own, and the EU institutions' for an EU member. */
function homeCountries(home: string): string[] {
  // Written into the SQL as it is: readWhere lets through only 2 capital letters.
  if (!/^[A-Z]{2}$/.test(home)) throw new Error(`not a country code: ${home}`);
  return EU_MEMBERS.includes(home) ? [home, EU] : [home];
}

/**
 * For you (#170): every decision of the reader's own country (and of the EU
 * institutions for a reader in an EU member), and from the rest of the world
 * only what matters: importance FOR_YOU_MIN_IMPORTANCE or more, at most
 * FOR_YOU_PER_DAY a day from one country, the most important first, then the
 * first released. The world's picks are one subquery over the feed's 7 days,
 * read once per query through the (is_news, published_at) index.
 */
function forYouCondition(home: string): string {
  const own = homeCountries(home)
    .map((country) => `'${country}'`)
    .join(", ");
  return `(a.source_id IN (SELECT id FROM sources WHERE +country IN (${own}))
    OR a.id IN (SELECT id FROM (
      SELECT w.id, ROW_NUMBER() OVER (
               PARTITION BY ws.country, substr(w.published_at, 1, 10) ORDER BY w.importance DESC, w.feed_seq
             ) AS day_rank
      FROM articles w JOIN sources ws ON ws.id = w.source_id
      WHERE w.is_news = 1 AND +w.feed_seq IS NOT NULL AND w.importance >= ${FOR_YOU_MIN_IMPORTANCE}
        AND w.published_at >= strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-7 days')
        AND ws.country NOT IN (${own})
    ) WHERE day_rank <= ${FOR_YOU_PER_DAY}))`;
}

/**
 * An article's topics as a JSON list for json_each: anything that is not a
 * list reads as none, as in toArticle, instead of failing the query (CASE
 * tries json_type only on valid JSON).
 */
const TOPIC_LIST = `CASE WHEN NOT json_valid(a.topics) THEN '[]' WHEN json_type(a.topics) = 'array' THEN a.topics ELSE '[]' END`;

/**
 * Where: `country`, the articles of that country's sources only; `group`, the
 * articles of its members' sources, and of the EU institutions' where the group
 * includes them (GROUPS); `home`, For you (forYouCondition). `topic`: articles
 * the AI gave that topic. Neither: the whole feed (all countries, all topics).
 *
 * The source countries are checked on the article's source_id against the
 * matching sources, read once (a few dozen rows), so a page skips another
 * country's article without reading its source: about 270 rows read for a page
 * of a country with few articles, against about 360 with `s.country` (live D1,
 * 16 Oct). The unary + reads that list with one plain pass over sources: for a
 * single country (`country IN (?)` is `country = ?`) SQLite would otherwise
 * build an automatic index on sources for it, which reads them all as well.
 */
export function feedFilters(where: Where, topic: Topic | null): Filters {
  const home = where !== null && "home" in where ? where.home : null;
  const filters: Filters = { where: [], binds: [], oneCountry: where !== null && "country" in where, home };
  if (home !== null) filters.where.push(forYouCondition(home));
  const countries = whereCountries(where);
  if (countries) {
    filters.where.push(`a.source_id IN (SELECT id FROM sources WHERE +country IN (${countries.map(() => "?").join(", ")}))`);
    filters.binds.push(...countries);
  }
  if (topic) {
    filters.where.push(`EXISTS (SELECT 1 FROM json_each(${TOPIC_LIST}) WHERE value = ?)`);
    filters.binds.push(topic);
  }
  return filters;
}

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

/** The stored impact JSON (#63), or null when there is none or it cannot be read. */
function parseImpact(value: string | null): unknown {
  if (!value) return null;
  try {
    const parsed: unknown = JSON.parse(value);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : null;
  } catch {
    return null;
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
    headlineType: row.headline_type,
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
    impact: parseImpact(row.impact),
  };
}

/**
 * Cloudflare keeps a response with one of these in its cache in front of the
 * Worker (Workers Caching, `cache` in wrangler.jsonc, #121), keyed by the path
 * and the whole query string. A feed page is the same for every reader of a
 * language, and a hit does not run the Worker: no D1 rows, no CPU. The lists
 * for a minute, an article for 5 (it changes only when summarized or translated
 * again). Any other response, errors included, is `no-store` (json below): a
 * 404 for an article not released yet must not outlive its release.
 */
const LIST_CACHE = { "cache-control": "public, max-age=60" };
const ARTICLE_CACHE = { "cache-control": "public, max-age=300" };

const json = (body: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...headers },
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
 * `GET /articles?limit=&cursor=&after=&since=&lang=`: official decisions of the
 * last 7 days in the order they appeared in the feed (`feed_seq`), newest
 * first, so one that appears late lands on top, never between ones already
 * read. `cursor` continues from the previous page; `after` keeps only articles
 * that appeared after a given `feedSeq` (the "N new" check); `since` is the
 * older check by publication time, kept for app builds before `after`. `top`
 * is filled on the first page only.
 *
 * With `lang` other than `en` (#46), the same feed in that language: the same
 * order, the same cursors and `after`, the same top stories, keeping only the
 * articles whose translation into it is shown (release together: every article
 * appears in all languages at once, except where a translation failed or the
 * language is paused). `translationsDelayed` says the language is paused or
 * off, so its newest articles may be missing for a while.
 *
 * With `country` or `group`, and/or `topic` (#67, #68), the same feed keeping
 * only the articles that pass the filters (feedFilters): items, cursors,
 * `after` and top alike. With `for` instead of `country` or `group`, For you
 * (#170): what concerns a reader in that country (forYouCondition).
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

  const lang = readLang(params);
  if (lang === undefined) return badRequest(LANG_ERROR);
  const place = readWhere(params);
  if ("error" in place) return badRequest(place.error);
  const topic = readTopic(params);
  if (topic === undefined) return badRequest(TOPIC_ERROR);
  const filters = feedFilters(place.where, topic);

  const where = [...PAGE_CONDITIONS, ...(lang ? [RECENT_TRANSLATION, ...TRANSLATED_CONDITIONS] : []), ...filters.where];
  // The language is bound in the join (FROM_TRANSLATED), before the conditions.
  const binds: (string | number)[] = [...(lang ? [lang] : []), ...filters.binds];

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
    `SELECT ${lang ? translatedColumns(lang) : ARTICLE_COLUMNS} ${lang ? FROM_TRANSLATED : FROM_ARTICLES}
     WHERE ${where.join(" AND ")}
     ORDER BY a.feed_seq DESC
     LIMIT ?`,
  ).bind(...binds, limit + 1);

  const firstPage = cursorParam === null && sinceParam === null && afterParam === null;
  const topSql = topStories(filters, lang);
  const topQuery = firstPage ? env.DB.prepare(topSql.sql).bind(...topSql.binds) : null;
  const switchQuery = lang ? env.DB.prepare(LANG_SWITCH).bind(lang) : null;
  const [page, ...more] = await env.DB.batch<TranslatedRow & { delayed?: number }>(
    [pageQuery, topQuery, switchQuery].filter((q): q is D1PreparedStatement => q !== null),
  );
  const top = topQuery ? more.shift() : undefined;
  const delayed = switchQuery ? more.shift() : undefined;

  const rows = page.results.slice(0, limit);
  const last = rows.at(-1);
  const nextCursor = page.results.length > limit && last?.feed_seq != null ? encodeCursor(last.feed_seq) : null;
  const shape = (row: TranslatedRow) => (lang ? toTranslatedArticle(row, lang) : toArticle(row));

  return json(
    {
      items: rows.map(shape),
      nextCursor,
      top: top ? top.results.map(shape) : [],
      ...(lang ? { translationsDelayed: delayed?.results[0]?.delayed !== 0 } : {}),
    },
    200,
    LIST_CACHE,
  );
}

/** `GET /articles/:id`: one article shown in the feed (released), or 404. */
async function getArticle(id: string, env: Env): Promise<Response> {
  const row = await env.DB.prepare(`SELECT ${ARTICLE_COLUMNS} ${FROM_ARTICLES} WHERE a.id = ? AND a.is_news = 1 AND a.feed_seq IS NOT NULL`)
    .bind(id)
    .first<ArticleRow>();
  return row ? json(toArticle(row), 200, ARTICLE_CACHE) : json({ error: "Not found" }, 404);
}

// Translated feeds (#46). With `?lang=uk` (any of LANGS) the API shows the
// English feed's articles that have a shown translation into that language, in
// the English order (feed_seq), never an English one mixed in. `lang=en`, or no
// `lang`, is the English feed above, unchanged.

/** A row of `articles` joined with its source and, in a language feed, its translation. */
interface TranslatedRow extends ArticleRow {
  t_headline?: string;
  t_short_summary?: string;
  t_summary?: string;
}

/** The columns of a language feed: the article with its source named in `lang`, and the translation. */
const translatedColumns = (lang: Lang) => `${articleColumns(lang)},
  t.headline AS t_headline, t.short_summary AS t_short_summary, t.summary AS t_summary`;

/**
 * The feed's articles with their translation into the language bound here. The
 * language's `translation_langs` row `l` comes first, one row (RECENT_TRANSLATION);
 * then CROSS JOIN keeps articles the outer loop, so a page walks
 * articles_feed_seq newest first as the English feed does and finds each
 * translation by its primary key.
 */
export const FROM_TRANSLATED = `FROM translation_langs l CROSS JOIN articles a ON l.lang = ?
  JOIN sources s ON s.id = a.source_id
  CROSS JOIN article_translations t ON t.article_id = a.id AND t.lang = l.lang`;

/**
 * A translation that is shown: it has a text (the CHECK constraint of
 * migration 0008 keeps the three fields together), and not one of an older English whose
 * new English used up its tries (SHOWN: not `failed`, unless its text is of the
 * English it failed for).
 */
export const TRANSLATED_CONDITIONS = ["t.headline IS NOT NULL", SHOWN];

/**
 * The language's newest translation (its highest lang_seq; translated_at rises
 * with it) is from the feed's 7 days (#121, Yurii's condition on #89). A
 * translation is written after its article was fetched, and the feed's
 * articles were published in the 7 days, so when the newest is older, none of
 * them has one. One row, through article_translations_lang_seq. It reads only
 * the language's `translation_langs` row `l`, and every language query starts
 * from `l` (CROSS JOIN keeps it the outer loop), so it runs once, before the
 * walk: a language with none (German while it is off) answers its empty feed
 * in a few rows instead of the whole window.
 */
export const RECENT_TRANSLATION = `(SELECT h.translated_at FROM article_translations h
   WHERE h.lang = l.lang AND h.lang_seq IS NOT NULL ORDER BY h.lang_seq DESC LIMIT 1)
   >= strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-7 days')`;

/** The feed's articles after `lang`'s `translation_langs` row `l`, for the top stories (`lang` is one of LANGS). */
const fromLangArticles = (lang: Lang) =>
  `FROM translation_langs l CROSS JOIN articles a ON l.lang = '${lang}' JOIN sources s ON s.id = a.source_id`;

/**
 * A language's top stories: the English top stories (same selection, same
 * order, same filters) that have a shown translation into it, so the language
 * never gets a top story the English feed does not have. Their sources are
 * named in `lang` (#76). Picked only while the language has a translation in
 * the 7 days (RECENT_TRANSLATION). Binds the filters' values, then the language.
 * CROSS JOIN keeps the top stories the outer loop, each translation found
 * by its primary key: with table statistics SQLite would otherwise read every
 * translation into the language first.
 */
const translatedTop = (filters: Filters, lang: Lang) => `
  SELECT top.*, t.headline AS t_headline, t.short_summary AS t_short_summary, t.summary AS t_summary
  FROM (${topQuery(articleColumns(lang), fromLangArticles(lang), `${RECENT_TRANSLATION} AND ${topWhere(filters)}`, filters)}) top
  CROSS JOIN article_translations t ON t.article_id = top.id AND t.lang = ?
  WHERE ${TRANSLATED_CONDITIONS.join(" AND ")}
  ORDER BY top.score DESC, top.published_at DESC, top.id DESC`;

/** 0 while the language is translated as it should be; 1 while it is paused (by hand or automatically) or off. */
const LANG_SWITCH = "SELECT CASE WHEN enabled = 1 AND paused = 0 THEN 0 ELSE 1 END AS delayed FROM translation_langs WHERE lang = ?";

/** `lang`: null for English (absent or `en`), undefined when it is not a language we serve. */
function readLang(params: URLSearchParams): Lang | null | undefined {
  const value = params.get("lang");
  if (value === null || value === "en") return null;
  return isLang(value) ? value : undefined;
}

const LANG_ERROR = `lang must be one of: en, ${LANGS.join(", ")}`;

/**
 * The article in `lang`: its translated headline, short summary and summary,
 * and the language. `feedSeq` and `addedAt` are the English ones: every
 * language has the same feed.
 */
function toTranslatedArticle(row: TranslatedRow, lang: Lang) {
  return {
    ...toArticle(row),
    headline: row.t_headline ?? null,
    shortSummary: row.t_short_summary ?? null,
    summary: row.t_summary ?? null,
    // Not translated yet: English is never mixed into a language feed (#46).
    impact: null,
    lang,
  };
}

/** `GET /articles/:id?lang=uk`: one article shown in the feed, translated into `lang`, or 404 when it is not (yet). */
async function getTranslated(id: string, lang: Lang, env: Env): Promise<Response> {
  const row = await env.DB.prepare(
    `SELECT ${translatedColumns(lang)} ${FROM_TRANSLATED}
     WHERE a.id = ? AND a.is_news = 1 AND a.feed_seq IS NOT NULL AND ${TRANSLATED_CONDITIONS.join(" AND ")}`,
  )
    .bind(lang, id)
    .first<TranslatedRow>();
  return row ? json(toTranslatedArticle(row, lang), 200, ARTICLE_CACHE) : json({ error: "Not found" }, 404);
}

/**
 * The topics of the feed's articles that pass `filters`, one row per article:
 * the English feed's, or with `lang` that language's feed (its articles with a
 * shown translation, as listArticles), whose language is bound first. Counted
 * in the Worker: a GROUP BY over json_each would also count every article's
 * topics, in its temporary table, as rows read (about 850 instead of 180 for
 * the whole feed, live D1, 16 Oct).
 */
export const feedTopics = (filters: Filters, lang: Lang | null = null) =>
  lang
    ? `SELECT a.topics FROM translation_langs l CROSS JOIN articles a ON l.lang = ?
       CROSS JOIN article_translations t ON t.article_id = a.id AND t.lang = l.lang
       WHERE ${[...PAGE_CONDITIONS, RECENT_TRANSLATION, ...TRANSLATED_CONDITIONS, ...filters.where].join(" AND ")}`
    : `SELECT a.topics FROM articles a
       WHERE ${[...PAGE_CONDITIONS, ...filters.where].join(" AND ")}`;

/**
 * `GET /topics?lang=&country=|group=` (#67): the topics with at least one article in
 * the feed's 7 days in `lang` (among that country's or group's, with `country` or `group`),
 * busiest first (ties in the order of TOPICS), named in `lang`. The app builds
 * its Topics menu from it, so a topic with no posts is never offered. Counted
 * on that language's own feed, not the English one: an article can be released
 * without a language's translation (the language paused or off, the translator
 * not running, the translation failed), so a topic can have posts in English
 * and none in that language. Topics read as toArticle reads them. Walks the
 * feed's 7 days through articles_feed_seq: about as many rows as the feed
 * holds (150 to 250), plus one translation per article in a language.
 */
async function listTopics(url: URL, env: Env): Promise<Response> {
  const lang = readLang(url.searchParams);
  if (lang === undefined) return badRequest(LANG_ERROR);
  const place = readWhere(url.searchParams);
  if ("error" in place) return badRequest(place.error);
  const filters = feedFilters(place.where, null);

  const { results } = await env.DB.prepare(feedTopics(filters, lang))
    .bind(...(lang ? [lang] : []), ...filters.binds)
    .all<{ topics: string | null }>();

  const counts = new Map<string, number>();
  for (const row of results) {
    for (const topic of new Set(parseStringArray(row.topics))) counts.set(topic, (counts.get(topic) ?? 0) + 1);
  }
  const names = TOPIC_NAMES[lang ?? "en"];
  const topics = TOPICS.filter((topic) => counts.has(topic))
    // Stable: equal counts keep the order of TOPICS.
    .sort((a, b) => (counts.get(b) ?? 0) - (counts.get(a) ?? 0))
    .map((id) => ({ id, name: names[id] }));
  return json({ topics }, 200, LIST_CACHE);
}

/**
 * `GET /countries?lang=` (#68): the Where menu. `groups`: every group of
 * GROUPS, always, in its fixed order, named in `lang`, with the source
 * countries it shows (`EU` for the EU institutions). `countries`: the countries
 * of active sources (real ones, not the Kickoff seed), without the EU
 * institutions (in the European Union group instead), named in `lang` and
 * sorted by that name. The sources table holds a few dozen rows.
 */
async function listCountries(url: URL, env: Env): Promise<Response> {
  const lang = readLang(url.searchParams);
  if (lang === undefined) return badRequest(LANG_ERROR);
  const nameLang = lang ?? "en";

  const { results } = await env.DB.prepare(
    `SELECT DISTINCT country FROM sources WHERE status = 'active' AND ${REAL_SOURCE}`,
  ).all<{ country: string }>();

  const groups = GROUPS.map((group) => ({ id: group.id, name: groupName(group, nameLang), members: groupCountries(group) }));
  const countries = results
    .map((r) => r.country)
    .filter((code) => /^[A-Z]{2}$/.test(code) && code !== EU)
    .map((code) => ({ code, name: countryName(code, nameLang) }));
  return json({ groups, countries: byName(countries, nameLang) }, 200, LIST_CACHE);
}

/** The country Cloudflare sees the request from, or null: unknown (XX), Tor (T1), or none (a local run). */
function requestCountry(request: Request): string | null {
  const country = (request.cf as { country?: unknown } | undefined)?.country;
  return typeof country === "string" && /^[A-Z]{2}$/.test(country) && country !== "XX" ? country : null;
}

/** The POST paths (#146). */
const POSTS: Record<string, "status" | "credits" | "notifications"> = {
  "/v1/chat/status": "status",
  "/v1/chat/credits": "credits",
  "/v1/appstore/notifications": "notifications",
};

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  // The AI chat by subscription (#146) and Apple's notifications about it: the POSTs.
  const post = POSTS[url.pathname];
  if (post) {
    if (request.method !== "POST") return json({ error: "Method not allowed" }, 405, { allow: "POST" });
    const body = await request.json().catch(() => null);
    const { status, body: answer } = await (post === "notifications"
      ? receiveNotification(body, env)
      : post === "status"
        ? chatStatus(body, env)
        : creditChatPack(body, env));
    return json(answer, status);
  }

  if (request.method !== "GET") return json({ error: "Method not allowed" }, 405, { allow: "GET" });

  if (url.pathname === "/articles") return listArticles(url, env);
  if (url.pathname === "/topics") return listTopics(url, env);
  if (url.pathname === "/countries") return listCountries(url, env);

  const match = url.pathname.match(/^\/articles\/([^/]+)$/);
  if (match) {
    let id: string;
    try {
      id = decodeURIComponent(match[1]);
    } catch {
      return json({ error: "Not found" }, 404);
    }
    const lang = readLang(url.searchParams);
    if (lang === undefined) return badRequest(LANG_ERROR);
    return lang === null ? getArticle(id, env) : getTranslated(id, lang, env);
  }

  // For you (#170): the country the request comes from, for a phone without a region. Never cached (no-store), never stored.
  if (url.pathname === "/locate") return json({ country: requestCountry(request) });

  // Never cached (no-store, json): both show whether the steps are running now.
  if (url.pathname === "/health") {
    return json(await health(env));
  }

  // The translation queue per language and the articles waiting for release (#46): read-only counts and times, no secrets.
  if (url.pathname === "/queue") {
    const [languages, release] = await Promise.all([queueStatus(env), releaseStatus(env)]);
    return json({ languages, release });
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
