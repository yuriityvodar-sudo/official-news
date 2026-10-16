// The site's addresses (#88). Every absolute URL starts with SITE_ORIGIN,
// never the request's host: Workers Cache keys a page by path and query only,
// so a page rendered for one host is served on every other.
import { EU, GROUPS, type GroupId, hasCountryName } from "../api/filters";
import { TOPICS, type Topic } from "../summarizer/schema";
import type { SiteLang } from "./texts";

/** The pages every language has. */
export const INFO_PAGES = ["about", "privacy", "terms", "support"] as const;
export type InfoPage = (typeof INFO_PAGES)[number];

/** An article id: a ULID (fetcher/text.ts), 26 characters of Crockford base 32. */
export const ARTICLE_ID = /^[0-9A-HJKMNP-TV-Z]{26}$/;

/** The longest slug, cut back to the last hyphen. */
export const SLUG_MAX = 60;

/** The site's origin without a trailing slash. */
export const originOf = (siteOrigin: string) => siteOrigin.replace(/\/+$/, "");

/** The country part of an article's address: "de", "eu". */
export const countryPath = (country: string) => (/^[A-Z]{2}$/.test(country) ? country.toLowerCase() : "xx");

/**
 * Where a list's articles come from, as the app's Where chip (#67, #68) and
 * the API's `country=` / `group=` (readWhere in api/filters.ts): one country
 * alone (`{ country: "DE" }`, that country's sources only), a group of
 * countries (`{ group: "g7" }`, one of GROUPS), or null for all countries.
 */
export type Place = { country: string } | { group: GroupId } | null;

/** A list's filters: Where, and one `topic` or null for All topics. */
export interface ListFilter {
  place: Place;
  topic: Topic | null;
}

export const ALL: ListFilter = { place: null, topic: null };

/**
 * Whether `/{lang}/{cc}` is a country's page: a code the API names in every
 * language (COUNTRIES in api/filters.ts: the source countries and the ones
 * planned next), so it needs no D1 read and the set of cached URLs is
 * bounded. A named country without sources is a page with the empty state.
 * Not the EU institutions (`EU`): they are in the European Union group, and
 * `/{lang}/eu` is that group's page.
 */
export const isCountryPage = (code: string) => /^[A-Z]{2}$/.test(code) && code !== EU && hasCountryName(code);

/** The group with this id (GROUPS: eu, g7, g20, nato), or null. */
export const groupOf = (id: string): GroupId | null => GROUPS.find((g) => g.id === id)?.id ?? null;

export const isTopic = (value: string): value is Topic => (TOPICS as readonly string[]).includes(value);

/**
 * The path segment of a place: a country's code in lower case (`de`) or a
 * group's id (`g7`, `eu`, `nato`). One segment after the language is a place
 * to read the decisions of, as in an article's `/{lang}/{cc}/…`. A group's id
 * is never a country's code (`eu` is ISO 3166's code reserved for the EU
 * itself) nor an information page's name (site-filters.test.ts checks both).
 */
export const placeSegment = (place: NonNullable<Place>) => ("country" in place ? place.country.toLowerCase() : place.group);

/**
 * The one URL of a list: `/en`, `/en/de`, `/en/g7?topic=economy`,
 * `/en/nato?topic=security-defence&before=120`. The place is the path, the
 * topic and the page parameters, always in this order; handler.ts sends every
 * other spelling here with a 301, so each view has one cache entry.
 */
export function listPath(lang: SiteLang, filter: ListFilter = ALL, before: number | null = null): string {
  const path = filter.place ? `/${lang}/${placeSegment(filter.place)}` : `/${lang}`;
  const query = [filter.topic && `topic=${filter.topic}`, before && `before=${before}`].filter(Boolean).join("&");
  return query ? `${path}?${query}` : path;
}

export const infoPath = (lang: SiteLang, page: InfoPage) => `/${lang}/${page}`;

/** `/uk/de/01JB…-uriad-nimechchyny-skhvalyv…`: only the id is looked up; the rest is for people. */
export function articlePath(lang: SiteLang, article: { id: string; country: string; headline: string | null; originalTitle: string }) {
  const slug = slugify(article.headline ?? article.originalTitle, lang);
  return `/${lang}/${countryPath(article.country)}/${article.id}${slug ? `-${slug}` : ""}`;
}

