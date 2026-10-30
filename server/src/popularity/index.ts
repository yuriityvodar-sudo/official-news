// Popularity per country (#230 step 4): how much each country's readers look
// an item up on Wikipedia, and how much its own media publish about it, from
// open data, for For you's order (step 5). One item a check, every 4 minutes
// (the summarizer's runs at minutes 1, 5, 9…, 15 an hour), each item of the
// last 72 hours again after 12 hours: Wikipedia's views come a day at a time.
// A check sends at most 2 + WIKI_LANGS.length requests outside, within the
// free plan's 50 a run.
import type { Env } from "../env";
import { USER_AGENT } from "../fetcher";
import { isAllowed, robotsFromResponse } from "../fetcher/robots";
import { type MediaLink, GDELT_TIMEOUT_MS, gdeltUrl, mediaFrom } from "./gdelt";
import { WIKI_LANGS } from "./places";
import { mediaScore, viewsScore } from "./score";
import { articlePage, day, languageLinks, readStart, viewsFrom, viewsUrl, USUAL_DAYS } from "./views";

/** The step runs in the summarizer's runs whose minute leaves 1 when divided by this: 1, 5, 9… */
export const POPULARITY_EVERY_MINUTES = 4;
/** Items of the last 72 hours are checked, as the top stories are picked from them. */
export const POPULARITY_HOURS = 72;
/** An item is checked again this long after its last check. */
export const RECHECK_HOURS = 12;
/** Only items of this importance or more: a minor one is never in For you from abroad. */
export const POPULARITY_MIN_IMPORTANCE = 2;

type Get = (url: string, init?: RequestInit) => Promise<Response>;

interface Due {
  id: string;
  published_at: string;
  wikipedia: string | null;
  keywords: string | null;
}

export interface Views {
  lang: string;
  title: string;
  views: number;
  usual: number;
}

const stored = (date: Date) => `${date.toISOString().slice(0, 19)}Z`;

function list(value: string | null): string[] {
  try {
    const parsed: unknown = JSON.parse(value ?? "[]");
    return Array.isArray(parsed) ? parsed.filter((v): v is string => typeof v === "string") : [];
  } catch {
    return [];
  }
}

/**
 * Claims the item to check, in one statement: a released news item of the
 * last POPULARITY_HOURS with something to look for, never checked first, then
 * the most important and the newest, not checked in the last RECHECK_HOURS.
 * The claim (`popularity_at`) keeps an overlapping run from checking it too.
 * The unary + keeps the (is_news, published_at) index, as the top stories do.
 */
async function claim(env: Env, now: Date): Promise<Due | null> {
  return env.DB.prepare(
    `UPDATE articles SET popularity_at = ?1
     WHERE id = (
       SELECT a.id FROM articles a
       WHERE a.is_news = 1 AND +a.feed_seq IS NOT NULL AND a.published_at >= ?2 AND a.importance >= ?3
         AND (COALESCE(a.wikipedia, '[]') != '[]' OR COALESCE(a.keywords, '[]') != '[]')
         AND (a.popularity_at IS NULL OR a.popularity_at < ?4)
       ORDER BY a.popularity_at IS NOT NULL, a.importance DESC, a.published_at DESC
       LIMIT 1)
     RETURNING id, published_at, wikipedia, keywords`,
  )
    .bind(
      stored(now),
      stored(new Date(now.getTime() - POPULARITY_HOURS * 3_600_000)),
      POPULARITY_MIN_IMPORTANCE,
      stored(new Date(now.getTime() - RECHECK_HOURS * 3_600_000)),
    )
    .first<Due>();
}

/**
 * The views of the item's first Wikipedia article in each language of
 * WIKI_LANGS it has: its English page for its titles, then the views a day
 * from USUAL_DAYS before the item to yesterday. Null when the page could not
 * be read (the views already stored stay); an empty list when there is no such
 * article or no day since the item has ended yet.
 */
