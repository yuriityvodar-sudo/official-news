// The feed's filters (#67, #68): GET /articles with country, group and topic, GET /topics and GET /countries.
import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { FROM_TRANSLATED, PAGE_CONDITIONS, RECENT_TRANSLATION, TRANSLATED_CONDITIONS, feedFilters, feedTopics, topStories } from "../src/api";
import { GROUPS, type GroupId, TOPIC_NAMES, type Where, countryName, groupCountries, hasCountryName } from "../src/api/filters";
import { TOPICS, type Topic } from "../src/summarizer/schema";
import { LANGS, type Lang } from "../src/translator";
import { type ArticlesPage, QWEN, get, hideSeed, hoursAgo, ids, minutesAgo, rowsRead } from "./helpers";

/** A source per country: Kickoff seed rows, and test ones for Ukraine, Czechia and Poland, which have none. */
const SOURCE: Record<string, string> = {
  DE: "de-federal-government",
  EU: "eu-european-commission",
  FR: "fr-foreign-ministry",
  US: "us-white-house",
  GB: "gb-prime-minister-s-office",
  JP: "jp-foreign-ministry",
  AR: "ar-central-bank",
  TR: "tr-foreign-ministry",
  SA: "sa-saudi-press-agency-state-agency",
  RU: "ru-kremlin",
  UA: "ua-test-cabinet",
  CZ: "cz-test-government",
  PL: "pl-test-government",
};

/** The Where filter for feedFilters. */
const group = (id: GroupId): Where => ({ group: GROUPS.find((g) => g.id === id)! });

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
  // Marked as seed rows, so GET /countries lists only the real sources its tests add.
  await env.DB.prepare(
    `INSERT INTO sources (id, country, name, kind, url, status, config) VALUES
       ('cz-test-government', 'CZ', 'Government', 'rss', 'https://vlada.gov.cz/rss', 'active', '{"seed":true}'),
       ('pl-test-government', 'PL', 'Council of Ministers', 'rss', 'https://www.gov.pl/rss', 'active', '{"seed":true}')`,
  ).run();
});

describe("GET /articles with country", () => {
  beforeEach(async () => {
    await add({ id: "de", country: "DE" }, { id: "eu", country: "EU" }, { id: "us", country: "US" }, { id: "fr", country: "FR" }, { id: "ua", country: "UA" });
  });

  it("returns only that country's own articles, never the EU's mixed in", async () => {
    expect(await ids("/articles")).toEqual(["ua", "fr", "us", "eu", "de"]);
    expect(await ids("/articles?country=DE")).toEqual(["de"]);
    expect(await ids("/articles?country=FR")).toEqual(["fr"]);
    expect(await ids("/articles?country=UA")).toEqual(["ua"]);
    expect(await ids("/articles?country=US")).toEqual(["us"]);
    // A country without articles (or without sources): nothing.
    expect(await ids("/articles?country=GR")).toEqual([]);
    expect(await ids("/articles?country=JP")).toEqual([]);
    // The EU institutions' own decisions (not in the menu: they are in the European Union group).
    expect(await ids("/articles?country=EU")).toEqual(["eu"]);
  });

  it("keeps the article format: each article's country is the filter's", async () => {
    const items = (await page("/articles?country=DE")).items;
    expect(items.map((a) => a.country)).toEqual(["DE"]);
  });
});

