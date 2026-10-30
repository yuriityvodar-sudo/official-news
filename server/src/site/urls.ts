// The site's addresses (#88). Every absolute URL starts with SITE_ORIGIN,
// never the request's host: Workers Cache keys a page by path and query only,
// so a page rendered for one host is served on every other.
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

/** The latest list in a language: `/en`. */
export const listPath = (lang: SiteLang) => `/${lang}`;

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
