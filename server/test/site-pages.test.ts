// Every page of the website in every language (#88): no placeholder left, the
// AI label and notice where AI text is shown, the app's behaviour for an
// article without a summary, and the credit line per source.
import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { SITE_LANGS, text } from "../src/site/texts";
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
    expect(article).toContain(text("uk", "aiNotice"));
    expect(article).toMatch(/<meta name="description" content="Стислий виклад від ШІ: /);
    expect(article).toMatch(/<meta property="og:description" content="Стислий виклад від ШІ: /);
    expect((await site("/es")).body).toContain(text("es", "aiNotice"));
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
    expect(ogl).toContain(
      'Source: UK Government (GOV.UK) · <a href="https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/" rel="license">Open Government Licence v3.0</a> · <span lang="en">Contains public sector information licensed under the Open Government Licence v3.0.</span>',
    );
    // A seed source has no row: the generic line, which still marks the AI's text as ours.
    const { body: generic } = await site(`/en/de/${testId(1)}`);
    expect(generic).toContain("Source: Federal Government</p>");
    expect(generic).toContain(text("en", "creditNote"));
    expect(generic).not.toContain('rel="license"');
  });
});
