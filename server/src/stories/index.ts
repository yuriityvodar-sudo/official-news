// Each country's stories (#230, the aggregator, step 2), one D1 row per
// country (`country_stories`, migration 0029), so a reader's request reads one
// row: built by the api Worker's cron, a country in a call of its own
// (`StoryBuilder` in src/index.ts) with its own 10 ms of CPU, when the
// country's outlets have new headlines.
import type { Env } from "../env";
import { type OutletHeadline, parseHeadlines } from "../fetcher/types";
import { type Story, clusterHeadlines, storyScore } from "./cluster";

export const BUILD = {
  /** Stories are made of the last day's headlines: a story's weight halves every 6 hours, so older ones barely count. */
  windowHours: 24,
  /**
   * At most this many of them, the newest: grouping took up to 7 ms of CPU for India's 439 headlines of
   * 1 Nov (laptop), of the 10 ms a call has.
   */
  maxHeadlines: 450,
  /** Stories kept per country, the weightiest when built. */
  perCountry: 100,
  /** Countries a run builds at most, each in a call of its own. */
  perRun: 6,
  /** A country is built again at most this often, and only when its outlets have something new... */
  minMinutes: 5,
  /** ...or at least this often, as its oldest headlines leave the window. */
  maxMinutes: 30,
} as const;

/** What `country_stories.json` holds. */
export interface CountryStories {
  builtAt: string;
  stories: Story[];
}

const stored = (date: Date) => `${date.toISOString().slice(0, 19)}Z`;

/**
 * Builds a country's stories from its outlets' headlines of the last
 * BUILD.windowHours (the newest BUILD.maxHeadlines) and keeps the weightiest BUILD.perCountry. `version` is
 * the newest headline the run saw, so the next run knows whether anything is new.
 */
export async function buildCountryStories(env: Env, country: string, version: string, now = new Date()): Promise<number> {
  const { results } = await env.DB.prepare("SELECT id, name, site, headlines FROM outlets WHERE country = ? AND status != 'blocked'")
    .bind(country)
    .all<{ id: string; name: string; site: string; headlines: string }>();
  const cutoff = stored(new Date(now.getTime() - BUILD.windowHours * 3_600_000));
  const headlines: OutletHeadline[] = results
    .flatMap((o) =>
      parseHeadlines(o.headlines)
        .filter((h) => h.publishedAt >= cutoff)
        .map((h) => ({ ...h, outlet: { id: o.id, name: o.name, site: o.site } })),
    )
    .sort((a, b) => b.publishedAt.localeCompare(a.publishedAt))
    .slice(0, BUILD.maxHeadlines);
  const stories = clusterHeadlines(headlines)
    .map((story) => ({ story, score: storyScore(story, now) }))
    .sort((a, b) => b.score - a.score)
    .slice(0, BUILD.perCountry)
    .map(({ story }) => story);
  const json = JSON.stringify({ builtAt: stored(now), stories } satisfies CountryStories);
  await env.DB.prepare(
    `INSERT INTO country_stories (country, json, version, built_at) VALUES (?1, ?2, ?3, ?4)
     ON CONFLICT (country) DO UPDATE SET json = excluded.json, version = excluded.version, built_at = excluded.built_at`,
  )
    .bind(country, json, version, stored(now))
    .run();
  console.log(JSON.stringify({ message: "stories built", country, headlines: headlines.length, stories: stories.length, bytes: json.length }));
  return stories.length;
}

/**
 * The countries due to be built: their outlets have a newer headline than
 * their stories (and those are BUILD.minMinutes old), or their stories are
 * BUILD.maxMinutes old; never built first, then the longest waiting. Two small
 * reads: the outlets' newest headline per country (by its index), and the
 * stories' versions.
 */
export async function dueCountries(env: Env, now = new Date()): Promise<{ country: string; version: string }[]> {
  const [newest, built] = await env.DB.batch<Record<string, string | null>>([
    env.DB.prepare("SELECT country, MAX(last_item_at) AS version FROM outlets WHERE status != 'blocked' GROUP BY country"),
    env.DB.prepare("SELECT country, version, built_at FROM country_stories"),
  ]);
  const stories = new Map(built.results.map((r) => [r.country!, r]));
  const minutes = (since: string) => (now.getTime() - Date.parse(since)) / 60_000;
  return newest.results
    .filter((r) => r.version !== null)
    .map((r) => ({ country: r.country!, version: r.version!, built: stories.get(r.country!) }))
    .filter(({ version, built }) => {
      if (!built) return true;
      const age = minutes(built.built_at!);
      return age >= BUILD.maxMinutes || (version !== built.version && age >= BUILD.minMinutes);
    })
    .sort((a, b) => (a.built?.built_at ?? "").localeCompare(b.built?.built_at ?? ""))
    .slice(0, BUILD.perRun)
    .map(({ country, version }) => ({ country, version }));
}

/**
 * The stories step at the end of the summarizer's and the translator's runs:
 * up to BUILD.perRun due countries, each in a call of its own. Without calls
 * of their own (`wrangler dev`, tests of the runs) one country a run, in this
 * one. An error is logged, never thrown: the stories never break those runs.
 */
export async function storiesStep(env: Env, build?: (country: string, version: string) => Promise<number>, now = new Date()): Promise<void> {
  try {
    const due = await dueCountries(env, now);
    const calls = build ? due : due.slice(0, 1);
    const settled = await Promise.allSettled(calls.map(({ country, version }) => (build ?? ((c, v) => buildCountryStories(env, c, v, now)))(country, version)));
    const failed = settled.flatMap((result, i) => (result.status === "rejected" ? [{ country: calls[i].country, error: String(result.reason) }] : []));
    if (failed.length) console.error(JSON.stringify({ message: "stories step error", failed }));
  } catch (error) {
    console.error(JSON.stringify({ message: "stories step error", error: error instanceof Error ? error.message : String(error) }));
  }
}

/** A story as `GET /stories` gives it: its weight now and how many outlets carry it. */
export interface RankedStory extends Story {
  outlets: number;
  score: number;
}

/**
 * GET /stories?country=XX: the country's stories, the weightiest now first
 * (storyScore at the time of the request), from its one row.
 */
export async function countryStories(env: Env, country: string, now = new Date()): Promise<{ builtAt: string | null; stories: RankedStory[] }> {
  const row = await env.DB.prepare("SELECT json FROM country_stories WHERE country = ?").bind(country).first<{ json: string }>();
  if (!row) return { builtAt: null, stories: [] };
  const saved = JSON.parse(row.json) as CountryStories;
  const stories = saved.stories
    .map((story) => ({ ...story, outlets: story.items.length, score: Math.round(storyScore(story, now) * 1000) / 1000 }))
    .sort((a, b) => b.score - a.score || b.lastSeen.localeCompare(a.lastSeen));
  return { builtAt: saved.builtAt, stories };
}
