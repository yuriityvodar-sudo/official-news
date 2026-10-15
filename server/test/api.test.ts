import { env, exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";

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
}

async function insertArticles(articles: TestArticle[]) {
  await env.DB.batch(
    articles.map((a) =>
      env.DB.prepare(
        `INSERT INTO articles (id, source_id, url, original_title, published_at, fetched_at,
                               headline, is_news, importance, topics, decision_type)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'decision')`,
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
        "country", "dateOnly", "decisionType", "headline", "id", "imageUrl", "importance",
        "originalLanguage", "originalTitle", "originalUrl", "publishedAt", "shortSummary",
        "source", "summary", "tags", "topics",
      ].sort(),
    );
    const times = page.items.map((a) => a.publishedAt);
    expect(times).toEqual([...times].sort().reverse());
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

  it("with since, returns only articles published after that time", async () => {
    await insertArticles([
      { id: "older", publishedAt: hoursAgo(5) },
      { id: "newer", publishedAt: hoursAgo(1) },
    ]);
    const page = await getPage(`/articles?since=${encodeURIComponent(hoursAgo(2))}`);
    expect(page.items.map((a) => a.id)).toEqual(["newer"]);
    expect(page.top).toEqual([]);
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
  it("GET /health counts real sources per status, and seed rows not at all", async () => {
    const { status, body } = await get("/health");
    expect(status).toBe(200);
    // Only the 20 Kickoff seed sources exist here, and health skips them.
    expect(body).toEqual({ sources: {}, lastFetcherRun: null, articles: { fetchedLast24h: expect.any(Number), waitingForSummary: 0, inFeed: 3 } });
  });

  it("GET /health shows the last fetcher run and the articles waiting for the AI", async () => {
    await env.DB.batch([
      env.DB.prepare(
        "INSERT INTO sources (id, country, name, kind, url, status, last_checked_at) VALUES ('xx-a', 'XX', 'A', 'rss', 'https://a.test/feed', 'active', '2026-10-14T18:00:00Z'), ('xx-b', 'XX', 'B', 'rss', 'https://b.test/feed', 'broken', '2026-10-14T18:01:00Z')",
      ),
      env.DB.prepare(
        "INSERT INTO articles (id, source_id, url, original_title, published_at, fetched_at) VALUES ('w1', 'xx-a', 'https://a.test/1', 'Waiting', strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-1 hours'), strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-1 hours'))",
      ),
    ]);
    const { body } = await get("/health");
    expect(body).toMatchObject({
      sources: { active: 1, broken: 1 },
      lastFetcherRun: "2026-10-14T18:01:00Z",
      articles: { waitingForSummary: 1, inFeed: 3 },
    });
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
