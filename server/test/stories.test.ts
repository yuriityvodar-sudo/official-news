import { env, exports } from "cloudflare:workers";
import { createScheduledController } from "cloudflare:test";
import { describe, expect, it, vi } from "vitest";
import type { OutletHeadline } from "../src/fetcher/types";
import worker, { CRONS } from "../src/index";
import { runCleanup } from "../src/health/cleanup";
import { BUILD, buildCountryStories, dueCountries, storiesStep } from "../src/stories";
import { STORIES, type Story, clusterHeadlines, headlineWords, storyScore, terms, topStories } from "../src/stories/cluster";
import { TITLES, type WriteTitles, storyTitles, toTitles } from "../src/stories/titles";
import { HEADLINES_2026_11_01 } from "./fixtures/headlines-2026-11-01";
import { chat, fakeAi } from "./helpers";

/** A usable answer of the model (titles.ts): the same five headlines for any story. */
const TITLES_OK = {
  en: "Composer Pavel Žák has died at 85",
  uk: "Помер композитор Павел Жак, йому було 85 років",
  ru: "Умер композитор Павел Жак, ему было 85 лет",
  es: "Murió el compositor Pavel Žák a los 85 años",
  de: "Der Komponist Pavel Žák ist mit 85 Jahren gestorben",
};
const writeOk: WriteTitles = async () => JSON.stringify(TITLES_OK);

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

