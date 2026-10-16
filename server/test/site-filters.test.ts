// The website's filters (#67, #68): a country's list `/{lang}/{cc}`, one topic
// `?topic=`, Local `/{lang}/local`, and the two menus under the title. The
// lists are the API's filtered pages; the menus offer only what GET /countries
// and GET /topics list; nothing per reader is ever in a cached page.
import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import type { ApiList } from "../src/site/data";
import { filterBar } from "../src/site/pages/filters";
import { CACHE } from "../src/site/respond";
import { SITE_LANGS, type SiteLang, text } from "../src/site/texts";
import { GLOBAL } from "../src/site/urls";
import { get, hideSeed } from "./helpers";
import { ORIGIN, hreflangs, insertArticle, insertTranslation, linkedIds, site, siteRowsRead as rowsRead, testId } from "./site-helpers";

const SOURCE = { DE: "de-federal-government", EU: "eu-european-commission", FR: "fr-foreign-ministry", US: "us-white-house" } as const;

/** 45 articles: Germany, the EU and the US in turn, economy and health in turn, a third in Ukrainian; one French on climate. */
async function fixtures() {
  await hideSeed();
  // These four count as real sources, so GET /countries lists DE, FR and US (never the EU).
  await env.DB.prepare(`UPDATE sources SET config = NULL WHERE id IN (${Object.values(SOURCE).map(() => "?").join(", ")})`)
    .bind(...Object.values(SOURCE))
    .run();
  const countries = ["DE", "EU", "US"] as const;
  for (let n = 10; n < 55; n++) {
    await insertArticle({ id: testId(n), sourceId: SOURCE[countries[n % 3]], topics: [n % 2 ? "health" : "economy"], importance: n % 5 });
    if (n % 3 === 0) await insertTranslation(testId(n), "uk");
  }
  await insertArticle({ id: testId(60), sourceId: SOURCE.FR, topics: ["climate"] });
}

beforeEach(fixtures);

/** The links of a menu's lists: [href, label, current] (the label without its detail line). */
function menu(body: string, which: 0 | 1) {
  const details = [...body.matchAll(/<details class="pick"[\s\S]*?<\/details>/g)].map((m) => m[0])[which] ?? "";
  return [...details.matchAll(/<li><a href="([^"]+)"( aria-current="page")?><span>([^<]+)/g)].map((m) => [m[1].replaceAll("&amp;", "&"), m[3].trim(), !!m[2]] as const);
}

const nextLink = (body: string) => /<a class="more" href="([^"]+)" rel="next">/.exec(body)?.[1].replaceAll("&amp;", "&") ?? null;

