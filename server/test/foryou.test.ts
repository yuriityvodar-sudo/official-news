// For you's order (#230 step 5): importance + relevance + popularity − age, at most 2 of the world's a page.
import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { type Ranked, decodeForYouCursor, encodeForYouCursor, nearCountries, rankForYou } from "../src/api/foryou";
import { type ArticlesPage, get, hideSeed, hoursAgo } from "./helpers";
// Counts `first()` too, which For you reads its kept ranking with (#266: rowsRead alone missed it).
import { siteRowsRead as rowsRead } from "./site-helpers";

const NOW = Date.parse("2026-10-30T12:00:00Z");

/** A row as the ranking reads it: published `hours` before NOW. */
const row = (id: string, importance: number, concern: number, hours = 0, popularity = 0): Ranked => ({
  id,
  importance,
  published_at: new Date(NOW - hours * 3_600_000).toISOString(),
  concern,
  relevance: concern,
  popularity,
});

describe("rankForYou", () => {
  it("orders by importance + relevance + popularity − half a point a day", () => {
    const ranked = rankForYou([row("world-5", 5, 0), row("own-3", 3, 2), row("near-4-two-days", 4, 1, 48), row("own-2-popular", 2, 2, 0, 1.5)], 20, NOW);
    // own-3 5, world-5 5 (the higher id on a tie), own-2-popular 5.5, near-4-two-days 4.
    expect(ranked.map((r) => r.id)).toEqual(["own-2-popular", "world-5", "own-3", "near-4-two-days"]);
  });

  it("takes at most 2 of the world's a page while the reader's own last, then lets the world fill the pages", () => {
    const rows = [...[1, 2, 3, 4, 5, 6].map((n) => row(`world-${n}`, 5, 0, n)), row("own-1", 2, 2, 1)];
    // Pages of 3: two of the world's and the reader's own; then the world, with no own left, fills them.
    expect(rankForYou(rows, 3, NOW).map((r) => r.id)).toEqual(["world-1", "world-2", "own-1", "world-3", "world-4", "world-5", "world-6"]);
    // Pages of 20: one page, in score order.
    expect(rankForYou(rows, 20, NOW).map((r) => r.id)).toEqual(["world-1", "world-2", "world-3", "world-4", "world-5", "world-6", "own-1"]);
    // The world's wait for the next page while the reader's own last.
    const more = [...rows, row("own-2", 2, 2, 2), row("own-3", 2, 2, 3)];
    expect(rankForYou(more, 3, NOW).map((r) => r.id)).toEqual(["world-1", "world-2", "own-1", "world-3", "world-4", "own-2", "world-5", "world-6", "own-3"]);
  });

  it("keeps the EU for its members and for Ukraine among a reader's neighbours and groups", () => {
    expect(nearCountries("CZ")).toEqual(["AT", "DE", "PL", "SK", "EU"]);
    expect(nearCountries("UA")).toContain("EU");
    expect(nearCountries("US")).toEqual(["CA", "MX"]);
    expect(nearCountries("JP")).toEqual([]);
  });

  it("pages with a cursor that keeps the moment the list was ranked at; a feed cursor is not one", () => {
    const cursor = encodeForYouCursor({ at: NOW, seq: 412, offset: 20 });
    expect(decodeForYouCursor(cursor)).toEqual({ at: NOW, seq: 412, offset: 20 });
    expect(decodeForYouCursor(btoa(JSON.stringify([42])))).toBeNull();
    expect(decodeForYouCursor("not a cursor")).toBeNull();
  });
});

