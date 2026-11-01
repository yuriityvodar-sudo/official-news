// For you's order (#230 step 5, docs/plan.md "Sources and relevance by
// country"): for a reader in country C, the highest score first, where the
// score is importance (1 to 5) + relevance to C + popularity in C (0 to 2,
// popularity/) − half a point a day of age. Relevance is 2 when the item
// concerns C, 1 when it concerns C's neighbours or groups (the EU for its
// members and for Ukraine), and 1 for a global item. From the rest of the
// world at most 2 items a page (forYouCondition picks them, importance 3 or
// more). The list is ranked in the Worker over For you's whole 7 days, a
// little more than a hundred items for one country, and paged by position at
// one moment, which the cursor keeps, so the pages of one scroll agree.
import { COUNTRY_WIKI } from "../popularity/places";
import { POPULARITY_MAX } from "../popularity/score";
import { EU, EU_MEMBERS } from "./filters";

/** Land neighbours of the countries For you serves (#170: those with sources and the EU's 27). */
export const NEIGHBOURS: Readonly<Record<string, readonly string[]>> = {
  AR: ["BO", "BR", "CL", "PY", "UY"],
  AT: ["CH", "CZ", "DE", "HU", "IT", "LI", "SI", "SK"],
  BE: ["DE", "FR", "LU", "NL"],
  BG: ["GR", "MK", "RO", "RS", "TR"],
  BR: ["AR", "BO", "CO", "GY", "PE", "PY", "SR", "UY", "VE"],
  CA: ["US"],
  CN: ["AF", "BT", "IN", "KG", "KP", "KZ", "LA", "MM", "MN", "NP", "PK", "RU", "TJ", "VN"],
  CZ: ["AT", "DE", "PL", "SK"],
  DE: ["AT", "BE", "CH", "CZ", "DK", "FR", "LU", "NL", "PL"],
  DK: ["DE"],
  EE: ["LV", "RU"],
  ES: ["AD", "FR", "MA", "PT"],
  FI: ["NO", "RU", "SE"],
  FR: ["AD", "BE", "CH", "DE", "ES", "IT", "LU", "MC"],
  GB: ["IE"],
  GR: ["AL", "BG", "MK", "TR"],
  HR: ["BA", "HU", "ME", "RS", "SI"],
  HU: ["AT", "HR", "RO", "RS", "SI", "SK", "UA"],
  ID: ["MY", "PG", "TL"],
  IE: ["GB"],
  IN: ["BD", "BT", "CN", "MM", "NP", "PK"],
  IT: ["AT", "CH", "FR", "SI", "SM", "VA"],
  KR: ["KP"],
  LT: ["BY", "LV", "PL", "RU"],
  LU: ["BE", "DE", "FR"],
  LV: ["BY", "EE", "LT", "RU"],
  MX: ["BZ", "GT", "US"],
  NL: ["BE", "DE"],
  PL: ["BY", "CZ", "DE", "LT", "RU", "SK", "UA"],
  PT: ["ES"],
  RO: ["BG", "HU", "MD", "RS", "UA"],
  SE: ["FI", "NO"],
  SI: ["AT", "HR", "HU", "IT"],
  SK: ["AT", "CZ", "HU", "PL", "UA"],
  TR: ["AM", "AZ", "BG", "GE", "GR", "IQ", "IR", "SY"],
  UA: ["BY", "HU", "MD", "PL", "RO", "RU", "SK"],
  US: ["CA", "MX"],
  ZA: ["BW", "LS", "MZ", "NA", "SZ", "ZW"],
};

/** Outside the Union, the countries whose readers the EU's decisions concern as their own group's (the plan: Ukraine). */
const EU_CLOSE = ["UA"];

/** C's neighbours and groups: its land neighbours, and the EU for its members and EU_CLOSE. */
export function nearCountries(home: string): string[] {
  const union = EU_MEMBERS.includes(home) || EU_CLOSE.includes(home) ? [EU] : [];
  return [...(NEIGHBOURS[home] ?? []), ...union];
}

/** The reader's country, checked before it is written into the SQL (readWhere lets through only 2 capital letters). */
function checked(home: string): string {
  if (!/^[A-Z]{2}$/.test(home)) throw new Error(`not a country code: ${home}`);
  return home;
}

/** The codes as SQL text: only 2 capital letters each (the lists are ours, the reader's country is checked). */
const codes = (list: readonly string[]) => list.filter((c) => /^[A-Z]{2}$/.test(c)).map((c) => `'${c}'`).join(", ");

/** Whether article `a` (from source `s`) concerns one of `list`: its source's country, or one the summarizer named (#230). */
const concernsAny = (list: readonly string[]) =>
  list.length
    ? `(s.country IN (${codes(list)}) OR EXISTS (SELECT 1 FROM article_countries c WHERE c.article_id = a.id AND c.country IN (${codes(list)})))`
    : "0";

