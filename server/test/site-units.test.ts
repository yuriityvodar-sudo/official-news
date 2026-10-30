// The website's building blocks (#88): escaping, links, dates and texts.
import { describe, expect, it } from "vitest";
import { APP_TEXTS } from "../src/site/app-texts.generated";
import { fullDate, publishedDate } from "../src/site/dates";
import { Html, esc, html, raw, safeHttps } from "../src/site/html";
import { SITE_LANGS, aiLabel, countryName, decisionLabel, languageName, t, text } from "../src/site/texts";
import { LANGS } from "../src/translator";

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
    expect(t("en", "publisher", { name: `<O'Brien>` }).value).toBe("&lt;O&#39;Brien&gt;, Czech Republic");
    expect(t("en", "lastUpdated", { date: raw("<b>today</b>") }).value).toBe("Last updated <b>today</b>");
    expect(t("en", "publisher")).toBeInstanceOf(Html);
    expect(text("en", "readOfficialDecisionOn", { site: "gov.pl" })).toBe("Read the official decision on gov.pl");
  });

  it("follow the app: the AI label by the source's language, unknown codes as the app shows them", () => {
    expect(aiLabel("uk", "uk")).toBe(APP_TEXTS.uk.summaryByAi);
    expect(aiLabel("uk", "de")).toBe("Стислий виклад від ШІ · переклад з німецької");
    expect(aiLabel("en", null)).toBe("Summary by AI");
    expect(aiLabel("en", "cs")).toBe("Summary by AI · translated from Czech");
    // A source language the app has no name for shows its code.
    expect(aiLabel("en", "fi")).toBe("Summary by AI · translated from FI");
    expect(countryName("es", "DE")).toBe("Alemania");
    expect(countryName("en", "XX")).toBe("XX");
    // The countries #72 added, named by the app's ARB files since (the API's names are the same: site-texts.check.mjs).
    expect(countryName("uk", "UA")).toBe("Україна");
    expect(countryName("de", "PL")).toBe("Polen");
    expect(languageName("de", "pt")).toBe("Portugiesischen");
    expect(decisionLabel("ru", "cabinet-decision")).toBe(APP_TEXTS.ru.decisionTypeCabinetDecision);
    expect(decisionLabel("en", "verdict")).toBeNull();
    expect(decisionLabel("en", null)).toBeNull();
  });
});