describe("routing", () => {
  it("tells a country's list from an article: one segment after the language is a list, two an article", async () => {
    const list = await site("/en/de");
    expect(list.status).toBe(200);
    expect(list.headers.get("cloudflare-cdn-cache-control")).toBe(CACHE.list.edge);
    expect(list.body).toContain('<h1 class="page-title">');
    expect(list.body).toContain('<nav class="filters"');
    for (const path of [`/en/de/${testId(10)}`, `/en/de/${testId(10)}-a-slug`, `/en/eu/${testId(10)}`]) {
      const article = await site(path);
      expect(article.status, path).toBe(200);
      expect(article.headers.get("cloudflare-cdn-cache-control")).toBe(CACHE.article.edge);
      expect(article.body).not.toContain('class="filters"');
    }
  });

  it("has a page for every country the API names, the EU's too, and none for anything else (no D1 read)", async () => {
    for (const path of ["/en/de", "/en/eu", "/en/ua", "/en/pl", "/uk/us"]) expect((await site(path)).status, path).toBe(200);
    for (const path of ["/en/zz", "/en/xx", "/en/fi", "/en/DE", "/en/d1", "/en/deu"]) {
      let status = 0;
      expect(await rowsRead(async () => (status = (await site(path)).status)), path).toBe(0);
      expect(status, path).toBe(404);
    }
  });

  it("has one form for a topic, the query: a topic as a path segment is no page", async () => {
    expect((await site("/en?topic=economy")).status).toBe(200);
    expect((await site("/en/de?topic=economy")).status).toBe(200);
    for (const path of ["/en/economy", "/en/topic/economy", "/en/de/economy", "/en/de/topic/economy", "/en/topics"]) {
      expect((await site(path)).status, path).toBe(404);
    }
  });

  it("answers 404 to a topic that is not one of the list, or more than one, with no D1 read", async () => {
    for (const path of ["/en?topic=nonsense", "/en?topic=", "/en?topic=Economy", "/en?topic=economy&topic=health", "/en/de?topic=x", "/en/local?topic=x"]) {
      let status = 0;
      expect(await rowsRead(async () => (status = (await site(path, { cf: { country: "DE" } })).status)), path).toBe(0);
      expect(status, path).toBe(404);
    }
  });

  it("sends every other spelling of a list to its one URL with a 301 and no D1 read", async () => {
    for (const [path, location] of [
      ["/en/de/", "/en/de"],
      ["/en/de/?topic=economy", "/en/de?topic=economy"],
      ["/en/de?before=5&topic=economy", "/en/de?topic=economy&before=5"],
      ["/en?topic=economy&utm_source=x", "/en?topic=economy"],
      ["/en?topic=econom%79", "/en?topic=economy"],
      ["/en/de?menu=where", "/en/de"],
      ["/en?before=5&menu=where", "/en?before=5"],
      ["/en?menu=topics", "/en"],
      ["/en?menu=where&topic=health", "/en?topic=health&menu=where"],
    ]) {
      let response: Awaited<ReturnType<typeof site>> | undefined;
      expect(await rowsRead(async () => (response = await site(path))), path).toBe(0);
      expect(response!.status, path).toBe(301);
      expect(response!.headers.get("location"), path).toBe(ORIGIN + location);
    }
  });
});

describe("the lists are the API's filtered pages", () => {
  /** Every page of the API's list for the query, through nextCursor. */
  async function apiPages(query: string) {
    const pages: ApiList[] = [];
    let cursor: string | null = null;
    do {
      const page = (await get(`/articles?limit=20${query}${cursor ? `&cursor=${cursor}` : ""}`)).body as ApiList;
      pages.push(page);
      cursor = page.nextCursor;
    } while (cursor);
    return pages;
  }

  /** Every page of the site's list, through its "Older decisions" links. */
  async function sitePages(path: string) {
    const pages: { top: string[]; items: string[] }[] = [];
    let next: string | null = path;
    while (next) {
      const page = await site(next);
      expect(page.status, next).toBe(200);
      const main = page.body.split("<footer")[0];
      const top = /<section aria-labelledby="top">[\s\S]*?<\/section>/.exec(main)?.[0] ?? "";
      pages.push({ top: linkedIds(top), items: linkedIds(main.replace(top, "")) });
      next = nextLink(page.body);
    }
    return pages;
  }

  it("in every language, for a country, a topic and both, with the same top stories and pages", async () => {
    const cases: [string, string, string][] = [];
    for (const lang of SITE_LANGS) {
      const l = lang === "en" ? "" : `&lang=${lang}`;
      cases.push(
        [lang, `/${lang}/de`, `${l}&country=DE`],
        [lang, `/${lang}/us`, `${l}&country=US`],
        [lang, `/${lang}/eu`, `${l}&country=EU`],
        [lang, `/${lang}?topic=economy`, `${l}&topic=economy`],
        [lang, `/${lang}/de?topic=health`, `${l}&country=DE&topic=health`],
        [lang, `/${lang}/fr?topic=economy`, `${l}&country=FR&topic=economy`],
      );
    }
    let multiPage = 0;
    for (const [lang, path, query] of cases) {
      const api = await apiPages(query);
      const ours = await sitePages(path);
      expect(ours.map((p) => p.items), `${lang} ${path}`).toEqual(api.map((p) => p.items.map((a) => a.id)));
      expect(ours.map((p) => p.top), `${lang} ${path}`).toEqual(api.map((p) => p.top.map((a) => a.id)));
      if (api.length > 1) multiPage++;
    }
    // Germany with the EU (30 articles) and economy (23) page in English.
    expect(multiPage).toBeGreaterThanOrEqual(2);
    // Germany's list has the EU's decisions too, as the app's Local.
    const de = (await get("/articles?country=DE")).body as ApiList;
    expect(new Set(de.items.map((a) => a.country))).toEqual(new Set(["DE", "EU"]));
  });
});

