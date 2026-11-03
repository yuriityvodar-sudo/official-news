import { env, exports } from "cloudflare:workers";
import { createScheduledController } from "cloudflare:test";
import { describe, expect, it, vi } from "vitest";
import worker, { CRONS } from "../src/index";
import { buildCountryStories, storiesStep } from "../src/stories";
import { headlineWords } from "../src/stories/cluster";
import { type Tick, type TitledStory, WORLD, type WorldStories, buildWorldStories, englishWords } from "../src/stories/world";
import { TITLED_STORIES_2026_11_03 } from "./fixtures/titled-stories-2026-11-03";
import { chat, fakeAi } from "./helpers";

/** The fixture's time. */
const NOW = new Date("2026-11-03T10:00:00Z");
const stored = (date: Date) => `${date.toISOString().slice(0, 19)}Z`;

/** The fixture's countries' titled stories as their builds keep them (`country_stories.top`), but `without` some. */
async function addCountries(without: (country: string, story: TitledStory) => boolean = () => false) {
  const byCountry = new Map<string, TitledStory[]>();
  for (const { country, story } of TITLED_STORIES_2026_11_03) {
    if (!without(country, story)) byCountry.set(country, [...(byCountry.get(country) ?? []), story]);
  }
  await env.DB.prepare("DELETE FROM country_stories").run();
  for (const [country, stories] of byCountry) {
    await env.DB.prepare(`INSERT INTO country_stories (country, json, top, version, built_at) VALUES (?, '{"builtAt":null,"stories":[]}', ?, 'v', ?)`)
      .bind(country, JSON.stringify(stories), stored(NOW))
      .run();
  }
}

const worldRow = async () => {
  const row = await env.DB.prepare("SELECT json, ids, built_at, failed_at FROM world_stories WHERE id = 1").first<{ json: string; ids: string; built_at: string; failed_at: string | null }>();
  return row && { ...row, saved: JSON.parse(row.json) as WorldStories };
};
const countriesOf = (story: { stories: { country: string }[] }) => [...new Set(story.stories.map((s) => s.country))].sort();

describe("the world's stories (#230 step 4)", () => {
  it("reads the model's English headlines as cluster.ts reads a headline, without Unicode regexes", () => {
    for (const { story } of TITLED_STORIES_2026_11_03) expect(englishWords(story.titles.en)).toBe(headlineWords(story.titles.en));
    expect(englishWords("US strikes Iran's Qeshm Island — 20,000 flee")).toBe("strik ^iran ^qeshm ^islan 20 000 flee");
  });

  it("finds the events several countries carry, by their stories' English headlines, and joins none wrongly", async () => {
    vi.spyOn(console, "log").mockImplementation(() => {});
    await addCountries();
    expect(await buildWorldStories(env, NOW)).toBe(6);
    const { saved } = (await worldRow())!;
    const found = saved.stories.map((s) => [countriesOf(s), s.titles.en]);
    // The US strikes on Qeshm, in 5 countries' first stories: told 5 ways.
    expect(found).toContainEqual([["BR", "FR", "UA", "US", "WW"], expect.stringContaining("Qeshm")]);
    expect(found).toContainEqual([["AR", "ES", "IT"], expect.stringContaining("Jesús de Miguel")]);
    expect(found).toContainEqual([["BR", "PL"], expect.stringContaining("Everest")]);
    expect(found).toContainEqual([["DE", "US"], expect.stringContaining("measles")]);
    expect(found).toContainEqual([["US", "WW"], expect.stringContaining("California")]);
    expect(found).toContainEqual([["AR", "DE"], expect.stringContaining("cardiac arrest")]);
    expect(saved.stories.every((s) => countriesOf(s).length >= WORLD.minCountries)).toBe(true);
  });

  it("gives each one its outlets' latest headlines with their countries, the most recent first, and one of its stories' headlines", async () => {
    vi.spyOn(console, "log").mockImplementation(() => {});
    await addCountries();
    await buildWorldStories(env, NOW);
    const qeshm = (await worldRow())!.saved.stories.find((s) => s.titles.en.includes("Qeshm"))!;
    const fixture = TITLED_STORIES_2026_11_03.filter(({ country, story }) => qeshm.stories.some((s) => s.country === country && s.id === story.id));
    expect(fixture.map((f) => f.story.titles)).toContainEqual(qeshm.titles);
    const outlets = new Set(fixture.flatMap((f) => f.story.items.map((i) => i.outlet.id)));
    expect(qeshm.outlets).toBe(outlets.size);
    expect(qeshm.items.length).toBe(Math.min(outlets.size, WORLD.items));
    expect(new Set(qeshm.items.map((i) => i.outlet.id)).size).toBe(qeshm.items.length);
    expect(qeshm.items.every((item, i) => i === 0 || qeshm.items[i - 1].publishedAt >= item.publishedAt)).toBe(true);
    expect(qeshm.items[0]).toMatchObject({ country: expect.stringMatching(/^[A-Z]{2}$/), outlet: { id: expect.any(String), name: expect.any(String) } });
    expect(qeshm.lastSeen).toBe(qeshm.items[0].publishedAt);
    expect(qeshm.firstSeen).toBe(fixture.map((f) => f.story.firstSeen).sort()[0]);
  });

  it("keeps a world story's id when a build finds most of its stories again", async () => {
    vi.spyOn(console, "log").mockImplementation(() => {});
    await addCountries();
    await buildWorldStories(env, NOW);
    const first = (await worldRow())!.saved.stories;
    const qeshm = first.find((s) => s.titles.en.includes("Qeshm"))!;
    // The world's outlets' story on it has left their first stories.
    await addCountries((country, story) => country === "WW" && story.titles.en.includes("Qeshm"));
    await buildWorldStories(env, new Date(NOW.getTime() + WORLD.minMinutes * 60_000));
    const again = (await worldRow())!.saved.stories;
    expect(again.find((s) => s.titles.en.includes("Qeshm"))).toMatchObject({ id: qeshm.id });
    expect(countriesOf(again.find((s) => s.id === qeshm.id)!)).toEqual(["BR", "FR", "UA", "US"]);
    expect(new Set(again.map((s) => s.id)).size).toBe(again.length);
    expect(JSON.parse((await worldRow())!.ids)[`US/${qeshm.stories.find((s) => s.country === "US")!.id}`]).toBe(qeshm.id);
  });
});