describe("headlineWords (#230, stories)", () => {
  it("gives a headline's words as the fetcher keeps them, a name's with ^ first", () => {
    expect(headlineWords("Zemřel textař Pavel Žák, bylo mu 85 let")).toEqual(["zemře", "texta", "^pavel", "^žák", "bylo", "85", "let"]);
    expect(headlineWords("Zemřel textař Pavel Žák, bylo mu 85 let").map((w) => w.replace("^", ""))).toEqual(terms("Zemřel textař Pavel Žák, bylo mu 85 let"));
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

describe("the stories of a build that starts cold (#230: Yurii's check of #282, 2 Nov)", () => {
  const withWords = (headlines: OutletHeadline[]) => headlines.map((h) => ({ ...h, words: headlineWords(h.title) }));

  it("are the same from the words the fetcher kept as from the headlines, and list none of the words", () => {
    for (const country of ["CZ", "US"]) {
      const stories = clusterHeadlines(withWords(real(country)));
      expect(stories).toEqual(clusterHeadlines(real(country)));
      expect(stories.flatMap((s) => s.items).some((i) => "words" in i)).toBe(false);
    }
  });

  it("in WebAssembly, whose memory an isolate keeps: builds one after another are as each alone, larger or smaller", () => {
    const cz = clusterHeadlines(real("CZ"));
    const us = clusterHeadlines(real("US"));
    const both = clusterHeadlines([...real("CZ"), ...real("US")]);
    expect(clusterHeadlines(real("US"))).toEqual(us);
    expect(clusterHeadlines(real("CZ"))).toEqual(cz);
    expect(clusterHeadlines([...real("CZ"), ...real("US")])).toEqual(both);
    expect(clusterHeadlines(real("CZ").slice(0, 5))).toEqual(clusterHeadlines(real("CZ").slice(0, 5)));
    expect(clusterHeadlines([])).toEqual([]);
    expect(topStories([], NOW, 10)).toEqual([]);
  });

  it("topStories: the weightiest stories of clusterHeadlines, in their order, made only for those", () => {
    for (const country of ["CZ", "US"]) {
      const ranked = clusterHeadlines(real(country))
        .map((story) => ({ story, score: storyScore(story, NOW) }))
        .sort((a, b) => b.score - a.score)
        .map(({ story }) => story);
      expect(topStories(withWords(real(country)), NOW, 10)).toEqual(ranked.slice(0, 10));
      expect(topStories(real(country), NOW, 1000)).toEqual(ranked);
    }
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
    const count = await buildCountryStories(env, "CZ", "2026-11-01T13:28:27Z", NOW, writeOk);
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
    await buildCountryStories(env, "CZ", "2026-11-01T13:28:27Z", NOW, writeOk);
    expect(await dueCountries(env, at(1))).toEqual([]);

    await env.DB.prepare("UPDATE outlets SET last_item_at = '2026-11-01T14:01:00Z' WHERE id = 'cz-ct24'").run();
    expect(await dueCountries(env, at(BUILD.minMinutes - 1))).toEqual([]);
    expect(await dueCountries(env, at(BUILD.minMinutes))).toEqual([{ country: "CZ", version: "2026-11-01T14:01:00Z" }]);
    await buildCountryStories(env, "CZ", "2026-11-01T14:01:00Z", at(BUILD.minMinutes), writeOk);
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
    const { ai } = fakeAi(chat(JSON.stringify(TITLES_OK)), chat(JSON.stringify(TITLES_OK)));
    await worker.scheduled(createScheduledController({ cron: CRONS.summarizer }), { ...env, AI: ai });
    const first = JSON.parse((await storiesRow("CZ"))!.json).stories[0];
    expect(first.title).toContain("Pavel Žák");
    expect(first.titles).toEqual(TITLES_OK);
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
    await buildCountryStories(env, "CZ", "v", now, writeOk);
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

describe("story titles (#230 step 3)", () => {
  it("takes five headlines, each in its language and short, without the full stop", () => {
    expect(toTitles(JSON.stringify({ ...TITLES_OK, ru: `${TITLES_OK.ru}.` }))).toEqual(TITLES_OK);
    expect(toTitles(JSON.stringify({ ...TITLES_OK, en: "IG Metall begins first warning strikes", uk: "IG Metall розпочала перші попереджувальні страйки" }))).toMatchObject({ uk: "IG Metall розпочала перші попереджувальні страйки" });
  });

  it("refuses an answer with a headline missing, too long, or not in its language", () => {
    const problems = (answer: object | string) => {
      const checked = toTitles(typeof answer === "string" ? answer : JSON.stringify(answer));
      return "problems" in checked ? checked.problems : [];
    };
    expect(problems("not json")).toEqual(["not JSON"]);
    const { de: _, ...withoutGerman } = TITLES_OK;
    expect(problems(withoutGerman)).toEqual(["de is missing"]);
    expect(problems({ ...TITLES_OK, es: "x".repeat(TITLES.maxLength + 1) })).toEqual([`es is longer than ${TITLES.maxLength} characters`]);
    // The trial's slip (1 Nov): one English word in a Ukrainian headline, which inLanguage alone lets through.
    expect(problems({ ...TITLES_OK, uk: "Фінансування суспільного медіа sharply розділяє виборців уряду та опозиції" })).toEqual(["uk has a word in Latin letters"]);
    expect(problems({ ...TITLES_OK, ru: "Помер композитор Павел Жак, йому було 85 років" })).toEqual(["ru is not in its language"]);
    // Russian without a letter Ukrainian lacks, by its words; English in the Spanish field; Spanish in the German one.
    expect(problems({ ...TITLES_OK, uk: "Правительство и парламент договорились о бюджете" })).toEqual(["uk is not in its language"]);
    expect(problems({ ...TITLES_OK, es: TITLES_OK.en })).toEqual(["es is not in its language"]);
    expect(problems({ ...TITLES_OK, de: "El Gobierno y el Parlamento acordaron el presupuesto" })).toEqual(["de is not in its language"]);
  });

  const czStories = () => clusterHeadlines(real("CZ")).sort((a, b) => storyScore(b, NOW) - storyScore(a, NOW));

  it("asks the model only for the first stories with 2 outlets or more, a few a build, and keeps what it wrote", async () => {
    const stories = czStories();
    const wanted = stories.filter((s) => s.items.length >= TITLES.minOutlets).slice(0, TITLES.perCountry);
    const asked: string[] = [];
    const write: WriteTitles = async (country, story) => {
      asked.push(`${country} ${story.id}`);
      return JSON.stringify(TITLES_OK);
    };
    const first = await storyTitles(env, "CZ", stories, write, NOW);
    expect(asked).toEqual(wanted.slice(0, TITLES.perBuild).map((s) => `CZ ${s.id}`));
    expect([...first.keys()]).toEqual(wanted.slice(0, TITLES.perBuild).map((s) => s.id));
    // Next build: the stored ones without a call, the next ones asked.
    asked.length = 0;
    const second = await storyTitles(env, "CZ", stories, write, NOW);
    expect(asked).toEqual(wanted.slice(TITLES.perBuild, 2 * TITLES.perBuild).map((s) => `CZ ${s.id}`));
    expect(second.size).toBe(2 * TITLES.perBuild);
    expect(second.get(wanted[0].id)).toEqual(TITLES_OK);
  });

  it("counts an unusable answer and stops at TITLES.maxAttempts; an error of Workers AI counts nothing", async () => {
    const stories = czStories().filter((s) => s.items.length >= TITLES.minOutlets).slice(0, 1);
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const error = vi.spyOn(console, "error").mockImplementation(() => {});
    let calls = 0;
    const failing: WriteTitles = async () => {
      calls++;
      throw new Error("3036: You have used up your daily free allocation of 10,000 neurons");
    };
    await storyTitles(env, "CZ", stories, failing, NOW);
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM story_titles").first()).toEqual({ n: 0 });
    expect(JSON.parse(String(error.mock.calls[0][0]))).toMatchObject({ message: "story titles error", country: "CZ", failed: 1 });

    const unusable: WriteTitles = async () => {
      calls++;
      return JSON.stringify({ ...TITLES_OK, uk: "" });
    };
    calls = 0;
    for (let i = 0; i < TITLES.maxAttempts + 2; i++) await storyTitles(env, "CZ", stories, unusable, NOW);
    expect(calls).toBe(TITLES.maxAttempts);
    expect(await env.DB.prepare("SELECT titles, attempts FROM story_titles").first()).toEqual({ titles: null, attempts: TITLES.maxAttempts });
    expect(JSON.parse(String(warn.mock.calls[0][0]))).toMatchObject({ message: "story titles unusable", problems: ["uk is missing"] });
  });

  it("gives the headline in the asked language, in GET /stories and in For you's stories, and the outlets' own until one is written", async () => {
    const now = new Date();
    await addOutlets("CZ", "CZ", now);
    await buildCountryStories(env, "CZ", "v", now, writeOk);
    const get = async (path: string) => (await exports.default.fetch(`https://api.test${path}`)).json() as Promise<Record<string, unknown>>;
    const stories = (await get("/stories?country=CZ&lang=ru")).stories as { title: string; aiTitle: boolean; outlets: number }[];
    expect(stories[0]).toMatchObject({ title: TITLES_OK.ru, aiTitle: true, outlets: 4 });
    // One the model has not written yet keeps its outlets' headline.
    expect(stories.find((s) => !s.aiTitle)?.title).toEqual(expect.any(String));
    expect((await exports.default.fetch("https://api.test/stories?country=CZ&lang=xx")).status).toBe(400);

    const forYou = await get("/articles?for=CZ&lang=ru");
    const home = forYou.stories as { title: string; outlets: number }[];
    expect(home.length).toBeGreaterThan(0);
    expect(home.length).toBeLessThanOrEqual(TITLES.perCountry);
    expect(home.every((s) => s.outlets >= TITLES.minOutlets)).toBe(true);
    expect(home[0].title).toBe(TITLES_OK.ru);
    expect(((await get("/articles?for=CZ")).stories as { title: string }[])[0].title).toBe(TITLES_OK.en);
    // Not with a topic, nor on a later page.
    expect((await get("/articles?for=CZ&topic=economy")).stories).toEqual([]);
  });
});

describe("a failed build waits (#230, Yurii's review of #281)", () => {
  it("lets a country whose build failed wait BUILD.failedMinutes, keeping the stories it has", async () => {
    await addOutlets("CZ");
    await buildCountryStories(env, "CZ", "2026-11-01T13:28:27Z", NOW, writeOk);
    await env.DB.prepare("UPDATE outlets SET last_item_at = '2026-11-01T14:01:00Z' WHERE id = 'cz-ct24'").run();
    const at = (minutes: number) => new Date(NOW.getTime() + minutes * 60_000);
    vi.spyOn(console, "error").mockImplementation(() => {});
    await storiesStep(env, async () => {
      throw new Error("Worker exceeded CPU time limit.");
    }, at(BUILD.minMinutes));
    const row = await env.DB.prepare("SELECT failed_at, json FROM country_stories WHERE country = 'CZ'").first<{ failed_at: string; json: string }>();
    expect(row?.failed_at).toBe("2026-11-01T14:05:00Z");
    expect(JSON.parse(row!.json).stories.length).toBeGreaterThan(0);
    expect(await dueCountries(env, at(BUILD.minMinutes + BUILD.failedMinutes - 1))).toEqual([]);
    expect(await dueCountries(env, at(BUILD.minMinutes + BUILD.failedMinutes))).toEqual([{ country: "CZ", version: "2026-11-01T14:01:00Z" }]);
    // A build that works clears it.
    await buildCountryStories(env, "CZ", "2026-11-01T14:01:00Z", at(BUILD.minMinutes + BUILD.failedMinutes), writeOk);
    expect(await env.DB.prepare("SELECT failed_at FROM country_stories WHERE country = 'CZ'").first()).toEqual({ failed_at: null });
  });

  it("gives a country never built an empty row to wait in", async () => {
    await addOutlets("CZ");
    vi.spyOn(console, "error").mockImplementation(() => {});
    await storiesStep(env, async () => {
      throw new Error("Worker exceeded CPU time limit.");
    }, NOW);
    expect(await dueCountries(env, NOW)).toEqual([]);
    expect(await exports.default.fetch("https://api.test/stories?country=CZ").then((r) => r.json())).toEqual({ country: "CZ", builtAt: null, stories: [] });
  });

  it("drops stories' headlines older than 3 days in the daily cleanup", async () => {
    const day = (days: number) => `${new Date(Date.now() - days * 86_400_000).toISOString().slice(0, 19)}Z`;
    await env.DB.prepare("INSERT INTO story_titles (story_id, country, titles, attempts, updated_at) VALUES ('old', 'CZ', NULL, 1, ?), ('new', 'CZ', NULL, 1, ?)")
      .bind(day(4), day(1))
      .run();
    vi.spyOn(console, "log").mockImplementation(() => {});
    await runCleanup(env);
    expect((await env.DB.prepare("SELECT story_id FROM story_titles").all()).results).toEqual([{ story_id: "new" }]);
  });
});
