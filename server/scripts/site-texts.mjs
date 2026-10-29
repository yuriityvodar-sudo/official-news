// The website (#88) shows the app's own words, so they are never copied by
// hand: this script reads them from the app and writes two committed files,
// checked by scripts/site-texts.check.mjs (`npm test`) so they never go stale.
//   src/site/app-texts.generated.ts: the ARB texts the site uses
//     (app/lib/l10n/app_*.arb), the publisher's name and the policies' date
//     (app/lib/features/settings/info_pages.dart), and the languages' names
//     (app/lib/core/feed_language.dart).
//   src/site/credits.generated.ts: the credit line per source
//     (docs/source-credits.csv).
// Run it with `npm run site:texts` after changing any of those.
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { parseCsv } from "./sources.mjs";

const root = new URL("../../", import.meta.url);
const at = (path) => fileURLToPath(new URL(path, root));

export const paths = {
  arb: (lang) => at(`app/lib/l10n/app_${lang}.arb`),
  infoPages: at("app/lib/features/settings/info_pages.dart"),
  feedLanguage: at("app/lib/core/feed_language.dart"),
  credits: at("docs/source-credits.csv"),
  sources: at("docs/sources.csv"),
  contract: at("docs/contract.md"),
  appTexts: at("server/src/site/app-texts.generated.ts"),
  creditsOut: at("server/src/site/credits.generated.ts"),
};

/** The site's languages: English, then LANGS (server/src/translator/languages.ts), in the app's order. */
export const SITE_LANGS = ["en", "uk", "ru", "es", "de"];

/** The ARB keys the site shows: these, plus every key matching KEY_PATTERNS. */
export const KEYS = [
  "topStoriesTitle",
  "feedEmpty",
  "feedNoTranslations",
  "feedTranslationsComing",
  "language",
  "summaryByAi",
  "summaryByAiTranslated",
  "summaryComing",
  "officialSource",
  "readOfficialDecision",
  "readOfficialDecisionOn",
  "dateAndTime",
  "aboutTitle",
  "contactSupport",
  "publisher",
  "publisherDetails",
  "lastUpdated",
  "aboutIntro",
  "aboutSourcesHeading",
  "aboutSources1",
  "aboutSources2",
  "aboutIndependentHeading",
  "aboutIndependent",
  "aboutPublishedBy",
  "supportMessages",
  "supportMistakes",
  "supportAppStore",
];

/** Countries, decision types, source languages, and the privacy policy's and terms' texts. */
export const KEY_PATTERNS = [/^country[A-Z]{2}$/, /^decisionType[A-Z]\w+$/, /^language[A-Z][a-z]$/, /^privacy[A-Z]\w*$/, /^terms[A-Z]\w*$/];

/** `{name}` placeholders of an ARB text, in order. */
export const placeholders = (text) => [...text.matchAll(/\{(\w+)\}/g)].map((m) => m[1]);

