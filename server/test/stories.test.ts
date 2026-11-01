import { env, exports } from "cloudflare:workers";
import { createScheduledController } from "cloudflare:test";
import { describe, expect, it, vi } from "vitest";
import type { OutletHeadline } from "../src/fetcher/types";
import worker, { CRONS } from "../src/index";
import { BUILD, buildCountryStories, dueCountries, storiesStep } from "../src/stories";
import { STORIES, type Story, clusterHeadlines, storyScore, terms } from "../src/stories/cluster";
import { HEADLINES_2026_11_01 } from "./fixtures/headlines-2026-11-01";

/** The fixture's time: its newest headline is 13:28 UTC. */
const NOW = new Date("2026-11-01T14:00:00Z");

/** The fixture's headlines of `country`, moved in time so that NOW is `base`. */
function real(country: string, base = NOW): OutletHeadline[] {
  const shift = base.getTime() - NOW.getTime();
  return HEADLINES_2026_11_01.filter((h) => h.country === country).map((h) => ({
    title: h.title,
    url: h.url,
    publishedAt: `${new Date(Date.parse(h.publishedAt) + shift).toISOString().slice(0, 19)}Z`,
    outlet: { id: h.outlet, name: h.name, site: `https://${new URL(h.url).host}` },
  }));
}

const storyOf = (stories: Story[], words: string) => stories.find((s) => s.items.some((i) => i.title.includes(words)));
const outletsOf = (story: Story | undefined) => story?.items.map((i) => i.outlet.name).sort();

describe("terms (#230, stories)", () => {
  it("cuts words to their stems, keeps numbers and drops short words, in any alphabet", () => {
    expect(terms("Zemřel textař Pavel Žák, bylo mu 85 let")).toEqual(["zemře", "texta", "pavel", "žák", "bylo", "85", "let"]);
    expect(terms("Зеленського")).toEqual(terms("Зеленський"));
    expect(terms("Sněžkou")).toEqual(terms("Sněžka"));
  });

  it("compares scripts without spaces, and Hangul, by pairs of characters", () => {
    expect(terms("海に転落")).toEqual(["海に", "に転", "転落"]);
    expect(terms("공군기지 훈련기")).toEqual(["공군", "군기", "기지", "훈련", "련기"]);
  });
});

describe("clusterHeadlines on the headlines of 1 Nov (#230, stories)", () => {
  it("groups a country's headlines on the same event, whatever their wording", () => {
    const stories = clusterHeadlines(real("CZ"));
    expect(outletsOf(storyOf(stories, "Pavel Žák"))).toEqual(["Novinky.cz", "Seznam Zprávy", "iROZHLAS", "ČT24"]);
    expect(outletsOf(storyOf(stories, "Sněžkou hořel hotel"))).toEqual(["Echo24", "Novinky.cz", "Seznam Zprávy", "ČT24"]);
    // Most headlines are no one else's story.
    expect(stories.length).toBeGreaterThan(120);
  });

  it("keeps two events apart that share only their kind: two shootings", () => {
    const stories = clusterHeadlines(real("US"));
    expect(outletsOf(storyOf(stories, "Alabama shooting"))).toEqual(["ABC News", "Fox News"]);
    expect(outletsOf(storyOf(stories, "California Spirit Halloween shooting"))).toEqual(["NBC News"]);
    expect(outletsOf(storyOf(stories, "Trump's planned arch"))).toEqual(["CBS News", "NPR", "PBS NewsHour"]);
  });

  it("counts an outlet once, under its latest headline on the story", () => {
    const later = { ...real("CZ").find((h) => h.title.startsWith("Zemřel textař, skladatel"))!, url: "https://ct24.ceskatelevize.cz/later" };
    const stories = clusterHeadlines([...real("CZ"), { ...later, title: "Zemřel textař a skladatel Pavel Žák, autor Holek z naší školky", publishedAt: "2026-11-01T13:50:00Z" }]);
    const zak = storyOf(stories, "Pavel Žák")!;
    expect(zak.items).toHaveLength(4);
    expect(zak.items[0]).toMatchObject({ outlet: { name: "ČT24" }, url: "https://ct24.ceskatelevize.cz/later" });
    expect(zak.lastSeen).toBe("2026-11-01T13:50:00Z");
  });

  it("gives a story an id from its first headline's link, the same whatever the order of the headlines", () => {
    const ids = (stories: Story[]) => stories.map((s) => s.id).sort();
    expect(ids(clusterHeadlines([...real("CZ")].reverse()))).toEqual(ids(clusterHeadlines(real("CZ"))));
  });
});

