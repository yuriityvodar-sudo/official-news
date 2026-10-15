import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";

import { LIMITS, USER_AGENT, runFetcher } from "../src/fetcher";

const NOW = new Date("2026-10-14T15:00:00Z");

type Site = Record<string, { status?: number; body: string; type?: string } | ((headers: Headers) => Response)>;

/** A fake internet: answers only the URLs in `site`, records every request. */
function fakeFetch(site: Site) {
  const requests: { url: string; userAgent: string | null; headers: Headers }[] = [];
  const fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    const headers = new Headers(init?.headers);
    requests.push({ url, userAgent: headers.get("user-agent"), headers });
    const page = site[url];
    if (!page) return new Response("not found", { status: 404 });
    if (typeof page === "function") return page(headers);
    return new Response(page.body, { status: page.status ?? 200, headers: { "content-type": page.type ?? "text/html; charset=utf-8" } });
  }) as typeof globalThis.fetch;
  return { fetch, requests };
}

async function addSource(id: string, url: string, kind: "rss" | "page" | "api", config: object | null = null, lastCheckedAt: string | null = null) {
  await env.DB.prepare(
    `INSERT INTO sources (id, country, name, kind, url, config, language, verified_by, verified_at, status, last_checked_at)
     VALUES (?, 'XX', ?, ?, ?, ?, 'en', 'domain', '2026-10-14', 'active', ?)`,
  )
    .bind(id, id, kind, url, config ? JSON.stringify(config) : null, lastCheckedAt)
    .run();
}

const articlesOf = async (sourceId: string) =>
  (
    await env.DB.prepare("SELECT url, original_title, published_at, date_only, text, image_url, is_news FROM articles WHERE source_id = ? ORDER BY published_at DESC")
      .bind(sourceId)
      .all<{ url: string; original_title: string; published_at: string; date_only: number; text: string | null; image_url: string | null; is_news: number | null }>()
  ).results;

const longText = "The government adopted the decision after a cabinet meeting today. ".repeat(5);

function rss(items: { title: string; link: string; date: string; text?: string }[]) {
  return `<?xml version="1.0"?><rss><channel>${items
    .map((i) => `<item><title>${i.title}</title><link>${i.link}</link><pubDate>${i.date}</pubDate><description>${i.text ?? longText}</description></item>`)
    .join("")}</channel></rss>`;
}

