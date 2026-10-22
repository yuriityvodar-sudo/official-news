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

  it("takes no picture from item pages when the source says so (pageImage: false), and opens no page only for one", async () => {
    // The ILO's only picture is its emblem, which its terms forbid with adaptations.
    await addSource("xx-emblem", "https://org.test/decisions", "page", { item: "li.d", summary: "p", date: { selector: "time", attr: "datetime" }, pageImage: false });
    const items = [
      `<li class="d"><a href="/d/teaser">Decision concerning A</a><p>Short intro.</p><time datetime="2026-10-14T09:00:00Z"></time></li>`,
      `<li class="d"><a href="/d/full">Decision concerning B</a><p>${"The Governing Body decided to adopt the programme. ".repeat(25)}</p><time datetime="2026-10-14T08:00:00Z"></time></li>`,
    ];
    const page = `<html><head><meta property="og:image" content="/sites/default/files/emblem.png"><meta name="twitter:image" content="/sites/default/files/emblem.png"></head><body><main><p>${longText}</p></main></body></html>`;
    const { fetch, requests } = fakeFetch({
      "https://org.test/robots.txt": { status: 404, body: "" },
      "https://org.test/decisions": { body: `<ul>${items.join("")}</ul>` },
      "https://org.test/d/teaser": { body: page },
      "https://org.test/d/full": { body: page },
    });

    const [check] = await runFetcher(env, { fetch, now: NOW });
    expect(check).toMatchObject({ ok: true, found: 2, saved: 2, waiting: 0 });
    const [teaser, full] = await articlesOf("xx-emblem");
    // The teaser's page is read for its text, but its picture is left out.
    expect(teaser).toMatchObject({ original_title: "Decision concerning A", image_url: null });
    expect(teaser.text).toContain("cabinet meeting");
    // A whole list text without a picture opens no page: there is nothing to take from it.
    expect(full).toMatchObject({ original_title: "Decision concerning B", image_url: null });
    expect(requests.some((r) => r.url.endsWith("/d/full"))).toBe(false);
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

  it("asks a list that takes a year for the current one ({year} in the URL), so it needs no change on 1 January", async () => {
    // Brazil's Senate lists federal norms one year at a time.
    const list = "https://legis.senado.test/dadosabertos/legislacao/lista.json?tipo=EMC&ano={year}";
    await addSource("xx-year", list, "api", {
      items: "ListaDocumento.documentos.documento",
      title: "{normaNome}: {ementa}",
      text: "{ementa}",
      date: { field: "dataassinatura", dateOnly: true },
      link: "https://legis.senado.test/norma/{id}",
      itemPages: false,
    });
    const norm = (id: string, nome: string, date: string) => ({ id, normaNome: nome, ementa: "Altera o art. 7º da Constituição Federal.", dataassinatura: date });
    const { fetch, requests } = fakeFetch({
      "https://legis.senado.test/robots.txt": { status: 403, body: "Forbidden" },
      "https://legis.senado.test/dadosabertos/legislacao/lista.json?tipo=EMC&ano=2026": {
        type: "application/json",
        body: JSON.stringify({ ListaDocumento: { documentos: { documento: [norm("44184944", "Emenda Constitucional nº 141 de 13/10/2026", "13/10/2026")] } } }),
      },
      "https://legis.senado.test/dadosabertos/legislacao/lista.json?tipo=EMC&ano=2027": {
        type: "application/json",
        body: JSON.stringify({ ListaDocumento: { documentos: { documento: [norm("45000001", "Emenda Constitucional nº 142 de 02/01/2027", "02/01/2027")] } } }),
      },
    });

    expect(await runFetcher(env, { fetch, now: NOW })).toMatchObject([{ ok: true, saved: 1 }]);
    await env.DB.prepare("UPDATE sources SET last_checked_at = NULL WHERE id = 'xx-year'").run();
    expect(await runFetcher(env, { fetch, now: new Date("2027-01-03T10:00:00Z") })).toMatchObject([{ ok: true, saved: 1 }]);

    expect(requests.map((r) => r.url).filter((u) => u.includes("lista.json"))).toEqual([
      "https://legis.senado.test/dadosabertos/legislacao/lista.json?tipo=EMC&ano=2026",
      "https://legis.senado.test/dadosabertos/legislacao/lista.json?tipo=EMC&ano=2027",
    ]);
    expect((await articlesOf("xx-year")).map((a) => [a.url, a.published_at])).toEqual([
      ["https://legis.senado.test/norma/45000001", "2027-01-02T12:00:00Z"],
      ["https://legis.senado.test/norma/44184944", "2026-10-13T12:00:00Z"],
    ]);
  });
});