describe("storyScore (#230, stories)", () => {
  const story = (hours: number[]): Story => ({
    id: "s",
    title: "t",
    firstSeen: "",
    lastSeen: "",
    items: hours.map((h, i) => ({ title: "t", url: `https://x.test/${i}`, publishedAt: new Date(NOW.getTime() - h * 3_600_000).toISOString(), outlet: { id: `o${i}`, name: "o", site: "" } })),
  });

  it("counts each outlet once, halved every 6 hours since its headline", () => {
    expect(STORIES.halfLifeHours).toBe(6);
    expect(storyScore(story([0, 0, 0, 0, 0]), NOW)).toBeCloseTo(5);
    expect(storyScore(story([12, 12, 12, 12, 12]), NOW)).toBeCloseTo(5 / 4);
    expect(storyScore(story([0, 0]), NOW)).toBeGreaterThan(storyScore(story([0]), NOW));
  });
});

/** The fixture's outlets of `country` with their headlines in their rows, as the fetcher keeps them. */
async function addOutlets(country: string, as = country, base = NOW) {
  const byOutlet = new Map<string, OutletHeadline[]>();
  for (const h of real(country, base)) byOutlet.set(h.outlet.id, [...(byOutlet.get(h.outlet.id) ?? []), h]);
  for (const [id, list] of byOutlet) {
    list.sort((a, b) => b.publishedAt.localeCompare(a.publishedAt));
    await env.DB.prepare("INSERT INTO outlets (id, country, name, url, site, language, headlines, last_item_at) VALUES (?, ?, ?, ?, ?, 'cs', ?, ?)")
      .bind(`${as.toLowerCase()}${id.slice(2)}`, as, list[0].outlet.name, `https://feeds.${id}.test/rss`, list[0].outlet.site, JSON.stringify(list.map(({ outlet, ...h }) => h)), list[0].publishedAt)
      .run();
  }
}

const storiesRow = (country: string) =>
  env.DB.prepare("SELECT json, version, built_at FROM country_stories WHERE country = ?").bind(country).first<{ json: string; version: string; built_at: string }>();

