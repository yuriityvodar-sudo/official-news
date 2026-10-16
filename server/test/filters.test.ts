// The feed's filters (#67, #68): GET /articles with country and topic, GET /topics and GET /countries.
import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { FROM_TRANSLATED, PAGE_CONDITIONS, TRANSLATED_CONDITIONS, feedFilters, feedTopics } from "../src/api";
import { BLOCS, TOPIC_NAMES, hasCountryName, localCountries } from "../src/api/filters";
import { TOPICS } from "../src/summarizer/schema";
import { LANGS, type Lang } from "../src/translator";
import { type ArticlesPage, QWEN, get, hideSeed, hoursAgo, ids, minutesAgo, rowsRead } from "./helpers";

/** A source per country: Kickoff seed rows, and one for Ukraine, which has none. */
const SOURCE: Record<string, string> = {
  DE: "de-federal-government",
  EU: "eu-european-commission",
  FR: "fr-foreign-ministry",
  US: "us-white-house",
  UA: "ua-test-cabinet",
};

interface Item {
  id: string;
  country?: keyof typeof SOURCE;
  topics?: string[] | string;
  importance?: number | null;
  publishedAt?: string;
  isNews?: number;
  /** In the feed (with the next feed_seq); false: a decision waiting for its release. */
  released?: boolean;
}

/** News articles, released in the order given: the last one is the newest in the feed. */
async function add(...items: Item[]) {
  await env.DB.batch(
    items.map((item) =>
      env.DB.prepare(
        `INSERT INTO articles (id, source_id, url, original_title, published_at, fetched_at, headline, short_summary, summary,
                               is_news, importance, decision_type, summarized_at, topics, tags, feed_seq, added_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?5, ?6, 'Short.', 'Summary.', ?7, ?8, 'decision', ?5, ?9, '[]',
                 CASE WHEN ?7 = 1 AND ?10 THEN (SELECT COALESCE(MAX(feed_seq), 0) + 1 FROM articles WHERE feed_seq IS NOT NULL) END,
                 CASE WHEN ?7 = 1 AND ?10 THEN strftime('%Y-%m-%dT%H:%M:%SZ', 'now') END)`,
      ).bind(
        item.id,
        SOURCE[item.country ?? "DE"],
        `https://example.gov/${item.id}`,
        `Title ${item.id}`,
        item.publishedAt ?? hoursAgo(1),
        `Headline ${item.id}`,
        item.isNews ?? 1,
        item.importance ?? null,
        typeof item.topics === "string" ? item.topics : JSON.stringify(item.topics ?? ["economy"]),
        item.released === false ? 0 : 1,
      ),
    ),
  );
}

/** A finished translation into `lang`, as the translator stores it. */
const translatedInto = (lang: Lang, ...articleIds: string[]) =>
  env.DB.batch(
    articleIds.map((id) =>
      env.DB.prepare(
        `INSERT INTO article_translations (article_id, lang, headline, short_summary, summary, model, source_summarized_at,
                                           attempts_source, lang_seq, translated_at, published_at, state)
         SELECT id, ?4, 'Headline ' || ?4 || ' ' || id, 'Short.', 'Summary.', ?2, summarized_at, summarized_at,
                (SELECT COALESCE(MAX(lang_seq), 0) + 1 FROM article_translations WHERE lang = ?4), ?3, ?3, 'published'
         FROM articles WHERE id = ?1`,
      ).bind(id, QWEN, minutesAgo(5), lang),
    ),
  );

/** A finished Ukrainian translation. */
const translated = (...articleIds: string[]) => translatedInto("uk", ...articleIds);

type Page = Omit<ArticlesPage, "items"> & { items: (ArticlesPage["items"][number] & { country: string })[] };

async function page(path: string): Promise<Page> {
  const { status, body } = await get(path);
  expect(status, path).toBe(200);
  return body as Page;
}

const topIds = async (path: string) => (await page(path)).top.map((a) => a.id);

