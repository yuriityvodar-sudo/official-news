// The website's snapshot of the feed (#88). On the site's first day live (30
// Oct) crawlers opened about 4,800 list pages in two hours; each ran the API's
// list, top-stories, countries and topics queries in the site Worker, about
// 960 D1 rows a page, and the free plan's 5 million rows a day ran out. Now
// `site_snapshots` (migration 0023) holds one row per site language with
// everything its list pages show, built here by the api Worker's cron, and
// the site reads that one row per list page, whatever the filter, the page
// or the traffic (site/data.ts; the filtering, paging and top stories are
// worked out in the Worker, site/snapshot.ts). The site runs no SQL of its own
// (scripts/site.check.mjs), so reading the row lives here too.
import { type ListRow, TOP_HOURS, type WhereMenu, activeCountries, parseStringArray, topCandidates, whereMenu, wholeFeed } from ".";
import type { Env } from "../env";
import { LANGS, type Lang } from "../translator";
import type { NameLang } from "./filters";

/** The site's languages (SITE_LANGS in site/texts.ts, which a test checks): English and every language of LANGS. */
export const SNAPSHOT_LANGS: readonly NameLang[] = ["en", ...LANGS];

/** Every language gets a run this often: one language a run, in turn, by the minute of the run (snapshotLang). */
export const SNAPSHOT_EVERY_MINUTES = SNAPSHOT_LANGS.length;

/**
 * A run rebuilds its language when the feed changed since its row (feedVersion),
 * and anyway once the row is this old: the 7-day and 72-hour windows move, a
 * source's status or an article's visibility can change without a release.
 * Measured on a test database of 300 feed articles with 2 countries each:
 * about 2,100 rows for English, 1,800 for a language, 300 for one that is off,
 * about 7,800 a round; 72 forced rounds a day are about 560,000 rows, a
 * release round (every language rebuilt once more) about 8,000.
 */
export const SNAPSHOT_FULL_MS = 20 * 60_000;

/** A snapshot older than this is not served: the cron stopped, and the site reads the API's queries instead (site/data.ts). */
export const SNAPSHOT_MAX_AGE_MS = 30 * 60_000;

/** An article as a list page shows it: the API's fields the site's lists and menus read (site/pages/list.ts, filters.ts, seo.ts), nothing else. */
export interface SnapshotArticle {
  id: string;
  /** The source's country; `countries` what it concerns (#230), for an event's place. */
  country: string;
  countries: string[];
  source: { name: string };
  headline: string | null;
  originalTitle: string;
  shortSummary: string | null;
  decisionType: string | null;
  topics: string[];
  publishedAt: string;
  dateOnly: boolean;
  /** Never null in the feed; typed as the API's, so an API answer is a list of these too. */
  feedSeq: number | null;
  addedAt: string | null;
}

/** What the top stories are picked from (topCandidates in index.ts), scored and ranked per filter in the Worker. */
export interface TopCandidate {
  id: string;
  /** The source's country: at most one top story per source country, unless Where is that country. */
  country: string;
  importance: number;
  publishedAt: string;
  topics: string[];
}

/** One language's row of `site_snapshots`, as JSON. */
export interface Snapshot {
  /** When it was built: the feed as of then. */
  builtAt: string;
  /** The 7-day feed in the language, newest first (feedSeq descending), as GET /articles pages it. */
  articles: SnapshotArticle[];
  /** The English feed's top-story candidates of the last 72 hours; a language shows those of them it has. */
  top: TopCandidate[];
  /** GET /countries in the language. */
  where: WhereMenu;
}

const toSnapshotArticle = (row: ListRow): SnapshotArticle => ({
  id: row.id,
  country: row.country,
  countries: parseStringArray(row.countries),
  source: { name: row.source_name },
  headline: row.headline,
  originalTitle: row.original_title,
  shortSummary: row.short_summary,
  decisionType: row.decision_type,
  topics: parseStringArray(row.topics),
  publishedAt: row.published_at,
  dateOnly: row.date_only === 1,
  feedSeq: row.feed_seq,
  addedAt: row.added_at,
});

type CandidateRow = Pick<ListRow, "id" | "country" | "importance" | "published_at" | "topics">;

const toCandidate = (row: CandidateRow): TopCandidate => ({
  id: row.id,
  country: row.country,
  importance: row.importance ?? 0,
  publishedAt: row.published_at,
  topics: parseStringArray(row.topics),
});

/**
 * The snapshot of `lang`, read from the database in one batch: the language's
 * whole feed (wholeFeed: the feed's articles, each with its source and its
 * countries), the top-story candidates (the last 72 hours with their sources;
 * for English, the ones among the feed's rows) and the active source countries
 * (a few dozen).
 */
export async function buildSnapshot(env: Env, lang: NameLang, now = new Date()): Promise<Snapshot> {
  const feedLang: Lang | null = lang === "en" ? null : lang;
  const [feed, countries, candidates] = await env.DB.batch<ListRow>([
    wholeFeed(env, feedLang),
    activeCountries(env),
    ...(feedLang ? [topCandidates(env)] : []),
  ]);
  const since = `${new Date(now.getTime() - TOP_HOURS * 3_600_000).toISOString().slice(0, 19)}Z`;
  const top = candidates
    ? candidates.results.map(toCandidate)
    : feed.results.filter((row) => row.importance !== null && row.published_at >= since).map(toCandidate);
  return {
    builtAt: `${now.toISOString().slice(0, 19)}Z`,
    articles: feed.results.map(toSnapshotArticle),
    top,
    where: whereMenu(countries.results, lang),
  };
}