describe("GET /ticks (#230 step 4)", () => {
  const get = async (path: string) => {
    const response = await exports.default.fetch(`https://api.test${path}`);
    return { status: response.status, cache: response.headers.get("cache-control"), body: (await response.json()) as { builtAt: string | null; ticks: Tick[] } };
  };

  it("gives the world's stories in the asked language, the weightiest now first, with their countries", async () => {
    vi.spyOn(console, "log").mockImplementation(() => {});
    await addCountries();
    await buildWorldStories(env, new Date());
    const { status, cache, body } = await get("/ticks?lang=ru");
    expect([status, cache]).toEqual([200, "public, max-age=60"]);
    expect(body.builtAt).toEqual(expect.any(String));
    expect(body.ticks).toHaveLength(6);
    const qeshm = body.ticks.find((t) => t.countries.length === 5)!;
    expect(qeshm.title).toMatch(/Кешм/);
    expect(qeshm.countries.sort()).toEqual(["BR", "FR", "UA", "US", "WW"]);
    expect(body.ticks.every((t, i) => i === 0 || body.ticks[i - 1].score >= t.score)).toBe(true);
    expect(qeshm).not.toHaveProperty("titles");
    expect((await get("/ticks")).body.ticks.find((t) => t.id === qeshm.id)?.title).toMatch(/Qeshm/);
  });

  it("refuses a language it has not, and gives none before the first build", async () => {
    expect((await get("/ticks?lang=xx")).status).toBe(400);
    expect((await get("/ticks")).body).toEqual({ builtAt: null, ticks: [] });
  });
});

describe("For you's ticks (#230 step 4)", () => {
  it("gives the world's stories on For you's first page, but those it shows as the reader's country's stories, WORLD.forYou at most", async () => {
    vi.spyOn(console, "log").mockImplementation(() => {});
    await addCountries();
    // The US row as its build keeps it: its titled stories are its first ones.
    const us = TITLED_STORIES_2026_11_03.filter((s) => s.country === "US").map((s) => s.story);
    await env.DB.prepare("UPDATE country_stories SET json = ? WHERE country = 'US'").bind(JSON.stringify({ builtAt: stored(NOW), stories: us })).run();
    await buildWorldStories(env, new Date());
    const get = async (path: string) => (await exports.default.fetch(`https://api.test${path}`)).json() as Promise<{ stories: { id: string }[]; ticks: Tick[] }>;

    const forUs = await get("/articles?for=US&lang=ru");
    const shown = new Set(forUs.stories.map((s) => s.id));
    expect(shown.size).toBe(us.length);
    // Qeshm, the measles death and California's ballots are the US's own stories here.
    expect(forUs.ticks.map((t) => t.countries.sort().join()).sort()).toEqual(["AR,DE", "AR,ES,IT", "BR,PL"]);
    expect(forUs.ticks.every((t) => !t.stories.some((s) => s.country === "US" && shown.has(s.id)))).toBe(true);
    expect(forUs.ticks[0].title).toMatch(/[а-яА-Я]/);

    expect((await get("/articles?for=CZ")).ticks).toHaveLength(WORLD.forYou);
    expect((await get("/articles?for=CZ&topic=economy")).ticks).toEqual([]);
  });
});