const topicIds = async (path: string) => ((await get(path)).body as { topics: { id: string }[] }).topics.map((t) => t.id);

beforeEach(async () => {
  // Only the articles each test adds are in the feed.
  await hideSeed();
  await env.DB.prepare(
    "INSERT INTO sources (id, country, name, kind, url, status) VALUES ('ua-test-cabinet', 'UA', 'Cabinet of Ministers', 'rss', 'https://www.kmu.gov.ua/rss', 'active')",
  ).run();
});

describe("GET /articles with country (Local)", () => {
  beforeEach(async () => {
    await add({ id: "de", country: "DE" }, { id: "eu", country: "EU" }, { id: "us", country: "US" }, { id: "fr", country: "FR" }, { id: "ua", country: "UA" });
  });

  it("returns the country's own articles, and the EU's for an EU member", async () => {
    expect(await ids("/articles")).toEqual(["ua", "fr", "us", "eu", "de"]);
    expect(await ids("/articles?country=DE")).toEqual(["eu", "de"]);
    expect(await ids("/articles?country=FR")).toEqual(["fr", "eu"]);
    // Not EU members: their own sources only.
    expect(await ids("/articles?country=UA")).toEqual(["ua"]);
    expect(await ids("/articles?country=US")).toEqual(["us"]);
    // An EU member without sources of its own still gets the EU's; a country with none at all, nothing.
    expect(await ids("/articles?country=GR")).toEqual(["eu"]);
    expect(await ids("/articles?country=JP")).toEqual([]);
    // The bloc itself: its own articles.
    expect(await ids("/articles?country=EU")).toEqual(["eu"]);
  });

  it("keeps the article format: each article's country is the filter's or its bloc's", async () => {
    const items = (await page("/articles?country=DE")).items;
    expect(items.map((a) => a.country)).toEqual(["EU", "DE"]);
  });

  it("knows which countries belong to which bloc", () => {
    expect(localCountries("DE")).toEqual(["DE", "EU"]);
    expect(localCountries("GR")).toEqual(["GR", "EU"]);
    expect(localCountries("UA")).toEqual(["UA"]);
    expect(localCountries("GB")).toEqual(["GB"]);
    expect(localCountries("EU")).toEqual(["EU"]);
    expect(BLOCS.EU).toHaveLength(27);
    expect(new Set(BLOCS.EU).size).toBe(27);
  });
});

describe("GET /articles with topic", () => {
  it("returns only the articles the AI gave that topic", async () => {
    await add(
      { id: "economy", topics: ["economy"] },
      { id: "health-economy", topics: ["health", "economy"] },
      { id: "health", topics: ["health"] },
      { id: "broken", topics: "not json" },
      { id: "object", topics: '{"topic": "health"}' },
      { id: "none", topics: [] },
    );
    expect(await ids("/articles?topic=health")).toEqual(["health", "health-economy"]);
    expect(await ids("/articles?topic=economy")).toEqual(["health-economy", "economy"]);
    expect(await ids("/articles?topic=science")).toEqual([]);
    // Without a topic, every article, broken topics included (read as none).
    expect(await ids("/articles")).toEqual(["none", "object", "broken", "health", "health-economy", "economy"]);
  });

  it("combines with country and lang", async () => {
    await add(
      { id: "de-health", country: "DE", topics: ["health"] },
      { id: "de-economy", country: "DE", topics: ["economy"] },
      { id: "eu-health", country: "EU", topics: ["health", "trade"] },
      { id: "us-health", country: "US", topics: ["health"] },
      { id: "fr-health", country: "FR", topics: ["health"] },
    );
    expect(await ids("/articles?country=DE&topic=health")).toEqual(["eu-health", "de-health"]);
    expect(await ids("/articles?topic=health&country=US")).toEqual(["us-health"]);
    expect(await ids("/articles?country=UA&topic=health")).toEqual([]);

    // In Ukrainian: the same filters, among the articles translated into it.
    await translated("de-health", "de-economy", "us-health");
    const uk = await page("/articles?country=DE&topic=health&lang=uk");
    expect(uk.items.map((a) => [a.id, a.lang])).toEqual([["de-health", "uk"]]);
    expect(uk.translationsDelayed).toBe(false);
    expect(await ids("/articles?lang=uk&country=DE")).toEqual(["de-economy", "de-health"]);
    expect(await ids("/articles?lang=uk&topic=health")).toEqual(["us-health", "de-health"]);
    // lang=en is the English feed, filtered the same way.
    expect(await ids("/articles?lang=en&country=DE&topic=health")).toEqual(["eu-health", "de-health"]);
  });
});