describe("the menus", () => {
  it("offer the countries GET /countries lists, by name in the page's language, keeping the topic", async () => {
    for (const lang of SITE_LANGS) {
      const countries = ((await get(`/countries?lang=${lang}`)).body as { countries: { code: string; name: string }[] }).countries;
      expect(countries.map((c) => c.code).sort()).toEqual(["DE", "FR", "US"]);
      const where = menu((await site(`/${lang}?topic=health`)).body, 0);
      expect(where.slice(0, 2)).toEqual([
        [`/${lang}?topic=health`, text(lang, "filterGlobal"), true],
        [`/${lang}/local?topic=health`, text(lang, "filterLocal"), false],
      ]);
      expect(where.slice(2)).toEqual(countries.map((c) => [`/${lang}/${c.code.toLowerCase()}?topic=health`, c.name, false]));
    }
  });

  it("offer the topics GET /topics lists for the country and language, busiest first, keeping the country", async () => {
    for (const lang of SITE_LANGS) {
      for (const [path, country] of [[`/${lang}`, null], [`/${lang}/de`, "DE"], [`/${lang}/fr`, "FR"], [`/${lang}/us`, "US"]] as const) {
        const query = new URLSearchParams();
        if (lang !== "en") query.set("lang", lang);
        if (country) query.set("country", country);
        const topics = ((await get(`/topics?${query}`)).body as { topics: { id: string; name: string }[] }).topics;
        const items = menu((await site(path)).body, 1);
        expect(items[0], path).toEqual([path, text(lang, "filterAllTopics"), true]);
        expect(items.slice(1), path).toEqual(topics.map((x) => [`${path}?topic=${x.id}`, x.name, false]));
      }
    }
    // German has no translations: its menu has All topics only.
    expect(menu((await site("/de")).body, 1)).toHaveLength(1);
  });

  it("mark the current choice, and keep it offered when the list does not have it", async () => {
    const us = await site("/en/us?topic=climate");
    // The US has health (8) and economy (7) only: climate stays, checked, first after All topics; then busiest first.
    expect(menu(us.body, 1)).toEqual([
      ["/en/us", "All topics", false],
      ["/en/us?topic=climate", "Climate", true],
      ["/en/us?topic=health", "Health", false],
      ["/en/us?topic=economy", "Economy", false],
    ]);
    expect(menu(us.body, 0).filter(([, , current]) => current)).toEqual([["/en/us?topic=climate", "United States", true]]);
    // France is an EU member: its list has the EU's decisions, so their topics too, after its own.
    expect(menu((await site("/en/fr")).body, 1).map(([, name]) => name)).toEqual(["All topics", "Economy", "Health", "Climate"]);
    // Ukraine has no source: offered first, checked, before the countries with sources.
    const ua = menu((await site("/uk/ua")).body, 0);
    expect(ua[2]).toEqual(["/uk/ua", "Україна", true]);
    expect(ua.filter(([, , current]) => current)).toHaveLength(1);
  });

  it("show the active filter as a red chip, the others grey", async () => {
    const chips = async (path: string) => [...(await site(path)).body.matchAll(/<summary><span class="chip( on)?">[\s\S]*?<span class="label">([^<]+)<\/span>/g)].map((m) => [m[2], !!m[1]]);
    expect(await chips("/en")).toEqual([["Global", false], ["All topics", false]]);
    expect(await chips("/en/de?topic=health")).toEqual([["Germany", true], ["Health", true]]);
    expect(await chips("/uk?topic=economy")).toEqual([["Увесь світ", false], ["Економіка", true]]);
    expect(await chips("/de/us")).toEqual([["Vereinigte Staaten", true], ["Alle Themen", false]]);
  });

  it("are closed, except Where on the page Local sends a reader to without a country", async () => {
    expect((await site("/en")).body).not.toMatch(/<details[^>]* open/);
    const open = await site("/en?topic=economy&menu=where");
    expect(open.status).toBe(200);
    expect(open.body).toMatch(/<details class="pick" name="filters" open>\n<summary><span class="chip">/);
    expect(open.body).toContain(`<p class="menu-note">${text("en", "localNone")}</p>`);
    expect([...open.body.matchAll(/<details[^>]* open>/g)]).toHaveLength(1);
    // The same list: its canonical and language links have no open menu.
    expect(open.body).toContain(`<link rel="canonical" href="${ORIGIN}/en?topic=economy">`);
    expect(open.body).not.toMatch(/hreflang="\w+" href="[^"]*menu=/);
  });

  it("escape every name: a country or topic name can never become markup", () => {
    const evil = `"><script>alert(1)</script>`;
    const bar = filterBar("en", { country: "DE", topic: "economy" }, { countries: [{ code: "DE", name: evil }], topics: [{ id: "economy", name: evil }] }, "where").value;
    expect(bar).not.toContain("<script>");
    expect(bar.split("&quot;&gt;&lt;script&gt;alert(1)&lt;/script&gt;").length - 1).toBe(2);
    // A code is a path segment of its own: never a quote or a slash.
    const odd = filterBar("en", GLOBAL, { countries: [{ code: `D"E/x`, name: "x" }], topics: [] }, null).value;
    expect(odd).toContain('href="/en/d&quot;e/x"');
  });

  it("list only real countries: a source country that is not a code is not offered", async () => {
    await env.DB.prepare(
      `INSERT INTO sources (id, country, name, kind, url, status) VALUES ('xx-evil', '"><b>', 'Evil', 'rss', 'https://evil.test', 'active')`,
    ).run();
    const { body } = await site("/en");
    expect(body).not.toMatch(/<b>|evil/i);
    // By name: France, Germany, United States.
    expect(menu(body, 0).map(([href]) => href).slice(2)).toEqual(["/en/fr", "/en/de", "/en/us"]);
  });
});

