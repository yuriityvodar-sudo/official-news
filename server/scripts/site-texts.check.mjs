// Tests for scripts/site-texts.mjs (`node --test`, part of `npm test`): the
// website's generated texts and credits match the app and the docs they come
// from, and every source, country, language and decision type has its words.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";

import { parseCsv } from "./sources.mjs";
import {
  CREDIT_COLUMNS,
  SITE_LANGS,
  build,
  credits,
  decisionTypeKey,
  fromDart,
  languageKey,
  paths,
  readArb,
  siteTexts,
} from "./site-texts.mjs";

const read = (path) => readFileSync(path, "utf8");
const english = () => readArb(read(paths.arb("en")));
const arbs = () => Object.fromEntries(SITE_LANGS.map((lang) => [lang, readArb(read(paths.arb(lang)))]));
const sources = () => {
  const [header, ...rows] = parseCsv(read(paths.sources));
  return rows.map((cells) => Object.fromEntries(header.map((name, i) => [name, cells[i]])));
};

describe("the generated files", () => {
  test("are what the app's texts and docs/source-credits.csv give today (else run `npm run site:texts` in server/)", () => {
    for (const [path, content] of Object.entries(build())) {
      assert.equal(read(path), content, `${path} is out of date: run \`npm run site:texts\` in server/ and commit it`);
    }
  });
});

