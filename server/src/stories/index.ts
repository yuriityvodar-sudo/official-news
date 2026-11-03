// Each country's stories (#230, the aggregator, step 2), one D1 row per
// country (`country_stories`, migration 0029), so a reader's request reads one
// row: built by the api Worker's cron, a country in a call of its own
// (`StoryBuilder` in src/index.ts) with its own 10 ms of CPU, when the
// country's outlets have new headlines.
import type { Env } from "../env";
import { parseHeadlines } from "../fetcher/types";
import { type Story, type StoryHeadline, storyScore, topStories } from "./cluster";
import { TITLES, type TitleLang, type Titles, type WriteTitles, storyTitles } from "./titles";
import { buildWorldStories, englishWords, worldDue, worldFailed } from "./world";

export const BUILD = {
  /** Stories are made of the last day's headlines: a story's weight halves every 6 hours, so older ones barely count. */
  windowHours: 24,
  /**
   * At most this many of them, the newest. A build's call starts cold, its code not yet warmed up: on
   * Workers, 2 Nov (Yurii's check of #282), 40 ms of CPU for Germany's 300 headlines and 12 for South
   * Africa's 31, against the 10 ms a call has. With a day of words kept by the fetcher as one string,
   * their numbers and the grouping's loops in WebAssembly, the code warmed up by the Worker's start and
   * the headlines' check without Unicode regexes, Germany's cold build of 300 takes about 4 ms (laptop,
   * docs/decisions/2026-11-03-stories-lighter.md).
   */
  maxHeadlines: 300,
  /** Stories kept per country, the weightiest when built: the app shows the first ones. */
  perCountry: 50,
  /** Countries a run builds at most, each in a call of its own. */
  perRun: 6,
  /** A country is built again at most this often, and only when its outlets have something new... */
  minMinutes: 5,
  /** ...or at least this often, as its oldest headlines leave the window. */
  maxMinutes: 30,
  /** A country whose build failed (its call stopped by a limit) is tried again after this long. */
  failedMinutes: 30,
} as const;

/** A story as kept: with its headline in every language once the model has written it (titles.ts). */
export interface StoredStory extends Story {
  titles?: Titles;
}

/** What `country_stories.json` holds. */
export interface CountryStories {
  builtAt: string;
  stories: StoredStory[];
}

const stored = (date: Date) => `${date.toISOString().slice(0, 19)}Z`;
/** Stored times in order, newest first, without localeCompare's cost. */
const newestFirst = (a: string, b: string) => (a < b ? 1 : a > b ? -1 : 0);

/**
 * Builds a country's stories from its outlets' headlines of the last
 * BUILD.windowHours (the newest BUILD.maxHeadlines) and keeps the weightiest BUILD.perCountry. `version` is
 * the newest headline the run saw, so the next run knows whether anything is new.
 */
export async function buildCountryStories(env: Env, country: string, version: string, now = new Date(), write?: WriteTitles): Promise<number> {
  const { results } = await env.DB.prepare("SELECT id, name, site, headlines FROM outlets WHERE country = ? AND status != 'blocked'")
    .bind(country)
    .all<OutletRow>();
  const headlines = newestHeadlines(results, stored(new Date(now.getTime() - BUILD.windowHours * 3_600_000)), BUILD.maxHeadlines);
  const stories = topStories(headlines, now, BUILD.perCountry);
  // The first stories' headlines in every language (#230 step 3): stored ones, and the model's for new ones.
  const titles = await storyTitles(env, country, stories, write, now);
  const kept: StoredStory[] = stories.map((story) => (titles.has(story.id) ? { ...story, titles: titles.get(story.id) } : story));
  const json = JSON.stringify({ builtAt: stored(now), stories: kept } satisfies CountryStories);
  // The titled ones apart too, with their English headline's words, for the world's stories (world.ts).
  const top = JSON.stringify(kept.flatMap((story) => (story.titles ? [{ ...story, words: englishWords(story.titles.en) }] : [])));
  await env.DB.prepare(
    `INSERT INTO country_stories (country, json, top, version, built_at) VALUES (?1, ?2, ?3, ?4, ?5)
     ON CONFLICT (country) DO UPDATE SET json = excluded.json, top = excluded.top, version = excluded.version, built_at = excluded.built_at, failed_at = NULL`,
  )
    .bind(country, json, top, version, stored(now))
    .run();
  console.log(JSON.stringify({ message: "stories built", country, headlines: headlines.length, stories: stories.length, bytes: json.length }));
  return stories.length;
}