describe("Local", () => {
  const local = (path: string, country?: string) => site(path, country ? { cf: { country } } : {});

  it("sends a reader to their own country's list, with the topic, never stored", async () => {
    for (const [path, country, location] of [
      ["/en/local", "DE", "/en/de"],
      ["/uk/local?topic=health", "DE", "/uk/de?topic=health"],
      ["/es/local?topic=economy&utm=1", "US", "/es/us?topic=economy"],
      // An EU member without sources of its own still gets the EU's decisions, as in the app.
      ["/en/local", "PL", "/en/pl"],
    ] as const) {
      for (const method of ["GET", "HEAD"]) {
        const { status, headers, body } = await site(path, { method, cf: { country } }, "evil.test");
        expect(status, path).toBe(302);
        expect(headers.get("location"), path).toBe(ORIGIN + location);
        expect(headers.get("cache-control")).toBe("private, no-store");
        expect(headers.get("cloudflare-cdn-cache-control")).toBe("no-store");
        expect(headers.get("x-robots-tag")).toBe("noindex");
        expect(headers.get("vary")).toBeNull();
        expect(headers.get("set-cookie")).toBeNull();
        expect(body).toBe("");
      }
    }
  });

  it("opens the Global list's Where menu when it has no country to go to", async () => {
    await env.DB.prepare("UPDATE sources SET status = 'stale' WHERE id = ?").bind(SOURCE.US).run();
    for (const [path, country, location] of [
      ["/en/local", undefined, "/en?menu=where"],
      ["/en/local?topic=economy", undefined, "/en?topic=economy&menu=where"],
      // A country without an active source, Tor, a code without a name or page, the bloc itself.
      ["/uk/local", "US", "/uk?menu=where"],
      ["/en/local", "UA", "/en?menu=where"],
      ["/en/local", "T1", "/en?menu=where"],
      ["/en/local", "XX", "/en?menu=where"],
      ["/en/local", "FI", "/en?menu=where"],
      ["/en/local", "EU", "/en?menu=where"],
      ["/en/local", "de", "/en?menu=where"],
    ] as const) {
      const { status, headers } = await local(path, country);
      expect(status, `${path} ${country}`).toBe(302);
      expect(headers.get("location"), `${path} ${country}`).toBe(ORIGIN + location);
      expect(headers.get("cache-control")).toBe("private, no-store");
    }
  });

  it("reads D1 only to check a country outside a bloc has sources (GET /countries)", async () => {
    expect(await rowsRead(() => local("/en/local", "DE"))).toBe(0);
    expect(await rowsRead(() => local("/en/local", "PL"))).toBe(0);
    expect(await rowsRead(() => local("/en/local"))).toBe(0);
    const us = await rowsRead(() => local("/en/local", "US"));
    expect(us).toBeGreaterThan(0);
    expect(us).toBeLessThan(60);
  });

  it("is linked from every list's Where menu, never with a country in it", async () => {
    for (const path of ["/en", "/en/de?topic=health", "/ru/us"]) {
      const links = menu((await site(path)).body, 0).filter(([href]) => href.includes("/local"));
      expect(links, path).toHaveLength(1);
      expect(links[0][0], path).toMatch(/^\/[a-z]{2}\/local(\?topic=[a-z-]+)?$/);
    }
  });
});