describe("GET /articles?for= ranked (#230 step 5)", () => {
  async function add(id: string, source: string, importance: number, hours: number) {
    await env.DB.prepare(
      `INSERT INTO articles (id, source_id, url, original_title, published_at, fetched_at, headline, short_summary, summary,
                             is_news, importance, decision_type, summarized_at, topics, tags, feed_seq, added_at)
       VALUES (?1, ?2, 'https://example.gov/' || ?1, ?1, ?3, ?3, 'Headline ' || ?1, 'Short.', 'Summary.', 1, ?4, 'decision', ?3,
               '["economy"]', '[]', (SELECT COALESCE(MAX(feed_seq), 0) + 1 FROM articles WHERE feed_seq IS NOT NULL), ?3)`,
    )
      .bind(id, source, hoursAgo(hours), importance)
      .run();
  }
  const ids = async (path: string) => ((await get(path)).body as ArticlesPage).items.map((a) => a.id);
  /** Five minutes later: the kept rankings are too old for a first page (RANKING_MINUTES). */
  const fiveMinutesLater = () => env.DB.prepare("UPDATE for_you_rankings SET built_at = '2000-01-01T00:00:00Z'").run();

  beforeEach(async () => {
    await hideSeed();
    await env.DB.prepare(
      "INSERT INTO sources (id, country, name, kind, url, status) VALUES ('cz-test-government', 'CZ', 'Government', 'rss', 'https://vlada.gov.cz/rss', 'active')",
    ).run();
    await add("us-4", "us-white-house", 4, 2);
    await add("cz-3", "cz-test-government", 3, 3);
    await add("fr-4", "fr-foreign-ministry", 4, 1);
  });

  it("lifts what the reader's country reads about and shows its own media about it", async () => {
    // cz-3 5, us-4 and fr-4 4 each: the US one a moment older.
    expect(await ids("/articles?for=CZ")).toEqual(["cz-3", "fr-4", "us-4"]);
    await env.DB.batch([
      env.DB.prepare("INSERT INTO article_views (article_id, lang, title, views, usual, score, checked_at) VALUES ('us-4', 'cs', 'Volby', 2000, 20, 1.5, ?)").bind(hoursAgo(0)),
      env.DB.prepare(
        `INSERT INTO article_media (article_id, country, count, links, score, checked_at)
         VALUES ('us-4', 'CZ', 12, '[{"title":"Volby v USA","outlet":"novinky.cz","url":"https://www.novinky.cz/1"},{"title":"x","outlet":"y","url":"javascript:1"}]', 1, ?)`,
      ).bind(hoursAgo(0)),
    ]);
    // The ranking is kept 5 minutes while nothing new appears; then us-4 4 + 2 (popularity, at most 2):
    // first in Czechia, and nowhere else.
    expect(await ids("/articles?for=CZ")).toEqual(["cz-3", "fr-4", "us-4"]);
    await fiveMinutesLater();
    expect(await ids("/articles?for=CZ")).toEqual(["us-4", "cz-3", "fr-4"]);
    expect(await ids("/articles?for=FR")).toEqual(["fr-4", "us-4", "cz-3"]);
    const items = ((await get("/articles?for=CZ")).body as { items: { id: string; media?: unknown }[] }).items;
    expect(items.find((a) => a.id === "us-4")?.media).toEqual([{ title: "Volby v USA", outlet: "novinky.cz", url: "https://www.novinky.cz/1" }]);
    expect(items.find((a) => a.id === "cz-3")?.media).toEqual([]);
    // Only For you's items carry it.
    expect(((await get("/articles")).body as { items: Record<string, unknown>[] }).items[0]).not.toHaveProperty("media");
  });

  it("keeps the pages of one scroll in the order of their first page, and pages an older feed cursor the old way", async () => {
    const first = (await get("/articles?for=CZ&limit=2")).body as ArticlesPage;
    expect(first.items.map((a) => a.id)).toEqual(["cz-3", "fr-4"]);
    // A new decision meanwhile, better than both: the next page still follows the first one's order.
    await add("cz-5", "cz-test-government", 5, 0);
    expect(await ids(`/articles?for=CZ&limit=2&cursor=${first.nextCursor}`)).toEqual(["us-4"]);
    // The next first page is ranked again: something appeared since (a pull after "N new" shows it).
    expect(await ids("/articles?for=CZ&limit=2")).toEqual(["cz-5", "cz-3"]);
    // The kept ranking a cursor came from still pages it.
    expect(await ids(`/articles?for=CZ&limit=2&cursor=${first.nextCursor}`)).toEqual(["us-4"]);
    // A feed cursor below fr-4 (from an app page loaded before this deploy): the feed's order, as before.
    const feedCursor = btoa(JSON.stringify([first.items[1].feedSeq])).replace(/=+$/, "");
    expect(await ids(`/articles?for=CZ&cursor=${feedCursor}`)).toEqual(["cz-3", "us-4"]);
  });
});

