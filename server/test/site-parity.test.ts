// The website shows exactly what the app's API shows (#88): for every article
// and language, the page is there exactly when GET /articles/:id?lang= is, with
// the API's texts; the lists are the API's pages, in the same order (page 1's
// Latest without its Top stories, as the app). Written
// as loops over the API, so a change to its rules (#84 source names, #86
// filters) is covered without touching these tests.
import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import type { ApiArticle, ApiList } from "../src/site/data";
import { SITE_LANGS, type SiteLang, decisionLabel } from "../src/site/texts";
import { get, hideSeed } from "./helpers";
import { ORIGIN, escaped, hoursAgo, hreflangs, insertArticle, insertTranslation, linkedIds, reach, site, siteRowsRead as rowsRead, testId } from "./site-helpers";

const A = {
  englishOnly: testId(1),
  ukrainian: testId(2),
  ruFailedNewer: testId(3),
  esUpdating: testId(4),
  ruFailedSame: testId(5),
  hidden: testId(6),
  notReleased: testId(7),
  old: testId(8),
  blockedSource: testId(9),
  unknown: testId(99),
};

async function fixtures() {
  await hideSeed();
  await insertArticle({ id: A.englishOnly });
  await insertArticle({ id: A.ukrainian, originalLanguage: "uk" });
  await insertTranslation(A.ukrainian, "uk");
  await insertArticle({ id: A.ruFailedNewer });
  await insertTranslation(A.ruFailedNewer, "ru", "failed-newer");
  await insertTranslation(A.ruFailedNewer, "uk");
  await insertArticle({ id: A.esUpdating, decisionType: null });
  await insertTranslation(A.esUpdating, "es", "updating");
  await insertArticle({ id: A.ruFailedSame, decisionType: "law" });
  await insertTranslation(A.ruFailedSame, "ru", "failed-same");
  await insertTranslation(A.ruFailedSame, "de", "queued");
  await insertArticle({ id: A.hidden, isNews: 0, released: false });
  await insertTranslation(A.hidden, "uk");
  await insertArticle({ id: A.notReleased, released: false });
  await insertArticle({ id: A.old, publishedAt: hoursAgo(24 * 10) });
  await insertTranslation(A.old, "es");
  await insertArticle({ id: A.blockedSource, sourceId: "us-white-house", originalLanguage: "en" });
  await env.DB.prepare("UPDATE sources SET status = 'blocked' WHERE id = 'us-white-house'").run();
}

const apiArticle = async (id: string, lang: SiteLang) => get(lang === "en" ? `/articles/${id}` : `/articles/${id}?lang=${lang}`);

beforeEach(fixtures);

