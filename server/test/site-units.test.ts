// The website's building blocks (#88): escaping, links, slugs, dates and texts.
import { describe, expect, it } from "vitest";
import { APP_TEXTS } from "../src/site/app-texts.generated";
import { fullDate, publishedDate } from "../src/site/dates";
import { Html, esc, html, raw, safeHttps } from "../src/site/html";
import { SITE_LANGS, aiLabel, countryName, decisionLabel, languageName, t, text } from "../src/site/texts";
import { SLUG_MAX, articlePath, slugify } from "../src/site/urls";
import { LANGS } from "../src/translator";

const ID = "01JTEST0000000000000000001";

describe("html", () => {
  it("escapes every value unless it is Html, joins arrays and leaves out null and false", () => {
    const value = `<a href="x">'&'</a>`;
    expect(html`<p title="${value}">${value}</p>`.value).toBe(
      "<p title=\"&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;&lt;/a&gt;\">&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;&lt;/a&gt;</p>",
    );
    expect(html`${raw("<b>")}${["a", raw("<i>")]}${null}${false}${undefined}${0}`.value).toBe("<b>a<i>0");
    expect(esc("&amp;")).toBe("&amp;amp;");
  });

  it("lets only https links through, without their #fragment", () => {
    expect(safeHttps("https://www.gov.pl/web/a#2026-10-15")).toBe("https://www.gov.pl/web/a");
    for (const url of ["javascript:alert(1)", "JAVASCRIPT:alert(1)", "http://kremlin.ru/acts", "data:text/html,x", "//evil.test", "", null, "https://"]) {
      expect(safeHttps(url), String(url)).toBeNull();
    }
  });
});

describe("slugs", () => {
  it("transliterate Ukrainian by the national table, Russian by its own", () => {
    expect(slugify("Уряд Німеччини схвалив бюджет", "uk")).toBe("uriad-nimechchyny-skhvalyv-biudzhet");
    expect(slugify("Євросоюз і Їжакевич: юрист Яна, Згурський, м’ясо", "uk")).toBe("yevrosoiuz-i-yizhakevych-yuryst-yana-zghurskyi-miaso");
    expect(slugify("Правительство Германии одобрило объём щедрых выплат", "ru")).toBe("pravitelstvo-germanii-odobrilo-obem-shchedrykh-vyplat");
  });

  it("fold Latin marks, German umlauts as ae, oe, ue", () => {
    expect(slugify("El Gobierno aprueba la reforma de pensiones del año", "es")).toBe("el-gobierno-aprueba-la-reforma-de-pensiones-del-ano");
    expect(slugify("Kabinett beschließt Gesetz für Bürger und Ölheizungen", "de")).toBe("kabinett-beschliesst-gesetz-fuer-buerger-und-oelheizungen");
    expect(slugify("Ação do Governo: São Paulo", "en")).toBe("acao-do-governo-sao-paulo");
    expect(slugify("Café Türkiye’s İstanbul", "en")).toBe("cafe-turkiyes-istanbul");
  });

  it("are cut at the last hyphen before 60 characters, and empty when nothing is left", () => {
    const long = slugify("The European Commission proposes new rules for the single market in digital services and data", "en");
    expect(long.length).toBeLessThanOrEqual(SLUG_MAX);
    expect(long).toBe("the-european-commission-proposes-new-rules-for-the-single");
    expect(slugify("閣議決定 🇯🇵 —", "en")).toBe("");
    expect(articlePath("en", { id: ID, country: "JP", headline: null, originalTitle: "閣議" })).toBe(`/en/jp/${ID}`);
    expect(slugify("x".repeat(80), "en")).toBe("x".repeat(60));
  });
});

describe("dates", () => {
  const date = new Date("2026-10-15T23:05:00Z");
  it("are written in each language, in UTC, with the time when the source gave one", () => {
    expect(SITE_LANGS.map((lang) => fullDate(lang, date))).toEqual([
      "15 October 2026",
      "15 жовтня 2026 р.",
      "15 октября 2026 г.",
      "15 de octubre de 2026",
      "15. Oktober 2026",
    ]);
    expect(publishedDate("en", date, false)).toBe("15 October 2026, 23:05 UTC");
    expect(publishedDate("uk", date, false)).toBe("15 жовтня 2026 р. о 23:05 UTC");
    expect(publishedDate("de", date, true)).toBe("15. Oktober 2026");
  });
});

describe("languages", () => {
  it("are English and the API's LANGS, in the app's order: a language the API refuses would turn every article page into a 500", () => {
    expect(SITE_LANGS).toEqual(["en", ...LANGS]);
  });
});

describe("texts", () => {
  it("fill placeholders, escaping the text and each value but keeping Html", () => {
    expect(t("en", "contactSupport").value).toBe("Contact &amp; Support");
    expect(t("en", "creditSource", { source: `<O'Brien>` }).value).toBe("Source: &lt;O&#39;Brien&gt;");
    expect(t("en", "prevails", { link: raw('<a href="/en/terms">English</a>') }).value).toContain('<a href="/en/terms">English</a>');
    expect(t("en", "creditSource")).toBeInstanceOf(Html);
    expect(text("en", "readOfficialDecisionOn", { site: "gov.pl" })).toBe("Read the official decision on gov.pl");
  });

  it("follow the app: the AI label by the source's language, unknown codes as the app shows them", () => {
    expect(aiLabel("uk", "uk")).toBe(APP_TEXTS.uk.summaryByAi);
    expect(aiLabel("uk", "de")).toBe("Стислий виклад від ШІ · переклад з німецької");
    expect(aiLabel("en", null)).toBe("Summary by AI");
    expect(aiLabel("en", "cs")).toBe("Summary by AI · translated from CS");
    expect(countryName("es", "DE")).toBe("Alemania");
    expect(countryName("en", "XX")).toBe("XX");
    expect(languageName("de", "pt")).toBe("Portugiesischen");
    expect(decisionLabel("ru", "cabinet-decision")).toBe(APP_TEXTS.ru.decisionTypeCabinetDecision);
    expect(decisionLabel("en", "verdict")).toBeNull();
    expect(decisionLabel("en", null)).toBeNull();
  });
});
