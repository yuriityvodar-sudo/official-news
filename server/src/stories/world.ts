// The world's stories (#230, the aggregator step 4): an event that the outlets
// of several countries carry, which the app shows as ticks (Roman, 3 Nov: the
// glass capsule of handoff/tick-strip.html, time first and the AI's mark on the
// right; a tap opens the AI chat). Found by the English headline the model
// wrote for each country's first stories (titles.ts), grouped as a country's
// headlines are (cluster.ts), so no AI call of their own. On 3 Nov at 10:00
// UTC, 73 titled stories of 23 countries gave 6 events of 2 countries or more,
// the US strikes on Qeshm in 5, none joined wrongly. One D1 row
// (`world_stories`, migration 0033), built in a call of its own.
import type { Env } from "../env";
import type { OutletHeadline } from "../fetcher/types";
import { STORIES, type StoryHeadline, hash, itemWeight, topStories } from "./cluster";
import type { StoredStory } from "./index";
import { type TitleLang, type Titles, isDigit, isLetter } from "./titles";

export const WORLD = {
  /** An event in this many countries' first stories or more is the world's; the world's own outlets (WW) count as a country. */
  minCountries: 2,
  /** The weightiest kept when built. */
  count: 12,
  /** Each one's outlets' latest headlines, the most recent first, at most this many: for the chat. */
  items: 20,
  /** Built again at most this often, after a country's stories were built. */
  minMinutes: 5,
  /** For you's first page gives at most this many as ticks: two, one and two before its decisions (handoff/tick-strip.html). */
  forYou: 5,
} as const;

/**
 * A country's story with its headline in every language, and that headline's
 * words (englishWords), read by the country's build: what `country_stories.top`
 * holds. The world's call reads them as they are: on a laptop, reading 73
 * headlines' words took a cold call 1.2 of its 3 ms (3 Nov).
 */
export type TitledStory = StoredStory & { titles: Titles; words?: string };

/** An outlet's headline on a world story, with the outlet's country. */
export type WorldItem = OutletHeadline & { country: string };

/** A world story as kept. */
export interface WorldStory {
  id: string;
  /** The model's headline of the story nearest the event's centre, of one of its countries. */
  titles: Titles;
  /** Each country's story on it, the most recent first: its last headline on it is the country's weight. */
  stories: { country: string; id: string; lastSeen: string }[];
  /** All its countries' outlets, how many. */
  outlets: number;
  items: WorldItem[];
  firstSeen: string;
  lastSeen: string;
}

/** What `world_stories.json` holds. */
export interface WorldStories {
  builtAt: string;
  stories: WorldStory[];
}

const stored = (date: Date) => `${date.toISOString().slice(0, 19)}Z`;
const newestFirst = (a: string, b: string) => (a < b ? 1 : a > b ? -1 : 0);

// The characters as cluster.ts reads a headline's words, by their codes: the
// model writes these headlines in Latin letters, and Unicode regexes take a
// call that starts cold milliseconds to compile (titles.ts).
const isMark = (c: number) => c >= 0x300 && c <= 0x36f;
const isSpace = (c: number) => c === 32 || (c >= 9 && c <= 13) || c === 0xa0 || c === 0x1680 || (c >= 0x2000 && c <= 0x200a) || c === 0x2028 || c === 0x2029 || c === 0x202f || c === 0x205f || c === 0x3000;
/** What may stand between a phrase's end and its first word, and what ends a phrase (cluster.ts). */
const PASSED = new Set([..."\"'«»„“”‚‘’()[]"]);
const PHRASE_END = new Set([..."．.!?:;…|-–—"]);

function phraseStart(text: string, index: number): boolean {
  for (let i = index - 1; i >= 0; i--) {
    if (isSpace(text.charCodeAt(i)) || PASSED.has(text[i])) continue;
    return PHRASE_END.has(text[i]);
  }
  return true;
}

/**
 * An English headline's words as cluster.ts keeps a headline's (headlineWords):
 * a word's first STORIES.stemLength letters if it has STORIES.minWordLength, a
 * number whole, a name's with "^" first.
 */