describe("GET /articles with group", () => {
  /** One article per source country, in this order. */
  const countries = ["DE", "EU", "US", "FR", "UA", "GB", "CZ", "JP", "AR", "PL", "TR", "SA", "RU"] as const;
  beforeEach(async () => {
    await add(...countries.map((country) => ({ id: country.toLowerCase(), country })));
  });

  it("returns its member countries' articles, and the EU institutions' in the EU, the G7 and the G20 (not NATO)", async () => {
    expect(await ids("/articles?group=eu")).toEqual(["pl", "cz", "fr", "eu", "de"]);
    expect(await ids("/articles?group=g7")).toEqual(["jp", "gb", "fr", "us", "eu", "de"]);
    // Saudi Arabia is a member with no source yet (here a seed row has one); Russia is in no group.
    expect(await ids("/articles?group=g20")).toEqual(["sa", "tr", "ar", "jp", "gb", "fr", "us", "eu", "de"]);
    expect(await ids("/articles?group=nato")).toEqual(["tr", "pl", "cz", "gb", "fr", "us", "de"]);
    // Ukraine and Russia are in none; every country is still in the whole feed.
    for (const g of GROUPS) {
      const shown = await ids(`/articles?group=${g.id}`);
      expect(shown, g.id).not.toContain("ua");
      expect(shown, g.id).not.toContain("ru");
      // Exactly the articles of the group's source countries, in feed order.
      expect(shown, g.id).toEqual(
        [...countries]
          .reverse()
          .filter((c) => groupCountries(g).includes(c))
          .map((c) => c.toLowerCase()),
      );
    }
    expect(await ids("/articles")).toHaveLength(countries.length);
  });

  it("combines with topic and lang", async () => {
    await add(
      { id: "de-health", country: "DE", topics: ["health"] },
      { id: "eu-health", country: "EU", topics: ["health"] },
      { id: "jp-health", country: "JP", topics: ["health"] },
      { id: "cz-health", country: "CZ", topics: ["health"] },
    );
    expect(await ids("/articles?group=eu&topic=health")).toEqual(["cz-health", "eu-health", "de-health"]);
    expect(await ids("/articles?topic=health&group=nato")).toEqual(["cz-health", "de-health"]);
    expect(await ids("/articles?group=g7&topic=health")).toEqual(["jp-health", "eu-health", "de-health"]);
    await translated("de-health", "eu-health", "cz-health");
    expect(await ids("/articles?group=g7&topic=health&lang=uk")).toEqual(["eu-health", "de-health"]);
    expect(await ids("/articles?lang=en&group=nato&topic=health")).toEqual(["cz-health", "de-health"]);
  });

  it("knows each group's members, with the EU institutions in the EU, the G7 and the G20", () => {
    expect(GROUPS.map((g) => g.id)).toEqual(["eu", "g7", "g20", "nato"]);
    const members = Object.fromEntries(GROUPS.map((g) => [g.id, groupCountries(g)]));
    expect(members).toEqual({
      eu: ["CZ", "DE", "ES", "FR", "IT", "PL", "EU"],
      g7: ["CA", "DE", "FR", "GB", "IT", "JP", "US", "EU"],
      g20: ["AR", "AU", "BR", "CA", "CN", "DE", "FR", "GB", "ID", "IN", "IT", "JP", "KR", "MX", "SA", "TR", "US", "ZA", "EU"],
      nato: ["CA", "CZ", "DE", "ES", "FR", "GB", "IT", "PL", "TR", "US"],
    });
    for (const g of GROUPS) {
      expect(new Set(g.members).size, g.id).toBe(g.members.length);
      expect(g.members, g.id).not.toContain("EU");
      // Russia is not a source country (#42).
      expect(g.members, g.id).not.toContain("RU");
      for (const code of g.members) expect(hasCountryName(code), `${g.id} ${code}`).toBe(true);
      // Every member is a country of docs/sources.csv, except Saudi Arabia (G20), which has no source yet.
      for (const code of g.members) if (code !== "SA") expect(env.TEST_SOURCE_COUNTRIES, `${g.id} ${code}`).toContain(code);
    }
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
    expect(await ids("/articles?country=DE&topic=health")).toEqual(["de-health"]);
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
    expect(await ids("/articles?lang=en&country=DE&topic=health")).toEqual(["de-health"]);
  });
});