describe("the world's build in the stories step (#230 step 4)", () => {
  const SK_OUTLET = "INSERT INTO outlets (id, country, name, url, site, language, headlines, last_item_at) VALUES ('sk-a', 'SK', 'A', 'https://a.test/rss', 'https://a.test', 'sk', '[]', '2026-11-03T09:59:00Z')";

  it("builds the world's stories after a country's, at most every WORLD.minMinutes, in a call of its own", async () => {
    await addCountries();
    // A country never built: due in every run, as the fake build writes nothing.
    await env.DB.prepare(SK_OUTLET).run();
    let worlds = 0;
    const calls = { build: async () => 1, world: async () => buildWorldStories(env, NOW).then((n) => (worlds++, n)) };
    vi.spyOn(console, "log").mockImplementation(() => {});
    await storiesStep(env, calls, NOW);
    expect(worlds).toBe(1);
    // A minute later, a country built again: too soon for the world.
    await storiesStep(env, calls, new Date(NOW.getTime() + 60_000));
    expect(worlds).toBe(1);
    await storiesStep(env, calls, new Date(NOW.getTime() + WORLD.minMinutes * 60_000));
    expect(worlds).toBe(2);
  });

  it("lets a world's build that failed wait WORLD.minMinutes, keeping the stories it has", async () => {
    vi.spyOn(console, "log").mockImplementation(() => {});
    const error = vi.spyOn(console, "error").mockImplementation(() => {});
    await addCountries();
    await buildWorldStories(env, NOW);
    await env.DB.prepare(SK_OUTLET).run();
    let worlds = 0;
    const failing = {
      build: async () => 1,
      world: async () => {
        worlds++;
        throw new Error("Worker exceeded CPU time limit.");
      },
    };
    const at = (minutes: number) => new Date(NOW.getTime() + minutes * 60_000);
    await storiesStep(env, failing, at(WORLD.minMinutes));
    expect(worlds).toBe(1);
    expect(JSON.parse(String(error.mock.calls[0][0]))).toMatchObject({ message: "world stories error" });
    const row = (await worldRow())!;
    expect(row.failed_at).toBe(stored(at(WORLD.minMinutes)));
    expect(row.saved.stories).toHaveLength(6);
    await storiesStep(env, failing, at(2 * WORLD.minMinutes - 1));
    expect(worlds).toBe(1);
    await storiesStep(env, failing, at(2 * WORLD.minMinutes));
    expect(worlds).toBe(2);
  });

  it("gets a country's titled stories kept apart by its build, with their English headline's words", async () => {
    vi.spyOn(console, "log").mockImplementation(() => {});
    const now = new Date();
    const at = stored(now);
    const outlet = (id: string, title: string) =>
      env.DB.prepare("INSERT INTO outlets (id, country, name, url, site, language, headlines, last_item_at) VALUES (?1, 'SK', ?1, ?2, ?3, 'sk', ?4, ?5)")
        .bind(id, `https://${id}.test/rss`, `https://${id}.test`, JSON.stringify([{ title, url: `https://${id}.test/1`, publishedAt: at }]), at)
        .run();
    await outlet("sk-a", "Minister Novák resigns over the budget");
    await outlet("sk-b", "Novák quits as minister over the budget");
    await outlet("sk-c", "Storm warning for the coast");
    const titles = {
      en: "Composer Pavel Žák has died at 85",
      uk: "Помер композитор Павел Жак, йому було 85 років",
      ru: "Умер композитор Павел Жак, ему было 85 лет",
      es: "Murió el compositor Pavel Žák a los 85 años",
      de: "Der Komponist Pavel Žák ist mit 85 Jahren gestorben",
    };
    await buildCountryStories(env, "SK", at, now, async () => JSON.stringify(titles));
    const row = await env.DB.prepare("SELECT json, top FROM country_stories WHERE country = 'SK'").first<{ json: string; top: string }>();
    expect(JSON.parse(row!.json).stories).toHaveLength(2);
    const top = JSON.parse(row!.top) as TitledStory[];
    expect(top).toHaveLength(1);
    expect(top[0]).toMatchObject({ titles, words: "compo ^pavel ^žák has died 85" });
    expect(top[0].items).toHaveLength(2);
  });

  it("runs at the end of the summarizer's run, in the run itself without calls of their own, from the countries' titled stories", async () => {
    vi.spyOn(console, "log").mockImplementation(() => {});
    const now = new Date();
    await env.DB.prepare("INSERT INTO outlets (id, country, name, url, site, language, headlines, last_item_at) VALUES ('cz-a', 'CZ', 'A', 'https://a.test/rss', 'https://a.test', 'cs', ?, ?)")
      .bind(JSON.stringify([{ title: "Novák resigns", url: "https://a.test/1", publishedAt: stored(now) }]), stored(now))
      .run();
    const { ai } = fakeAi(chat("{}"));
    await worker.scheduled(createScheduledController({ cron: CRONS.summarizer }), { ...env, AI: ai });
    const cz = await env.DB.prepare("SELECT top FROM country_stories WHERE country = 'CZ'").first<{ top: string }>();
    // One outlet's story: no headline from the model, so none among the titled ones.
    expect(JSON.parse(cz!.top)).toEqual([]);
    expect((await worldRow())!.saved.stories).toEqual([]);
  });
});