export function englishWords(title: string): string {
  const found = new Map<string, boolean>();
  let start = -1;
  for (let i = 0; i <= title.length; i++) {
    const c = i < title.length ? title.charCodeAt(i) : 32;
    if (isLetter(c) || isDigit(c) || isMark(c)) {
      if (start < 0) start = i;
      continue;
    }
    if (start < 0) continue;
    const word = title.slice(start, i);
    let digits = true;
    for (let k = 0; k < word.length && digits; k++) digits = isDigit(word.charCodeAt(k));
    const term = digits ? word : word.length >= STORIES.minWordLength ? word.toLowerCase().slice(0, STORIES.stemLength) : "";
    if (term) {
      const name = word[0] !== word[0].toLowerCase() && !phraseStart(title, start);
      found.set(term, name || (found.get(term) ?? false));
    }
    start = -1;
  }
  const words: string[] = [];
  for (const [term, name] of found) words.push(name ? `^${term}` : term);
  return words.join(" ");
}

/** A world story's weight at `now`: each country on it counts 1, halved every STORIES.halfLifeHours since its last headline on it. */
export function worldScore(story: WorldStory, now: Date): number {
  const latest = new Map<string, string>();
  for (const { country, lastSeen } of story.stories) if ((latest.get(country) ?? "") < lastSeen) latest.set(country, lastSeen);
  let sum = 0;
  for (const lastSeen of latest.values()) sum += itemWeight(lastSeen, now);
  return sum;
}

/**
 * The world's stories from the countries' titled stories (`country_stories.top`):
 * their English headlines grouped as one country's headlines are, each story a
 * headline of its own; an event of WORLD.minCountries countries or more is the
 * world's, the WORLD.count weightiest kept. A world story keeps the id it had
 * in the last build (`before`, a country's story to its world story's id) when
 * most of the stories that had it are in it again, so a tick's chat finds it
 * after a build; `ids` is the same for the next build.
 */
export function worldStories(countries: { country: string; top: string }[], before: Record<string, string>, now: Date): { stories: WorldStory[]; ids: Record<string, string> } {
  const titled = new Map<string, { country: string; story: TitledStory }>();
  const headlines: StoryHeadline[] = [];
  for (const { country, top } of countries) {
    for (const story of JSON.parse(top) as TitledStory[]) {
      const key = `${country}/${story.id}`;
      titled.set(key, { country, story });
      headlines.push({ title: story.titles.en, url: key, publishedAt: story.lastSeen, outlet: { id: key, name: country, site: "" }, words: story.words ?? englishWords(story.titles.en) });
    }
  }
  const taken = new Set<string>();
  const world: WorldStory[] = [];
  for (const group of topStories(headlines, now, headlines.length)) {
    const parts = group.items.map((item) => titled.get(item.url)!);
    if (new Set(parts.map((p) => p.country)).size < WORLD.minCountries) continue;
    // Each outlet's latest headline on it, of any of its countries' stories.
    const latest = new Map<string, WorldItem>();
    for (const { country, story } of parts) {
      for (const item of story.items) if ((latest.get(item.outlet.id)?.publishedAt ?? "") < item.publishedAt) latest.set(item.outlet.id, { ...item, country });
    }
    const items = [...latest.values()].sort((a, b) => newestFirst(a.publishedAt, b.publishedAt));
    const first = parts.reduce((a, b) => (b.story.firstSeen < a.story.firstSeen ? b : a));
    // The id most of its stories had, unless a weightier one took it; else its first story's.
    const votes = new Map<string, number>();
    for (const { country, story } of parts) {
      const id = before[`${country}/${story.id}`];
      if (id && !taken.has(id)) votes.set(id, (votes.get(id) ?? 0) + 1);
    }
    const id = [...votes].sort((a, b) => b[1] - a[1])[0]?.[0] ?? hash(`${first.country}/${first.story.id}`);
    taken.add(id);
    world.push({
      id,
      titles: (parts.find((p) => p.story.titles.en === group.title) ?? parts[0]).story.titles,
      stories: parts.map(({ country, story }) => ({ country, id: story.id, lastSeen: story.lastSeen })).sort((a, b) => newestFirst(a.lastSeen, b.lastSeen)),
      outlets: items.length,
      items: items.slice(0, WORLD.items),
      firstSeen: first.story.firstSeen,
      lastSeen: items[0].publishedAt,
    });
  }
  const stories = world.sort((a, b) => worldScore(b, now) - worldScore(a, now) || newestFirst(a.lastSeen, b.lastSeen)).slice(0, WORLD.count);
  const ids: Record<string, string> = {};
  for (const story of stories) for (const part of story.stories) ids[`${part.country}/${part.id}`] = story.id;
  return { stories, ids };
}