/** How much the article concerns the reader's country: 2 its own, 1 its neighbours' or group's, else 0 (the rest of the world). */
const concernSql = (home: string) => `CASE WHEN ${concernsAny([checked(home)])} THEN 2 WHEN ${concernsAny(nearCountries(home))} THEN 1 ELSE 0 END`;

/** Relevance in SQL, for the top stories' score (topScore): the concern, or 1 for a global item that concerns neither. */
export const relevanceSql = (home: string) => `MAX(${concernSql(home)}, CASE WHEN a.reach = 'global' THEN 1 ELSE 0 END)`;

/**
 * The same in the Worker, from what the row has read already (its source's
 * country and its `countries`), so ranking For you's 7 days runs no lookup
 * per article for it: the concern (2, 1 or 0) and the relevance.
 */
export function relevanceOf(home: string, sourceCountry: string, countries: string[], reach: string | null): { concern: number; relevance: number } {
  const its = new Set([sourceCountry, ...countries]);
  const concern = its.has(home) ? 2 : nearCountries(home).some((c) => its.has(c)) ? 1 : 0;
  return { concern, relevance: Math.max(concern, reach === "global" ? 1 : 0) };
}

/** Popularity in the reader's country (#230 step 4): its language's Wikipedia views and its media, at most POPULARITY_MAX. */
export function popularitySql(home: string): string {
  const lang = COUNTRY_WIKI[home];
  const views = lang && /^[a-z]{2,3}$/.test(lang) ? `COALESCE((SELECT v.score FROM article_views v WHERE v.article_id = a.id AND v.lang = '${lang}'), 0)` : "0";
  const media = `COALESCE((SELECT m.score FROM article_media m WHERE m.article_id = a.id AND m.country = '${checked(home)}'), 0)`;
  return `MIN(${POPULARITY_MAX}, ${views} + ${media})`;
}

/** The reader's country's links to its own media about the article (#230 step 5: "In the media"), as stored. */
export const mediaLinksSql = (home: string) => `(SELECT m.links FROM article_media m WHERE m.article_id = a.id AND m.country = '${checked(home)}')`;

/** What the ranking reads of a row besides the article. */
export interface Ranked {
  id: string;
  importance: number | null;
  published_at: string;
  concern: number;
  relevance: number;
  popularity: number;
}

/** Half a point a day since publication, as the top stories (TOP_SCORE). */
export const score = (row: Ranked, now: number) => (row.importance ?? 0) + row.relevance + row.popularity - (0.5 * (now - Date.parse(row.published_at))) / 86_400_000;

/** The top stories (#164): of the last 72 hours, with an importance, at most one a source country, TOP_SIZE in all. */
export function topForYou<T extends Ranked & { country: string }>(rows: T[], now: number, size: number, hours: number): T[] {
  const since = now - hours * 3_600_000;
  const compare = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);
  const candidates = rows
    .filter((r) => r.importance !== null && Date.parse(r.published_at) >= since)
    .sort((a, b) => score(b, now) - score(a, now) || compare(b.published_at, a.published_at) || compare(b.id, a.id));
  const countries = new Set<string>();
  const top: T[] = [];
  for (const row of candidates) {
    if (countries.has(row.country)) continue;
    countries.add(row.country);
    top.push(row);
    if (top.length === size) break;
  }
  return top;
}

/** At most this many items a page from the rest of the world (concern 0). */
export const OTHERS_PER_PAGE = 2;

/**
 * For you's whole list in order, in pages of `limit`: the highest score at
 * `now` first, the newer on equal scores, then the higher id. A page takes at
 * most OTHERS_PER_PAGE items from the rest of the world while the reader's
 * own, neighbours' and groups' items last; one more waits for the next page,
 * where its score places it. Once those are all placed, the rest of the world
 * fills the pages, so every page but the last is full and a cursor's position
 * is a page's start.
 */
export function rankForYou<T extends Ranked>(rows: T[], limit: number, now: number): T[] {
  const compare = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);
  const order = (a: T, b: T) => score(b, now) - score(a, now) || compare(b.published_at, a.published_at) || compare(b.id, a.id);
  let pending = [...rows].sort(order);
  const ranked: T[] = [];
  while (pending.length) {
    const page: T[] = [];
    const later: T[] = [];
    let others = 0;
    for (const row of pending) {
      const other = row.concern === 0;
      if (page.length === limit || (other && others === OTHERS_PER_PAGE)) {
        later.push(row);
        continue;
      }
      if (other) others++;
      page.push(row);
    }
    if (!later.some((row) => row.concern > 0)) while (page.length < limit && later.length) page.push(later.shift()!);
    ranked.push(...page.sort(order));
    pending = later;
  }
  return ranked;
}

