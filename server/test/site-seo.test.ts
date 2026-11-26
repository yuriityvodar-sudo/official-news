// What search engines read (#88, SEO): the sitemap, robots.txt's pointer to
// it and an article's structured data.
import { newsSitemapXml } from "../src/site/seo";
import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { slugify } from "../src/site/urls";
import { CF_BEACON_TOKEN, CONSENT_JS, GA_ID, consentHash } from "../src/site/consent";
import { SITE_LANGS } from "../src/site/texts";
import { hideSeed, rowsRead } from "./helpers";
import { ORIGIN, insertArticle, insertTranslation, reach, refreshSite, site, testId, withoutConsentScript } from "./site-helpers";

const ID = testId(1);
const OTHER = testId(2);
const EN = `/en/de/${ID}-${slugify("Cabinet decision 0001 on the budget", "en")}`;
const UK = `/uk/de/${ID}-${slugify("[uk] Рішення 0001 про бюджет", "uk")}`;

beforeEach(async () => {
  await hideSeed();
  await insertArticle({ id: ID });
  await insertTranslation(ID, "uk");
  await insertArticle({ id: OTHER });
});

describe("the sitemap", () => {
  it("lists each language's latest list while it has articles, and each indexable article in English and in its source's language, with the other as alternate", async () => {
    const { status, headers, body } = await site("/sitemap-latest.xml");
    expect(status).toBe(200);
    expect(headers.get("content-type")).toBe("application/xml; charset=utf-8");
    expect(body.startsWith('<?xml version="1.0" encoding="UTF-8"?>')).toBe(true);
    const locs = [...body.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
    // Only English and Ukrainian have articles here; an empty list is noindex, so not listed.
    for (const lang of SITE_LANGS) expect(locs.includes(`${ORIGIN}/${lang}`), lang).toBe(lang === "en" || lang === "uk");
    expect(locs).toContain(ORIGIN + EN);
    // ID is a German source's decision: its Ukrainian page is a third language, so not listed (#350).
    expect(locs).not.toContain(ORIGIN + UK);
    expect(locs.filter((l) => l.includes(OTHER))).toHaveLength(1);
    const enEntry = body.split("<url>").find((u) => u.includes(`<loc>${ORIGIN}${EN}</loc>`))!;
    expect(enEntry).not.toContain('hreflang="uk"');
    expect(enEntry).toMatch(/<lastmod>\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ<\/lastmod>/);
  });

  it("names each country's page with something in the 7 days, and says when each file and list last changed (#350)", async () => {
    const { body } = await site("/sitemap-latest.xml");
    const locs = [...body.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
    // The fixtures' source is Germany's: its page in English and Ukrainian, each naming the other, with the newest article's time.
    expect(locs).toContain(`${ORIGIN}/en/de`);
    expect(locs).toContain(`${ORIGIN}/uk/de`);
    expect(locs).not.toContain(`${ORIGIN}/en/fr`);
    const entry = body.split("<url>").find((u) => u.includes(`<loc>${ORIGIN}/en/de</loc>`))!;
    expect(entry).toContain(`<xhtml:link rel="alternate" hreflang="uk" href="${ORIGIN}/uk/de"/>`);
    expect(entry).toMatch(/<lastmod>\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ<\/lastmod>/);
    expect((await site("/en/de")).headers.get("x-robots-tag")).toBe("index, follow");
    expect(body.split("<url>").find((u) => u.includes(`<loc>${ORIGIN}/en</loc>`))!).toContain("<lastmod>");
    // The index: every file with its date; a past month's is the month's end.
    const index = (await site("/sitemap.xml")).body;
    expect(index.match(/<lastmod>/g)!.length).toBe(index.match(/<sitemap>/g)!.length);
    expect(index).toContain(`<loc>${ORIGIN}/sitemap-2026-10.xml</loc><lastmod>2026-11-01T00:00:00Z</lastmod>`);
    // An official decision's page links to its country's page.
    expect((await site(EN)).body).toContain('<a href="/en/de">Germany</a>');
  });

  it("has a news sitemap of the last 2 days' indexable articles, named in the index (#350)", async () => {
    const { status, headers, body } = await site("/sitemap-news.xml");
    expect(status).toBe(200);
    expect(headers.get("content-type")).toBe("application/xml; charset=utf-8");
    expect(body).toContain('xmlns:news="http://www.google.com/schemas/sitemap-news/0.9"');
    const entry = body.split("<url>").find((u) => u.includes(`<loc>${ORIGIN}${EN}</loc>`))!;
    expect(entry).toContain("<news:name>Outer News</news:name><news:language>en</news:language>");
    expect(entry).toContain("<news:title>Cabinet decision 0001 on the budget</news:title>");
    expect(entry).toMatch(/<news:publication_date>\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ<\/news:publication_date>/);
    // Not the Ukrainian page of a German source (not indexable).
    expect(body).not.toContain(ORIGIN + UK);
    // Nor what came more than 2 days ago: the rule itself, on two articles 1 hour and 3 days old.
    const at = (hours: number) => new Date(Date.now() - hours * 3_600_000).toISOString().replace(/\.\d+Z$/, "Z");
    const one = (id: string, hours: number) => ({ id, country: "DE", countries: [], source: { name: "S" }, headline: `Decision ${id}`, originalTitle: "T", shortSummary: null, decisionType: "law", importance: 4, originalLanguage: "de", topics: [], publishedAt: at(hours), dateOnly: false, feedSeq: 1, addedAt: at(hours) });
    const xmlOf = newsSitemapXml(ORIGIN, { en: [one(testId(51), 1), one(testId(52), 72)] }, new Date());
    expect(xmlOf).toContain(testId(51));
    expect(xmlOf).not.toContain(testId(52));
    expect((await site("/sitemap.xml")).body).toContain(`<loc>${ORIGIN}/sitemap-news.xml</loc><lastmod>`);
  });

  it("lists only the best pages: a decision of importance 3 and up, in English and in its source's own language (#350)", async () => {
    const [OWN, MINOR, EVENT] = [testId(31), testId(32), testId(33)];
    await insertArticle({ id: OWN, headline: "Ukraine decision on schools", originalLanguage: "uk" });
    await insertTranslation(OWN, "uk");
    await insertArticle({ id: MINOR, headline: "Minor notice", importance: 2 });
    await insertArticle({ id: EVENT, headline: "Something happened", decisionType: "event", importance: 5 });
    const { body } = await site("/sitemap-latest.xml");
    const locs = [...body.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
    // The source's own language and English, each naming the other.
    expect(locs.filter((l) => l.includes(OWN)).map((l) => l.slice(ORIGIN.length, ORIGIN.length + 3)).sort()).toEqual(["/en", "/uk"]);
    const own = body.split("<url>").find((u) => u.includes(OWN) && u.includes(`<loc>${ORIGIN}/en/`))!;
    expect(own).toContain('hreflang="uk"');
    expect(locs.some((l) => l.includes(MINOR))).toBe(false);
    expect(locs.some((l) => l.includes(EVENT))).toBe(false);
    // Their pages stay on the site, with noindex and no alternates; the best page says index.
    const page = async (id: string, lang = "en") => reach(`/${lang}/de/${id}`);
    for (const id of [MINOR, EVENT]) {
      const { status, headers, body: html } = await page(id);
      expect(status, id).toBe(200);
      expect(headers.get("x-robots-tag"), id).toBe("noindex");
      expect(html, id).not.toContain('rel="alternate"');
    }
    for (const lang of ["en", "uk"]) {
      const { headers, body: html } = await page(OWN, lang);
      expect(headers.get("x-robots-tag"), lang).toBe("index, follow");
      expect([...html.matchAll(/<link rel="alternate" hreflang="([^"]+)"/g)].map((m) => m[1])).toEqual(["en", "uk", "x-default"]);
    }
  });

  // 30 Oct: article pages never expire, but the sitemap listed only the 7 days (about 970 of 3,250 pages).
  it("is an index of the latest file and one file per month since October 2026, read with no D1 row", async () => {
    const { status, headers, body } = await site("/sitemap.xml");
    expect(status).toBe(200);
    expect(headers.get("content-type")).toBe("application/xml; charset=utf-8");
    const locs = [...body.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
    expect(body).toContain('<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">');
    expect(locs[0]).toBe(`${ORIGIN}/sitemap-latest.xml`);
    expect(locs[1]).toBe(`${ORIGIN}/sitemap-news.xml`);
    expect(locs[2]).toBe(`${ORIGIN}/sitemap-2026-10.xml`);
    const now = new Date();
    expect(locs.at(-1)).toBe(`${ORIGIN}/sitemap-${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}.xml`);
  });

  it("lists in a month's file every indexable article released that month, older than the 7 days too, in English and its source's language", async () => {
    const OLD = testId(9);
    await insertArticle({ id: OLD, headline: "Old decision on water", originalLanguage: "uk" });
    await insertTranslation(OLD, "uk");
    const OLD_MINOR = testId(10);
    await insertArticle({ id: OLD_MINOR, headline: "Old minor notice", importance: 1 });
    await env.DB.prepare("UPDATE articles SET added_at = '2026-10-15T10:00:00Z' WHERE id = ?").bind(OLD_MINOR).run();
    await env.DB.prepare("UPDATE articles SET added_at = '2026-10-15T09:00:00Z', published_at = '2026-10-15T08:00:00Z' WHERE id = ?").bind(OLD).run();
    const month = await site("/sitemap-2026-10.xml");
    expect(month.status).toBe(200);
    const locs = [...month.body.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
    const enOld = `${ORIGIN}/en/de/${OLD}-${slugify("Old decision on water", "en")}`;
    expect(locs).toContain(enOld);
    expect(locs.filter((l) => l.includes(OLD))).toHaveLength(2);
    expect(locs.some((l) => l.includes(OLD_MINOR))).toBe(false);
    expect(month.body).toContain("<lastmod>2026-10-15T09:00:00Z</lastmod>");
    // The latest file keeps to the 7 days.
    expect((await site("/sitemap-latest.xml")).body).not.toContain(OLD);
    // A month before the first, a future one, or a malformed one is no sitemap.
    for (const path of ["/sitemap-2026-09.xml", "/sitemap-2099-01.xml", "/sitemap-2026-1.xml"]) expect((await site(path)).status, path).toBe(404);
    // A past month is kept a day; the current one 6 hours (its new articles are in the latest file within the hour).
    const past = month.headers.get("cloudflare-cdn-cache-control");
    const now = new Date();
    const currentMonth = `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}`;
    expect(past).toBe(currentMonth === "2026-10" ? "max-age=21600, stale-if-error=604800" : "max-age=86400, stale-if-error=604800");
    // What a month's file reads: the month's articles and their translations, through the (added_at) index.
    console.log(JSON.stringify({ rowsRead: { sitemapMonth: await rowsRead(() => site("/sitemap-2026-10.xml")), sitemapIndex: await rowsRead(() => site("/sitemap.xml")) } }));
    expect(await rowsRead(() => site("/sitemap.xml"))).toBe(0);
  });

  it("is named in robots.txt, which keeps crawlers only from addresses with a query", async () => {
    const { body } = await site("/robots.txt");
    expect(body).toMatch(/^Disallow: \/\*\?$/m);
    expect(body).toContain(`Sitemap: ${ORIGIN}/sitemap.xml`);
  });
});

describe("an article's structured data", () => {
  it("is a NewsArticle by Outer News, in the page's language, based on the official page", async () => {
    for (const [path, lang] of [[EN, "en"], [UK, "uk"]] as const) {
      const { body } = await site(path);
      const json = /<script type="application\/ld\+json">([^<]*)<\/script>/.exec(body)?.[1];
      expect(json, path).toBeDefined();
      const data = JSON.parse(json!);
      expect(data["@type"]).toBe("NewsArticle");
      expect(data.inLanguage).toBe(lang);
      expect(data.url).toBe(ORIGIN + path);
      expect(data.publisher.name).toBe("Outer News");
      expect(data.author.name).toBe("Outer News");
      expect(data.isBasedOn).toMatch(/^https:\/\//);
      expect(data.datePublished).toMatch(/Z$/);
    }
  });
});

describe("/ opens the visitor's language (no page to choose one)", () => {
  const go = async (acceptLanguage: string | null) => {
    const headers: Record<string, string> = {};
    if (acceptLanguage !== null) headers["accept-language"] = acceptLanguage;
    const { status, headers: h } = await site("/", { headers });
    return { status, location: h.get("location"), cache: h.get("cache-control") };
  };

  it("takes the browser's first language the site has, and is never cached", async () => {
    expect(await go("uk-UA,uk;q=0.9,en;q=0.8")).toEqual({ status: 302, location: `${ORIGIN}/uk`, cache: "private, no-store" });
    expect((await go("ru-RU,ru;q=0.9")).location).toBe(`${ORIGIN}/ru`);
    expect((await go("es-MX,es;q=0.9")).location).toBe(`${ORIGIN}/es`);
    expect((await go("fr-FR,fr;q=0.9,en;q=0.5")).location).toBe(`${ORIGIN}/en`);
    expect((await go("en;q=0.4,uk;q=0.9")).location).toBe(`${ORIGIN}/uk`);
  });

  it("leaves German out while the server does not translate into it, and falls back to English", async () => {
    expect((await go("de-DE,de;q=0.9")).location).toBe(`${ORIGIN}/en`);
    expect((await go(null)).location).toBe(`${ORIGIN}/en`);
    expect((await go("*")).location).toBe(`${ORIGIN}/en`);
  });
});

describe("Cloudflare Web Analytics, for every visitor", () => {
  // #60, 5 Nov: the beacon Cloudflare injected reported to the site's own /cdn-cgi/rum, which answered browsers 503.
  it("every page carries Cloudflare's cookieless beacon, reporting to cloudflareinsights.com, which the CSP allows", async () => {
    for (const path of ["/en", "/uk", EN, "/es/about"]) {
      const { body, headers } = await site(path);
      expect(body, path).toContain(
        `<script defer src="https://static.cloudflareinsights.com/beacon.min.js" data-cf-beacon='{"token":"${CF_BEACON_TOKEN}"}'></script>`,
      );
      const policy = headers.get("content-security-policy") ?? "";
      expect(policy, path).toContain(" https://static.cloudflareinsights.com;");
      expect(policy, path).toContain(" https://cloudflareinsights.com;");
    }
    expect(CF_BEACON_TOKEN).toMatch(/^[0-9a-f]{32}$/);
  });
});

describe("Google Analytics, after the visitor accepts cookies", () => {
  it("every page carries the notice hidden and the one script the CSP allows by its hash; Google's tag is not in the page", async () => {
    for (const path of ["/en", "/uk", EN, "/es/about"]) {
      const { body, headers } = await site(path);
      expect(body, path).toMatch(/<div class="consent" id="consent" role="dialog" aria-modal="(true|false)" aria-label="[^"]+"( data-wall)? hidden>/);
      expect(body, path).toContain(`<script>${CONSENT_JS}</script>`);
      // Google's tag is added by the script after Accept, never written into the page.
      expect(withoutConsentScript(body), path).not.toContain("googletagmanager");
      expect(headers.get("content-security-policy"), path).toContain(`script-src '${await consentHash()}' https://*.googletagmanager.com`);
    }
    expect(CONSENT_JS).toContain(`"${GA_ID}"`);
    expect(GA_ID).toBe("G-D0H8XW2SWJ");
  });

  // Yurii, 30 Oct: a cookie wall with a general message; Details is the privacy policy, which names Google Analytics.
  it("covers articles and lists until Accept, and is a bar on the information pages so Details can be read", async () => {
    for (const path of ["/en", EN]) {
      const { body } = await site(path);
      expect(body, path).toContain('aria-modal="true" aria-label="Cookies" data-wall hidden>');
      expect(body, path).toContain("We use cookies to give you a better experience on Outer News.");
      expect(body, path).toContain('<a href="/en/privacy">Details</a>');
      // The notice itself names no company; the privacy policy does.
      expect(body.slice(body.indexOf('<div class="consent"'), body.indexOf("<script>")), path).not.toContain("Google");
    }
    for (const page of ["about", "privacy", "terms", "support"]) {
      expect((await site(`/en/${page}`)).body, page).toContain('aria-modal="false" aria-label="Cookies" hidden>');
    }
    expect((await site("/en/privacy")).body).toContain("Google Analytics");
    // No way to say no: the only answer is OK (Yurii, 30 Oct: "just OK button and no cancel button").
    expect(CONSENT_JS).not.toContain('"no"');
  });

  // Roman's review of #240: the policy says what the site does, and withdrawing is as easy as accepting.
  it("names Google Analytics and its cookies in the privacy policy, and every page has Cookie settings to withdraw", async () => {
    const privacy = (await site("/en/privacy")).body;
    expect(privacy).toContain("this website uses Google Analytics, a service of Google");
    expect(privacy).toContain(`_ga_${GA_ID.slice(2)}`);
    expect(privacy).not.toContain("sets no cookies");
    for (const path of ["/en", EN, "/uk/terms"]) {
      expect((await site(path)).body, path).toMatch(/<button type="button" class="link" data-consent-reset>[^<]+<\/button><\/nav>/);
    }
    // Withdrawing forgets the yes, deletes Google's cookies and asks again.
    expect(CONSENT_JS).toContain("localStorage.removeItem(k)");
    expect(CONSENT_JS).toContain('indexOf("_ga")');
    expect(CONSENT_JS).toContain("location.reload()");
  });
});

describe("the front page's title", () => {
  it("leads with the name; a filtered list names its filters first", async () => {
    expect((await site("/uk")).body).toContain("<title>Outer News · ");
    expect((await site("/en")).body).toContain("<title>Outer News · Official decisions</title>");
    expect((await site("/en/de")).body).toMatch(/<title>Germany · [^<]* · Outer News<\/title>/);
  });
});