// Ukrainian: the national transliteration (Cabinet of Ministers resolution 55,
// 2010). Є, Ї, Й, Ю, Я start a word as ye, yi, y, yu, ya, otherwise ie, i, i,
// iu, ia; "зг" is "zgh"; the soft sign and the apostrophe are dropped.
const UK: Record<string, string> = {
  а: "a", б: "b", в: "v", г: "h", ґ: "g", д: "d", е: "e", є: "ie", ж: "zh", з: "z", и: "y", і: "i", ї: "i", й: "i",
  к: "k", л: "l", м: "m", н: "n", о: "o", п: "p", р: "r", с: "s", т: "t", у: "u", ф: "f", х: "kh", ц: "ts", ч: "ch",
  ш: "sh", щ: "shch", ь: "", ю: "iu", я: "ia",
};
const UK_INITIAL: Record<string, string> = { є: "ye", ї: "yi", й: "y", ю: "yu", я: "ya" };

// Russian, and Cyrillic on pages in other languages: a plain table.
const RU: Record<string, string> = {
  а: "a", б: "b", в: "v", г: "g", д: "d", е: "e", ё: "e", ж: "zh", з: "z", и: "i", й: "y", к: "k", л: "l", м: "m",
  н: "n", о: "o", п: "p", р: "r", с: "s", т: "t", у: "u", ф: "f", х: "kh", ц: "ts", ч: "ch", ш: "sh", щ: "shch",
  ъ: "", ы: "y", ь: "", э: "e", ю: "yu", я: "ya", і: "i", ї: "yi", є: "ye", ґ: "g",
};

// Latin letters with marks, folded by hand (no String.normalize: it loads ICU data).
const LATIN: Record<string, string> = {
  à: "a", á: "a", â: "a", ã: "a", ä: "a", å: "a", ā: "a", ą: "a", ă: "a", æ: "ae",
  ç: "c", ć: "c", č: "c", ď: "d", đ: "d", è: "e", é: "e", ê: "e", ë: "e", ē: "e", ę: "e", ě: "e",
  ğ: "g", ì: "i", í: "i", î: "i", ï: "i", ī: "i", ı: "i", ł: "l", ľ: "l", ĺ: "l", ñ: "n", ń: "n", ň: "n",
  ò: "o", ó: "o", ô: "o", õ: "o", ö: "o", ø: "o", ō: "o", ő: "o", œ: "oe", ŕ: "r", ř: "r", ś: "s", š: "s", ş: "s", ș: "s",
  ß: "ss", ť: "t", ţ: "t", ț: "t", ù: "u", ú: "u", û: "u", ü: "u", ū: "u", ů: "u", ű: "u", ý: "y", ÿ: "y",
  ź: "z", ż: "z", ž: "z", þ: "th", ð: "d",
};
const GERMAN: Record<string, string> = { ä: "ae", ö: "oe", ü: "ue", ß: "ss" };

const APOSTROPHES = /['’ʼ`´]/g;
const COMBINING = /[̀-ͯ]/g;
const LETTER = /\p{L}/u;

/**
 * A slug from a headline in the page's language: lower case `[a-z0-9-]`,
 * Cyrillic transliterated (Ukrainian or Russian rules by the page), marks on
 * Latin letters folded (ä → ae on German pages), cut at the last hyphen before
 * 60 characters. Empty when nothing is left (a Japanese title), and the
 * address is then the id alone.
 */
export function slugify(headline: string, lang: SiteLang): string {
  // Combining marks (a decomposed "é") and apostrophes go; they are not word breaks.
  const input = headline.replace(/İ/g, "i").toLowerCase().replace(COMBINING, "").replace(APOSTROPHES, "");
  let out = "";
  for (let i = 0; i < input.length; i++) {
    const c = input[i];
    if (lang === "uk" && c in UK) {
      const initial = i === 0 || !LETTER.test(input[i - 1]);
      if (c === "г" && input[i - 1] === "з") out += "gh";
      else out += initial && c in UK_INITIAL ? UK_INITIAL[c] : UK[c];
    } else if (c in RU) out += RU[c];
    else if (lang === "de" && c in GERMAN) out += GERMAN[c];
    else if (c in LATIN) out += LATIN[c];
    else out += /[a-z0-9]/.test(c) ? c : "-";
  }
  let slug = out.replace(/-+/g, "-").replace(/^-|-$/g, "");
  if (slug.length > SLUG_MAX) {
    const cut = slug.slice(0, SLUG_MAX + 1);
    const hyphen = cut.lastIndexOf("-");
    slug = (hyphen > 0 ? cut.slice(0, hyphen) : slug.slice(0, SLUG_MAX)).replace(/-$/, "");
  }
  return slug;
}