/** Writes the snapshot as the language's row, with the feed version it was built from: one UPSERT. */
export async function writeSnapshot(env: Env, lang: NameLang, snapshot: Snapshot, version = ""): Promise<number> {
  const json = JSON.stringify(snapshot);
  await env.DB.prepare(
    `INSERT INTO site_snapshots (lang, json, version, updated_at) VALUES (?1, ?2, ?3, ?4)
     ON CONFLICT (lang) DO UPDATE SET json = excluded.json, version = excluded.version, updated_at = excluded.updated_at`,
  )
    .bind(lang, json, version, snapshot.builtAt)
    .run();
  return json.length;
}

/**
 * What changes a language's feed between releases, one row each through the
 * end of an index (articles_feed_seq, article_translations_lang_seq): the
 * newest release, and the language's newest translation (one written before
 * its release counts too: a rebuild for nothing, once a release round). A
 * released article's texts change only by hand (a re-summary; a translation
 * written again keeps its lang_seq), as a source's status does: the forced
 * rebuild (SNAPSHOT_FULL_MS) carries those. The version as text, with what the
 * language's row holds (`current`, null without a row).
 */
async function feedVersion(env: Env, lang: NameLang) {
  const [feedSeq, row, langSeq] = await env.DB.batch<{ v?: number | null; version?: string; updated_at?: string }>([
    env.DB.prepare("SELECT MAX(feed_seq) AS v FROM articles WHERE feed_seq IS NOT NULL"),
    env.DB.prepare("SELECT version, updated_at FROM site_snapshots WHERE lang = ?").bind(lang),
    ...(lang === "en" ? [] : [env.DB.prepare("SELECT MAX(lang_seq) AS v FROM article_translations WHERE lang = ? AND lang_seq IS NOT NULL").bind(lang)]),
  ]);
  const version = [feedSeq.results[0]?.v, langSeq?.results[0]?.v].map((v) => v ?? "").join("|");
  const current = row.results[0];
  return { version, current: current ? { version: current.version ?? "", updatedAt: current.updated_at ?? "" } : null };
}

/**
 * The language a run rebuilds: by the minute of its scheduled time, so the
 * summarizer's (odd minutes) and the translator's (even minutes) runs together
 * give each language a run every 5 minutes, and every 10 while one of the two
 * triggers is not firing (#50), well within SNAPSHOT_MAX_AGE_MS.
 */
export const snapshotLang = (scheduledTime: number): NameLang => SNAPSHOT_LANGS[new Date(scheduledTime).getUTCMinutes() % SNAPSHOT_LANGS.length];

/**
 * The snapshot step at the end of a summarizer's or translator's run
 * (index.ts), after the release, so a decision released in this run is on the
 * site within 5 minutes: the run's language is rebuilt when its feed changed
 * since its row, or when the row is SNAPSHOT_FULL_MS old; otherwise the run
 * reads 3 rows and leaves it. An error is logged, never thrown: a snapshot
 * never breaks a run, and a stale row only sends the site back to the API's
 * queries.
 */
export async function snapshotStep(env: Env, scheduledTime: number, now = new Date()): Promise<void> {
  const lang = snapshotLang(scheduledTime);
  try {
    const { version, current } = await feedVersion(env, lang);
    if (current && current.version === version && now.getTime() - Date.parse(current.updatedAt) < SNAPSHOT_FULL_MS) return;
    const snapshot = await buildSnapshot(env, lang, now);
    const bytes = await writeSnapshot(env, lang, snapshot, version);
    console.log(JSON.stringify({ message: "site snapshot", lang, articles: snapshot.articles.length, top: snapshot.top.length, bytes }));
  } catch (error) {
    console.error(JSON.stringify({ message: "site snapshot error", lang, error: error instanceof Error ? error.message : String(error) }));
  }
}

/**
 * The language's snapshot, one row, or null when there is none yet or it is
 * older than SNAPSHOT_MAX_AGE_MS (the cron stopped): logged, and the site then
 * reads the API's queries instead, so it never breaks.
 */
export async function readSnapshot(env: Env, lang: NameLang, now = new Date()): Promise<Snapshot | null> {
  const row = await env.DB.prepare("SELECT json, updated_at FROM site_snapshots WHERE lang = ?").bind(lang).first<{ json: string; updated_at: string }>();
  if (!row) {
    console.warn(JSON.stringify({ message: "site snapshot missing", lang }));
    return null;
  }
  const age = now.getTime() - Date.parse(row.updated_at);
  if (!(age <= SNAPSHOT_MAX_AGE_MS)) {
    console.warn(JSON.stringify({ message: "site snapshot stale", lang, updatedAt: row.updated_at }));
    return null;
  }
  return JSON.parse(row.json) as Snapshot;
}