/** An outlet's row as a build reads it. */
export interface OutletRow {
  id: string;
  name: string;
  site: string;
  headlines: string;
}

/**
 * The newest `count` of the outlets' headlines from `cutoff` on, newest first,
 * each with its outlet, two of the same time in the outlets' order. The parsed
 * headlines get their outlet, one object an outlet: copying each of a big
 * country's thousand headlines of the day took a cold call 0.2 ms (3 Nov).
 */
export function newestHeadlines(outlets: OutletRow[], cutoff: string, count: number): StoryHeadline[] {
  const day: StoryHeadline[] = [];
  for (const { id, name, site, headlines } of outlets) {
    const outlet = { id, name, site };
    for (const headline of parseHeadlines(headlines) as StoryHeadline[]) {
      if (headline.publishedAt < cutoff) continue;
      headline.outlet = outlet;
      day.push(headline);
    }
  }
  return day.sort((a, b) => newestFirst(a.publishedAt, b.publishedAt)).slice(0, count);
}

/**
 * The countries due to be built: their outlets have a newer headline than
 * their stories (and those are BUILD.minMinutes old), or their stories are
 * BUILD.maxMinutes old; never built first, then the longest waiting; not one
 * whose last build failed less than BUILD.failedMinutes ago (Yurii's review
 * of #281: a build stopped by a limit would take a call every run). Two small
 * reads: the outlets' newest headline per country (by its index), and the
 * stories' versions.
 */
export async function dueCountries(env: Env, now = new Date()): Promise<{ country: string; version: string }[]> {
  const [newest, built] = await env.DB.batch<Record<string, string | null>>([
    env.DB.prepare("SELECT country, MAX(last_item_at) AS version FROM outlets WHERE status != 'blocked' GROUP BY country"),
    env.DB.prepare("SELECT country, version, built_at, failed_at FROM country_stories"),
  ]);
  const stories = new Map(built.results.map((r) => [r.country!, r]));
  const minutes = (since: string) => (now.getTime() - Date.parse(since)) / 60_000;
  return newest.results
    .filter((r) => r.version !== null)
    .map((r) => ({ country: r.country!, version: r.version!, built: stories.get(r.country!) }))
    .filter(({ version, built }) => {
      if (!built) return true;
      if (built.failed_at && minutes(built.failed_at) < BUILD.failedMinutes) return false;
      const age = minutes(built.built_at!);
      return age >= BUILD.maxMinutes || (version !== built.version && age >= BUILD.minMinutes);
    })
    .sort((a, b) => -newestFirst(a.built?.built_at ?? "", b.built?.built_at ?? ""))
    .slice(0, BUILD.perRun)
    .map(({ country, version }) => ({ country, version }));
}

/** The builds as calls of their own (StoryBuilder in src/index.ts): a country's stories, and the world's. */
export interface StoryCalls {
  build(country: string, version: string): Promise<number>;
  world(): Promise<number>;
}

/**
 * The stories step at the end of the summarizer's and the translator's runs:
 * up to BUILD.perRun due countries, each in a call of its own, then, when one
 * was built, the world's stories (world.ts) in another. Without calls of their
 * own (`wrangler dev`, tests of the runs) one country a run, and the world, in
 * this one. An error is logged, never thrown: the stories never break those runs.
 */
export async function storiesStep(env: Env, own?: StoryCalls, now = new Date()): Promise<void> {
  try {
    const due = await dueCountries(env, now);
    const calls = own ? due : due.slice(0, 1);
    const settled = await Promise.allSettled(calls.map(({ country, version }) => (own ? own.build(country, version) : buildCountryStories(env, country, version, now))));
    if (settled.some((result) => result.status === "fulfilled")) await worldStep(env, own, now);
    const failed = settled.flatMap((result, i) => (result.status === "rejected" ? [{ country: calls[i].country, error: String(result.reason) }] : []));
    if (failed.length) {
      console.error(JSON.stringify({ message: "stories step error", failed }));
      // It waits BUILD.failedMinutes, keeping the stories it has; one never built gets an empty row to wait in.
      await env.DB.batch(
        failed.map(({ country }) =>
          env.DB.prepare(
            `INSERT INTO country_stories (country, json, version, built_at, failed_at) VALUES (?1, '{"builtAt":null,"stories":[]}', '', '1970-01-01T00:00:00Z', ?2)
             ON CONFLICT (country) DO UPDATE SET failed_at = excluded.failed_at`,
          ).bind(country, stored(now)),
        ),
      );
    }
  } catch (error) {
    console.error(JSON.stringify({ message: "stories step error", error: error instanceof Error ? error.message : String(error) }));
  }
}