/** ICU plural or select: the site fills only plain `{name}` placeholders. */
const ICU = /\{\s*\w+\s*,\s*(plural|select|selectordinal)\s*,/;

/** "cabinet-decision" → "decisionTypeCabinetDecision", as the app names its keys. */
export const decisionTypeKey = (id) => `decisionType${id.split("-").map((w) => w[0].toUpperCase() + w.slice(1)).join("")}`;

/** "de" → "languageDe". */
export const languageKey = (code) => `language${code[0].toUpperCase()}${code.slice(1)}`;

/** The texts of one ARB file, without its `@` metadata. */
export function readArb(text) {
  const arb = JSON.parse(text);
  return Object.fromEntries(Object.entries(arb).filter(([key]) => !key.startsWith("@")));
}

/** The keys the site uses, in the template's (English) order. */
export const pickKeys = (english) => Object.keys(english).filter((key) => KEYS.includes(key) || KEY_PATTERNS.some((p) => p.test(key)));

/**
 * The site's texts per language: every key in every language, with the same
 * placeholders as the English template and no ICU syntax. Throws one error
 * listing every problem.
 */
export function siteTexts(arbs) {
  const problems = [];
  const keys = pickKeys(arbs.en);
  for (const key of KEYS) if (!(key in arbs.en)) problems.push(`app_en.arb has no "${key}"`);
  const texts = {};
  for (const lang of SITE_LANGS) {
    texts[lang] = {};
    for (const key of keys) {
      const value = arbs[lang]?.[key];
      if (typeof value !== "string" || !value) {
        problems.push(`app_${lang}.arb has no "${key}"`);
        continue;
      }
      if (ICU.test(value)) problems.push(`app_${lang}.arb "${key}" uses plural or select, which the site does not fill`);
      const want = placeholders(arbs.en[key]).sort().join(",");
      const got = placeholders(value).sort().join(",");
      if (want !== got) problems.push(`app_${lang}.arb "${key}" has placeholders {${got}}, the English has {${want}}`);
      texts[lang][key] = value;
    }
  }
  if (problems.length) throw new Error(`App texts for the website:\n${problems.join("\n")}`);
  return texts;
}

/**
 * What the site needs from the app's Dart code: the publisher's name, seat,
 * company ID and register file, and the policies' date (info_pages.dart), and each language's own name and short
 * label (feed_language.dart). Throws if any of it is not found.
 */
export function fromDart(infoPages, feedLanguage) {
  const problems = [];
  const name = /const publisherName = '([^']+)';/.exec(infoPages)?.[1];
  if (!name) problems.push("info_pages.dart: no `const publisherName = '…';`");
  const details = Object.fromEntries(
    ["Address", "Id", "File"].map((part) => {
      const value = new RegExp(`const publisher${part} = '([^']+)';`).exec(infoPages)?.[1];
      if (!value) problems.push(`info_pages.dart: no \`const publisher${part} = '…';\``);
      return [part.toLowerCase(), value];
    }),
  );
  const date = /final policyUpdated = DateTime\((\d{4}), (\d{1,2}), (\d{1,2})\);/.exec(infoPages);
  if (!date) problems.push("info_pages.dart: no `final policyUpdated = DateTime(y, m, d);`");
  const languages = [...feedLanguage.matchAll(/^\s+(\w+)\('(\w+)', '([^']+)', '([^']+)'\)[,;]/gm)].map((m) => ({
    code: m[2],
    nativeName: m[3],
    shortLabel: m[4],
  }));
  const codes = languages.map((l) => l.code).join(",");
  if (codes !== SITE_LANGS.join(",")) problems.push(`feed_language.dart: languages are [${codes}], the site has [${SITE_LANGS.join(",")}]`);
  if (problems.length) throw new Error(`App code for the website:\n${problems.join("\n")}`);
  const pad = (n) => String(n).padStart(2, "0");
  return {
    publisherName: name,
    publisherDetails: details,
    policyUpdated: `${date[1]}-${pad(date[2])}-${pad(date[3])}`,
    languages: Object.fromEntries(languages.map((l) => [l.code, { nativeName: l.nativeName, shortLabel: l.shortLabel }])),
  };
}

const HEADER = (from) => `// Generated by scripts/site-texts.mjs from ${from}.
// Do not edit: change the source, then run \`npm run site:texts\` in server/.
`;

const literal = (value) => JSON.stringify(value, null, 2);

export function appTextsModule(texts, dart) {
  const keys = Object.keys(texts.en);
  return `${HEADER("app/lib/l10n/app_*.arb, app/lib/features/settings/info_pages.dart and app/lib/core/feed_language.dart")}
/** The app's texts the website shows, by key. */
export type AppKey =
${keys.map((k) => `  | ${JSON.stringify(k)}`).join("\n")};

export type SiteLang = ${SITE_LANGS.map((l) => JSON.stringify(l)).join(" | ")};

export const SITE_LANGS: readonly SiteLang[] = ${JSON.stringify(SITE_LANGS)};

/** The app's texts, from app/lib/l10n/app_<lang>.arb. */
export const APP_TEXTS: Record<SiteLang, Record<AppKey, string>> = ${literal(texts)};

/** Who publishes the app (\`publisherName\` in info_pages.dart): never translated. */
export const PUBLISHER_NAME = ${JSON.stringify(dart.publisherName)};

/** The publisher's seat, company ID and commercial register file (info_pages.dart): never translated. */
export const PUBLISHER_DETAILS = ${literal(dart.publisherDetails)};

/** When the privacy policy and the terms last changed (\`policyUpdated\` in info_pages.dart). */
export const POLICY_UPDATED = ${JSON.stringify(dart.policyUpdated)};

/** Each language's own name and short label (FeedLanguage in feed_language.dart). */
export const LANGUAGE_NAMES: Record<SiteLang, { nativeName: string; shortLabel: string }> = ${literal(dart.languages)};
`;
}

