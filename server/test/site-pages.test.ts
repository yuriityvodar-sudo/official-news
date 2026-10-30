// Every page of the website in every language (#88): no placeholder left, and
// the publisher named as the app names it.
import { describe, expect, it } from "vitest";
import { SITE_LANGS } from "../src/site/texts";
import { INFO_PAGES } from "../src/site/urls";
import { site } from "./site-helpers";

describe("every page in every language", () => {
  it("renders with no placeholder, undefined or null left", async () => {
    const paths = [...SITE_LANGS.flatMap((l) => [`/${l}/nowhere`, ...INFO_PAGES.map((p) => `/${l}/${p}`)])];
    for (const path of paths) {
      const { status, body } = await site(path);
      expect([200, 404], path).toContain(status);
      // CSS has braces; the page's text has none left.
      const visible = body.replace(/<style>[\s\S]*<\/style>/, "");
      expect(visible, path).not.toMatch(/\{\w+\}|undefined|null|NaN|\[object/);
    }
  });

  it("names the publisher with its seat, company ID and register file on the privacy policy and the terms, as the app does", async () => {
    for (const lang of SITE_LANGS) {
      for (const page of ["privacy", "terms"]) {
        const { body } = await site(`/${lang}/${page}`);
        expect(body, `${lang} ${page}`).toContain("RS Elite Pro s.r.o., Na Okrouhlíku 2563/31, 182 00 Praha 8");
        expect(body, `${lang} ${page}`).toContain("29536316");
        expect(body, `${lang} ${page}`).toContain("C 448095");
      }
    }
  });

  it("gives the support e-mail on Contact & Support, as the app's info page does (#220)", async () => {
    for (const lang of SITE_LANGS) {
      const { body } = await site(`/${lang}/support`);
      expect(body, lang).toContain('<a href="mailto:support@outernews.app">support@outernews.app</a>');
    }
  });
});