/**
 * For you's cursor: the moment the list was ranked at, the feed's newest
 * article then (`seq`, its feed_seq), and where the next page starts. Later
 * pages rank the same articles at the same moment, so the pages of one scroll
 * agree; what appeared since comes with the next first page, as "N new" says.
 */
export interface ForYouCursor {
  at: number;
  seq: number;
  offset: number;
}

export const encodeForYouCursor = (cursor: ForYouCursor) =>
  btoa(JSON.stringify(["fy", cursor.at, cursor.seq, cursor.offset])).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");

/** For you's cursor, or null when `value` is not one (a feed cursor, from before #230 step 5, pages the old way). */
export function decodeForYouCursor(value: string): ForYouCursor | null {
  try {
    const parsed: unknown = JSON.parse(atob(value.replaceAll("-", "+").replaceAll("_", "/")));
    if (
      Array.isArray(parsed) &&
      parsed.length === 4 &&
      parsed[0] === "fy" &&
      parsed.slice(1).every((n) => Number.isSafeInteger(n) && (n as number) >= 0)
    ) {
      return { at: parsed[1] as number, seq: parsed[2] as number, offset: parsed[3] as number };
    }
  } catch {
    // Not ours.
  }
  return null;
}

/** For you's ranking is kept this long (Yurii's review of #260): a first page within it reads its articles by id. */
export const RANKING_MINUTES = 5;
/** Rankings older than this are deleted when a new one is written. */
const RANKING_KEPT_MINUTES = 60;

/** Which ranking: the reader's country, the feed's language, the topic ('' for all) and the page size. */
export type RankingKey = readonly [home: string, lang: string, topic: string, size: number];

/** A kept ranking: its moment and newest feed_seq (the cursor's), the articles' ids in order, and the top stories' ids. */
export interface Ranking {
  at: number;
  seq: number;
  ids: string[];
  top: string[];
}

const idList = (value: string): string[] => {
  try {
    const parsed: unknown = JSON.parse(value);
    return Array.isArray(parsed) ? parsed.filter((v): v is string => typeof v === "string") : [];
  } catch {
    return [];
  }
};

/**
 * The kept ranking for a page, or null to rank again: a first page takes the
 * newest one of its key, if it is at most RANKING_MINUTES old and nothing has
 * appeared in the feed since (its `seq` is still the feed's newest: a reader
 * who pulls after "N new" sees them); a later page the one its cursor was
 * made from (the same moment and feed), whatever its age, while it is kept.
 * One row through the primary key, and for a first page the feed's newest
 * number through articles_feed_seq, whose `feed_seq IS NOT NULL` the query
 * must repeat: without it SQLite cannot use the partial index and reads every
 * article ever fetched (#266: 1,048 rows on 31 Oct, growing each day).
 */
export async function keptRanking(db: D1Database, key: RankingKey, cursor: ForYouCursor | null, now: number): Promise<Ranking | null> {
  type Row = { at: number; seq: number; ids: string; top: string; built_at: string; newest?: number | null };
  const row = cursor
    ? await db
        .prepare("SELECT at, seq, ids, top, built_at FROM for_you_rankings WHERE home = ? AND lang = ? AND topic = ? AND size = ? AND at = ?")
        .bind(...key, cursor.at)
        .first<Row>()
    : await db
        .prepare(
          `SELECT at, seq, ids, top, built_at, (SELECT MAX(feed_seq) FROM articles WHERE feed_seq IS NOT NULL) AS newest
           FROM for_you_rankings WHERE home = ? AND lang = ? AND topic = ? AND size = ? ORDER BY at DESC LIMIT 1`,
        )
        .bind(...key)
        .first<Row>();
  if (!row) return null;
  if (cursor ? row.seq !== cursor.seq : !(now - Date.parse(row.built_at) <= RANKING_MINUTES * 60_000) || (row.newest ?? 0) > row.seq) return null;
  return { at: row.at, seq: row.seq, ids: idList(row.ids), top: idList(row.top) };
}

/** Keeps a ranking, and deletes the ones older than RANKING_KEPT_MINUTES (a few dozen rows at most). */
export async function keepRanking(db: D1Database, key: RankingKey, ranking: Ranking, now: number): Promise<void> {
  const stored = (ms: number) => `${new Date(ms).toISOString().slice(0, 19)}Z`;
  await db.batch([
    db.prepare("DELETE FROM for_you_rankings WHERE built_at < ?").bind(stored(now - RANKING_KEPT_MINUTES * 60_000)),
    db
      .prepare(
        `INSERT INTO for_you_rankings (home, lang, topic, size, at, seq, ids, top, built_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT (home, lang, topic, size, at) DO UPDATE SET seq = excluded.seq, ids = excluded.ids, top = excluded.top, built_at = excluded.built_at`,
      )
      .bind(...key, ranking.at, ranking.seq, JSON.stringify(ranking.ids), JSON.stringify(ranking.top), stored(now)),
  ]);
}