/** Columns of docs/source-credits.csv, in order. `note` is for people only. */
export const CREDIT_COLUMNS = ["id", "licence", "licence_url", "wording", "wording_lang", "note"];

/**
 * The credit line per source: every source in docs/sources.csv needs a row
 * (an empty licence gives the generic line). A row for a source no longer in
 * sources.csv is allowed: its articles stay on the site and still need their
 * credit (removing a source keeps it, as `blocked`).
 */
export function credits(creditsCsv, sourcesCsv) {
  const [header, ...rows] = parseCsv(creditsCsv);
  if (header?.join(",") !== CREDIT_COLUMNS.join(",")) throw new Error(`source-credits.csv header must be: ${CREDIT_COLUMNS.join(",")}`);
  const problems = [];
  const out = {};
  rows.forEach((cells, index) => {
    const line = index + 2;
    const c = Object.fromEntries(CREDIT_COLUMNS.map((name, i) => [name, (cells[i] ?? "").trim()]));
    const fail = (message) => problems.push(`source-credits.csv line ${line} (${c.id || "no id"}): ${message}`);
    if (cells.length !== CREDIT_COLUMNS.length) fail(`has ${cells.length} fields, expected ${CREDIT_COLUMNS.length}`);
    if (!/^[a-z]{2}-[a-z0-9-]+$/.test(c.id)) fail("id must be a source id from sources.csv");
    if (c.id in out) fail("id is used twice");
    if (c.licence_url && !c.licence) fail("licence_url without a licence");
    if (c.licence_url && !/^https:\/\/[^\s"'<>]+$/.test(c.licence_url)) fail("licence_url must start with https://");
    if (c.wording && !/^[a-z]{2,3}$/.test(c.wording_lang)) fail("wording needs wording_lang, a language code such as en or ja");
    if (!c.wording && c.wording_lang) fail("wording_lang without wording");
    out[c.id] = {
      ...(c.licence ? { licence: c.licence } : {}),
      ...(c.licence_url ? { licenceUrl: c.licence_url } : {}),
      ...(c.wording ? { wording: c.wording, wordingLang: c.wording_lang } : {}),
    };
  });
  const [, ...sources] = parseCsv(sourcesCsv);
  for (const [id] of sources) if (!(id in out)) problems.push(`source-credits.csv has no row for source "${id}" (docs/sources.csv)`);
  if (problems.length) throw new Error(problems.join("\n"));
  return out;
}

export function creditsModule(rows) {
  return `${HEADER("docs/source-credits.csv")}
/** How the site credits a source (#88). Temporary home: once #84 merges, credits move into the sources' config and the API, so the app shows them too. */
export interface Credit {
  /** The licence's name, shown as a link when there is a URL. */
  licence?: string;
  licenceUrl?: string;
  /** Exact credit wording the source asks for, in \`wordingLang\`. */
  wording?: string;
  wordingLang?: string;
}

/** By source id; a source without a licence here gets the generic line. */
export const CREDITS: Record<string, Credit> = ${literal(rows)};
`;
}

/** Both generated files' contents from the files in the repo. */
export function build(read = (path) => readFileSync(path, "utf8")) {
  const arbs = Object.fromEntries(SITE_LANGS.map((lang) => [lang, readArb(read(paths.arb(lang)))]));
  const texts = siteTexts(arbs);
  const dart = fromDart(read(paths.infoPages), read(paths.feedLanguage));
  return {
    [paths.appTexts]: appTextsModule(texts, dart),
    [paths.creditsOut]: creditsModule(credits(read(paths.credits), read(paths.sources))),
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  for (const [path, content] of Object.entries(build())) writeFileSync(path, content);
  console.log("Wrote src/site/app-texts.generated.ts and src/site/credits.generated.ts");
}