describe("GET /articles with filters: paging, after= and top", () => {
  it("pages within the filter: each cursor continues the filtered feed, without gaps or repeats", async () => {
    // 30 articles: DE, EU and US in turn, every other one about health.
    const items: Item[] = Array.from({ length: 30 }, (_, i) => ({
      id: `a${String(i).padStart(2, "0")}`,
      country: (["DE", "EU", "US"] as const)[i % 3],
      topics: i % 2 ? ["health"] : ["economy"],
    }));
    await add(...items);
    const expected = items
      .filter((a) => a.country !== "US" && JSON.stringify(a.topics).includes("health"))
      .map((a) => a.id)
      .reverse();
    expect(expected).toHaveLength(10);

    for (const lang of ["", "&lang=uk"]) {
      if (lang) await translated(...items.map((a) => a.id));
      const seen: string[] = [];
      let path = `/articles?country=DE&topic=health&limit=3${lang}`;
      for (let pages = 0; pages < 10; pages++) {
        const p = await page(path);
        seen.push(...p.items.map((a) => a.id));
        if (pages > 0) expect(p.top).toEqual([]);
        if (!p.nextCursor) break;
        path = `/articles?country=DE&topic=health&limit=3&cursor=${p.nextCursor}${lang}`;
      }
      expect(seen, lang).toEqual(expected);
    }

    // Exactly a page's worth left: the last full page says there is no next one.
    const twoPages = await page("/articles?country=DE&topic=health&limit=5");
    const second = await page(`/articles?country=DE&topic=health&limit=5&cursor=${twoPages.nextCursor}`);
    expect(second.items).toHaveLength(5);
    expect(second.nextCursor).toBeNull();
  });

  it("with after, counts only the new articles that pass the filters", async () => {
    await add({ id: "seen", country: "DE" });
    const seen = (await page("/articles")).items[0] as unknown as { feedSeq: number };
    await add(
      { id: "us-new", country: "US", topics: ["health"] },
      { id: "de-new", country: "DE", topics: ["economy"] },
      { id: "eu-new", country: "EU", topics: ["economy", "trade"] },
      { id: "de-health", country: "DE", topics: ["health"] },
      // Published two days ago, released now: new too.
      { id: "de-late", country: "DE", topics: ["economy"], publishedAt: hoursAgo(48) },
    );
    expect(await ids(`/articles?after=${seen.feedSeq}`)).toEqual(["de-late", "de-health", "eu-new", "de-new", "us-new"]);
    expect(await ids(`/articles?after=${seen.feedSeq}&country=DE`)).toEqual(["de-late", "de-health", "eu-new", "de-new"]);
    expect(await ids(`/articles?after=${seen.feedSeq}&country=DE&topic=economy`)).toEqual(["de-late", "eu-new", "de-new"]);
    expect(await ids(`/articles?after=${seen.feedSeq}&topic=health`)).toEqual(["de-health", "us-new"]);
    expect(await ids(`/articles?after=${seen.feedSeq}&country=UA`)).toEqual([]);
    expect((await page(`/articles?after=${seen.feedSeq}&country=DE`)).top).toEqual([]);
  });

  it("picks the top stories among the articles that pass the filters, in English and in a language", async () => {
    await add(
      { id: "de-5", country: "DE", importance: 5, topics: ["economy"] },
      { id: "de-4", country: "DE", importance: 4, topics: ["health"] },
      { id: "de-3", country: "DE", importance: 3, topics: ["economy"] },
      { id: "eu-3", country: "EU", importance: 3, topics: ["economy"] },
      { id: "us-5", country: "US", importance: 5, topics: ["economy"] },
      { id: "fr-4", country: "FR", importance: 4, topics: ["health"] },
      { id: "ua-2", country: "UA", importance: 2, topics: ["economy"] },
    );
    // Global: by importance, at most 2 per country, 5 in all, shown newest first.
    expect(await topIds("/articles")).toEqual(["fr-4", "us-5", "eu-3", "de-4", "de-5"]);
    // Local: Germany and the EU; Ukraine has a top story of its own, however low its importance.
    expect(await topIds("/articles?country=DE")).toEqual(["eu-3", "de-4", "de-5"]);
    expect(await topIds("/articles?country=UA")).toEqual(["ua-2"]);
    expect(await topIds("/articles?topic=health")).toEqual(["fr-4", "de-4"]);
    // At most 2 per country: de-3 makes it here, below de-5.
    expect(await topIds("/articles?country=DE&topic=economy")).toEqual(["eu-3", "de-3", "de-5"]);
    expect(await topIds("/articles?country=US&topic=health")).toEqual([]);
    // Top stories are in items too.
    const p = await page("/articles?country=DE&topic=economy");
    expect(p.items.map((a) => a.id)).toEqual(["eu-3", "de-3", "de-5"]);

    // In Ukrainian: the same top stories that are translated.
    await translated("de-5", "us-5", "fr-4");
    expect(await topIds("/articles?lang=uk&country=DE")).toEqual(["de-5"]);
    expect(await topIds("/articles?lang=uk&topic=health")).toEqual(["fr-4"]);
    expect(await topIds("/articles?lang=uk")).toEqual(["fr-4", "us-5", "de-5"]);
  });

  it("walks the feed index from the 7-day edge with filters too, also with table statistics", async () => {
    // As in the live table: older rows have lower numbers and appeared earlier.
    await env.DB.prepare("UPDATE articles SET feed_seq = NULL, added_at = NULL").run();
    await add(...Array.from({ length: 60 }, (_, i) => ({ id: `old-${i}`, country: "DE" as const, publishedAt: hoursAgo(10 * 24 + 60 - i) })));
    await env.DB.prepare("UPDATE articles SET added_at = published_at WHERE id LIKE 'old-%'").run();
    await add(
      { id: "now-de", country: "DE", topics: ["health"] },
      { id: "now-us", country: "US", topics: ["health"] },
      { id: "now-eu", country: "EU", topics: ["economy"] },
    );
    const filters = feedFilters("DE", "health");
    const queries = [
      // The feed page, in English and in a language (the language is bound first).
      `SELECT a.id FROM articles a JOIN sources s ON s.id = a.source_id
       WHERE ${[...PAGE_CONDITIONS, ...filters.where].join(" AND ")} ORDER BY a.feed_seq DESC LIMIT 21`,
      `SELECT a.id ${FROM_TRANSLATED}
       WHERE ${[...PAGE_CONDITIONS, ...TRANSLATED_CONDITIONS, ...filters.where].join(" AND ")} ORDER BY a.feed_seq DESC LIMIT 21`,
      // The topics menu, with and without a country, in English and in a language.
      feedTopics(feedFilters("DE", null)),
      feedTopics(feedFilters(null, null)),
      feedTopics(feedFilters("DE", null), "uk"),
      feedTopics(feedFilters(null, null), "uk"),
    ];
    const binds = [filters.binds, ["uk", ...filters.binds], ["DE", "EU"], [], ["uk", "DE", "EU"], ["uk"]];

    for (const analyzed of [false, true]) {
      // Statistics of a nearly empty table make other plans look cheaper.
      if (analyzed) await env.DB.prepare("ANALYZE").run();
      for (const [i, sql] of queries.entries()) {
        const { results } = await env.DB.prepare(`EXPLAIN QUERY PLAN ${sql}`)
          .bind(...binds[i])
          .all<{ detail: string }>();
        const plan = results.map((r) => r.detail).join("; ");
        expect(plan, `${analyzed ? "analyzed" : "fresh"} ${i}: ${plan}`).toMatch(/^SEARCH a USING INDEX articles_feed_seq \(feed_seq>\?\)/);
        expect(plan).not.toMatch(/SCAN (a|s|t)\b|AUTOMATIC|TEMP B-TREE/);
        // The country: the matching sources read once, not a join that drives the walk.
        if (i !== 3 && i !== 5) expect(plan).toContain("LIST SUBQUERY");
        if (i < 2) expect(plan).toMatch(/SEARCH s USING (COVERING )?INDEX sqlite_autoindex_sources_1 \(id=\?\)/);
        // A language: each article's translation found by its primary key.
        if (i === 1 || i >= 4) expect(plan).toMatch(/SEARCH t USING INDEX sqlite_autoindex_article_translations_1 \(article_id=\? AND lang=\?\)/);
      }
    }

    expect(await ids("/articles?country=DE&topic=health")).toEqual(["now-de"]);
    // The 3 new rows (and the 7-day edge) and the sources table once per query (page and top), not the 60 older rows.
    const sources = (await env.DB.prepare("SELECT COUNT(*) AS n FROM sources").first<{ n: number }>())?.n ?? 0;
    expect(await rowsRead(() => get("/articles?country=DE&topic=health"))).toBeLessThan(2 * sources + 40);
    expect(await rowsRead(() => get("/topics?country=DE"))).toBeLessThan(sources + 10);
    expect(await rowsRead(() => get("/topics"))).toBeLessThan(10);
    await translated("now-de", "now-us", "now-eu");
    expect(await rowsRead(() => get("/topics?lang=uk&country=DE"))).toBeLessThan(sources + 15);
    expect(await rowsRead(() => get("/topics?lang=uk"))).toBeLessThan(15);
  });
});