/** Builds the world's stories (worldStories) into their one row, from the countries' rows: a call of its own. */
export async function buildWorldStories(env: Env, now = new Date()): Promise<number> {
  const [countries, last] = await env.DB.batch<Record<string, string | null>>([
    env.DB.prepare("SELECT country, top FROM country_stories WHERE top IS NOT NULL"),
    env.DB.prepare("SELECT ids FROM world_stories WHERE id = 1"),
  ]);
  const before = JSON.parse(last.results[0]?.ids ?? "{}") as Record<string, string>;
  const { stories, ids } = worldStories(countries.results as { country: string; top: string }[], before, now);
  const json = JSON.stringify({ builtAt: stored(now), stories } satisfies WorldStories);
  await env.DB.prepare(
    `INSERT INTO world_stories (id, json, ids, built_at) VALUES (1, ?1, ?2, ?3)
     ON CONFLICT (id) DO UPDATE SET json = excluded.json, ids = excluded.ids, built_at = excluded.built_at, failed_at = NULL`,
  )
    .bind(json, JSON.stringify(ids), stored(now))
    .run();
  console.log(JSON.stringify({ message: "world stories built", countries: countries.results.length, stories: stories.length, bytes: json.length }));
  return stories.length;
}

/** Built after a country's stories, when the world's are WORLD.minMinutes old, and not again within that of a build that failed. */
export async function worldDue(env: Env, now = new Date()): Promise<boolean> {
  const row = await env.DB.prepare("SELECT built_at, failed_at FROM world_stories WHERE id = 1").first<{ built_at: string; failed_at: string | null }>();
  const minutes = (since: string | null) => (since ? (now.getTime() - Date.parse(since)) / 60_000 : Infinity);
  return !row || (minutes(row.built_at) >= WORLD.minMinutes && minutes(row.failed_at) >= WORLD.minMinutes);
}

/** A build that failed (its call stopped by a limit) waits WORLD.minMinutes, keeping the stories it has. */
export async function worldFailed(env: Env, now = new Date()): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO world_stories (id, json, ids, built_at, failed_at) VALUES (1, '{"builtAt":null,"stories":[]}', '{}', '1970-01-01T00:00:00Z', ?1)
     ON CONFLICT (id) DO UPDATE SET failed_at = excluded.failed_at`,
  )
    .bind(stored(now))
    .run();
}

/** One world story by its id, as kept, for the chat about a tick (src/chat/), or null when the last build has none of it. */
export async function worldStory(env: Env, id: string): Promise<WorldStory | null> {
  const row = await env.DB.prepare("SELECT json FROM world_stories WHERE id = 1").first<{ json: string }>();
  return row ? ((JSON.parse(row.json) as WorldStories).stories.find((story) => story.id === id) ?? null) : null;
}

/** A world story as the API gives it: its headline in the asked language, its countries, and its weight now. */
export interface Tick extends Omit<WorldStory, "titles"> {
  title: string;
  countries: string[];
  score: number;
}

/**
 * For you's `ticks` (#230 step 4): the world's stories, the weightiest now
 * first, but those with a story of the reader's country among the `stories`
 * For you shows them with, WORLD.forYou of them.
 */
export async function homeTicks(env: Env, home: string, shown: { id: string }[], lang: TitleLang, now = new Date()): Promise<Tick[]> {
  const ids = new Set(shown.map((story) => story.id));
  const { ticks } = await worldTicks(env, lang, now);
  return ticks.filter((tick) => !tick.stories.some((s) => s.country === home && ids.has(s.id))).slice(0, WORLD.forYou);
}

/** The world's stories, the weightiest now first, titled in `lang`: GET /ticks. */
export async function worldTicks(env: Env, lang: TitleLang = "en", now = new Date()): Promise<{ builtAt: string | null; ticks: Tick[] }> {
  const row = await env.DB.prepare("SELECT json FROM world_stories WHERE id = 1").first<{ json: string }>();
  if (!row) return { builtAt: null, ticks: [] };
  const saved = JSON.parse(row.json) as WorldStories;
  const ticks = saved.stories
    .map(({ titles, ...story }) => ({
      ...story,
      title: titles[lang],
      countries: [...new Set(story.stories.map((s) => s.country))],
      score: Math.round(worldScore({ titles, ...story }, now) * 1000) / 1000,
    }))
    .sort((a, b) => b.score - a.score || newestFirst(a.lastSeen, b.lastSeen));
  return { builtAt: saved.builtAt, ticks };
}