describe("empty lists", () => {
  it("say so with the app's words and lead to all countries and all topics", async () => {
    const ua = (await site("/en/ua")).body;
    expect(ua).toContain(`<p class="meta">${text("en", "filterEmpty")}</p>`);
    expect(ua).toContain(`<a class="more" href="/en">${text("en", "filterShowGlobal")}</a>`);
    expect(ua).not.toContain(text("en", "filterShowAllTopics"));
    expect(ua).not.toContain('class="notice"');

    const both = (await site("/uk/de?topic=science")).body;
    expect(both).toContain(text("uk", "filterEmpty"));
    expect(both).toContain(`<a class="more" href="/uk?topic=science">${text("uk", "filterShowGlobal")}</a>`);
    expect(both).toContain(`<a class="more" href="/uk/de">${text("uk", "filterShowAllTopics")}</a>`);

    const topic = (await site("/es?topic=science")).body;
    expect(topic).toContain(`<a class="more" href="/es">${text("es", "filterShowAllTopics")}</a>`);
    expect(topic).not.toContain(text("es", "filterShowGlobal"));
  });

  it("keep the unfiltered list's own empty texts", async () => {
    expect((await site("/de")).body).toContain("Noch keine übersetzten Entscheidungen.");
    expect((await site("/de")).body).not.toContain(text("de", "filterEmpty"));
  });
});

describe("paging and languages keep the filters", () => {
  it("Older decisions, Latest decisions, the language links and the alternates", async () => {
    for (const path of ["/en/de", "/en?topic=economy"]) {
      const first = await site(path);
      const next = nextLink(first.body)!;
      expect(next, path).toMatch(new RegExp(`^${path.replace("?", "\\?")}[?&]before=\\d+$`));
      const later = await site(next);
      expect(later.status).toBe(200);
      expect(later.body).toContain(`<a class="more" href="${path.replace("&", "&amp;")}">${text("en", "latestLink")}</a>`);
      const before = /before=(\d+)/.exec(next)![1];
      for (const lang of SITE_LANGS) {
        const there = next.replace(/^\/en/, `/${lang}`);
        expect(later.body).toContain(`<link rel="alternate" hreflang="${lang}" href="${ORIGIN}${there.replace("&", "&amp;")}">`);
        expect(later.body).toContain(`<a href="${there.replace("&", "&amp;")}" hreflang="${lang}"`);
      }
      expect(later.body).toContain(`<link rel="canonical" href="${ORIGIN}${next.replace("&", "&amp;")}">`);
      expect(later.body).toContain(`before=${before}`);
    }
  });

  it("a filtered first page names the filtered list everywhere: canonical, alternates, x-default, title", async () => {
    const { body } = await site("/uk/de?topic=health");
    expect(body).toContain(`<link rel="canonical" href="${ORIGIN}/uk/de?topic=health">`);
    expect(hreflangs(body)).toEqual([...SITE_LANGS]);
    for (const lang of SITE_LANGS) expect(body).toContain(`hreflang="${lang}" href="${ORIGIN}/${lang}/de?topic=health"`);
    expect(body).toContain(`<link rel="alternate" hreflang="x-default" href="${ORIGIN}/en/de?topic=health">`);
    expect(body).toContain("<title>Німеччина · Здоров’я · Останні рішення · Official News</title>");
    // The unfiltered first page keeps the landing page as x-default.
    expect((await site("/uk")).body).toContain(`<link rel="alternate" hreflang="x-default" href="${ORIGIN}/">`);
  });

  it("a later page shows its filters without menus, and reads no rows for them", async () => {
    const next = nextLink((await site("/en/de")).body)!;
    const later = await site(next);
    expect(later.body).not.toContain("<details");
    expect(later.body).toMatch(/<p class="filters"><span class="chip on">[\s\S]*?Germany/);
    const withMenus = await rowsRead(() => site("/en/de"));
    const without = await rowsRead(() => site(next));
    expect(without).toBeLessThan(withMenus);
  });

  it("article links from a filtered list are the article's own address", async () => {
    const ids = linkedIds((await site("/en/de")).body);
    expect(ids.length).toBeGreaterThan(0);
    const body = (await site("/en/de")).body;
    expect(body).toMatch(new RegExp(`href="/en/eu/${ids.find((id) => body.includes(`/en/eu/${id}`))}`));
  });
});

