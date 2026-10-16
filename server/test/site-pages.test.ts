// Every page of the website in every language (#88): no placeholder left, the
// AI label and notice where AI text is shown (and each disclaimer once), the
// app's behaviour for an article without a summary, and the credit line per source.
import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { LANGUAGE_NAMES, SITE_LANGS, aiNoticeText, text } from "../src/site/texts";
import { INFO_PAGES } from "../src/site/urls";
import { hideSeed } from "./helpers";
import { insertArticle, insertTranslation, site, testId } from "./site-helpers";

describe("every page in every language", () => {
  beforeEach(async () => {
    await hideSeed();
    await insertArticle({ id: testId(1), importance: 5 });
    for (const lang of ["uk", "ru", "es", "de"] as const) await insertTranslation(testId(1), lang);
    await insertArticle({ id: testId(2), headline: null, summary: "", shortSummary: "" });
  });

  it("renders with no placeholder, undefined or null left", async () => {
    const paths = ["/", ...SITE_LANGS.flatMap((l) => [`/${l}`, `/${l}/de/${testId(1)}`, `/${l}/nowhere`, ...INFO_PAGES.map((p) => `/${l}/${p}`)])];
    paths.push(`/en/de/${testId(2)}`, `/uk/de/${testId(2)}`);
    for (const path of paths) {
      const { status, body } = await site(path);
      expect([200, 404], path).toContain(status);
      // CSS has braces; the page's text has none left.
      const visible = body.replace(/<style>[\s\S]*<\/style>/, "");
      expect(visible, path).not.toMatch(/\{\w+\}|undefined|null|NaN|\[object/);
    }
  });

  it("shows the AI label under the headline and the AI notice on articles and lists", async () => {
    const article = (await site(`/uk/de/${testId(1)}`)).body;
    expect(article).toMatch(/<\/h1>\n<p class="ai meta">.*Стислий виклад від ШІ · переклад з німецької/);
    expect(article).toContain(aiNoticeText("uk"));
    expect(article).toMatch(/<meta name="description" content="Стислий виклад від ШІ: /);
    expect(article).toMatch(/<meta property="og:description" content="Стислий виклад від ШІ: /);
    // iMessage previews show only the title: it carries the label; the tab's title does not.
    expect(article).toMatch(/<meta property="og:title" content="\[uk\] Рішення \w+ про бюджет · Стислий виклад від ШІ">/);
    expect(article).toMatch(/<title>\[uk\] Рішення \w+ про бюджет · Official News<\/title>/);
    expect((await site("/es")).body).toContain(aiNoticeText("es"));
  });

  it("puts the AI notice on every page that shows an AI headline, the not-in-language 404 too", async () => {
    await insertArticle({ id: testId(4) }); // English only
    const paths = SITE_LANGS.flatMap((l) => [`/${l}`, `/${l}/de/${testId(1)}`]);
    paths.push(`/en?before=${Number.MAX_SAFE_INTEGER}`, `/uk/de/${testId(4)}`);
    for (const path of paths) {
      const { status, body } = await site(path);
      const lang = path.slice(1, 3) as (typeof SITE_LANGS)[number];
      expect(body, path).toMatch(/Cabinet decision|Рішення/);
      expect(body.split(aiNoticeText(lang)).length - 1, `${path} (${status})`).toBe(1);
    }
    // The 404 names each language it can be read in.
    expect((await site(`/uk/de/${testId(4)}`)).body).toMatch(new RegExp(`<span class="meta">${LANGUAGE_NAMES.en.nativeName}</span>`));
  });

  it("says each disclaimer once on an article: AI notice, independence note (header), no app footer", async () => {
    for (const lang of SITE_LANGS) {
      const { body } = await site(`/${lang}/de/${testId(1)}`);
      expect(body.split(text(lang, "independentNote")).length - 1, lang).toBe(1);
      expect(body, lang).not.toContain(text(lang, "aboutIndependent"));
    }
  });

  it("titles a list apart from its sections, and a later page has no section heading", async () => {
    for (const lang of SITE_LANGS) {
      const first = (await site(`/${lang}`)).body;
      const h1 = /<h1 class="page-title">([^<]+)<\/h1>/.exec(first)![1];
      const h2s = [...first.matchAll(/<h2 class="section"[^>]*>([^<]+)<\/h2>/g)].map((m) => m[1]);
      expect(h2s, lang).not.toContain(h1);
      const later = (await site(`/${lang}?before=${Number.MAX_SAFE_INTEGER}`)).body;
      expect(later, lang).not.toContain('<h2 class="section"');
      expect(later, lang).toContain('<ol class="items">');
    }
  });

  it("shows an article the AI has not summarized like the app: its original title, the 'on its way' note, no AI label", async () => {
    const { body } = await site(`/en/de/${testId(2)}`);
    expect(body).toContain(`<h1>Kabinett beschließt ${testId(2).slice(-4)}</h1>`);
    expect(body).toContain(text("en", "summaryComing"));
    expect(body).not.toContain('class="ai meta"');
  });

  it("credits the source by its row in docs/source-credits.csv, else with the generic line", async () => {
    await env.DB.prepare(
      `INSERT INTO sources (id, country, name, kind, url, language) VALUES ('gb-policy-consultations', 'GB', 'UK Government (GOV.UK)', 'rss', 'https://www.gov.uk', 'en')`,
    ).run();
    await insertArticle({ id: testId(3), sourceId: "gb-policy-consultations", originalLanguage: "en" });
    const { body: ogl } = await site(`/en/gb/${testId(3)}`);
    // The OGL's statement names the licence, so it is the licence link (the licence is not said twice).
    expect(ogl).toContain(
      'Source: UK Government (GOV.UK) · <a href="https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/" rel="license" lang="en">Contains public sector information licensed under the Open Government Licence v3.0.</a></p>',
    );
    // A copyright notice the licensor supplies (CC BY 4.0 §3(a)(1)(A)) comes before the licence link.
    await env.DB.prepare(
      `INSERT INTO sources (id, country, name, kind, url, language) VALUES ('eu-commission-press-releases', 'EU', 'European Commission', 'rss', 'https://ec.europa.eu', 'en')`,
    ).run();
    await insertArticle({ id: testId(5), sourceId: "eu-commission-press-releases", originalLanguage: "en" });
    expect((await site(`/en/eu/${testId(5)}`)).body).toContain(
      'Source: European Commission · <span lang="en">© European Union, 1995-2026</span> · <a href="https://creativecommons.org/licenses/by/4.0/" rel="license">CC BY 4.0</a></p>',
    );
    // A seed source has no row: the generic line; the AI notice still marks the AI's text as ours, and names us.
    const { body: generic } = await site(`/en/de/${testId(1)}`);
    expect(generic).toContain("Source: Federal Government</p>");
    expect(generic).toContain("written by AI for Official News (RS Elite Pro s.r.o.)");
    expect(generic).not.toContain('rel="license"');
  });
});