describe("GET /articles with filters: paging, after= and top", () => {
  it("pages within the filter: each cursor continues the filtered feed, without gaps or repeats", async () => {
    // 48 articles: DE, EU, US and UA in turn, every third one about health.
    const items: Item[] = Array.from({ length: 48 }, (_, i) => ({
      id: `a${String(i).padStart(2, "0")}`,
      country: (["DE", "EU", "US", "UA"] as const)[i % 4],
      topics: i % 3 ? ["economy"] : ["health"],
    }));
    await add(...items);
    await translated(...items.map((a) => a.id));
    const health = (a: Item) => JSON.stringify(a.topics).includes("health");
    const filters: [query: string, passes: (a: Item) => boolean][] = [
      ["country=DE&topic=health", (a) => a.country === "DE" && health(a)],
      ["group=g7&topic=health", (a) => a.country !== "UA" && health(a)],
      ["group=nato", (a) => a.country === "DE" || a.country === "US"],
      ["group=eu", (a) => a.country === "DE" || a.country === "EU"],
    ];

    for (const [query, passes] of filters) {
      const expected = items.filter(passes).map((a) => a.id).reverse();
      expect(expected.length, query).toBeGreaterThan(2);
      for (const lang of ["", "&lang=uk"]) {
        const seen: string[] = [];
        let path = `/articles?${query}&limit=2${lang}`;
        for (let pages = 0; pages < 20; pages++) {
          const p = await page(path);
          seen.push(...p.items.map((a) => a.id));
          if (pages > 0) expect(p.top).toEqual([]);
          if (!p.nextCursor) break;
          path = `/articles?${query}&limit=2&cursor=${p.nextCursor}${lang}`;
        }
        expect(seen, query + lang).toEqual(expected);
      }
    }

    // Exactly a page's worth left: the last full page says there is no next one (nato: 24 articles).
    const first = await page("/articles?group=nato&limit=12");
    const second = await page(`/articles?group=nato&limit=12&cursor=${first.nextCursor}`);
    expect(second.items).toHaveLength(12);
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
    expect(await ids(`/articles?after=${seen.feedSeq}&country=DE`)).toEqual(["de-late", "de-health", "de-new"]);
    expect(await ids(`/articles?after=${seen.feedSeq}&country=DE&topic=economy`)).toEqual(["de-late", "de-new"]);
    expect(await ids(`/articles?after=${seen.feedSeq}&topic=health`)).toEqual(["de-health", "us-new"]);
    expect(await ids(`/articles?after=${seen.feedSeq}&country=UA`)).toEqual([]);
    expect(await ids(`/articles?after=${seen.feedSeq}&group=eu`)).toEqual(["de-late", "de-health", "eu-new", "de-new"]);
    expect(await ids(`/articles?after=${seen.feedSeq}&group=nato&topic=health`)).toEqual(["de-health", "us-new"]);
    expect(await ids(`/articles?after=${seen.feedSeq}&group=g7&topic=economy`)).toEqual(["de-late", "eu-new", "de-new"]);
    expect((await page(`/articles?after=${seen.feedSeq}&country=DE`)).top).toEqual([]);
    expect((await page(`/articles?after=${seen.feedSeq}&group=g20`)).top).toEqual([]);
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
    // Global: the best scores (all published at once here, so by importance; on equal scores the later id),
    // at most 1 per country, 3 in all, best first.
    expect(await topIds("/articles")).toEqual(["us-5", "de-5", "fr-4"]);
    // One country: its own only, all 3 from it; Ukraine has a top story of its own, however low its importance.
    expect(await topIds("/articles?country=DE")).toEqual(["de-5", "de-4", "de-3"]);
    expect(await topIds("/articles?country=UA")).toEqual(["ua-2"]);
    expect(await topIds("/articles?topic=health")).toEqual(["fr-4", "de-4"]);
    expect(await topIds("/articles?country=DE&topic=economy")).toEqual(["de-5", "de-3"]);
    expect(await topIds("/articles?country=US&topic=health")).toEqual([]);
    // A group: among its members' (and the EU institutions'), still at most 1 per country, the EU counted as its own.
    expect(await topIds("/articles?group=eu")).toEqual(["de-5", "fr-4", "eu-3"]);
    expect(await topIds("/articles?group=nato")).toEqual(["us-5", "de-5", "fr-4"]);
    expect(await topIds("/articles?group=g7&topic=economy")).toEqual(["us-5", "de-5", "eu-3"]);
    // Top stories are in items too.
    const p = await page("/articles?group=eu&topic=economy");
    expect(p.items.map((a) => a.id)).toEqual(["eu-3", "de-3", "de-5"]);
    expect(p.top.map((a) => a.id)).toEqual(["de-5", "eu-3"]);

    // In Ukrainian: the same top stories that are translated, in the same order.
    await translated("de-5", "us-5", "fr-4");
    expect(await topIds("/articles?lang=uk&country=DE")).toEqual(["de-5"]);
    expect(await topIds("/articles?lang=uk&group=nato")).toEqual(["us-5", "de-5", "fr-4"]);
    expect(await topIds("/articles?lang=uk&topic=health")).toEqual(["fr-4"]);
    expect(await topIds("/articles?lang=uk")).toEqual(["us-5", "de-5", "fr-4"]);
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
    const pageQuery = (where: Where, lang: boolean) => {
      const filters = feedFilters(where, "health");
      return {
        sql: lang
          ? `SELECT a.id ${FROM_TRANSLATED}
             WHERE ${[...PAGE_CONDITIONS, RECENT_TRANSLATION, ...TRANSLATED_CONDITIONS, ...filters.where].join(" AND ")} ORDER BY a.feed_seq DESC LIMIT 21`
          : `SELECT a.id FROM articles a JOIN sources s ON s.id = a.source_id
             WHERE ${[...PAGE_CONDITIONS, ...filters.where].join(" AND ")} ORDER BY a.feed_seq DESC LIMIT 21`,
        // The language is bound first.
        binds: [...(lang ? ["uk"] : []), ...filters.binds],
        lang,
        where,
        join: true,
      };
    };
    const topics = (where: Where, lang: boolean) => {
      const filters = feedFilters(where, null);
      return { sql: feedTopics(filters, lang ? "uk" : null), binds: [...(lang ? ["uk"] : []), ...filters.binds], lang, where, join: false };
    };
    // The feed page and the topics menu: one country, a small group, the largest (19 source
    // countries), and no Where, in English and in a language.
    const wheres: Where[] = [{ country: "DE" }, group("nato"), group("g20")];
    const queries = [
      ...wheres.flatMap((where) => [pageQuery(where, false), pageQuery(where, true)]),
      ...[...wheres, null].flatMap((where) => [topics(where, false), topics(where, true)]),
    ];
    expect(queries[4].binds).toHaveLength(1 + 19);

    for (const analyzed of [false, true]) {
      // Statistics of a nearly empty table make other plans look cheaper.
      if (analyzed) await env.DB.prepare("ANALYZE").run();
      for (const [i, query] of queries.entries()) {
        const { results } = await env.DB.prepare(`EXPLAIN QUERY PLAN ${query.sql}`)
          .bind(...query.binds)
          .all<{ detail: string }>();
        const plan = results.map((r) => r.detail).join("; ");
        // A language first reads its one translation_langs row and its newest translation (#121).
        const langRow = /^SEARCH l USING COVERING INDEX sqlite_autoindex_translation_langs_1 \(lang=\?\); CORRELATED SCALAR SUBQUERY \d+; SEARCH h USING INDEX article_translations_lang_seq \(lang=\? AND lang_seq>\?\); /;
        if (query.lang) expect(plan, `${i}: ${plan}`).toMatch(langRow);
        expect(plan.replace(langRow, ""), `${analyzed ? "analyzed" : "fresh"} ${i}: ${plan}`).toMatch(/^SEARCH a USING INDEX articles_feed_seq \(feed_seq>\?\)/);
        expect(plan, `${i}: ${plan}`).not.toMatch(/SCAN (a|s|t)\b|AUTOMATIC|TEMP B-TREE/);
        // The country or group: the matching sources read once, in one pass (no automatic index), not a join that drives the walk.
        if (query.where) expect(plan, `${i}: ${plan}`).toMatch(/LIST SUBQUERY \d+; SCAN sources\b/);
        if (query.join) expect(plan).toMatch(/SEARCH s USING (COVERING )?INDEX sqlite_autoindex_sources_1 \(id=\?\)/);
        // A language: each article's translation found by its primary key.
        if (query.lang) expect(plan).toMatch(/SEARCH t USING INDEX sqlite_autoindex_article_translations_1 \(article_id=\? AND lang=\?\)/);
      }
    }

    expect(await ids("/articles?country=DE&topic=health")).toEqual(["now-de"]);
    // The 3 new rows (and the 7-day edge) and the sources table once per query (page and top), not the 60 older rows.
    const sources = (await env.DB.prepare("SELECT COUNT(*) AS n FROM sources").first<{ n: number }>())?.n ?? 0;
    expect(await ids("/articles?group=g20&topic=health")).toEqual(["now-us", "now-de"]);
    expect(await rowsRead(() => get("/articles?country=DE&topic=health"))).toBeLessThan(2 * sources + 40);
    expect(await rowsRead(() => get("/articles?group=g20&topic=health"))).toBeLessThan(2 * sources + 40);
    expect(await rowsRead(() => get("/articles?group=nato"))).toBeLessThan(2 * sources + 40);
    expect(await rowsRead(() => get("/topics?country=DE"))).toBeLessThan(sources + 10);
    expect(await rowsRead(() => get("/topics?group=g20"))).toBeLessThan(sources + 10);
    expect(await rowsRead(() => get("/topics"))).toBeLessThan(10);
    await translated("now-de", "now-us", "now-eu");
    expect(await rowsRead(() => get("/topics?lang=uk&country=DE"))).toBeLessThan(sources + 15);
    expect(await rowsRead(() => get("/topics?lang=uk&group=eu"))).toBeLessThan(sources + 15);
    expect(await rowsRead(() => get("/topics?lang=uk"))).toBeLessThan(15);
  });

  it("reads the top stories from the last 24 hours only, also with table statistics, fresh or stale", async () => {
    // Few released articles and many waiting for their release: with statistics of such a
    // table (ANALYZE), SQLite would rather walk articles_feed_seq, every released article
    // ever, and keeps doing so as older articles fill the table, since nothing refreshes them.
    const countries = ["DE", "US", "FR", "EU"] as const;
    const recent: Item[] = [
      ...Array.from({ length: 10 }, (_, i) => ({ id: `top-${i}`, country: countries[i % 4], importance: 3 + (i % 3), topics: [i % 2 ? "health" : "economy"] })),
      ...Array.from({ length: 100 }, (_, i) => ({ id: `waiting-${i}`, released: false })),
    ];
    await add(...recent);
    await translated("top-0", "top-1", "top-2");
    const top = (where: Where, topic: Topic | null, lang: Lang | null) => ({ ...topStories(feedFilters(where, topic), lang), where, lang });
    // One country, a small group, the largest (19 source countries), and no Where, in English and in a language.
    const wheres: Where[] = [{ country: "DE" }, group("nato"), group("g20"), null];
    const queries = [
      ...wheres.flatMap((where) => [top(where, null, null), top(where, null, "uk")]),
      top(group("g20"), "health", null),
      top(group("g20"), "health", "uk"),
    ];

    for (const step of ["fresh", "analyzed", "stale"] as const) {
      if (step === "analyzed") await env.DB.prepare("ANALYZE").run();
      // Older released articles, after the statistics were taken.
      if (step === "stale") await add(...Array.from({ length: 300 }, (_, i) => ({ id: `old-${i}`, publishedAt: hoursAgo(8 * 24 + i) })));
      for (const [i, query] of queries.entries()) {
        const { results } = await env.DB.prepare(`EXPLAIN QUERY PLAN ${query.sql}`)
          .bind(...query.binds)
          .all<{ detail: string }>();
        const plan = results.map((r) => r.detail).join("; ");
        const label = `${step} ${i}: ${plan}`;
        // The (is_news, published_at) index over the 72 hours; the window and its order then sort what it read.
        expect(plan, label).toMatch(/SEARCH a USING INDEX articles_feed \(is_news=\? AND published_at>\?\)/);
        expect(plan, label).not.toMatch(/articles_feed_seq|SCAN (a|s|t)\b|AUTOMATIC/);
        expect(plan, label).toMatch(/SEARCH s USING (COVERING )?INDEX sqlite_autoindex_sources_1 \(id=\?\)/);
        if (query.where) expect(plan, label).toMatch(/LIST SUBQUERY \d+; SCAN sources\b/);
        if (query.lang) expect(plan, label).toMatch(/SEARCH t USING INDEX sqlite_autoindex_article_translations_1 \(article_id=\? AND lang=\?\)/);
      }
    }

    // The 110 articles of the last 72 hours and the sources table, not the 300 older articles.
    const sources = (await env.DB.prepare("SELECT COUNT(*) AS n FROM sources").first<{ n: number }>())?.n ?? 0;
    for (const [i, query] of queries.entries()) {
      const { meta } = await env.DB.prepare(query.sql).bind(...query.binds).all();
      expect(meta.rows_read, `${i}`).toBeLessThan(recent.length + 3 * sources + 40);
    }
    // And still the right ones.
    expect(await topIds("/articles")).toEqual(["top-8", "top-5", "top-2"]);
    expect(await topIds("/articles?lang=uk")).toEqual(["top-2"]);
  });
});