export async function pageViews(title: string, published: string, now: Date, get: Get): Promise<Views[] | null> {
  // The page is read as the fetcher reads a source's: only where robots.txt allows (CLAUDE.md). The two
  // APIs, Wikimedia's pageviews and GDELT's search, are made for programs.
  const page = new URL(articlePage(title));
  const rules = await get(`${page.origin}/robots.txt`, { headers: { "user-agent": USER_AGENT } });
  const robots = robotsFromResponse(rules.status, rules.ok ? await rules.text() : "");
  if (!isAllowed(robots, page.pathname + page.search)) return null;
  const response = await get(page.href, { headers: { "user-agent": USER_AGENT }, redirect: "follow" });
  if (response.status === 404) return [];
  if (!response.ok) return null;
  const { title: english, links } = languageLinks(await readStart(response));
  const titles = new Map(links);
  titles.set("en", english ?? title);
  const start = published.slice(0, 10).replaceAll("-", "");
  const from = day(new Date(Date.parse(`${published.slice(0, 10)}T00:00:00Z`) - USUAL_DAYS * 86_400_000));
  const to = day(new Date(now.getTime() - 86_400_000));
  if (to < start) return [];
  const langs = WIKI_LANGS.filter((lang) => titles.has(lang));
  const answers = await Promise.all(
    langs.map(async (lang) => {
      const r = await get(viewsUrl(lang, titles.get(lang)!, from, to), { headers: { "user-agent": USER_AGENT } });
      // 404: no views in those days; anything else: not known this time.
      if (!r.ok) return null;
      const counted = viewsFrom(await r.json(), start);
      return counted ? { lang, title: titles.get(lang)!, ...counted } : null;
    }),
  );
  return answers.filter((v): v is Views => v !== null && v.views > 0);
}

/** GDELT's count of the item's coverage by country, or null when GDELT gave no usable answer (429, an error, a timeout). */
export async function coverage(keywords: string[], get: Get): Promise<Map<string, { count: number; links: MediaLink[] }> | null> {
  const url = gdeltUrl(keywords);
  if (!url) return null;
  try {
    const response = await get(url, { headers: { "user-agent": USER_AGENT }, signal: AbortSignal.timeout(GDELT_TIMEOUT_MS) });
    if (!response.ok) return null;
    return mediaFrom(JSON.parse(await response.text()));
  } catch {
    return null;
  }
}

/**
 * Stores a check in one batch: the views per language (replacing that
 * language's row), and, when GDELT answered, the media per country in place of
 * the item's earlier ones.
 */
async function save(env: Env, id: string, views: Views[] | null, media: Map<string, { count: number; links: MediaLink[] }> | null, now: Date) {
  const at = stored(now);
  const statements: D1PreparedStatement[] = [];
  for (const v of views ?? []) {
    statements.push(
      env.DB.prepare(
        `INSERT INTO article_views (article_id, lang, title, views, usual, score, checked_at) VALUES (?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT (article_id, lang) DO UPDATE SET title = excluded.title, views = excluded.views, usual = excluded.usual,
           score = excluded.score, checked_at = excluded.checked_at`,
      ).bind(id, v.lang, v.title, v.views, v.usual, viewsScore(v.views, v.usual), at),
    );
  }
  if (media) {
    statements.push(env.DB.prepare("DELETE FROM article_media WHERE article_id = ?").bind(id));
    for (const [country, m] of media) {
      statements.push(
        env.DB.prepare("INSERT INTO article_media (article_id, country, count, links, score, checked_at) VALUES (?, ?, ?, ?, ?, ?)").bind(
          id,
          country,
          m.count,
          JSON.stringify(m.links),
          mediaScore(m.count),
          at,
        ),
      );
    }
  }
  if (statements.length) await env.DB.batch(statements);
}

/**
 * The popularity step at the end of a summarizer's run (index.ts): one item's
 * check. An error is logged, never thrown: popularity never breaks a run, and
 * the item is checked again after RECHECK_HOURS.
 */
export async function popularityStep(env: Env, scheduledTime: number, now = new Date(), get: Get = fetch): Promise<void> {
  if (new Date(scheduledTime).getUTCMinutes() % POPULARITY_EVERY_MINUTES !== 1) return;
  const started = Date.now();
  try {
    const due = await claim(env, now);
    if (!due) return;
    const title = list(due.wikipedia)[0];
    const [views, media] = await Promise.all([
      title ? pageViews(title, due.published_at, now, get).catch(() => null) : Promise.resolve([] as Views[]),
      coverage(list(due.keywords), get),
    ]);
    await save(env, due.id, views, media, now);
    console.log(
      JSON.stringify({
        message: "popularity",
        id: due.id,
        views: views === null ? "unknown" : views.map((v) => `${v.lang} ${v.views}/${v.usual}`).join(", "),
        media: media === null ? "unknown" : [...media].map(([c, m]) => `${c} ${m.count}`).join(", "),
        // As the fetcher logs its runs: a check that creeps up shows here (the page read is up to 200 KB).
        ms: Date.now() - started,
      }),
    );
  } catch (error) {
    console.error(JSON.stringify({ message: "popularity error", error: error instanceof Error ? error.message : String(error) }));
  }
}