// #71: sources whose list gives only a teaser. Fixtures are trimmed from the real pages and answers.
describe("runFetcher: whole texts (#71)", () => {
  const deTeaser =
    "Mit der Cyberresilienz-Verordnung werden erstmalig Mindeststandards bei der Cybersicherheit für smarte Geräte, Software und weitere Produkte mit digitalen Elementen festgelegt. Europa macht sich widerstandsfähiger gegen Cyberangriffe und gewährleistet sichere digitale Dienste.";
  const deBody = [
    "Der sogenannte Cyber Resilience Act (CRA) legt erstmalig ein Mindestmaß an Cybersicherheit für alle vernetzten Produkte fest, die auf dem EU-Markt erhältlich sind.",
    "Mit der europäischen Cyberresilienz-Verordnung werden verbindliche Cybersicherheitsanforderungen für „Produkte mit digitalen Elementen“ eingeführt.",
    "Das Bundesamt für Sicherheit in der Informationstechnik wird Marktüberwachungsbehörde im Sinne dieser Verordnung.",
  ];
  const dePage = (body: string[]) => `<html><head><meta property="og:image" content="/resource/image/2427030/og.jpg"></head><body>
    <main id="main"><header class="bpa-article-header"><div class="bpa-short-text"><p>${deTeaser}</p></div></header>
    <div class="bpa-share"><ul><li><a href="mailto:?">per E-Mail teilen, Mehr Resilienz für Smart-Geräte</a></li></ul></div>
    <div class="bpa-module-full bpa-article bpa-padded"><div class="bpa-richtext">${body.map((p) => `<p>${p}</p>`).join("")}</div></div></main></body></html>`;
  const deItem = (slug: string, date: string, description = deTeaser) =>
    `<item><title>${slug}</title><link>https://www.bundesregierung.de/breg-de/aktuelles/${slug}</link><description>${description}</description>
      <enclosure url="https://www.bundesregierung.de/resource/blob/975228/${slug}-data.jpg" length="803620" type="image/jpeg" /><pubDate>${date}</pubDate></item>`;
  const deFeed = (...items: string[]) => `<?xml version="1.0" encoding="UTF-8"?><rss version="2.0"><channel><title>Artikel</title>${items.join("")}</channel></rss>`;
  const DE_FEED = "https://www.bundesregierung.de/service/rss/breg-de/1151246/feed.xml";
  const DE_CONFIG = { textSelector: "div.bpa-article .bpa-richtext" };

  it("reads the item page for a teaser, also when the feed has a picture; a full feed text opens no page", async () => {
    await addSource("xx-de", DE_FEED, "rss", DE_CONFIG);
    const fullText = "Die Bundesregierung hat heute im Kabinett den Entwurf beschlossen. ".repeat(16);
    const { fetch, requests } = fakeFetch({
      "https://www.bundesregierung.de/robots.txt": { status: 404, body: "" },
      [DE_FEED]: {
        type: "application/rss+xml",
        body: deFeed(deItem("cyberresilienz-2426502", "Wed, 14 Oct 2026 09:00:00 GMT"), deItem("haushalt-2027", "Wed, 14 Oct 2026 08:00:00 GMT", fullText)),
      },
      "https://www.bundesregierung.de/breg-de/aktuelles/cyberresilienz-2426502": { body: dePage(deBody) },
    });

    const [check] = await runFetcher(env, { fetch, now: NOW });
    expect(check).toMatchObject({ ok: true, saved: 2, waiting: 0 });
    const [teaser, full] = await articlesOf("xx-de");
    // The feed's lead is not in the article body, so it stays in front of it.
    expect(teaser.text).toBe([deTeaser, ...deBody].join("\n"));
    // The feed's picture stays; the page only adds one when the feed has none.
    expect(teaser.image_url).toBe("https://www.bundesregierung.de/resource/blob/975228/cyberresilienz-2426502-data.jpg");
    expect(full.text).toBe(fullText.trim());
    expect(requests.some((r) => r.url.endsWith("/haushalt-2027"))).toBe(false);
  });

  it("lets a teaser wait for the page budget instead of saving it", async () => {
    await addSource("xx-de", DE_FEED, "rss", DE_CONFIG);
    const slugs = ["a-3", "b-2", "c-1"];
    const site: Site = {
      "https://www.bundesregierung.de/robots.txt": { status: 404, body: "" },
      [DE_FEED]: { body: deFeed(...slugs.map((s, i) => deItem(s, `Wed, 14 Oct 2026 0${9 - i}:00:00 GMT`))) },
    };
    for (const s of slugs) site[`https://www.bundesregierung.de/breg-de/aktuelles/${s}`] = { body: dePage([...deBody, s]) };
    const { fetch } = fakeFetch(site);

    expect((await runFetcher(env, { fetch, now: NOW }))[0]).toMatchObject({ saved: LIMITS.pagesPerRun, waiting: 3 - LIMITS.pagesPerRun });
    expect((await runFetcher(env, { fetch, now: new Date("2026-10-14T15:20:00Z") }))[0]).toMatchObject({ saved: 1, waiting: 0 });
    const saved = await articlesOf("xx-de");
    expect(saved.map((a) => a.text?.split("\n").at(-1))).toEqual(slugs);
    expect(saved.every((a) => a.text?.startsWith(`${deTeaser}\n`))).toBe(true);
  });

  it("reads at most one text as long as the stored maximum per run: reading it takes the most CPU", async () => {
    await addSource("xx-de", DE_FEED, "rss", DE_CONFIG);
    const long = Array.from({ length: 400 }, (_, i) => `Absatz ${i}: Die Bundesregierung hat die Verordnung beschlossen.`);
    const { fetch } = fakeFetch({
      "https://www.bundesregierung.de/robots.txt": { status: 404, body: "" },
      [DE_FEED]: { body: deFeed(deItem("long-2", "Wed, 14 Oct 2026 10:00:00 GMT"), deItem("long-1", "Wed, 14 Oct 2026 09:00:00 GMT")) },
      "https://www.bundesregierung.de/breg-de/aktuelles/long-2": { body: dePage(long) },
      "https://www.bundesregierung.de/breg-de/aktuelles/long-1": { body: dePage(long) },
    });
    expect((await runFetcher(env, { fetch, now: NOW }))[0]).toMatchObject({ saved: 1, waiting: 1 });
    const [first] = await articlesOf("xx-de");
    expect(first.text).toHaveLength(LIMITS.maxText);
    expect(first.text?.startsWith(`${deTeaser}\nAbsatz 0:`)).toBe(true);
    expect((await runFetcher(env, { fetch, now: new Date("2026-10-14T15:20:00Z") }))[0]).toMatchObject({ saved: 1, waiting: 0 });
  });

  it("asks a busy site (429) again on a later check, and not again in the same run", async () => {
    await addSource("xx-br", "https://dadosabertos.camara.leg.br/api/v2/proposicoes?itens=30", "api", {
      items: "dados",
      title: "{siglaTipo} {numero}/{ano}: {ementa}",
      text: "{ementa}",
      date: { field: "dataApresentacao", utcOffset: "-03:00" },
      link: "https://www.camara.leg.br/propostas-legislativas/{id}",
      allowedHosts: ["www.camara.leg.br"],
      textSelector: "#identificacaoProposicao",
    });
    const ementa = (n: number) => `Institui mecanismos para o aproveitamento da capacidade assistencial ociosa (${n}).`;
    const bill = (id: number, numero: number, date: string) => ({ id, siglaTipo: "PL", numero, ano: 2026, ementa: ementa(numero), dataApresentacao: date });
    const page = (numero: number) =>
      `<html><body><div id="portal-breadcrumbs">Página Inicial / PL</div><div id="identificacaoProposicao"><p><strong>Autor</strong><br />\r\nJosé Medeiros - PL/MT\r\n</p><p><strong>Apresentação</strong><br />14/10/2026</p><p><strong>Ementa</strong><br />${ementa(numero)}</p></div></body></html>`;
    let busy = true;
    const site: Site = {
      "https://dadosabertos.camara.leg.br/robots.txt": { status: 404, body: "" },
      "https://www.camara.leg.br/robots.txt": { status: 404, body: "" },
      "https://dadosabertos.camara.leg.br/api/v2/proposicoes?itens=30": {
        type: "application/json",
        // The newest two today; the third three days old, past the time we wait for a busy site.
        body: JSON.stringify({ dados: [bill(2647775, 5576, "2026-10-14T10:46"), bill(2647774, 5575, "2026-10-14T09:10"), bill(2647001, 5501, "2026-10-11T09:00")] }),
      },
    };
    for (const [id, numero] of [[2647775, 5576], [2647774, 5575], [2647001, 5501]]) {
      site[`https://www.camara.leg.br/propostas-legislativas/${id}`] = () =>
        busy
          ? new Response("<html><head><title>429 Too Many Requests</title></head></html>", { status: 429 })
          : new Response(page(numero), { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    const { fetch, requests } = fakeFetch(site);

    const [first] = await runFetcher(env, { fetch, now: NOW });
    expect(first).toMatchObject({ ok: true, saved: 1, waiting: 2 });
    expect(requests.filter((r) => r.url.includes("/propostas-legislativas/"))).toHaveLength(1);
    expect((await articlesOf("xx-br")).map((a) => [a.url, a.text])).toEqual([["https://www.camara.leg.br/propostas-legislativas/2647001", ementa(5501)]]);

    busy = false;
    const [second] = await runFetcher(env, { fetch, now: new Date("2026-10-14T15:20:00Z") });
    expect(second).toMatchObject({ saved: 2, waiting: 0 });
    const [newest] = await articlesOf("xx-br");
    expect(newest.text).toBe(`Autor\nJosé Medeiros - PL/MT\nApresentação\n14/10/2026\nEmenta\n${ementa(5576)}`);
  });

  it("lets only the item wait when its own page fails (5xx): older items' pages are read in the same run", async () => {
    await addSource("xx-de", DE_FEED, "rss", DE_CONFIG);
    const pageOf = (slug: string) => `https://www.bundesregierung.de/breg-de/aktuelles/${slug}`;
    const { fetch, requests } = fakeFetch({
      "https://www.bundesregierung.de/robots.txt": { status: 404, body: "" },
      [DE_FEED]: {
        body: deFeed(
          deItem("broken-1", "Wed, 14 Oct 2026 14:00:00 GMT"),
          deItem("broken-2", "Wed, 14 Oct 2026 13:00:00 GMT"),
          deItem("works-3", "Wed, 14 Oct 2026 10:00:00 GMT"),
        ),
      },
      // gov.za did this on 16 Oct: 500 for some notice pages while the rest of the site answered.
      [pageOf("broken-1")]: { status: 500, body: "The website encountered an unexpected error." },
      [pageOf("broken-2")]: { status: 500, body: "The website encountered an unexpected error." },
      [pageOf("works-3")]: { body: dePage(deBody) },
    });

    // The failed pages do not use the run's page budget either.
    expect((await runFetcher(env, { fetch, now: NOW }))[0]).toMatchObject({ saved: 1, waiting: 2 });
    expect((await articlesOf("xx-de")).map((a) => [a.url, a.text])).toEqual([[pageOf("works-3"), [deTeaser, ...deBody].join("\n")]]);

    // Asked again on later checks while new; after 24 hours saved with the teaser.
    expect((await runFetcher(env, { fetch, now: new Date("2026-10-14T15:20:00Z") }))[0]).toMatchObject({ saved: 0, waiting: 2 });
    expect((await runFetcher(env, { fetch, now: new Date("2026-10-15T13:30:00Z") }))[0]).toMatchObject({ saved: 1, waiting: 1 });
    expect((await runFetcher(env, { fetch, now: new Date("2026-10-15T14:30:00Z") }))[0]).toMatchObject({ saved: 1, waiting: 0 });
    expect((await articlesOf("xx-de")).map((a) => a.text)).toEqual([deTeaser, deTeaser, [deTeaser, ...deBody].join("\n")]);
    expect(requests.filter((r) => r.url === pageOf("broken-1"))).toHaveLength(4);
    expect(requests.filter((r) => r.url === pageOf("works-3"))).toHaveLength(1);
  });

  it("leaves a site alone for the rest of the run after a 503, or after three failed pages", async () => {
    await addSource("xx-de", DE_FEED, "rss", DE_CONFIG);
    const slugs = ["a-5", "b-4", "c-3", "d-2", "e-1"];
    const pageOf = (slug: string) => `https://www.bundesregierung.de/breg-de/aktuelles/${slug}`;
    let answer: (slug: string) => Response = () => new Response("", { status: 503 });
    const site: Site = {
      "https://www.bundesregierung.de/robots.txt": { status: 404, body: "" },
      [DE_FEED]: { body: deFeed(...slugs.map((slug, i) => deItem(slug, `Wed, 14 Oct 2026 1${4 - i}:00:00 GMT`))) },
    };
    for (const slug of slugs) site[pageOf(slug)] = () => answer(slug);
    const { fetch, requests } = fakeFetch(site);
    const pageRequests = () => requests.filter((r) => r.url.includes("/aktuelles/")).length;

    // 503: the site asks us to wait, so no other page of it is asked in this run.
    expect((await runFetcher(env, { fetch, now: NOW }))[0]).toMatchObject({ saved: 0, waiting: 5 });
    expect(pageRequests()).toBe(1);

    // A 500, no answer in time, a 502: three pages of the site failed, so it counts as busy.
    answer = (slug) => {
      if (slug === "a-5") return new Response("error", { status: 500 });
      if (slug === "b-4") throw new DOMException("The operation was aborted due to timeout", "TimeoutError");
      if (slug === "c-3") return new Response("bad gateway", { status: 502 });
      return new Response(dePage([...deBody, slug]), { headers: { "content-type": "text/html" } });
    };
    expect((await runFetcher(env, { fetch, now: new Date("2026-10-14T15:20:00Z") }))[0]).toMatchObject({ saved: 0, waiting: 5 });
    expect(pageRequests()).toBe(1 + 3);

    // Back to normal: the page budget again decides.
    answer = (slug) => new Response(dePage([...deBody, slug]), { headers: { "content-type": "text/html" } });
    expect((await runFetcher(env, { fetch, now: new Date("2026-10-14T15:40:00Z") }))[0]).toMatchObject({ saved: LIMITS.pagesPerRun, waiting: 5 - LIMITS.pagesPerRun });
  });

  it("does not repeat a cut list text that the page already starts with", async () => {
    await addSource("xx-de", DE_FEED, "rss", DE_CONFIG);
    const cut = `${deBody[0].slice(0, 120)}...`;
    const { fetch } = fakeFetch({
      "https://www.bundesregierung.de/robots.txt": { status: 404, body: "" },
      [DE_FEED]: { body: deFeed(deItem("cut-1", "Wed, 14 Oct 2026 09:00:00 GMT", cut)) },
      "https://www.bundesregierung.de/breg-de/aktuelles/cut-1": { body: dePage(deBody) },
    });
    expect((await runFetcher(env, { fetch, now: NOW }))[0]).toMatchObject({ saved: 1 });
    expect((await articlesOf("xx-de"))[0].text).toBe(deBody.join("\n"));
  });

  it("reads the text from a JSON endpoint (fullText) instead of a script-built item page", async () => {
    const feed = "https://ec.europa.eu/commission/presscorner/api/rss?language=en&documenttype=1&pagesize=40";
    await addSource("xx-eu", feed, "rss", {
      fullText: {
        from: "/detail/en/ip_(\\d+)_(\\d+)$",
        url: "https://ec.europa.eu/commission/presscorner/api/documents?reference=IP/{1}/{2}&language=en",
        json: ["docuLanguageResource.htmlContent", "docuLanguageResource.dolaQuoteResources.*.{author.authorName}: {extract}"],
      },
    });
    const item = (ref: string, title: string) =>
      `<item><title>${title}</title><link>https://ec.europa.eu/commission/presscorner/detail/en/${ref}</link><description>European Commission Press release Brussels, 14 Oct 2026 Today, the European Commission disbursed €2.86 billion to Ukraine under the defence component of the Ukraine Facility.</description><pubDate>Wed, 14 Oct 2026 08:16:16 GMT</pubDate></item>`;
    const htmlContent =
      '<p>Today, the European Commission disbursed &euro;2.86 billion to Ukraine under the defence component of the <a href="https://eu-solidarity-ukraine.ec.europa.eu/">Ukraine Facility</a>.</p>\n<p>The funds will finance drones, missiles and urgent battlefield needs.</p>\n<h2>Next steps</h2><ul><li>A second payment is planned for December.</li></ul>';
    const { fetch, requests } = fakeFetch({
      "https://ec.europa.eu/robots.txt": { body: "User-agent: *\nDisallow: /commission/presscorner/detail/print/", type: "text/plain" },
      [feed]: {
        body: `<rss version="2.0"><channel>${item("ip_26_2153", "Commission disburses €2.86 billion to Ukraine")}${item("ip_26_2175", "RAISE initiative")}${item("statement_26_2131", "Statement by the President")}</channel></rss>`,
      },
      "https://ec.europa.eu/commission/presscorner/api/documents?reference=IP/26/2153&language=en": {
        type: "application/json",
        body: JSON.stringify({
          docuLanguageResource: {
            title: "Commission disburses €2.86 billion to Ukraine",
            htmlContent,
            pdfContent: null,
            // The page shows these under "Quote(s)"; they are not in htmlContent.
            dolaQuoteResources: [{ author: { authorName: "Ursula von der Leyen, President of the European Commission" }, extract: "Europe stands with Ukraine.", orderNb: 1 }],
          },
          refCd: "IP/26/2153",
        }),
      },
      // Bigger than LIMITS.fullTextBytes: not read, the teaser stays.
      "https://ec.europa.eu/commission/presscorner/api/documents?reference=IP/26/2175&language=en": {
        type: "application/json",
        body: JSON.stringify({ docuLanguageResource: { htmlContent: "<p>Annex table row</p>".repeat(12_000) } }),
      },
    });

    const [check] = await runFetcher(env, { fetch, now: NOW });
    expect(check).toMatchObject({ ok: true, saved: 3, waiting: 0 });
    const byRef = Object.fromEntries((await articlesOf("xx-eu")).map((a) => [a.url.split("/").at(-1), a]));
    expect(byRef.ip_26_2153.text).toBe(
      // The feed's "European Commission Press release Brussels, <date>" teaser ends with the first paragraph, so it is not added again.
      "Today, the European Commission disbursed €2.86 billion to Ukraine under the defence component of the Ukraine Facility .\nThe funds will finance drones, missiles and urgent battlefield needs.\nNext steps\nA second payment is planned for December.\nUrsula von der Leyen, President of the European Commission: Europe stands with Ukraine.",
    );
    expect(byRef.ip_26_2175.text).toMatch(/^European Commission Press release/);
    expect(byRef.statement_26_2131.text).toMatch(/^European Commission Press release/);
    // The item pages (a JavaScript shell with the Commission logo as picture) are never opened.
    expect(requests.some((r) => r.url.includes("/detail/"))).toBe(false);
    // JSON first, anything else accepted: Mexico's SIDOF answers a bare "application/json" with 406.
    expect(requests.filter((r) => r.url.includes("/api/documents")).map((r) => r.headers.get("accept"))).toEqual([
      "application/json, */*;q=0.1",
      "application/json, */*;q=0.1",
    ]);
    expect(byRef.ip_26_2153.image_url).toBeNull();
  });

  it("follows full-text steps to another official site, each item one page of the budget", async () => {
    const list = "https://www.saij.gob.ar/busqueda?o=0&p=50&v=colapsada";
    await addSource("xx-ar", list, "api", {
      items: "searchResults.documentResultList",
      itemRoot: "documentAbstract.document",
      keep: { "metadata.document-content-type": "^novedad$" },
      title: "content.titulo_1",
      text: "content.sintesis",
      date: { field: "content.fecha_bo" },
      link: "https://www.saij.gob.ar/{metadata.friendly-url.description}/{metadata.uuid}",
      itemPages: false,
      fullText: [
        { from: "/([^/]+)$", url: "https://www.saij.gob.ar/view-document?guid={1}", json: "data.document.content.url_portal" },
        { link: "a[href$='norma.htm']" },
        { encoding: "iso-8859-1" },
      ],
      allowedHosts: ["servicios.infoleg.gob.ar"],
    });
    const doc = (uuid: string, title: string, date: string) => ({
      documentAbstract: JSON.stringify({
        document: {
          metadata: { uuid, "document-content-type": "novedad", "friendly-url": { description: `nv-${uuid}` } },
          content: { titulo_1: title, sintesis: `El Ministerio de Salud aprobó ${title.toLowerCase()}.`, fecha_bo: date },
        },
      }),
    });
    const viewDocument = (portal: string) => JSON.stringify({ data: JSON.stringify({ document: { content: { url_portal: portal } } }), guid: "x" });
    const verNorma = (id: number) => `<html><head><meta charset="ISO-8859-1"></head><body><div id="Textos_Completos">
      <p><strong>Resolución&nbsp;${id}</strong></p><p><a href='anexos/430000-434999/${id}/norma.htm'><b>Texto completo de la norma</b></a></p></div></body></html>`;
    // InfoLEG serves ISO-8859-1 without saying so in the header.
    const latin1 = (text: string) => Uint8Array.from(text, (c) => c.charCodeAt(0));
    const norma = (n: number) => `<html><head><meta content="text/html; charset=ISO-8859-1" http-equiv="content-type"></head><body>
      <header id="branding"><img src="/infolegInternet/imagenes/left.png"></header>
      <p>MINISTERIO DE SALUD<br>Resolución ${n}/2026<br>RESOL-2026-${n}-APN-MS</p><p>Ciudad de Buenos Aires, 14/10/2026</p>
      <p>VISTO el Expediente N° EX-2026-99251956-APN-DGD#MS, la Ley de Ministerios N° 22.520 y sus modificatorias, y</p>
      <p>CONSIDERANDO: Que la hipertensión arterial es el principal factor de riesgo de las enfermedades cardiovasculares.</p>
      <p>Por ello, EL MINISTRO DE SALUD RESUELVE: ARTÍCULO 1°.- Apruébase el Plan Nacional de Abordaje Integral de Salud Vascular 2026-2030.</p></body></html>`;
    const site: Site = {
      "https://www.saij.gob.ar/robots.txt": { body: "User-agent: *\nDisallow: /descarga-archivo", type: "text/plain" },
      "https://servicios.infoleg.gob.ar/robots.txt": { status: 404, body: "" },
      [list]: {
        type: "application/json",
        body: JSON.stringify({
          searchResults: {
            documentResultList: [doc("u-1445", "Plan nacional de salud vascular", "2026-10-14"), doc("u-9999", "Otra norma", "2026-10-13"), doc("u-1447", "Listado de medicamentos esenciales", "2026-10-12")],
          },
        }),
      },
      "https://www.saij.gob.ar/view-document?guid=u-1445": { type: "application/json", body: viewDocument("https://servicios.infoleg.gob.ar/infolegInternet/verNorma.do?id=431253") },
      // A link that leaves the official sites is never followed.
      "https://www.saij.gob.ar/view-document?guid=u-9999": { type: "application/json", body: viewDocument("https://mirror.example.com/verNorma.do?id=1") },
      "https://www.saij.gob.ar/view-document?guid=u-1447": { type: "application/json", body: viewDocument("https://servicios.infoleg.gob.ar/infolegInternet/verNorma.do?id=431256") },
      "https://servicios.infoleg.gob.ar/infolegInternet/verNorma.do?id=431253": { body: verNorma(431253) },
      "https://servicios.infoleg.gob.ar/infolegInternet/verNorma.do?id=431256": { body: verNorma(431256) },
      "https://servicios.infoleg.gob.ar/infolegInternet/anexos/430000-434999/431253/norma.htm": () => new Response(latin1(norma(1445)), { headers: { "content-type": "text/html" } }),
      "https://servicios.infoleg.gob.ar/infolegInternet/anexos/430000-434999/431256/norma.htm": () => new Response(latin1(norma(1447)), { headers: { "content-type": "text/html" } }),
    };
    const { fetch, requests } = fakeFetch(site);

    const [first] = await runFetcher(env, { fetch, now: NOW });
    expect(first).toMatchObject({ ok: true, saved: 2, waiting: 1 });
    expect(requests.some((r) => r.url.includes("mirror.example.com"))).toBe(false);
    const [plan, other] = await articlesOf("xx-ar");
    // SAIJ's plain-language summary stays in front of the norm's text.
    expect(plan.text).toMatch(/^El Ministerio de Salud aprobó plan nacional de salud vascular\.\nMINISTERIO DE SALUD\nResolución 1445\/2026\nRESOL-2026-1445-APN-MS\nCiudad de Buenos Aires, 14\/10\/2026\nVISTO el Expediente N° EX-2026/);
    expect(plan.text).toContain("ARTÍCULO 1°.- Apruébase el Plan Nacional");
    expect(other.text).toBe("El Ministerio de Salud aprobó otra norma.");

    const [second] = await runFetcher(env, { fetch, now: new Date("2026-10-14T15:20:00Z") });
    expect(second).toMatchObject({ saved: 1, waiting: 0 });
    expect((await articlesOf("xx-ar")).at(-1)?.text).toContain("Resolución 1447/2026");
  });
});