describe("For you's D1 rows (Yurii's review of #260)", () => {
  /** About a week of For you for a reader in Czechia: 200 articles from 5 source countries, 2 countries each, views and media. */
  async function week() {
    await hideSeed();
    await env.DB.prepare(
      "INSERT INTO sources (id, country, name, kind, url, status) VALUES ('cz-test-government', 'CZ', 'Government', 'rss', 'https://vlada.gov.cz/rss', 'active')",
    ).run();
    const sources = ["cz-test-government", "de-federal-government", "eu-european-commission", "us-white-house", "fr-foreign-ministry"];
    const concerned = ["CZ", "DE", "EU", "US", "FR", "PL", "SK", "UA"];
    const statements: D1PreparedStatement[] = [];
    for (let i = 0; i < 200; i++) {
      const id = `w${i}`;
      statements.push(
        env.DB.prepare(
          `INSERT INTO articles (id, source_id, url, original_title, published_at, fetched_at, headline, short_summary, summary,
                                 is_news, importance, decision_type, summarized_at, topics, tags, feed_seq, added_at, reach)
           VALUES (?1, ?2, 'https://example.gov/' || ?1, ?1, ?3, ?3, 'Headline', 'Short.', 'Summary.', 1, ?4, 'decision', ?3,
                   '["economy"]', '[]', (SELECT COALESCE(MAX(feed_seq), 0) + 1 FROM articles WHERE feed_seq IS NOT NULL), ?3, ?5)`,
        ).bind(id, sources[i % sources.length], hoursAgo(160 - i * 0.8), 2 + (i % 4), i % 7 === 0 ? "global" : "national"),
        env.DB.prepare("INSERT INTO article_countries (article_id, country) VALUES (?1, ?2), (?1, ?3)").bind(id, concerned[i % 8], concerned[(i + 3) % 8]),
      );
      if (i % 3 === 0)
        statements.push(
          env.DB.prepare("INSERT INTO article_views (article_id, lang, title, views, usual, score, checked_at) VALUES (?, 'cs', 'X', 500, 20, 1, ?)").bind(id, hoursAgo(1)),
        );
      if (i % 5 === 0)
        statements.push(
          env.DB.prepare("INSERT INTO article_media (article_id, country, count, links, score, checked_at) VALUES (?, 'CZ', 4, '[]', 0.5, ?)").bind(id, hoursAgo(1)),
        );
    }
    await env.DB.batch(statements);
  }

  it("ranks the 7 days once in 5 minutes; a page meanwhile reads its own articles by id", async () => {
    await week();
    const first = await rowsRead(() => get("/articles?for=CZ"));
    const kept = await rowsRead(() => get("/articles?for=CZ"));
    const page = (await get("/articles?for=CZ")).body as ArticlesPage;
    const later = await rowsRead(() => get(`/articles?for=CZ&cursor=${page.nextCursor}`));
    // Measured 30 Oct (the numbers are in the PR and docs/decisions/2026-10-30-for-you-by-score.md).
    expect({ first, kept, later }).toEqual({ first: expect.any(Number), kept: expect.any(Number), later: expect.any(Number) });
    expect(kept).toBeLessThan(250);
    expect(later).toBeLessThan(250);
    expect(first).toBeGreaterThan(4 * kept);
    console.log(JSON.stringify({ forYouRows: { first, kept, later } }));
  });

  // #266: the check for anything new since the kept ranking read the whole table (1,048 rows live on 31 Oct).
  it("reads the same rows for a kept page however many articles the table holds besides the feed", async () => {
    await week();
    await get("/articles?for=CZ");
    const before = await rowsRead(() => get("/articles?for=CZ"));
    const unreleased: D1PreparedStatement[] = [];
    for (let i = 0; i < 300; i++) {
      unreleased.push(
        env.DB.prepare(
          `INSERT INTO articles (id, source_id, url, original_title, published_at, fetched_at, is_news)
           VALUES (?1, 'cz-test-government', 'https://example.gov/old/' || ?1, ?1, ?2, ?2, 0)`,
        ).bind(`old${i}`, hoursAgo(400)),
      );
    }
    await env.DB.batch(unreleased);
    const after = await rowsRead(() => get("/articles?for=CZ"));
    expect(after).toBe(before);
  });
});
