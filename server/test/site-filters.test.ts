// The website's filters (#67, #68; Yurii, 16 Oct): Where is all countries
// (`/{lang}`), a group of countries (`/{lang}/{group}`: eu, g7, g20, nato) or
// one country alone (`/{lang}/{cc}`), and one topic `?topic=`, with the two
// compact chips and their menus under the title. The lists are the API's
// filtered pages; the menus offer only what GET /countries and GET /topics
// list; every link is a list's one URL, so each view has one cache entry.
import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { EU, GROUPS, hasCountryName } from "../src/api/filters";
import type { ApiList, ApiWhere } from "../src/site/data";
import { CSS } from "../src/site/layout";
import { TOPIC_ICONS, filterBar } from "../src/site/pages/filters";
import { CACHE } from "../src/site/respond";
import { SITE_LANGS, type SiteLang, text } from "../src/site/texts";
import { ALL, COUNTRY_PAGES, INFO_PAGES, isCountryPage } from "../src/site/urls";
import { TOPICS } from "../src/summarizer/schema";
import { get, hideSeed } from "./helpers";
import { ORIGIN, hreflangs, insertArticle, insertTranslation, linkedIds, site, siteRowsRead as rowsRead, testId, withoutConsentScript } from "./site-helpers";

const SOURCE = {
  DE: "de-federal-government",
  EU: "eu-european-commission",
  FR: "fr-foreign-ministry",
  US: "us-white-house",
  GB: "gb-prime-minister-s-office",
  TR: "tr-foreign-ministry",
} as const;

/**
 * 48 articles: Germany, the EU institutions and the US in turn (15 each:
 * Germany and the EU 8 on economy and 7 on health, the US the other way
 * round), a quarter in Ukrainian; France on climate, the United Kingdom and
 * Türkiye on security and defence (one each).
 */
async function fixtures() {
  await hideSeed();
  // These count as real sources, so GET /countries lists DE, FR, GB, TR and US (never the EU institutions).
  await env.DB.prepare(`UPDATE sources SET config = NULL WHERE id IN (${Object.values(SOURCE).map(() => "?").join(", ")})`)
    .bind(...Object.values(SOURCE))
    .run();
  const countries = ["DE", "EU", "US"] as const;
  for (let n = 10; n < 55; n++) {
    await insertArticle({ id: testId(n), sourceId: SOURCE[countries[n % 3]], topics: [n % 2 ? "health" : "economy"], importance: n % 5 });
    if (n % 4 === 0) await insertTranslation(testId(n), "uk");
  }
  await insertArticle({ id: testId(60), sourceId: SOURCE.FR, topics: ["climate"] });
  await insertArticle({ id: testId(61), sourceId: SOURCE.GB, topics: ["security-defence"] });
  await insertArticle({ id: testId(62), sourceId: SOURCE.TR, topics: ["security-defence"] });
}

beforeEach(fixtures);

type Link = readonly [href: string, label: string, current: boolean];

/** A menu item's link, its icon or empty icon slot (the Topics menu), and its name. */
const MENU_ITEM = /<li><a href="([^"]+)"( aria-current="page")?>(<svg class="glyph"[\s\S]*?<\/svg>|<span class="glyph" aria-hidden="true"><\/span>)?<span>([^<]+)<\/span>/g;

/** A menu's lists (its sections: All, groups, countries), each as links [href, label, current]. */
function sections(body: string, which: 0 | 1): Link[][] {
  const details = [...body.matchAll(/<details class="pick"[\s\S]*?<\/details>/g)].map((m) => m[0])[which] ?? "";
  return [...details.matchAll(/<ul>([\s\S]*?)<\/ul>/g)].map((ul) =>
    [...ul[1].matchAll(MENU_ITEM)].map((m) => [m[1].replaceAll("&amp;", "&"), m[4], !!m[2]] as const),
  );
}

/** A menu's items as [what is before the name: "slot", the topic of its icon or "", name]. */
function leads(body: string, which: 0 | 1): [string, string][] {
  const details = [...body.matchAll(/<details class="pick"[\s\S]*?<\/details>/g)].map((m) => m[0])[which] ?? "";
  return [...details.matchAll(MENU_ITEM)].map((m) => {
    const lead = m[3] ?? "";
    const icon = Object.entries(TOPIC_ICONS).find(([, svg]) => lead.includes(svg))?.[0];
    return [lead.startsWith("<span") ? "slot" : (icon ?? (lead ? "unknown icon" : "")), m[4]];
  });
}
const menu = (body: string, which: 0 | 1) => sections(body, which).flat();

