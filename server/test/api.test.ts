import { env, exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { PAGE_CONDITIONS } from "../src/api";

interface Article {
  id: string;
  country: string;
  publishedAt: string;
  importance: number | null;
  topics: string[];
  tags: string[];
}

interface ArticlesPage {
  items: Article[];
  nextCursor: string | null;
  top: Article[];
}

async function get(path: string) {
  const response = await exports.default.fetch(`https://api.test${path}`);
  return { status: response.status, type: response.headers.get("content-type"), body: await response.json() };
}

async function getPage(path: string): Promise<ArticlesPage> {
  const { status, body } = await get(path);
  expect(status).toBe(200);
  return body as ArticlesPage;
}

/** A stored timestamp `hours` before now, in the `YYYY-MM-DDTHH:MM:SSZ` format. */
function hoursAgo(hours: number): string {
  return `${new Date(Date.now() - hours * 3_600_000).toISOString().slice(0, 19)}Z`;
}

interface TestArticle {
  id: string;
  publishedAt: string;
  sourceId?: string;
  isNews?: number | null;
  importance?: number | null;
  topics?: string;
  /** When it appeared in the feed; defaults to now, as the summarizer stamps it. */
  addedAt?: string;
}

async function insertArticles(articles: TestArticle[]) {
  await env.DB.batch(
    articles.map((a) =>
      env.DB.prepare(
        // Visible articles get the next feed_seq, as the summarizer gives it: insertion order is feed order.
        `INSERT INTO articles (id, source_id, url, original_title, published_at, fetched_at,
                               headline, is_news, importance, topics, decision_type, feed_seq, added_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, 'decision',
                 CASE WHEN ?8 = 1 THEN (SELECT COALESCE(MAX(feed_seq), 0) + 1 FROM articles WHERE feed_seq IS NOT NULL) END,
                 CASE WHEN ?8 = 1 THEN ?11 END)`,
      ).bind(
        a.id,
        a.sourceId ?? "de-federal-government",
        `https://example.gov/${a.id}`,
        `Title ${a.id}`,
        a.publishedAt,
        a.publishedAt,
        `Headline ${a.id}`,
        a.isNews === undefined ? 1 : a.isNews,
        a.importance ?? null,
        a.topics ?? '["economy"]',
        a.addedAt ?? hoursAgo(0),
      ),
    ),
  );
}

const SEED_DECISIONS = ["01JASEED000000000000000003", "01JASEED000000000000000014", "01JASEED000000000000000019"];

describe("GET /articles", () => {
  it("returns the seed decisions in the contract format, newest first", async () => {
    const page = await getPage("/articles");
    expect(page.items.map((a) => a.id).sort()).toEqual(SEED_DECISIONS);
    expect(page.nextCursor).toBeNull();
    expect(page.top).toEqual([]);
    expect(Object.keys(page.items[0]).sort()).toEqual(
      [
        "addedAt", "country", "dateOnly", "decisionType", "feedSeq", "headline", "id", "imageUrl", "importance",
        "originalLanguage", "originalTitle", "originalUrl", "publishedAt", "shortSummary",
        "source", "summary", "tags", "topics",
      ].sort(),
    );
    const order = page.items.map((a) => (a as unknown as { feedSeq: number }).feedSeq);
    expect(order).toEqual([...order].sort((x, y) => y - x));
  });

  it("puts an article that appears late on top, above newer publication dates", async () => {
    await insertArticles([{ id: "published-1h-ago", publishedAt: hoursAgo(1) }]);
    // Published 30 hours ago, but only now marked as news by the AI step.
    await insertArticles([{ id: "late", publishedAt: hoursAgo(30) }]);
    const ids = (await getPage("/articles")).items.map((a) => a.id);
    expect(ids.slice(0, 2)).toEqual(["late", "published-1h-ago"]);
  });

  it("with after, returns only articles that appeared after that feedSeq, late ones included", async () => {
    await insertArticles([{ id: "seen", publishedAt: hoursAgo(1) }]);
    const seen = (await getPage("/articles")).items[0] as unknown as { id: string; feedSeq: number };
    expect(seen.id).toBe("seen");
    await insertArticles([
      { id: "late", publishedAt: hoursAgo(40) },
      { id: "fresh", publishedAt: hoursAgo(0.5) },
    ]);
    const page = await getPage(`/articles?after=${seen.feedSeq}`);
    expect(page.items.map((a) => a.id)).toEqual(["fresh", "late"]);
    expect(page.top).toEqual([]);
  });

  it("still accepts a cursor from an app build before feed_seq", async () => {
    await insertArticles(Array.from({ length: 5 }, (_, i) => ({ id: `old-${i}`, publishedAt: hoursAgo(1) })));
    const first = await getPage("/articles?limit=3");
    const oldStyle = btoa(JSON.stringify([first.items[2].publishedAt, first.items[2].id])).replace(/=+$/, "");
    const next = await getPage(`/articles?limit=3&cursor=${oldStyle}`);
    expect(next.items.map((a) => a.id)).not.toContain(first.items[2].id);
    expect(next.items[0].id).toBe((await getPage("/articles?limit=4")).items[3].id);
  });

  it("hides articles the AI marked as not news or has not checked yet", async () => {
    await insertArticles([
      { id: "hidden-0", publishedAt: hoursAgo(1), isNews: 0 },
      { id: "unchecked", publishedAt: hoursAgo(1), isNews: null },
    ]);
    const ids = (await getPage("/articles")).items.map((a) => a.id);
    expect(ids).not.toContain("hidden-0");
    expect(ids).not.toContain("unchecked");
  });

  it("keeps only the last 7 days", async () => {
    await insertArticles([
      { id: "six-days", publishedAt: hoursAgo(6 * 24) },
      { id: "eight-days", publishedAt: hoursAgo(8 * 24) },
    ]);
    const ids = (await getPage("/articles")).items.map((a) => a.id);
    expect(ids).toContain("six-days");
    expect(ids).not.toContain("eight-days");
  });

  it("pages through articles with the same time without gaps or repeats", async () => {
    const sameTime = hoursAgo(2);
    await insertArticles(
      Array.from({ length: 25 }, (_, i) => ({ id: `same-${String(i).padStart(2, "0")}`, publishedAt: sameTime })),
    );

    const seen: string[] = [];
    let path = "/articles?limit=10";
    for (let pages = 0; pages < 10; pages++) {
      const page = await getPage(path);
      seen.push(...page.items.map((a) => a.id));
      if (!page.nextCursor) break;
      expect(page.top).toEqual([]);
      path = `/articles?limit=10&cursor=${page.nextCursor}`;
    }

    expect(seen).toHaveLength(25 + SEED_DECISIONS.length);
    expect(new Set(seen).size).toBe(seen.length);
  });

  it("with since, returns what appeared after the article the app showed first", async () => {
    await insertArticles([{ id: "older", publishedAt: hoursAgo(5) }]);
    const top = (await getPage("/articles")).items[0];
    expect(top.id).toBe("older");
    await insertArticles([{ id: "newer", publishedAt: hoursAgo(1) }]);
    const page = await getPage(`/articles?since=${encodeURIComponent(top.publishedAt)}`);
    expect(page.items.map((a) => a.id)).toEqual(["newer"]);
    expect(page.top).toEqual([]);
  });

  it("with since from a build before #39, counts only what appeared after its first article", async () => {
    // Such a build sends the publication time of the first article it shows; in the
    // feed's order that is the newest to appear, here one published 30 hours ago.
    await insertArticles([{ id: "late-top", publishedAt: hoursAgo(30) }]);
    const top = (await getPage("/articles")).items[0];
    expect(top.id).toBe("late-top");
    const since = `/articles?since=${encodeURIComponent(top.publishedAt)}`;
    expect((await getPage(since)).items).toEqual([]);
    await insertArticles([{ id: "fresh", publishedAt: hoursAgo(0.5) }]);
    expect((await getPage(since)).items.map((a) => a.id)).toEqual(["fresh"]);
  });

  it("with since from a build before #39, counts a late article and the fresh ones before it", async () => {
    await insertArticles([{ id: "seen", publishedAt: hoursAgo(1) }]);
    const top = (await getPage("/articles")).items[0];
    // After the app loaded: one fresh decision, then one published 40 hours ago.
    await insertArticles([
      { id: "fresh", publishedAt: hoursAgo(0.5) },
      { id: "late", publishedAt: hoursAgo(40) },
    ]);
    const page = await getPage(`/articles?since=${encodeURIComponent(top.publishedAt)}`);
    expect(page.items.map((a) => a.id)).toEqual(["late", "fresh"]);
  });

  it("walks the feed index and stops at the 7-day edge instead of reading older rows", async () => {
    // As in the live table: older rows have lower numbers and appeared earlier. The seed
    // rows' numbers are dropped so the 60 old rows can come first.
    await env.DB.prepare("UPDATE articles SET feed_seq = NULL, added_at = NULL").run();
    await insertArticles(
      Array.from({ length: 60 }, (_, i) => {
        const at = hoursAgo(10 * 24 + i);
        return { id: `old-${i}`, publishedAt: at, addedAt: at };
      }).reverse(),
    );
    await insertArticles(Array.from({ length: 3 }, (_, i) => ({ id: `now-${i}`, publishedAt: hoursAgo(1) })));
    const sql = `SELECT a.id FROM articles a JOIN sources s ON s.id = a.source_id
                 WHERE ${PAGE_CONDITIONS.join(" AND ")} ORDER BY a.feed_seq DESC LIMIT 21`;
    const plan = await env.DB.prepare(`EXPLAIN QUERY PLAN ${sql}`).all<{ detail: string }>();
    const details = plan.results.map((r) => r.detail).join(" | ");
    expect(details).toContain("articles_feed_seq");
    expect(details).not.toContain("TEMP B-TREE FOR ORDER BY");
    const { results, meta } = await env.DB.prepare(sql).all<{ id: string }>();
    expect(results.map((r) => r.id)).toEqual(expect.arrayContaining(["now-0", "now-1", "now-2"]));
    expect(results.some((r) => r.id.startsWith("old-"))).toBe(false);
    // The 3 new rows (and their sources), not the 60 older ones.
    expect(meta.rows_read).toBeLessThan(20);
  });

  it("continues an old cursor whose article is gone instead of ending the feed", async () => {
    await insertArticles(Array.from({ length: 3 }, (_, i) => ({ id: `kept-${i}`, publishedAt: hoursAgo(3) })));
    const gone = btoa(JSON.stringify([hoursAgo(2), "01JAGONE000000000000000000"])).replace(/=+$/, "");
    const ids = (await getPage(`/articles?cursor=${gone}`)).items.map((a) => a.id);
    expect(ids).toEqual(expect.arrayContaining(["kept-0", "kept-1", "kept-2"]));
  });

  it("shows in top only articles that are in the feed", async () => {
    await env.DB.prepare(
      `INSERT INTO articles (id, source_id, url, original_title, published_at, fetched_at, headline, is_news, importance, topics)
       VALUES ('no-number', 'de-federal-government', 'https://example.gov/no-number', 'T', ?1, ?1, 'H', 1, 5, '[]')`,
    )
      .bind(hoursAgo(1))
      .run();
    const page = await getPage("/articles");
    expect(page.top.map((a) => a.id)).not.toContain("no-number");
    expect(page.items.map((a) => a.id)).not.toContain("no-number");
  });

  it("puts the most important of the last 24 hours in top, at most 2 per country and 5 in all", async () => {
    await insertArticles([
      { id: "de-5", publishedAt: hoursAgo(1), importance: 5, sourceId: "de-federal-government" },
      { id: "de-4", publishedAt: hoursAgo(2), importance: 4, sourceId: "de-federal-government" },
      { id: "de-3", publishedAt: hoursAgo(3), importance: 3, sourceId: "de-federal-government" },
      { id: "us-5", publishedAt: hoursAgo(4), importance: 5, sourceId: "us-white-house" },
      { id: "fr-4", publishedAt: hoursAgo(1), importance: 4, sourceId: "fr-foreign-ministry" },
      { id: "jp-3", publishedAt: hoursAgo(1), importance: 3, sourceId: "jp-foreign-ministry" },
      { id: "gb-2", publishedAt: hoursAgo(1), importance: 2, sourceId: "gb-prime-minister-s-office" },
      { id: "it-5-old", publishedAt: hoursAgo(30), importance: 5, sourceId: "it-government-pm-meloni" },
    ]);
    const top = (await getPage("/articles")).top;
    expect(top.map((a) => a.id)).toEqual(["de-5", "us-5", "fr-4", "de-4", "jp-3"]);
  });

  it("reads broken JSON in topics as an empty list instead of failing the feed", async () => {
    await insertArticles([{ id: "bad-json", publishedAt: hoursAgo(1), topics: "not json" }]);
    const article = (await getPage("/articles")).items.find((a) => a.id === "bad-json");
    expect(article?.topics).toEqual([]);
  });

  it.each([
    ["limit=0"],
    ["limit=51"],
    ["limit=ten"],
    ["cursor=not-a-cursor"],
    ["since=yesterday"],
    ["after=-1"],
    ["after=12abc"],
  ])("rejects %s with a JSON error", async (query) => {
    const { status, type, body } = await get(`/articles?${query}`);
    expect(status).toBe(400);
    expect(type).toContain("application/json");
    expect(body).toHaveProperty("error");
  });
});

describe("GET /articles/:id", () => {
  it("returns one article shown in the feed", async () => {
    const { status, body } = await get(`/articles/${SEED_DECISIONS[0]}`);
    expect(status).toBe(200);
    expect(body).toMatchObject({ id: SEED_DECISIONS[0] });
  });

  it("returns 404 for a hidden or unknown article", async () => {
    expect((await get("/articles/01JASEED000000000000000001")).status).toBe(404);
    expect((await get("/articles/nope")).status).toBe(404);
    expect((await get("/articles/%E0%A4%A")).status).toBe(404);
  });
});

describe("other requests", () => {
  it("GET /health counts sources per status", async () => {
    const { status, body } = await get("/health");
    expect(status).toBe(200);
    expect(body).toEqual({ sources: { active: 20 }, lastFetcherRun: null });
  });

  it("returns JSON errors for unknown paths and other methods", async () => {
    const notFound = await get("/nope");
    expect(notFound.status).toBe(404);
    expect(notFound.type).toContain("application/json");

    const post = await exports.default.fetch("https://api.test/articles", { method: "POST" });
    expect(post.status).toBe(405);
    expect(post.headers.get("allow")).toBe("GET");
  });
});