describe("every new page", () => {
  const PAGES = ["/en/de", "/uk/de?topic=health", "/en?topic=economy", "/en?menu=where", "/en/ua", "/es/pl", "/en/de?before=30"];

  it("is noindex, with the same value in its meta tag, and loads nothing else", async () => {
    for (const path of PAGES) {
      const { status, headers, body } = await site(path);
      expect(status, path).toBe(200);
      expect(headers.get("x-robots-tag"), path).toBe("noindex");
      expect(body, path).toContain('<meta name="robots" content="noindex">');
      expect(body, path).not.toMatch(/<script|<img|<iframe|rel="stylesheet"|rel="preload"|rel="prefetch"/i);
      expect(headers.get("cloudflare-cdn-cache-control"), path).toBe(CACHE.list.edge);
    }
  });

  it("has no placeholder, undefined or null left, in every language", async () => {
    for (const lang of SITE_LANGS) {
      for (const path of PAGES.map((p) => p.replace(/^\/[a-z]{2}/, `/${lang}`))) {
        const visible = (await site(path)).body.replace(/<style>[\s\S]*<\/style>/, "");
        expect(visible, path).not.toMatch(/\{\w+\}|undefined|null|NaN|\[object/);
      }
    }
  });

  it("asks GET /topics only when the page does not hold its whole list: a country's complete first page counts its own articles", async () => {
    const api = (path: string) => rowsRead(() => get(path));
    // The US: 15 articles, one page. Germany with the EU: 30, two pages.
    expect(await rowsRead(() => site("/en/us"))).toBe((await api("/articles?limit=20&country=US")) + (await api("/countries")));
    expect(await rowsRead(() => site("/en/de"))).toBe(
      (await api("/articles?limit=20&country=DE")) + (await api("/countries")) + (await api("/topics?country=DE")),
    );
    // With a topic, the menu needs the country's whole feed: GET /topics.
    expect(await rowsRead(() => site("/en/us?topic=health"))).toBe(
      (await api("/articles?limit=20&country=US&topic=health")) + (await api("/countries")) + (await api("/topics?country=US")),
    );
  });

  it("reads a bounded number of D1 rows (numbers for docs/decisions.md; a test database of 46 articles)", async () => {
    const rows: Record<string, number> = {};
    for (const path of ["/en", "/en/de", "/en/us", "/en/ua", "/en?topic=economy", "/en/de?topic=health", "/uk/de", "/uk?topic=economy"]) {
      rows[path] = await rowsRead(() => site(path));
      expect(rows[path], path).toBeLessThan(700);
    }
    console.log(JSON.stringify({ rowsRead: rows }));
  });
});

describe("texts", () => {
  it("every filter word is in every language, and the privacy policy says what Local reads", async () => {
    for (const lang of SITE_LANGS as readonly SiteLang[]) {
      for (const key of ["filterGlobal", "filterGlobalDetail", "filterLocal", "filterAllTopics", "filterEmpty", "filterShowGlobal", "filterShowAllTopics", "filters", "localNone"] as const) {
        expect(text(lang, key), `${lang} ${key}`).toMatch(/\S/);
      }
      const privacy = (await site(`/${lang}/privacy`)).body;
      expect(privacy).toContain(text(lang, "siteLocal", { local: text(lang, "filterLocal") }));
      expect(privacy).toContain("Cloudflare");
    }
  });
});
