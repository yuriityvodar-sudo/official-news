// What search engines read (#88, SEO): the sitemap, robots.txt's pointer to
// it and an article's structured data.
import { beforeEach, describe, expect, it } from "vitest";
import { slugify } from "../src/site/urls";
import { SITE_LANGS } from "../src/site/texts";
import { hideSeed } from "./helpers";
import { ORIGIN, insertArticle, insertTranslation, site, testId } from "./site-helpers";

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
  it("lists every language's latest list and each article in each language it is shown in, with the others as alternates", async () => {
    const { status, headers, body } = await site("/sitemap.xml");
    expect(status).toBe(200);
    expect(headers.get("content-type")).toBe("application/xml; charset=utf-8");
    expect(body.startsWith('<?xml version="1.0" encoding="UTF-8"?>')).toBe(true);
    const locs = [...body.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
    for (const lang of SITE_LANGS) expect(locs).toContain(`${ORIGIN}/${lang}`);
    expect(locs).toContain(ORIGIN + EN);
    expect(locs).toContain(ORIGIN + UK);
    // OTHER is not translated: English only, so no Ukrainian address for it.
    expect(locs.filter((l) => l.includes(OTHER))).toHaveLength(1);
    const enEntry = body.split("<url>").find((u) => u.includes(`<loc>${ORIGIN}${EN}</loc>`))!;
    expect(enEntry).toContain(`<xhtml:link rel="alternate" hreflang="uk" href="${ORIGIN}${UK}"/>`);
    expect(enEntry).toMatch(/<lastmod>\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ<\/lastmod>/);
  });

  it("is named in robots.txt, which still disallows everything", async () => {
    const { body } = await site("/robots.txt");
    expect(body).toMatch(/^Disallow: \/$/m);
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