describe("GET /topics", () => {
  it("lists the topics that have posts in the feed, busiest first, named in English by default", async () => {
    await add(
      { id: "a", topics: ["economy", "health"] },
      { id: "b", topics: ["economy"] },
      { id: "c", topics: ["economy", "science"] },
      { id: "d", topics: ["health"] },
      // Ties keep the order of the fixed list: climate before science.
      { id: "e", topics: ["climate"] },
      // Not counted: broken topics, a topic not on the list, hidden, older than 7 days, not released yet.
      { id: "broken", topics: "not json" },
      { id: "unknown", topics: ["sports"] },
      { id: "hidden", topics: ["trade"], isNews: 0 },
      { id: "old", topics: ["energy"], publishedAt: hoursAgo(8 * 24) },
      { id: "waiting", topics: ["migration"], released: false },
    );
    const { status, body } = await get("/topics");
    expect(status).toBe(200);
    expect(body).toEqual({
      topics: [
        { id: "economy", name: "Economy" },
        { id: "health", name: "Health" },
        { id: "climate", name: "Climate" },
        { id: "science", name: "Science" },
      ],
    });
    expect(await get("/topics?lang=en")).toEqual({ status, body });
  });

  it("names the topics in the language asked for, in the same order", async () => {
    await add({ id: "a", topics: ["security-defence", "human-rights"] }, { id: "b", topics: ["human-rights"] });
    for (const lang of LANGS) await translatedInto(lang, "a", "b");
    for (const lang of LANGS) {
      const { body } = await get(`/topics?lang=${lang}`);
      expect(body, lang).toEqual({
        topics: [
          { id: "human-rights", name: TOPIC_NAMES[lang]["human-rights"] },
          { id: "security-defence", name: TOPIC_NAMES[lang]["security-defence"] },
        ],
      });
    }
    expect((await get("/topics?lang=uk")).body).toEqual({
      topics: [
        { id: "human-rights", name: "Права людини" },
        { id: "security-defence", name: "Безпека та оборона" },
      ],
    });
  });

  it("has a name for every topic in every language", () => {
    for (const lang of ["en", ...LANGS] as const) {
      expect(Object.keys(TOPIC_NAMES[lang]).sort(), lang).toEqual([...TOPICS].sort());
      for (const name of Object.values(TOPIC_NAMES[lang])) expect(name.trim(), lang).not.toBe("");
    }
  });

  it("with country, counts that country's Local feed", async () => {
    await add(
      { id: "de", country: "DE", topics: ["economy"] },
      { id: "eu-1", country: "EU", topics: ["trade"] },
      { id: "eu-2", country: "EU", topics: ["trade", "economy"] },
      { id: "us-1", country: "US", topics: ["health"] },
      { id: "us-2", country: "US", topics: ["health"] },
      { id: "us-3", country: "US", topics: ["health"] },
    );
    await translatedInto("de", "us-1", "us-2", "us-3");
    expect(await topicIds("/topics")).toEqual(["health", "economy", "trade"]);
    expect(await topicIds("/topics?country=DE")).toEqual(["economy", "trade"]);
    expect(await topicIds("/topics?country=US&lang=de")).toEqual(["health"]);
    expect(await get("/topics?country=UA")).toEqual({ status: 200, body: { topics: [] } });
  });

  it("in a language, counts that language's feed: a topic whose articles are not translated into it is not offered", async () => {
    // Released together, but only some translated: the language was paused or off, the translator
    // was not running, or the translation failed (release.ts releases without it then).
    await add(
      { id: "de-economy", country: "DE", topics: ["economy"] },
      { id: "de-rights", country: "DE", topics: ["human-rights"] },
      { id: "us-health", country: "US", topics: ["health"] },
      { id: "us-health-2", country: "US", topics: ["health", "trade"] },
    );
    await translated("de-economy", "us-health");
    expect(await topicIds("/topics")).toEqual(["health", "economy", "trade", "human-rights"]);
    expect(await topicIds("/topics?lang=uk")).toEqual(["economy", "health"]);
    expect(await topicIds("/topics?lang=uk&country=DE")).toEqual(["economy"]);
    expect(await topicIds("/topics?lang=uk&country=US")).toEqual(["health"]);
    // Every topic offered has posts in that feed, and none left out has.
    for (const topic of TOPICS) {
      const offered = (await topicIds("/topics?lang=uk&country=DE")).includes(topic);
      expect((await ids(`/articles?lang=uk&country=DE&topic=${topic}`)).length > 0, topic).toBe(offered);
    }

    // A translation that is not shown (failed for the article's current English) does not count.
    await env.DB.prepare(
      "UPDATE article_translations SET state = 'failed', attempts_source = 'newer' WHERE article_id = 'de-economy' AND lang = 'uk'",
    ).run();
    expect(await ids("/articles?lang=uk&country=DE")).toEqual([]);
    expect(await topicIds("/topics?lang=uk&country=DE")).toEqual([]);

    // A language with no translations at all (off, as German is live): no topics, as its feed is empty.
    expect(await topicIds("/topics?lang=de")).toEqual([]);
    expect(await ids("/articles?lang=de")).toEqual([]);
  });
});