describe("article pages", () => {
  it("exist exactly where the API shows the article, with its texts and alternates", async () => {
    let shownPairs = 0;
    for (const id of Object.values(A)) {
      const answers = await Promise.all(SITE_LANGS.map((lang) => apiArticle(id, lang)));
      const shownIn = SITE_LANGS.filter((_, i) => answers[i].status === 200);
      for (const [i, lang] of SITE_LANGS.entries()) {
        const page = await reach(`/${lang}/de/${id}`);
        const api = answers[i];
        expect(page.status === 200, `${id} ${lang}: site ${page.status}, API ${api.status}`).toBe(api.status === 200);
        if (api.status === 200) {
          shownPairs++;
          const a = api.body as ApiArticle;
          expect(page.body).toContain(escaped(a.headline!));
          expect(page.body).toContain(escaped(a.shortSummary!));
          for (const paragraph of a.summary!.split(/\n\s*\n/)) expect(page.body).toContain(escaped(paragraph.trim()));
          expect(page.body).toContain(escaped(a.source.name));
          const label = decisionLabel(lang, a.decisionType);
          if (label) expect(page.body).toContain(`<p class="kind">${escaped(label)}</p>`);
          else expect(page.body).not.toContain('class="kind"');
          expect(hreflangs(page.body)).toEqual(shownIn);
        } else if (shownIn.length) {
          // Not (yet) in this language: a 404 that leads to the languages it is in.
          expect(page.status).toBe(404);
          expect(page.body).toContain("class=\"choose\"");
          expect([...page.body.matchAll(/<li><a href="\/([a-z]{2})\//g)].map((m) => m[1])).toEqual(shownIn);
        } else {
          expect(page.status).toBe(404);
          expect(page.body).not.toContain("class=\"choose\"");
        }
      }
    }
    // The fixtures cover shown and not-shown pairs in every language.
    expect(shownPairs).toBeGreaterThan(10);
  });

  it("shows the queue states as the API does: updating and failed-for-the-same-English are shown, failed-for-a-newer-English is not", async () => {
    expect((await reach(`/es/de/${A.esUpdating}`)).status).toBe(200);
    expect((await reach(`/ru/de/${A.ruFailedSame}`)).status).toBe(200);
    expect((await reach(`/ru/de/${A.ruFailedNewer}`)).status).toBe(404);
    expect((await reach(`/de/de/${A.ruFailedSame}`)).status).toBe(404);
  });

  it("answers 404, not 410, for a hidden article: is_news = 0 means never shown, not removed", async () => {
    for (const lang of SITE_LANGS) {
      const page = await reach(`/${lang}/de/${A.hidden}`);
      expect(page.status).toBe(404);
      expect(page.body).not.toContain("removed");
    }
    expect((await reach(`/en/de/${A.notReleased}`)).status).toBe(404);
    expect((await reach(`/en/de/${A.unknown}`)).status).toBe(404);
  });

  it("keeps an article older than the feed's 7 days, and one from a blocked source, as the API does", async () => {
    expect((await reach(`/en/de/${A.old}`)).status).toBe(200);
    expect((await reach(`/es/de/${A.old}`)).status).toBe(200);
    expect((await reach(`/en/us/${A.blockedSource}`)).status).toBe(200);
  });

  it("sends an address with another country or slug, or none, to the article's own one with a 301 (#89 review)", async () => {
    const own = await reach(`/uk/de/${A.ukrainian}`);
    expect(own.status).toBe(200);
    const canonical = /<link rel="canonical" href="([^"]+)">/.exec(own.body)![1];
    expect(canonical).toMatch(new RegExp(`^https://site\\.test/uk/de/${A.ukrainian}-uk-rishennia-`));
    for (const path of [`/uk/de/${A.ukrainian}`, `/uk/fr/${A.ukrainian}-an-old-headline`, `/uk/zz/${A.ukrainian}-uk-rishennia`, `/uk/DE/${canonical.split("/").pop()}`]) {
      for (const method of ["GET", "HEAD"]) {
        const moved = await site(path, { method });
        expect(moved.status, path).toBe(301);
        expect(moved.headers.get("location"), path).toBe(canonical);
        expect(moved.body).toBe("");
      }
    }
    // The address itself is a page: no redirect loop.
    expect((await site(canonical.slice(ORIGIN.length))).status).toBe(200);
  });

  it("reads about 13 D1 rows for an article page, and no row for a malformed id", async () => {
    const own = (await site(`/uk/de/${A.ukrainian}`)).headers.get("location")!;
    const rows = await rowsRead(() => site(own.slice(ORIGIN.length)));
    console.log(JSON.stringify({ rowsRead: { article: rows } }));
    expect(rows).toBeGreaterThan(0);
    expect(rows).toBeLessThanOrEqual(20);
    expect(await rowsRead(() => site("/uk/de/01JTEST-not-an-id"))).toBe(0);
    expect(await rowsRead(() => site(`/uk/de/${A.ukrainian.toLowerCase()}`))).toBe(0);
  });
});

describe("latest lists", () => {
  beforeEach(async () => {
    // Enough for three pages of 20, Ukrainian on every third.
    for (let n = 10; n < 55; n++) {
      await insertArticle({ id: testId(n), importance: n % 5 });
      if (n % 3 === 0) await insertTranslation(testId(n), "uk");
    }
  });

  /** Every page of the API's list in `lang`, through nextCursor. */
  async function apiPages(lang: SiteLang) {
    const pages: ApiList[] = [];
    let cursor: string | null = null;
    do {
      const query: string = `limit=20${lang === "en" ? "" : `&lang=${lang}`}${cursor ? `&cursor=${cursor}` : ""}`;
      const page = (await get(`/articles?${query}`)).body as ApiList;
      pages.push(page);
      cursor = page.nextCursor;
    } while (cursor);
    return pages;
  }

  /** Every page of the site's list in `lang`, through its "Older decisions" links. */
  async function sitePages(lang: SiteLang) {
    const pages: { top: string[]; items: string[] }[] = [];
    let path: string | null = `/${lang}`;
    while (path) {
      const page = await site(path);
      expect(page.status).toBe(200);
      // Top stories are their own section (page 1 only); every other article link is the list's.
      const main = page.body.split("<footer")[0];
      const top = /<section aria-labelledby="top">[\s\S]*?<\/section>/.exec(main)?.[0] ?? "";
      pages.push({ top: linkedIds(top), items: linkedIds(main.replace(top, "")) });
      path = /<a class="more" href="([^"]+)" rel="next">/.exec(page.body)?.[1].replaceAll("&amp;", "&") ?? null;
    }
    return pages;
  }

  it("are the API's pages, in the same order, with the same top stories (not repeated under Latest), in every language", async () => {
    for (const lang of SITE_LANGS) {
      const api = await apiPages(lang);
      const ours = await sitePages(lang);
      // Page 1's Latest leaves out its Top stories, as the app's feed does (#89 review); the API gives top on page 1 only.
      expect(ours.map((p) => p.items), lang).toEqual(api.map((p) => p.items.filter((a) => !p.top.some((t) => t.id === a.id)).map((a) => a.id)));
      expect(ours.map((p) => p.top), lang).toEqual(api.map((p) => p.top.map((a) => a.id)));
      // The next page starts after the API's whole first page, Top stories included.
      if (api.length > 1) expect(ours[1].items[0], lang).toBe(api[1].items[0].id);
    }
    expect((await apiPages("en")).length).toBe(3);
    // The fixtures have Top stories that are also among the first page's latest 20, so the rule is exercised.
    const first = (await apiPages("en"))[0];
    expect(first.top.filter((t) => first.items.some((a) => a.id === t.id)).length).toBeGreaterThan(0);
  });

  it("say so when a language has nothing yet (German is off)", async () => {
    const page = await site("/de");
    expect(page.status).toBe(200);
    expect(page.body).toContain("Noch keine übersetzten Entscheidungen.");
    expect(linkedIds(page.body)).toEqual([]);
  });

  it("read a bounded number of D1 rows per page", async () => {
    const first = await rowsRead(() => site("/en"));
    const next = /<a class="more" href="([^"]+)" rel="next">/.exec((await site("/en")).body)![1];
    const later = await rowsRead(() => site(next));
    expect(first).toBeLessThan(400);
    expect(later).toBeLessThan(200);
    expect(await rowsRead(() => site("/uk?before=0"))).toBe(0);
    // The numbers, for docs/decisions.md (a test database: a few dozen articles).
    console.log(JSON.stringify({ rowsRead: { listFirstPage: first, listLaterPage: later } }));
  });
});