describe("a language with no translation in the feed's 7 days (#121)", () => {
  it("answers its empty feed, top stories and topics in a few rows, not the whole window", async () => {
    // German while it is off: the feed has articles, none of them in German.
    await add(...Array.from({ length: 60 }, (_, i) => ({ id: `n-${i}`, importance: 3 + (i % 3) })));
    await translated("n-0", "n-1");
    // An old German translation, of an article that has left the 7 days.
    await add({ id: "old", publishedAt: hoursAgo(9 * 24) });
    await translatedInto("de", "old");
    await env.DB.prepare("UPDATE article_translations SET translated_at = ? WHERE article_id = 'old'").bind(hoursAgo(9 * 24)).run();

    for (const path of ["/articles?lang=de", "/articles?lang=de&group=g20&topic=economy", "/articles?lang=de&after=3", "/topics?lang=de"]) {
      const { status, body } = await get(path);
      expect(status, path).toBe(200);
      expect(body, path).toMatchObject(path.startsWith("/topics") ? { topics: [] } : { items: [], top: [] });
      expect(await rowsRead(() => get(path)), path).toBeLessThan(10);
    }
    // A language with translations still walks its feed, as before.
    expect(await ids("/articles?lang=uk")).toEqual(["n-1", "n-0"]);
    expect(await rowsRead(() => get("/articles?lang=uk"))).toBeGreaterThan(60);
  });

  it("shows its first translation as soon as there is one", async () => {
    await add({ id: "first", importance: 5 });
    expect(await ids("/articles?lang=de")).toEqual([]);
    await translatedInto("de", "first");
    expect(await ids("/articles?lang=de")).toEqual(["first"]);
    expect(await topIds("/articles?lang=de")).toEqual(["first"]);
    expect(await topicIds("/topics?lang=de")).toEqual(["economy"]);
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

  it("with country, counts that country's feed only; with group, its members' and the EU institutions' where it has them", async () => {
    await add(
      { id: "de", country: "DE", topics: ["economy"] },
      { id: "eu-1", country: "EU", topics: ["trade"] },
      { id: "eu-2", country: "EU", topics: ["trade", "economy"] },
      { id: "us-1", country: "US", topics: ["health"] },
      { id: "us-2", country: "US", topics: ["health"] },
      { id: "us-3", country: "US", topics: ["health"] },
      { id: "cz-1", country: "CZ", topics: ["energy"] },
    );
    await translatedInto("de", "us-1", "us-2", "us-3", "eu-1");
    expect(await topicIds("/topics")).toEqual(["health", "economy", "trade", "energy"]);
    expect(await topicIds("/topics?country=DE")).toEqual(["economy"]);
    expect(await topicIds("/topics?country=EU")).toEqual(["trade", "economy"]);
    expect(await topicIds("/topics?country=US&lang=de")).toEqual(["health"]);
    expect(await get("/topics?country=UA")).toEqual({ status: 200, body: { topics: [] } });
    // EU: DE, CZ and the EU institutions; NATO: DE, US and CZ, without the EU's trade.
    expect(await topicIds("/topics?group=eu")).toEqual(["economy", "trade", "energy"]);
    expect(await topicIds("/topics?group=nato")).toEqual(["health", "economy", "energy"]);
    expect(await topicIds("/topics?group=g7")).toEqual(["health", "economy", "trade"]);
    expect(await topicIds("/topics?group=g20&lang=de")).toEqual(["health", "trade"]);
    expect(await topicIds("/topics?group=nato&lang=de")).toEqual(["health"]);
    // Every topic offered for a group has posts in its feed, and none left out has.
    for (const g of GROUPS) {
      const offered = await topicIds(`/topics?group=${g.id}`);
      for (const topic of TOPICS) {
        expect((await ids(`/articles?group=${g.id}&topic=${topic}`)).length > 0, `${g.id} ${topic}`).toBe(offered.includes(topic));
      }
    }
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

  /** The groups as GET /countries lists them in English: always all four, in this order. */
  const GROUPS_EN = [
    { id: "eu", name: "European Union", members: ["CZ", "DE", "ES", "FR", "IT", "PL", "EU"] },
    { id: "g7", name: "G7", members: ["CA", "DE", "FR", "GB", "IT", "JP", "US", "EU"] },
    {
      id: "g20",
      name: "G20",
      members: ["AR", "AU", "BR", "CA", "CN", "DE", "FR", "GB", "ID", "IN", "IT", "JP", "KR", "MX", "SA", "TR", "US", "ZA", "EU"],
    },
    { id: "nato", name: "NATO", members: ["CA", "CZ", "DE", "ES", "FR", "GB", "IT", "PL", "TR", "US"] },
  ];

  it("lists the countries of active sources, once each, without the EU or the Kickoff seed rows, after the groups", async () => {
    await env.DB.prepare("DELETE FROM sources WHERE id = 'ua-test-cabinet'").run();
    // Only the Kickoff seed sources: no country yet, but every group (a fixed choice, even with an empty feed).
    expect(await get("/countries")).toEqual({ status: 200, body: { groups: GROUPS_EN, countries: [] } });
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
        groups: GROUPS_EN,
        countries: [
          { code: "DE", name: "Germany" },
          { code: "UA", name: "Ukraine" },
        ],
      },
    });
  });

  it("names the groups in the language asked for, in the same fixed order, with the same members", async () => {
    const names: Record<string, string[]> = {
      en: ["European Union", "G7", "G20", "NATO"],
      uk: ["Європейський Союз", "G7", "G20", "НАТО"],
      ru: ["Европейский союз", "G7", "G20", "НАТО"],
      es: ["Unión Europea", "G7", "G20", "OTAN"],
      de: ["Europäische Union", "G7", "G20", "NATO"],
    };
    for (const lang of ["en", ...LANGS]) {
      const { status, body } = await get(`/countries?lang=${lang}`);
      expect(status, lang).toBe(200);
      const groups = (body as { groups: { id: string; name: string; members: string[] }[] }).groups;
      expect(groups.map((g) => g.name), lang).toEqual(names[lang]);
      expect(groups.map((g) => ({ ...g, name: "" })), lang).toEqual(GROUPS_EN.map((g) => ({ ...g, name: "" })));
    }
    // The European Union is named as the EU institutions' articles are.
    for (const lang of ["en", ...LANGS] as const) expect(names[lang][0]).toBe(countryName("EU", lang));
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
    expect((await get("/countries?lang=de")).body).toMatchObject({
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
    ["/articles?group=brics", "group must be one of: eu, g7, g20, nato"],
    ["/articles?group=EU", "group must be one of: eu, g7, g20, nato"],
    ["/articles?group=", "group must be one of: eu, g7, g20, nato"],
    ["/articles?group=un&topic=health", "group must be one of: eu, g7, g20, nato"],
    ["/topics?group=G7", "group must be one of: eu, g7, g20, nato"],
    ["/articles?country=DE&group=eu", "country and group cannot be used together: send one of them"],
    ["/articles?group=nato&country=US&topic=health&lang=uk", "country and group cannot be used together: send one of them"],
    ["/topics?country=FR&group=g7", "country and group cannot be used together: send one of them"],
    ["/articles?topic=sports", `topic must be one of: ${TOPICS.join(", ")}`],
    ["/articles?topic=Economy", `topic must be one of: ${TOPICS.join(", ")}`],
    ["/articles?topic=&country=DE", `topic must be one of: ${TOPICS.join(", ")}`],
    ["/topics?lang=pl", "lang must be one of: en, uk, ru, es, de"],
    ["/countries?lang=UK", "lang must be one of: en, uk, ru, es, de"],
  ])("rejects %s with a JSON error", async (path, error) => {
    expect(await get(path)).toEqual({ status: 400, body: { error } });
  });
});