describe("runFetcher", () => {
  it("saves new items from the last 7 days with their text, once", async () => {
    await addSource("xx-feed", "https://gov.test/feed.xml", "rss");
    const site: Site = {
      "https://gov.test/robots.txt": { body: "User-agent: *\nDisallow: /private/", type: "text/plain" },
      "https://gov.test/feed.xml": {
        type: "application/rss+xml",
        body: rss([
          { title: "Cabinet adopts budget", link: "https://gov.test/news/1", date: "Wed, 14 Oct 2026 09:00:00 GMT" },
          { title: "Law on water signed", link: "https://gov.test/news/2", date: "Mon, 12 Oct 2026 09:00:00 GMT" },
          { title: "Old decree", link: "https://gov.test/news/3", date: "Wed, 30 Sep 2026 09:00:00 GMT" },
        ]),
      },
    };
    const { fetch, requests } = fakeFetch(site);

    const [check] = await runFetcher(env, { fetch, now: NOW });
    expect(check).toMatchObject({ sourceId: "xx-feed", ok: true, httpStatus: 200, found: 3, saved: 2, error: null });
    expect(requests.every((r) => r.userAgent === USER_AGENT)).toBe(true);

    const saved = await articlesOf("xx-feed");
    expect(saved.map((a) => a.original_title)).toEqual(["Cabinet adopts budget", "Law on water signed"]);
    expect(saved[0]).toMatchObject({ published_at: "2026-10-14T09:00:00Z", date_only: 0, is_news: null });
    expect(saved[0].text).toContain("cabinet meeting");

    const source = await env.DB.prepare("SELECT last_checked_at, last_item_at FROM sources WHERE id = 'xx-feed'").first();
    expect(source).toEqual({ last_checked_at: "2026-10-14T15:00:00Z", last_item_at: "2026-10-14T09:00:00Z" });

    // A second run finds the same items and saves nothing new.
    const [again] = await runFetcher(env, { fetch, now: new Date("2026-10-14T15:10:00Z") });
    expect(again).toMatchObject({ ok: true, saved: 0 });
    expect(await articlesOf("xx-feed")).toHaveLength(2);
  });

  it("never checks Kickoff seed sources or blocked sources", async () => {
    await addSource("xx-blocked", "https://blocked.test/feed.xml", "rss");
    await env.DB.prepare("UPDATE sources SET status = 'blocked' WHERE id = 'xx-blocked'").run();
    const { fetch, requests } = fakeFetch({});
    const checks = await runFetcher(env, { fetch, now: NOW });
    expect(checks).toEqual([]);
    expect(requests).toEqual([]);
  });

  it("takes the source checked longest ago, one per run", async () => {
    await addSource("xx-a", "https://a.test/feed.xml", "rss", null, "2026-10-14T14:00:00Z");
    await addSource("xx-b", "https://b.test/feed.xml", "rss", null, "2026-10-14T13:00:00Z");
    await addSource("xx-c", "https://c.test/feed.xml", "rss", null, null);
    const { fetch } = fakeFetch({});
    const order: string[] = [];
    for (let minute = 0; minute < 3; minute++) {
      const checks = await runFetcher(env, { fetch, now: new Date(NOW.getTime() + minute * 60_000) });
      order.push(...checks.map((c) => c.sourceId));
    }
    expect(order).toEqual(["xx-c", "xx-b", "xx-a"]);
    expect(LIMITS.sourcesPerRun).toBe(1);
  });

  it("respects robots.txt and stays away when it cannot be read", async () => {
    await addSource("xx-robots", "https://norobots.test/private/feed.xml", "rss");
    await addSource("xx-down", "https://down.test/feed.xml", "rss");
    const { fetch, requests } = fakeFetch({
      "https://norobots.test/robots.txt": { body: "User-agent: *\nDisallow: /private/", type: "text/plain" },
      "https://down.test/robots.txt": { status: 503, body: "" },
    });
    const checks = [
      ...(await runFetcher(env, { fetch, now: NOW })),
      ...(await runFetcher(env, { fetch, now: new Date(NOW.getTime() + 60_000) })),
    ];
    expect(checks.map((c) => [c.sourceId, c.ok, c.error]).sort()).toEqual([
      ["xx-down", false, "robots.txt answered HTTP 503"],
      ["xx-robots", false, "robots.txt does not allow this path"],
    ]);
    expect(requests.map((r) => r.url).sort()).toEqual(["https://down.test/robots.txt", "https://norobots.test/robots.txt"]);
    const checked = await env.DB.prepare("SELECT count(*) AS n FROM sources WHERE id IN ('xx-robots', 'xx-down') AND last_checked_at IS NOT NULL").first<{ n: number }>();
    expect(checked?.n).toBe(2);
  });

  it("reports a broken list without stopping the run", async () => {
    await addSource("xx-gone", "https://gone.test/feed.xml", "rss");
    const { fetch } = fakeFetch({ "https://gone.test/robots.txt": { status: 404, body: "" } });
    const [check] = await runFetcher(env, { fetch, now: NOW });
    expect(check).toMatchObject({ ok: false, httpStatus: 404, error: "HTTP 404" });
  });

  it("opens item pages for text and image, within the page budget", async () => {
    const items = Array.from({ length: 6 }, (_, i) => `<li class="n"><a href="/d/${i}">Decision ${i}</a><time datetime="2026-10-14T0${i}:00:00Z"></time></li>`);
    await addSource("xx-page", "https://list.test/decisions", "page", { item: "li.n", date: { selector: "time", attr: "datetime" } });
    const site: Site = {
      "https://list.test/robots.txt": { status: 404, body: "" },
      "https://list.test/decisions": { body: `<ul>${items.join("")}</ul>` },
    };
    for (let i = 0; i < 6; i++) {
      site[`https://list.test/d/${i}`] = { body: `<html><head><meta property="og:image" content="/img/${i}.jpg"></head><body><main><p>${longText}</p></main></body></html>` };
    }
    const { fetch } = fakeFetch(site);

    const [check] = await runFetcher(env, { fetch, now: NOW });
    expect(check).toMatchObject({ ok: true, found: 6, saved: LIMITS.pagesPerRun, waiting: 6 - LIMITS.pagesPerRun });
    const saved = await articlesOf("xx-page");
    expect(saved[0]).toMatchObject({ original_title: "Decision 5", image_url: "https://list.test/img/5.jpg" });
    expect(saved[0].text).toContain("cabinet meeting");

    // The items left waiting are saved on the next checks, a page budget at a time.
    let left = 6 - LIMITS.pagesPerRun;
    for (let minute = 10; left > 0; minute += 10) {
      const [next] = await runFetcher(env, { fetch, now: new Date(NOW.getTime() + minute * 60_000) });
      const saved = Math.min(left, LIMITS.pagesPerRun);
      left -= saved;
      expect(next).toMatchObject({ saved, waiting: left });
    }
    expect(await articlesOf("xx-page")).toHaveLength(6);
  });

  it("keeps each new stage of the same item when the source asks for it", async () => {
    await addSource("xx-bills", "https://parl.test/bills.xml", "rss", { newStageIsNewItem: true });
    const bill = (date: string) => rss([{ title: "C-37 Clean Water Act", link: "https://parl.test/bill/C-37", date }]);
    const site: Site = { "https://parl.test/robots.txt": { status: 404, body: "" }, "https://parl.test/bills.xml": { body: bill("Fri, 09 Oct 2026 13:20:48 GMT") } };
    const { fetch } = fakeFetch(site);
    await runFetcher(env, { fetch, now: NOW });
    site["https://parl.test/bills.xml"] = { body: bill("Wed, 14 Oct 2026 10:00:00 GMT") };
    await runFetcher(env, { fetch, now: new Date("2026-10-14T15:10:00Z") });
    expect((await articlesOf("xx-bills")).map((a) => a.url)).toEqual(["https://parl.test/bill/C-37#2026-10-14", "https://parl.test/bill/C-37#2026-10-09"]);
  });

  it("asks only for changes when the source supports it, with the server's own validators", async () => {
    await addSource("xx-archive", "https://archive.test/list.json", "api", { items: "", title: "TITLE", link: "URL", date: { field: "DOCRELPUBTIME" }, conditionalGet: true, itemPages: false });
    const list = JSON.stringify([{ TITLE: "Opinions on new productive forces", URL: "https://archive.test/p/1.htm", DOCRELPUBTIME: "2026-10-13" }]);
    const { fetch, requests } = fakeFetch({
      "https://archive.test/robots.txt": { status: 404, body: "" },
      "https://archive.test/list.json": (headers) =>
        headers.get("if-none-match") === '"v1"'
          ? new Response(null, { status: 304 })
          : new Response(list, { headers: { "content-type": "application/json", etag: '"v1"', "last-modified": "Fri, 09 Oct 2026 10:19:05 GMT" } }),
    });

    const [first] = await runFetcher(env, { fetch, now: NOW });
    expect(first).toMatchObject({ ok: true, httpStatus: 200, saved: 1 });
    expect(await env.DB.prepare("SELECT list_etag, list_last_modified FROM sources WHERE id = 'xx-archive'").first()).toEqual({
      list_etag: '"v1"',
      list_last_modified: "Fri, 09 Oct 2026 10:19:05 GMT",
    });

    const [second] = await runFetcher(env, { fetch, now: new Date("2026-10-14T15:10:00Z") });
    expect(second).toMatchObject({ ok: true, httpStatus: 304, found: 0, saved: 0, error: null });
    const sent = requests.filter((r) => r.url.endsWith("list.json")).at(-1)?.headers;
    expect([sent?.get("if-none-match"), sent?.get("if-modified-since")]).toEqual(['"v1"', "Fri, 09 Oct 2026 10:19:05 GMT"]);
  });

  it("stores http links of an https source as https", async () => {
    await addSource("xx-kremlin", "https://kremlin.test/acts/feed", "rss", { itemPages: false });
    const { fetch } = fakeFetch({
      "https://kremlin.test/robots.txt": { status: 404, body: "" },
      "https://kremlin.test/acts/feed": { body: rss([{ title: "Decree signed", link: "http://kremlin.test/acts/80977", date: "Mon, 12 Oct 2026 15:06:00 +0300" }]) },
    });
    await runFetcher(env, { fetch, now: NOW });
    expect((await articlesOf("xx-kremlin")).map((a) => a.url)).toEqual(["https://kremlin.test/acts/80977"]);
  });

  it("claims its sources before reading them, so a cut-off run cannot stall the line", async () => {
    await addSource("xx-claim", "https://claim.test/feed.xml", "rss", null, "2026-10-01T00:00:00Z");
    let seenWhileFetching: unknown = null;
    const { fetch } = fakeFetch({
      "https://claim.test/robots.txt": () => new Response("", { status: 404 }),
      "https://claim.test/feed.xml": () => {
        throw new Error("the run is killed here");
      },
    });
    const watching = (async (input: RequestInfo | URL, init?: RequestInit) => {
      seenWhileFetching ??= (await env.DB.prepare("SELECT last_checked_at FROM sources WHERE id = 'xx-claim'").first())?.last_checked_at;
      return fetch(input, init);
    }) as typeof globalThis.fetch;
    const [check] = await runFetcher(env, { fetch: watching, now: NOW });
    expect(seenWhileFetching).toBe("2026-10-14T15:00:00Z");
    expect(check).toMatchObject({ ok: false, error: "the run is killed here" });
  });

  it("keeps only links on the source's own site, or hosts the config allows", async () => {
    await addSource("xx-links", "https://www.gov.test/feed.xml", "rss", { itemPages: false, allowedHosts: ["portal.partner.test"] });
    const { fetch } = fakeFetch({
      "https://www.gov.test/robots.txt": { status: 404, body: "" },
      "https://www.gov.test/feed.xml": {
        body: rss([
          { title: "Own page", link: "https://www.gov.test/news/1", date: "Wed, 14 Oct 2026 09:00:00 GMT" },
          { title: "Subdomain", link: "http://press.gov.test/news/2", date: "Wed, 14 Oct 2026 09:00:00 GMT" },
          { title: "Allowed partner", link: "https://portal.partner.test/3", date: "Wed, 14 Oct 2026 09:00:00 GMT" },
          { title: "Video", link: "https://www.youtube.com/watch?v=x", date: "Wed, 14 Oct 2026 09:00:00 GMT" },
          { title: "Lookalike", link: "https://gov.test.evil.example/4", date: "Wed, 14 Oct 2026 09:00:00 GMT" },
        ]),
      },
    });
    const [check] = await runFetcher(env, { fetch, now: NOW });
    expect(check).toMatchObject({ found: 3, saved: 3, offSite: 2 });
    expect((await articlesOf("xx-links")).map((a) => a.url).sort()).toEqual([
      "https://portal.partner.test/3",
      "https://press.gov.test/news/2",
      "https://www.gov.test/news/1",
    ]);
  });

  it("never stores a time later than the fetch, and skips items without a date", async () => {
    await addSource("xx-times", "https://times.test/list.json", "api", { items: "", title: "t", link: "u", date: { field: "d" }, itemPages: false });
    const { fetch } = fakeFetch({
      "https://times.test/robots.txt": { status: 404, body: "" },
      "https://times.test/list.json": {
        type: "application/json",
        body: JSON.stringify([
          { t: "Beijing time read as UTC", u: "https://times.test/1", d: "2026-10-14T20:00:00" },
          { t: "No date at all", u: "https://times.test/2", d: null },
        ]),
      },
    });
    const [check] = await runFetcher(env, { fetch, now: NOW });
    expect(check).toMatchObject({ saved: 1, undated: 1 });
    expect((await articlesOf("xx-times"))[0]).toMatchObject({ original_title: "Beijing time read as UTC", published_at: "2026-10-14T15:00:00Z" });
  });
});