describe("the app's texts", () => {
  test("every key the site uses is in every language, with the English placeholders", () => {
    const texts = siteTexts(arbs());
    for (const lang of SITE_LANGS) assert.deepEqual(Object.keys(texts[lang]), Object.keys(texts.en));
  });

  test("a missing key, other placeholders or ICU plural syntax are refused, all at once", () => {
    const all = arbs();
    delete all.uk.aboutIntro;
    all.ru.lastUpdated = "Обновлено {when}";
    all.de.topStoriesTitle = "{count, plural, one{Wichtig} other{Wichtig}}";
    assert.throws(
      () => siteTexts(all),
      (error) =>
        /app_uk.arb has no "aboutIntro"/.test(error.message) &&
        /app_ru.arb "lastUpdated" has placeholders \{when\}/.test(error.message) &&
        /app_de.arb "topStoriesTitle" uses plural or select/.test(error.message),
    );
  });

  test("every country in docs/sources.csv has a name (country<CC>)", () => {
    const en = english();
    // A hidden source's articles never reach the site (#230): its country gets a name when it is shown.
    const shown = sources().filter((s) => !(s.config && JSON.parse(s.config).hidden));
    const missing = [...new Set(shown.map((s) => s.country))].filter((cc) => !(`country${cc}` in en));
    assert.deepEqual(missing, [], `add country names to app/lib/l10n/app_*.arb: ${missing.join(", ")}`);
  });

  test("the API's country names (COUNTRIES in src/api/filters.ts) are the app's wherever the app has one, so the site's chips and the app's never differ", () => {
    const source = read(fileURLToPath(new URL("../src/api/filters.ts", import.meta.url)));
    const block = source.slice(source.indexOf("const COUNTRIES"), source.indexOf("\n};", source.indexOf("const COUNTRIES")));
    const api = Object.fromEntries([...block.matchAll(/^ {2}([A-Z]{2}): (\[.+\]),$/gm)].map((m) => [m[1], JSON.parse(m[2])]));
    assert.ok(Object.keys(api).length >= 20, "COUNTRIES not found in src/api/filters.ts");
    const all = arbs();
    for (const [code, names] of Object.entries(api)) {
      SITE_LANGS.forEach((lang, i) => {
        const key = `country${code}`;
        if (key in all[lang]) assert.equal(names[i], all[lang][key], `COUNTRIES.${code} in ${lang} differs from app_${lang}.arb`);
      });
    }
  });

  test("every source language in docs/sources.csv has a name (language<Xx>), or the AI label would show its code", () => {
    const en = english();
    const missing = [...new Set(sources().map((s) => s.language))].filter((code) => !(languageKey(code) in en));
    assert.deepEqual(missing, [], `add language names to app/lib/l10n/app_*.arb: ${missing.join(", ")}`);
  });

  test("every decision type in docs/contract.md has a label", () => {
    const contract = read(paths.contract);
    const section = contract.split("## Decision types")[1].split("\n## ")[0];
    const types = [...section.matchAll(/`([a-z-]+)` \(/g)].map((m) => m[1]);
    assert.ok(types.length >= 8, "decision types not found in docs/contract.md");
    const en = english();
    assert.deepEqual(
      types.filter((id) => !(decisionTypeKey(id) in en)),
      [],
    );
  });
});

describe("the site's own texts (src/site/texts.ts)", () => {
  /** Each language's texts in SITE_TEXTS, read from the source: { en: { key: text } }. */
  const siteOwn = () => {
    const source = read(fileURLToPath(new URL("../src/site/texts.ts", import.meta.url)));
    const out = {};
    for (const lang of SITE_LANGS) {
      const start = source.indexOf(`\n  ${lang}: {\n`);
      assert.ok(start > 0, `SITE_TEXTS.${lang} not found`);
      const block = source.slice(start, source.indexOf("\n  },", start));
      out[lang] = Object.fromEntries([...block.matchAll(/^ {4}(\w+):\s*("(?:[^"\\]|\\.)*")/gm)].map((m) => [m[1], JSON.parse(m[2])]));
    }
    return out;
  };

  test("say what the app's ARB files say for a key they share: a copy waiting for the app's PR (#87's filter words, the chips' prototype) is moved, never forked", () => {
    const own = siteOwn();
    const all = arbs();
    for (const lang of SITE_LANGS) {
      for (const [key, value] of Object.entries(own[lang])) {
        if (key in all[lang]) assert.equal(value, all[lang][key], `texts.ts ${lang}.${key} differs from app_${lang}.arb: use the app's text (move the key to KEYS in site-texts.mjs)`);
      }
    }
  });
});

describe("the app's code", () => {
  test("gives the publisher, the support e-mail, the policies' date and the five languages", () => {
    const dart = fromDart(read(paths.infoPages), read(paths.feedLanguage));
    assert.equal(dart.publisherName, "RS Elite Pro s.r.o.");
    assert.equal(dart.supportEmail, "support@outernews.app");
    assert.match(dart.policyUpdated, /^\d{4}-\d{2}-\d{2}$/);
    assert.deepEqual(Object.keys(dart.languages), SITE_LANGS);
    assert.equal(dart.languages.uk.nativeName, "Українська");
  });

  test("fails loudly when the Dart it reads has changed shape", () => {
    assert.throws(() => fromDart("const name = 'x';", "enum FeedLanguage {}"), /publisherName[\s\S]*supportEmail[\s\S]*policyUpdated[\s\S]*languages are \[\]/);
  });
});

describe("docs/source-credits.csv", () => {
  const header = CREDIT_COLUMNS.join(",");
  const sourcesCsv = "id,country\nde-cabinet,DE\n";

  test("has a row for every source in docs/sources.csv", () => {
    const rows = credits(read(paths.credits), read(paths.sources));
    for (const s of sources()) assert.ok(s.id in rows, s.id);
  });

  test("refuses a source without a row, a plain-http licence link and wording without its language", () => {
    assert.throws(() => credits(`${header}\n`, sourcesCsv), /no row for source "de-cabinet"/);
    assert.throws(() => credits(`${header}\nde-cabinet,CC BY 4.0,http://x.org,,,\n`, sourcesCsv), /licence_url must start with https/);
    assert.throws(() => credits(`${header}\nde-cabinet,,,Quelle: Bund,,\n`, sourcesCsv), /wording needs wording_lang/);
  });

  test("keeps a row for a source no longer listed: its articles stay on the site", () => {
    const rows = credits(`${header}\nde-cabinet,,,,,\nru-kremlin-acts,CC BY 4.0,https://creativecommons.org/licenses/by/4.0/,,,removed\n`, sourcesCsv);
    assert.equal(rows["ru-kremlin-acts"].licence, "CC BY 4.0");
  });
});

// Roman's review of #234: the website's About, Privacy, Terms and Support say
// everything the app's own pages say, since they cover both and are the URLs
// App Store Connect links.
describe("the website's information pages", () => {
  /** Keys the app's pages show that the website says its own way. */
  const APP_ONLY = {
    supportWrite: "the app's button to its message screen (#220); the website gives the e-mail (emailUs)",
    supportOrEmail: "the line under that button; the website gives the e-mail (emailUs)",
  };

  test("show every text the app's info pages show", () => {
    const dart = read(paths.infoPages);
    const site = read(fileURLToPath(new URL("../src/site/pages/info.ts", import.meta.url)));
    const shown = [...new Set([...dart.matchAll(/l10n\.((?:about|privacy|terms|support)[A-Za-z0-9]*)/g)].map((m) => m[1]))];
    assert.ok(shown.length > 20, `found only ${shown.length} keys in info_pages.dart`);
    const missing = shown.filter((key) => !(key in APP_ONLY) && !site.includes(`"${key}"`));
    assert.deepEqual(missing, [], `pages/info.ts misses texts the app's pages show: ${missing.join(", ")}`);
  });
});