/** The world's stories when due (worldDue); one that fails waits, logged, and stops nothing else. */
async function worldStep(env: Env, own: StoryCalls | undefined, now: Date): Promise<void> {
  try {
    if (!(await worldDue(env, now))) return;
    await (own ? own.world() : buildWorldStories(env, now));
  } catch (error) {
    console.error(JSON.stringify({ message: "world stories error", error: error instanceof Error ? error.message : String(error) }));
    await worldFailed(env, now);
  }
}

/**
 * A story as the API gives it: its weight now, how many outlets carry it, and
 * its title in the asked language, the model's (`aiTitle`) once written, else
 * the outlets' own headline nearest its centre.
 */
export interface RankedStory extends Story {
  outlets: number;
  score: number;
  aiTitle: boolean;
}

/**
 * The country's stories, the weightiest now first (storyScore at the time of
 * the request), from its one row, titled in `lang`: GET /stories?country=XX,
 * and For you's `stories`.
 */
export async function countryStories(env: Env, country: string, lang: TitleLang = "en", now = new Date()): Promise<{ builtAt: string | null; stories: RankedStory[] }> {
  const row = await env.DB.prepare("SELECT json FROM country_stories WHERE country = ?").bind(country).first<{ json: string }>();
  if (!row) return { builtAt: null, stories: [] };
  const saved = JSON.parse(row.json) as CountryStories;
  const stories = saved.stories
    .map(({ titles, ...story }) => ({
      ...story,
      title: titles?.[lang] ?? story.title,
      aiTitle: titles !== undefined,
      outlets: story.items.length,
      score: Math.round(storyScore(story, now) * 1000) / 1000,
    }))
    .sort((a, b) => b.score - a.score || newestFirst(a.lastSeen, b.lastSeen));
  return { builtAt: saved.builtAt, stories };
}

/** One of a country's stories by its id, as kept, for the chat about it (src/chat/), or null when its last build has none of it. */
export async function countryStory(env: Env, country: string, id: string): Promise<StoredStory | null> {
  const row = await env.DB.prepare("SELECT json FROM country_stories WHERE country = ?").bind(country).first<{ json: string }>();
  return row ? ((JSON.parse(row.json) as CountryStories).stories.find((story) => story.id === id) ?? null) : null;
}

/** For you's `stories` (#230 step 3): the reader's country's first stories carried by TITLES.minOutlets outlets, TITLES.perCountry of them. */
export async function homeStories(env: Env, home: string, lang: TitleLang, now = new Date()): Promise<RankedStory[]> {
  const { stories } = await countryStories(env, home, lang, now);
  return stories.filter((s) => s.outlets >= TITLES.minOutlets).slice(0, TITLES.perCountry);
}

/**
 * A build's call starts cold (#230, 3 Nov): its code runs for the first time
 * in the isolate, compiled as it goes and slow until it has seen its objects.
 * The Worker's start, which no call's CPU counts (a test Worker, 2 Nov), builds
 * the stories of a few made-up headlines once, so that a build's call finds
 * its code ready: Germany's cold build took 3.9 ms instead of 5.2 (laptop),
 * and the start 1.8 ms longer. Two outlets' headlines on one event and one
 * alone, so the build goes through all of its steps; their words written out,
 * as reading them would compile the Unicode regexes at every start.
 */
export const WARM_UP: OutletRow[] = [
  {
    id: "a",
    name: "A",
    site: "https://a.test",
    headlines: JSON.stringify([
      { title: "Minister Novák resigns over the budget", url: "https://a.test/1", publishedAt: "2026-11-03T07:00:00Z", words: "minis ^novák resig over the budge" },
      { title: "Storm warning for the coast", url: "https://a.test/2", publishedAt: "2026-11-03T06:00:00Z", words: "storm warni for the coast" },
    ]),
  },
  {
    id: "b",
    name: "B",
    site: "https://b.test",
    headlines: JSON.stringify([{ title: "Novák quits as minister over the budget", url: "https://b.test/1", publishedAt: "2026-11-03T06:30:00Z", words: "novák quits minis over the budge" }]),
  },
];
export const warmUp = (): Story[] =>
  topStories(newestHeadlines(WARM_UP, "2026-11-02T08:00:00Z", BUILD.maxHeadlines), new Date("2026-11-03T08:00:00Z"), BUILD.perCountry);
try {
  warmUp();
} catch (error) {
  console.error(JSON.stringify({ message: "stories warm-up error", error: error instanceof Error ? error.message : String(error) }));
}