/** The chips under the title: [shown (the label, or "icon"), what a screen reader hears, on]. */
const chips = (body: string) =>
  [...body.matchAll(/<span class="chip( on)?"><span class="label" aria-hidden="true">([\s\S]*?)<\/span><span class="vh">([^<]+)<\/span>/g)].map((m) => [
    m[2].startsWith("<svg") ? "icon" : m[2],
    m[3],
    !!m[1],
  ]);

const nextLink = (body: string) => /<a class="more" href="([^"]+)" rel="next">/.exec(body)?.[1].replaceAll("&amp;", "&") ?? null;

/** The API's query for a site list path: `/en/g7?topic=economy` → `&group=g7&topic=economy`. */
function apiQuery(path: string): string {
  const url = new URL(path, ORIGIN);
  const [, lang, place] = url.pathname.split("/");
  const params = new URLSearchParams();
  if (lang !== "en") params.set("lang", lang);
  if (place) params.set(GROUPS.some((g) => g.id === place) ? "group" : "country", GROUPS.some((g) => g.id === place) ? place : place.toUpperCase());
  for (const [k, v] of url.searchParams) params.set(k, v);
  return `&${params}`;
}

describe("routing", () => {
  it("one segment after the language is a list (a country or a group), two an article", async () => {
    for (const path of ["/en/de", "/en/eu", "/en/g7", "/en/g20", "/en/nato", "/uk/gb"]) {
      const list = await site(path);
      expect(list.status, path).toBe(200);
      expect(list.headers.get("cloudflare-cdn-cache-control")).toBe(CACHE.list.edge);
      expect(list.body).toContain('<h1 class="page-title">');
      expect(list.body).toContain('<nav class="filters"');
    }
    // An EU institutions' article keeps `eu` as its country: a second segment, so an article.
    const moved = await site(`/en/eu/${testId(10)}`);
    expect(moved.status).toBe(301);
    const article = await site(moved.headers.get("location")!.slice(ORIGIN.length));
    expect(article.status).toBe(200);
    expect(article.headers.get("cloudflare-cdn-cache-control")).toBe(CACHE.article.edge);
    expect(article.body).not.toContain('class="filters"');
  });

  it("has a page for every source country of docs/sources.csv but the EU institutions, one per group, and none for anything else (no D1 read)", async () => {
    // COUNTRY_PAGES is the source countries: a new one in docs/sources.csv fails here until it is added.
    // WW (the whole world: Wikipedia's current events, #230) is in no menu, so it has no page either.
    const countries = env.TEST_SOURCE_COUNTRIES.filter((c) => c !== "WW");
    expect([...COUNTRY_PAGES].sort()).toEqual(countries.filter((c) => c !== EU).sort());
    for (const code of COUNTRY_PAGES) expect(hasCountryName(code), code).toBe(true);
    for (const code of countries) expect((await site(`/en/${code.toLowerCase()}`)).status, code).toBe(200);
    for (const group of GROUPS) expect((await site(`/uk/${group.id}`)).status, group.id).toBe(200);
    for (const path of ["/en/ua", "/en/pl", "/de/cz"]) expect((await site(path)).status, path).toBe(200);
    // The EU's other members were Local's pages: a country alone shows only its own sources, so they have none.
    // Russia is no source country (#42), Saudi Arabia not yet: the API names both, but neither is a page (#89 review).
    for (const path of ["/en/ww", "/en/ru", "/uk/ru", "/ru/ru?topic=economy", "/en/sa", "/es/sa", "/en/zz", "/en/xx", "/en/no", "/en/at", "/en/fi", "/en/local", "/en/global", "/en/brics", "/en/g8", "/en/d1", "/en/deu", "/en/g/g7", "/en/groups"]) {
      let status = 0;
      expect(await rowsRead(async () => (status = (await site(path)).status)), path).toBe(0);
      expect(status, path).toBe(404);
    }
  });

  it("keeps groups, countries and information pages apart: a group's id is never a country's page or an information page", () => {
    for (const group of GROUPS) {
      expect(group.id, group.id).toMatch(/^[a-z0-9]{2,8}$/);
      expect(isCountryPage(group.id.toUpperCase()), group.id).toBe(false);
      // `eu` is ISO 3166's code reserved for the EU itself: its only name is the EU institutions'.
      if (group.id !== "eu") expect(hasCountryName(group.id.toUpperCase()), group.id).toBe(false);
      expect((INFO_PAGES as readonly string[]).includes(group.id), group.id).toBe(false);
    }
    expect(isCountryPage("EU")).toBe(false);
  });

  it("has one form for a topic, the query: a topic as a path segment is no page", async () => {
    for (const path of ["/en?topic=economy", "/en/de?topic=economy", "/en/g7?topic=economy"]) expect((await site(path)).status, path).toBe(200);
    for (const path of ["/en/economy", "/en/topic/economy", "/en/de/economy", "/en/g7/economy", "/en/de/topic/economy", "/en/topics"]) {
      expect((await site(path)).status, path).toBe(404);
    }
  });

  it("answers 404 to a topic that is not one of the list, or more than one, with no D1 read", async () => {
    for (const path of ["/en?topic=nonsense", "/en?topic=", "/en?topic=Economy", "/en?topic=economy&topic=health", "/en/de?topic=x", "/en/nato?topic=x", "/en/local?topic=economy"]) {
      let status = 0;
      expect(await rowsRead(async () => (status = (await site(path)).status)), path).toBe(0);
      expect(status, path).toBe(404);
    }
  });

  it("sends every other spelling of a list to its one URL with a 301 and no D1 read", async () => {
    for (const [path, location] of [
      ["/en/de/", "/en/de"],
      ["/en/DE", "/en/de"],
      ["/en/Gb?topic=health", "/en/gb?topic=health"],
      ["/en/G7", "/en/g7"],
      ["/en/EU", "/en/eu"],
      ["/en/NATO/?topic=economy", "/en/nato?topic=economy"],
      ["/en/de/?topic=economy", "/en/de?topic=economy"],
      ["/en/de?before=5&topic=economy", "/en/de?topic=economy&before=5"],
      ["/en/g20?before=5&topic=economy&x=1", "/en/g20?topic=economy&before=5"],
      ["/en?topic=economy&utm_source=x", "/en?topic=economy"],
      ["/en?topic=econom%79", "/en?topic=economy"],
      // Local's open menu is gone: an unused parameter.
      ["/en?menu=where", "/en"],
      ["/en?topic=health&menu=where", "/en?topic=health"],
      ["/en/de?menu=where", "/en/de"],
      // The API's spelling of a place is not the site's: the place is the path.
      ["/en?group=g7", "/en"],
    ]) {
      let response: Awaited<ReturnType<typeof site>> | undefined;
      expect(await rowsRead(async () => (response = await site(path))), path).toBe(0);
      expect(response!.status, path).toBe(301);
      expect(response!.headers.get("location"), path).toBe(ORIGIN + location);
      expect(response!.headers.get("cloudflare-cdn-cache-control"), path).toBe(CACHE.redirect.edge);
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
      const top = /<section[^>]*aria-labelledby="top">[\s\S]*?<\/section>/.exec(main)?.[0] ?? "";
      pages.push({ top: linkedIds(top), items: linkedIds(main.replace(top, "")) });
      next = nextLink(page.body);
    }
    return pages;
  }

  it("in every language, for a country, a group, a topic and both, with the same top stories and pages", async () => {
    let multiPage = 0;
    for (const lang of SITE_LANGS) {
      for (const path of ["/de", "/us", "/fr?topic=economy", "/eu", "/g7", "/g20", "/nato", "?topic=economy", "/de?topic=health", "/nato?topic=security-defence", "/g7?topic=health"]) {
        const sitePath = `/${lang}${path}`;
        const api = await apiPages(apiQuery(sitePath));
        const ours = await sitePages(sitePath);
        // Page 1's Latest leaves out its Top stories, as the app does (#89 review).
        expect(ours.map((p) => p.items), sitePath).toEqual(api.map((p) => p.items.filter((a) => !p.top.some((t) => t.id === a.id)).map((a) => a.id)));
        expect(ours.map((p) => p.top), sitePath).toEqual(api.map((p) => p.top.map((a) => a.id)));
        if (api.length > 1) multiPage++;
      }
    }
    // The G7 (47 articles), the G20 (48), the economy (23) and others page in English.
    expect(multiPage).toBeGreaterThanOrEqual(4);
  });

  it("show one country alone, and a group its members together (the EU institutions in the European Union, the G7 and the G20, not NATO)", async () => {
    const countries = async (path: string) => {
      // Top stories and Latest: France's one decision is a top story, not repeated under Latest.
      const ids = (await sitePages(path)).flatMap((p) => [...p.top, ...p.items]);
      const all = ((await get("/articles?limit=50")).body as ApiList).items;
      return new Set(ids.map((id) => all.find((a) => a.id === id)!.country));
    };
    expect(await countries("/en/de")).toEqual(new Set(["DE"]));
    expect(await countries("/en/fr")).toEqual(new Set(["FR"]));
    expect(await countries("/en/eu")).toEqual(new Set(["DE", "EU", "FR"]));
    expect(await countries("/en/g7")).toEqual(new Set(["DE", "EU", "FR", "GB", "US"]));
    expect(await countries("/en/g20")).toEqual(new Set(["DE", "EU", "FR", "GB", "TR", "US"]));
    expect(await countries("/en/nato")).toEqual(new Set(["DE", "FR", "GB", "TR", "US"]));
  });
});

describe("the menus", () => {
  it("Where: All countries, then every group of GET /countries in its order, then its countries by name, keeping the topic", async () => {
    for (const lang of SITE_LANGS) {
      const where = ((await get(`/countries?lang=${lang}`)).body as ApiWhere);
      expect(where.groups.map((g) => g.id)).toEqual(["eu", "g7", "g20", "nato"]);
      expect(where.countries.map((c) => c.code).sort()).toEqual(["DE", "FR", "GB", "TR", "US"]);
      const [all, groups, countries] = sections((await site(`/${lang}?topic=health`)).body, 0);
      expect(all).toEqual([[`/${lang}?topic=health`, text(lang, "filterAllCountries"), true]]);
      expect(groups).toEqual(where.groups.map((g) => [`/${lang}/${g.id}?topic=health`, g.name, false]));
      expect(countries).toEqual(where.countries.map((c) => [`/${lang}/${c.code.toLowerCase()}?topic=health`, c.name, false]));
    }
    // The groups' full names in the menu.
    expect(sections((await site("/uk")).body, 0)[1].map(([, name]) => name)).toEqual(["Європейський Союз", "G7", "G20", "НАТО"]);
  });

  it("Topics: what GET /topics lists for the place and the language, busiest first, keeping the place", async () => {
    for (const lang of SITE_LANGS) {
      for (const place of ["", "/de", "/fr", "/us", "/eu", "/g7", "/nato"]) {
        const path = `/${lang}${place}`;
        const topics = ((await get(`/topics?${apiQuery(path).slice(1)}`)).body as { topics: { id: string; name: string }[] }).topics;
        const [all, listed = []] = sections((await site(path)).body, 1);
        expect(all, path).toEqual([[path, text(lang, "filterAllTopics"), true]]);
        expect(listed, path).toEqual(topics.map((x) => [`${path}?topic=${x.id}`, x.name, false]));
      }
    }
    // France alone has only its climate decision now (the EU's are no longer mixed in).
    expect(menu((await site("/en/fr")).body, 1).map(([, name]) => name)).toEqual(["All topics", "Climate"]);
    // NATO: Germany, the US, France, the UK and Türkiye, without the EU institutions (economy and health 15 each, in the order of TOPICS).
    expect(menu((await site("/en/nato")).body, 1).map(([, name]) => name)).toEqual(["All topics", "Economy", "Health", "Security and defence", "Climate"]);
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
    expect(menu((await site("/en/nato")).body, 0).filter(([, , current]) => current)).toEqual([["/en/nato", "NATO", true]]);
    expect(menu((await site("/de/eu?topic=health")).body, 0).filter(([, , current]) => current)).toEqual([["/de/eu?topic=health", "Europäische Union", true]]);
    // Ukraine has no source: offered first among the countries, checked.
    const ua = sections((await site("/uk/ua")).body, 0)[2];
    expect(ua[0]).toEqual(["/uk/ua", "Україна", true]);
    expect(menu((await site("/uk/ua")).body, 0).filter(([, , current]) => current)).toHaveLength(1);
  });

  it("show a chip short once it is on: a country's code, a group's short name, a topic's icon; a screen reader hears the full name", async () => {
    expect(chips((await site("/en")).body)).toEqual([["All countries", "All countries", false], ["All topics", "All topics", false]]);
    expect(chips((await site("/en/de?topic=health")).body)).toEqual([["DE", "Country: Germany", true], ["icon", "Topic: Health", true]]);
    expect(chips((await site("/en/gb")).body)).toEqual([["GB", "Country: United Kingdom", true], ["All topics", "All topics", false]]);
    expect(chips((await site("/uk/g7")).body)).toEqual([["G7", "Країни: G7", true], ["Усі теми", "Усі теми", false]]);
    expect(chips((await site("/uk/nato?topic=economy")).body)).toEqual([["НАТО", "Країни: НАТО", true], ["icon", "Тема: Економіка", true]]);
    expect(chips((await site("/de/eu")).body)).toEqual([["EU", "Länder: Europäische Union", true], ["Alle Themen", "Alle Themen", false]]);
    // A group's short name is the language's (#89 review): the chip and its checked menu item agree.
    expect(chips((await site("/uk/eu")).body)[0]).toEqual(["ЄС", "Країни: Європейський Союз", true]);
    expect(chips((await site("/ru/eu")).body)[0]).toEqual(["ЕС", "Страны: Европейский союз", true]);
    expect(chips((await site("/es/eu")).body)[0]).toEqual(["UE", "Países: Unión Europea", true]);
    expect(chips((await site("/es/nato")).body)[0]).toEqual(["OTAN", "Países: OTAN", true]);
    expect(chips((await site("/en/nato")).body)[0]).toEqual(["NATO", "Countries: NATO", true]);
    for (const lang of SITE_LANGS) {
      const { body } = await site(`/${lang}/nato`);
      expect(menu(body, 0).find(([, , current]) => current)?.[1], lang).toBe(chips(body)[0][0]);
    }
    expect(chips((await site("/es/g20?topic=health")).body)).toEqual([["G20", "Países: G20", true], ["icon", "Tema: Salud", true]]);
    expect(chips((await site("/ru/tr")).body)).toEqual([["TR", "Страна: Турция", true], ["Все темы", "Все темы", false]]);
  });

  it("keep the chip grey when it is on: only its label and chevron turn red, the app's chip and filter red", () => {
    expect(CSS).toContain(".chip.on{color:var(--on)}");
    expect(CSS).not.toMatch(/\.chip\.on\{[^}]*background/);
    // The app's filterRed (feed_filters.dart) on iOS's tertiarySystemFill, as the app's chips (#89 review).
    expect(CSS).toMatch(/:root\{[^}]*--fill:rgba\(118,118,128,\.12\);--on:#c41230/);
    expect(CSS).toMatch(/prefers-color-scheme:dark\)\{:root\{[^}]*--fill:rgba\(118,118,128,\.24\);--on:#ff3b55/);
    expect(CSS).toMatch(/\.chip\{[^}]*background:var\(--fill\)/);
    expect(CSS).toContain(".menu .check{width:18px;height:18px;flex:none;color:var(--on)}");
  });

  it("open over the list under the chips, so neither chip moves (#89 review)", () => {
    // Below 720px too: no rule gives an open menu's chip its own row.
    expect(CSS).not.toMatch(/\.pick\[open\]\{[^}]*flex-basis/);
    expect(CSS).toContain(".filters{position:relative;");
    expect(CSS).toMatch(/\n\.menu\{position:absolute;z-index:2;left:0;right:0;top:100%;/);
    expect(CSS).toMatch(/\n\.pick\[open\]>summary::before\{content:"";position:fixed;inset:0;z-index:1;/);
    expect(CSS).toMatch(/@media \(min-width:720px\)\{[^\n]*\.pick\{position:relative\}\.menu\{right:auto;width:320px\}/);
  });

  it("Topics: each topic's icon before its name, the one its chip shows; All topics an empty slot so the names line up; Where has none", async () => {
    for (const path of ["/en", "/uk/de?topic=health", "/en/nato"]) {
      const { body } = await site(path);
      const items = leads(body, 1);
      expect(items[0], path).toEqual(["slot", text(path.startsWith("/uk") ? "uk" : "en", "filterAllTopics")]);
      expect(items.length, path).toBeGreaterThan(1);
      for (const [lead, name] of items.slice(1)) expect(TOPICS as readonly string[], `${path} ${name}`).toContain(lead);
      expect(leads(body, 0).every(([lead]) => lead === ""), path).toBe(true);
    }
    // The chosen topic's icon in the menu is its chip's.
    const { body } = await site("/en/de?topic=health");
    expect(leads(body, 1).find(([, name]) => name === "Health")?.[0]).toBe("health");
    expect(body).toContain(`<span class="label" aria-hidden="true"><svg class="glyph" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">${TOPIC_ICONS.health}</svg></span>`);
  });

  it("have an icon for every topic, drawn here and never loaded", () => {
    expect(Object.keys(TOPIC_ICONS).sort()).toEqual([...TOPICS].sort());
    for (const [topic, svg] of Object.entries(TOPIC_ICONS)) {
      expect(svg, topic).toMatch(/^<(path|rect|circle)/);
      expect(svg, topic).not.toMatch(/href|url\(|<image|<script/i);
    }
  });

  it("escape every name: a country, group or topic name can never become markup", () => {
    const evil = `"><script>alert(1)</script>`;
    const bar = filterBar(
      "en",
      { place: { country: "DE" }, topic: "economy" },
      { where: { groups: [{ id: "g7", name: evil, members: [] }], countries: [{ code: "DE", name: evil }] }, topics: [{ id: "economy", name: evil }] },
    ).value;
    expect(bar).not.toContain("<script>");
    expect(bar.split("&quot;&gt;&lt;script&gt;alert(1)&lt;/script&gt;").length - 1).toBe(3);
    // A code that is not a country with a page is never offered (it would be a 404, or break out of its path).
    const odd = filterBar("en", ALL, { where: { groups: [], countries: [{ code: `D"E/x`, name: "x" }, { code: "QQ", name: "Q" }] }, topics: [] }).value;
    expect(odd).not.toMatch(/d&quot;e|\/en\/qq/);
  });

  it("list only real countries: a source country that is not a code with a page is not offered", async () => {
    await env.DB.prepare(
      `INSERT INTO sources (id, country, name, kind, url, status) VALUES ('xx-evil', '"><b>', 'Evil', 'rss', 'https://evil.test', 'active'), ('qq-1', 'QQ', 'Q', 'rss', 'https://q.test', 'active')`,
    ).run();
    const { body } = await site("/en");
    expect(body).not.toMatch(/<b>|evil|\/en\/qq/i);
    // By name: France, Germany, Türkiye, United Kingdom, United States.
    expect(sections(body, 0)[2].map(([href]) => href)).toEqual(["/en/fr", "/en/de", "/en/tr", "/en/gb", "/en/us"]);
  });
});

describe("Local is gone", () => {
  it("has no page, no link and no word left", async () => {
    for (const path of ["/en/local", "/uk/local?topic=health"]) expect((await site(path)).status, path).toBe(404);
    for (const path of ["/en", "/en/de?topic=health", "/ru/g7", "/en/privacy", "/uk/privacy"]) {
      const { body } = await site(path);
      // The privacy policy's paragraph on what Local read (the country from the IP address) is gone too.
      // «Моя країна» stays: it is the app's Settings → My country, which For you's paragraph names (#170).
      expect(body, path).not.toMatch(/\/local|menu=where|“Local”|Cloudflare reads from your IP|за вашою IP-адресою/);
    }
    for (const lang of SITE_LANGS) expect((await site(`/${lang}`)).body).not.toContain(`<p class="menu-note">`);
  });
});

describe("empty lists", () => {
  it("say so with the app's words and lead to all countries and all topics", async () => {
    const ua = (await site("/en/ua")).body;
    expect(ua).toContain(`<p class="meta">${text("en", "filterEmpty")}</p>`);
    expect(ua).toContain(`<a class="more" href="/en">${text("en", "filterShowAllCountries")}</a>`);
    expect(ua).not.toContain(text("en", "filterShowAllTopics"));
    expect(ua).not.toContain('class="notice"');

    const both = (await site("/uk/de?topic=science")).body;
    expect(both).toContain(text("uk", "filterEmpty"));
    expect(both).toContain(`<a class="more" href="/uk?topic=science">${text("uk", "filterShowAllCountries")}</a>`);
    expect(both).toContain(`<a class="more" href="/uk/de">${text("uk", "filterShowAllTopics")}</a>`);

    const topic = (await site("/es?topic=science")).body;
    expect(topic).toContain(`<a class="more" href="/es">${text("es", "filterShowAllTopics")}</a>`);
    expect(topic).not.toContain(text("es", "filterShowAllCountries"));
  });

  it("a group with nothing in it is still a page and still offered (a fixed choice)", async () => {
    // German has no translations: every group is empty there.
    const nato = await site("/de/nato");
    expect(nato.status).toBe(200);
    expect(nato.body).toContain(text("de", "filterEmpty"));
    expect(nato.body).toContain(`<a class="more" href="/de">${text("de", "filterShowAllCountries")}</a>`);
    expect(sections(nato.body, 0)[1].map(([href, , current]) => [href, current])).toEqual([
      ["/de/eu", false],
      ["/de/g7", false],
      ["/de/g20", false],
      ["/de/nato", true],
    ]);
  });

  it("keep the unfiltered list's own empty texts", async () => {
    expect((await site("/de")).body).toContain("Noch keine übersetzten Entscheidungen.");
    expect((await site("/de")).body).not.toContain(text("de", "filterEmpty"));
  });
});

describe("paging and languages keep the filters", () => {
  it("Older decisions, Latest decisions, the language links and the alternates", async () => {
    for (const path of ["/en/g7", "/en?topic=economy", "/en/g20?topic=economy"]) {
      const first = await site(path);
      const next = nextLink(first.body)!;
      expect(next, path).toMatch(new RegExp(`^${path.replace("?", "\\?")}[?&]before=\\d+$`));
      const later = await site(next);
      expect(later.status).toBe(200);
      expect(later.body).toContain(`<a class="more" href="${path.replace("&", "&amp;")}">${text("en", "latestLink")}</a>`);
      for (const lang of SITE_LANGS) {
        const there = next.replace(/^\/en/, `/${lang}`);
        expect(later.body).toContain(`<link rel="alternate" hreflang="${lang}" href="${ORIGIN}${there.replace("&", "&amp;")}">`);
        expect(later.body).toContain(`<a href="${there.replace("&", "&amp;")}" hreflang="${lang}"`);
      }
      expect(later.body).toContain(`<link rel="canonical" href="${ORIGIN}${next.replace("&", "&amp;")}">`);
    }
  });

  it("a filtered first page names the filtered list everywhere: canonical, alternates, x-default, title", async () => {
    for (const [path, title] of [
      ["/de?topic=health", "Німеччина · Здоров’я · Останні рішення · Outer News"],
      ["/g7?topic=health", "G7 · Здоров’я · Останні рішення · Outer News"],
      ["/eu", "Європейський Союз · Останні рішення · Outer News"],
    ] as const) {
      const { body } = await site(`/uk${path}`);
      expect(body).toContain(`<link rel="canonical" href="${ORIGIN}/uk${path}">`);
      expect(hreflangs(body)).toEqual([...SITE_LANGS]);
      for (const lang of SITE_LANGS) expect(body).toContain(`hreflang="${lang}" href="${ORIGIN}/${lang}${path}"`);
      expect(body).toContain(`<link rel="alternate" hreflang="x-default" href="${ORIGIN}/en${path}">`);
      expect(body).toContain(`<title>${title}</title>`);
    }
    // The unfiltered first page keeps the landing page as x-default.
    expect((await site("/uk")).body).toContain(`<link rel="alternate" hreflang="x-default" href="${ORIGIN}/">`);
  });

  it("a later page shows its filters without menus, each a link to the list's first page, and reads no rows for them", async () => {
    const chipLinks = (body: string) =>
      [...body.matchAll(/<a class="chip-link" href="([^"]+)"><span class="(chip[^"]*)">[\s\S]*?<span class="vh">([^<]+)</g)].map((m) => [
        m[1].replaceAll("&amp;", "&"),
        m[2],
        m[3],
      ]);
    for (const [first, expected] of [
      ["/en/g7", [["/en/g7", "chip on", "Countries: G7"], ["/en/g7", "chip", "All topics"]]],
      ["/en?topic=health", [["/en?topic=health", "chip", "All countries"], ["/en?topic=health", "chip on", "Topic: Health"]]],
    ] as const) {
      const next = nextLink((await site(first)).body);
      expect(next, first).not.toBeNull();
      const later = await site(next!);
      expect(later.body).not.toContain("<details");
      expect(chipLinks(later.body), first).toEqual(expected);
      expect(later.body).toContain(`<nav class="filters" aria-label="${text("en", "filters")}"><a class="chip-link"`);
      const withMenus = await rowsRead(() => site(first));
      const without = await rowsRead(() => site(next!));
      expect(without, first).toBeLessThan(withMenus);
    }
  });
});

describe("one URL per view: every link is a cache key of its own", () => {
  it("every link of a list, its menus included, is a list's or an article's one URL (never a redirect), and a list's canonical", async () => {
    const seen = new Set<string>();
    for (const start of ["/en", "/en/g7?topic=health", "/uk/nato", "/en/de", "/es/eu?topic=economy", "/en/g7"]) {
      const first = await site(start);
      const later = nextLink(first.body);
      for (const body of [first.body, later ? (await site(later)).body : ""]) {
        const main = body.split("<footer")[0];
        // Every link but the home-screen icon's (icon.ts), which is no page.
        for (const m of main.matchAll(/href="(\/[^"]*)"/g)) if (m[1] !== "/apple-touch-icon.png") seen.add(m[1].replaceAll("&amp;", "&"));
      }
    }
    expect(seen.size).toBeGreaterThan(60);
    for (const href of seen) {
      const { status, body } = await site(href);
      expect(status, href).toBe(200);
      const canonical = /<link rel="canonical" href="([^"]+)">/.exec(body)?.[1].replaceAll("&amp;", "&");
      expect(canonical, href).toBe(ORIGIN + href);
    }
  });
});

describe("every new page", () => {
  const PAGES = ["/en/de", "/uk/de?topic=health", "/en?topic=economy", "/en/g7", "/uk/nato?topic=security-defence", "/en/eu", "/en/ua", "/es/pl", "/en/g20?before=30"];

  it("is indexed only as a first page with no topic and something on it, with the same value in its meta tag, and loads nothing else", async () => {
    for (const path of PAGES) {
      const { status, headers, body } = await site(path);
      expect(status, path).toBe(200);
      const robots = headers.get("x-robots-tag");
      if (path.includes("?") || !body.includes('class="title"')) expect(robots, path).toBe("noindex");
      else expect(robots, path).toBe("index, follow");
      expect(body, path).toContain(`<meta name="robots" content="${robots}">`);
      expect(withoutConsentScript(body), path).not.toMatch(/<script|<img|<iframe|rel="stylesheet"|rel="preload"|rel="prefetch"/i);
      expect(headers.get("cloudflare-cdn-cache-control"), path).toBe(CACHE.list.edge);
    }
  });

  it("has no placeholder, undefined or null left, in every language", async () => {
    for (const lang of SITE_LANGS) {
      for (const path of PAGES.map((p) => p.replace(/^\/[a-z]{2}/, `/${lang}`))) {
        const visible = withoutConsentScript((await site(path)).body).replace(/<style>[\s\S]*<\/style>/, "");
        expect(visible, path).not.toMatch(/\{\w+\}|undefined|null|NaN|\[object/);
      }
    }
  });

  it("asks GET /topics only when the page does not hold its whole list: a complete first page counts its own articles", async () => {
    const api = (path: string) => rowsRead(() => get(path));
    // The US: 15 articles, one page; NATO: 33, two pages.
    expect(await rowsRead(() => site("/en/us"))).toBe((await api("/articles?limit=20&country=US")) + (await api("/countries")));
    expect(await rowsRead(() => site("/en/nato"))).toBe(
      (await api("/articles?limit=20&group=nato")) + (await api("/countries")) + (await api("/topics?group=nato")),
    );
    // With a topic, the menu needs the place's whole feed: GET /topics.
    expect(await rowsRead(() => site("/en/us?topic=health"))).toBe(
      (await api("/articles?limit=20&country=US&topic=health")) + (await api("/countries")) + (await api("/topics?country=US")),
    );
  });

  it("reads a bounded number of D1 rows (numbers for docs/plan.md; a test database of 48 articles)", async () => {
    const rows: Record<string, number> = {};
    for (const path of ["/en", "/en/de", "/en/us", "/en/ua", "/en/eu", "/en/g7", "/en/g20", "/en/nato", "/en?topic=economy", "/en/g7?topic=health", "/uk/g20", "/uk?topic=economy"]) {
      rows[path] = await rowsRead(() => site(path));
      expect(rows[path], path).toBeLessThan(700);
    }
    console.log(JSON.stringify({ rowsRead: rows }));
  });
});

describe("texts", () => {
  it("every filter word is in every language, with its name where it has one", () => {
    for (const lang of SITE_LANGS as readonly SiteLang[]) {
      for (const key of ["filterAllCountries", "filterAllTopics", "filterGroupEUShort", "filterEmpty", "filterShowAllCountries", "filterShowAllTopics", "filters"] as const) {
        expect(text(lang, key), `${lang} ${key}`).toMatch(/\S/);
      }
      for (const key of ["filterCountryChip", "filterGroupChip", "filterTopicChip"] as const) {
        expect(text(lang, key, { name: "X" }), `${lang} ${key}`).toMatch(/^\S.*X$/);
      }
    }
  });
});