describe("the stories step (#230, stories)", () => {
  it("builds a country's stories from its outlets' headlines of the last day, the weightiest first, in one row", async () => {
    await addOutlets("CZ");
    const count = await buildCountryStories(env, "CZ", "2026-11-01T13:28:27Z", NOW);
    expect(count).toBe(BUILD.perCountry);
    const row = await storiesRow("CZ");
    expect(row).toMatchObject({ version: "2026-11-01T13:28:27Z", built_at: "2026-11-01T14:00:00Z" });
    const saved = JSON.parse(row!.json) as { builtAt: string; stories: Story[] };
    expect(saved.builtAt).toBe("2026-11-01T14:00:00Z");
    expect(saved.stories).toHaveLength(BUILD.perCountry);
    expect(saved.stories[0].title).toContain("Pavel Žák");
    expect(saved.stories[0].items).toHaveLength(4);
    // Nothing older than the window.
    const cutoff = `${new Date(NOW.getTime() - BUILD.windowHours * 3_600_000).toISOString().slice(0, 19)}Z`;
    expect(saved.stories.flatMap((s) => s.items).every((i) => i.publishedAt >= cutoff)).toBe(true);
  });

  it("builds a country again only when its outlets have a newer headline, at most every 5 minutes, and anyway every 30", async () => {
    await addOutlets("CZ");
    const at = (minutes: number) => new Date(NOW.getTime() + minutes * 60_000);
    expect(await dueCountries(env, NOW)).toEqual([{ country: "CZ", version: "2026-11-01T13:28:27Z" }]);
    await buildCountryStories(env, "CZ", "2026-11-01T13:28:27Z", NOW);
    expect(await dueCountries(env, at(1))).toEqual([]);

    await env.DB.prepare("UPDATE outlets SET last_item_at = '2026-11-01T14:01:00Z' WHERE id = 'cz-ct24'").run();
    expect(await dueCountries(env, at(BUILD.minMinutes - 1))).toEqual([]);
    expect(await dueCountries(env, at(BUILD.minMinutes))).toEqual([{ country: "CZ", version: "2026-11-01T14:01:00Z" }]);
    await buildCountryStories(env, "CZ", "2026-11-01T14:01:00Z", at(BUILD.minMinutes));
    expect(await dueCountries(env, at(BUILD.minMinutes + BUILD.maxMinutes))).toEqual([{ country: "CZ", version: "2026-11-01T14:01:00Z" }]);
  });

  it("builds up to BUILD.perRun countries a run, each in a call of its own; a failing call stops only its own", async () => {
    for (const country of ["AA", "BB", "CC", "DD", "EE", "FF", "GG"]) await addOutlets("CZ", country);
    const built: string[] = [];
    const error = vi.spyOn(console, "error").mockImplementation(() => {});
    await storiesStep(
      env,
      async (country) => {
        built.push(country);
        if (country === "BB") throw new Error("Worker exceeded CPU time limit.");
        return 1;
      },
      NOW,
    );
    expect(built).toHaveLength(BUILD.perRun);
    expect(JSON.parse(String(error.mock.calls[0][0]))).toMatchObject({ message: "stories step error", failed: [{ country: "BB" }] });
  });

  it("runs at the end of the summarizer's run, in the run itself without calls of their own", async () => {
    await addOutlets("CZ", "CZ", new Date());
    vi.spyOn(console, "log").mockImplementation(() => {});
    await worker.scheduled(createScheduledController({ cron: CRONS.summarizer }), env);
    expect(JSON.parse((await storiesRow("CZ"))!.json).stories[0].title).toContain("Pavel Žák");
  });
});

describe("GET /stories (#230)", () => {
  const get = async (path: string) => {
    const response = await exports.default.fetch(`https://api.test${path}`);
    return { status: response.status, cache: response.headers.get("cache-control"), body: (await response.json()) as Record<string, unknown> };
  };

  it("gives the country's stories, the weightiest now first, with how many outlets carry each", async () => {
    const now = new Date();
    await addOutlets("CZ", "CZ", now);
    await buildCountryStories(env, "CZ", "v", now);
    const { status, cache, body } = await get("/stories?country=CZ");
    expect([status, cache]).toEqual([200, "public, max-age=60"]);
    const stories = body.stories as (Story & { outlets: number; score: number })[];
    expect(stories[0]).toMatchObject({ outlets: 4, title: expect.stringContaining("Pavel Žák") });
    // ČT24's was the last headline on it.
    expect(stories[0].items[0]).toMatchObject({ outlet: { id: "cz-ct24", name: "ČT24", site: "https://ct24.ceskatelevize.cz" } });
    expect(stories.every((s, i) => i === 0 || stories[i - 1].score >= s.score)).toBe(true);
    expect(body).toMatchObject({ country: "CZ", builtAt: expect.any(String) });
  });

  it("needs a country as a 2-letter code in capitals, and gives none for a country without stories", async () => {
    expect((await get("/stories?country=cz")).status).toBe(400);
    expect((await get("/stories")).status).toBe(400);
    expect((await get("/stories?country=ZZ")).body).toEqual({ country: "ZZ", builtAt: null, stories: [] });
  });
});