describe("GET /countries", () => {
  /** Real sources (not the Kickoff seed), with their status. */
  const sources = (...rows: [id: string, country: string, status: string][]) =>
    env.DB.batch(
      rows.map(([id, country, status]) =>
        env.DB.prepare("INSERT INTO sources (id, country, name, kind, url, status) VALUES (?1, ?2, ?1, 'rss', 'https://example.gov/' || ?1, ?3)").bind(
          id,
          country,
          status,
        ),
      ),
    );

  it("lists the countries of active sources, once each, without the EU or the Kickoff seed rows", async () => {
    await env.DB.prepare("DELETE FROM sources WHERE id = 'ua-test-cabinet'").run();
    // Only the Kickoff seed sources: no country yet.
    expect(await get("/countries")).toEqual({ status: 200, body: { countries: [] } });
    await sources(
      ["de-1", "DE", "active"],
      ["de-2", "DE", "active"],
      ["ua-1", "UA", "active"],
      ["eu-1", "EU", "active"],
      ["in-1", "IN", "stale"],
      ["ru-1", "RU", "broken"],
      ["jp-1", "JP", "moved"],
      ["cn-1", "CN", "blocked"],
    );
    expect(await get("/countries")).toEqual({
      status: 200,
      body: {
        countries: [
          { code: "DE", name: "Germany" },
          { code: "UA", name: "Ukraine" },
        ],
      },
    });
  });

  it("names the countries in the language asked for, sorted by that name", async () => {
    await sources(["es-1", "ES", "active"], ["us-1", "US", "active"], ["de-1", "DE", "active"], ["ca-1", "CA", "active"], ["ar-1", "AR", "active"]);
    const names = async (lang: string) => ((await get(`/countries?lang=${lang}`)).body as { countries: { name: string }[] }).countries.map((c) => c.name);
    expect(await names("en")).toEqual(["Argentina", "Canada", "Germany", "Spain", "Ukraine", "United States"]);
    // Ukrainian і after и, not before а as in Unicode.
    expect(await names("uk")).toEqual(["Аргентина", "Іспанія", "Канада", "Німеччина", "США", "Україна"]);
    expect(await names("ru")).toEqual(["Аргентина", "Германия", "Испания", "Канада", "США", "Украина"]);
    // Accented letters with their base letter, ñ after n.
    expect(await names("es")).toEqual(["Alemania", "Argentina", "Canadá", "España", "Estados Unidos", "Ucrania"]);
    expect(await names("de")).toEqual(["Argentinien", "Deutschland", "Kanada", "Spanien", "Ukraine", "Vereinigte Staaten"]);
    expect((await get("/countries?lang=uk")).body).toMatchObject({ countries: expect.arrayContaining([{ code: "UA", name: "Україна" }]) });
  });

  it("has a name in every language for every country of docs/sources.csv", () => {
    expect(env.TEST_SOURCE_COUNTRIES.length).toBeGreaterThan(5);
    for (const code of env.TEST_SOURCE_COUNTRIES) expect(hasCountryName(code), code).toBe(true);
  });

  it("shows a code it has no name for as it is", async () => {
    await env.DB.prepare("INSERT INTO sources (id, country, name, kind, url, status) VALUES ('qq-1', 'QQ', 'Q', 'rss', 'https://q.example/feed', 'active')").run();
    expect((await get("/countries?lang=de")).body).toEqual({
      countries: [
        { code: "QQ", name: "QQ" },
        { code: "UA", name: "Ukraine" },
      ],
    });
  });
});

describe("filter errors", () => {
  it.each([
    ["/articles?country=de", "country must be a country code of 2 capital letters, such as DE"],
    ["/articles?country=DEU", "country must be a country code of 2 capital letters, such as DE"],
    ["/articles?country=", "country must be a country code of 2 capital letters, such as DE"],
    ["/articles?country=D1&topic=health", "country must be a country code of 2 capital letters, such as DE"],
    ["/topics?country=Germany", "country must be a country code of 2 capital letters, such as DE"],
    ["/articles?topic=sports", `topic must be one of: ${TOPICS.join(", ")}`],
    ["/articles?topic=Economy", `topic must be one of: ${TOPICS.join(", ")}`],
    ["/articles?topic=&country=DE", `topic must be one of: ${TOPICS.join(", ")}`],
    ["/topics?lang=pl", "lang must be one of: en, uk, ru, es, de"],
    ["/countries?lang=UK", "lang must be one of: en, uk, ru, es, de"],
  ])("rejects %s with a JSON error", async (path, error) => {
    expect(await get(path)).toEqual({ status: 400, body: { error } });
  });
});
