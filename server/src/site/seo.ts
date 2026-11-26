// What search engines read besides the page (#88, SEO, Yurii 28 Oct): an
// article's structured data (schema.org NewsArticle, in a JSON-LD block that
// browsers never run, so the CSP's no-scripts rule still holds) and the
// sitemap. Nothing is indexed until robots.txt and robotsFor() allow it.
import { mayIndex } from "../api/indexing";
import type { ApiArticle, ListArticle } from "./data";
import { isoTime, parseTime } from "./dates";
import { type Html, raw, safeHttps } from "./html";
import { SITE_NAME } from "./layout";
import { SITE_LANGS, type SiteLang, text } from "./texts";
import { articlePath, isCountryPage, listPath } from "./urls";

/** JSON for inside a <script> block: no `<`, so nothing in it can end the block or open a tag. */
const blockJson = (value: unknown) => JSON.stringify(value).replace(/</g, "\\u003c");

/**
 * NewsArticle for an article page: our AI headline and summary, written for
 * Outer News (the author and publisher are us, never the government), based
 * on the official page (isBasedOn).
 */
export function articleJsonLd(lang: SiteLang, origin: string, article: ApiArticle): Html {
  const published = parseTime(article.publishedAt);
  const added = parseTime(article.addedAt);
  const official = safeHttps(article.originalUrl);
  const us = { "@type": "Organization", name: SITE_NAME, url: `${origin}/`, logo: { "@type": "ImageObject", url: `${origin}/icon-512.png` } };
  const data = {
    "@context": "https://schema.org",
    "@type": "NewsArticle",
    headline: article.headline ?? article.originalTitle,
    description: article.shortSummary?.trim() || undefined,
    inLanguage: lang,
    url: origin + articlePath(lang, article),
    mainEntityOfPage: origin + articlePath(lang, article),
    datePublished: published ? isoTime(published) : undefined,
    dateModified: added ? isoTime(added) : undefined,
    image: `${origin}/icon-512.png`,
    author: us,
    publisher: us,
    isBasedOn: official ?? undefined,
    isAccessibleForFree: true,
    // Says what the text is, as every page does (AI Act Art. 50).
    creditText: article.headline !== null ? text(lang, "summaryByAi") : undefined,
  };
  return raw(`<script type="application/ld+json">${blockJson(data)}</script>`);
}

const xml = (value: string) => value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

/** What a sitemap entry needs of an article: its address (articlePath) and when it came. */
type SitemapEntry = Pick<ListArticle, "id" | "country" | "headline" | "originalTitle" | "addedAt" | "publishedAt">;

/** When the newest of `articles` came: a list's own last change. */
const newest = (articles: { addedAt: string | null; publishedAt: string }[]): Date | null =>
  articles.reduce<Date | null>((latest, a) => {
    const at = parseTime(a.addedAt) ?? parseTime(a.publishedAt);
    return at && (!latest || at > latest) ? at : latest;
  }, null);

const lastmod = (at: Date | null) => (at ? `<lastmod>${isoTime(at)}</lastmod>` : "");

const URLSET = '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">';

/** Each article in each language it is shown in, with its other languages as hreflang alternates, as the pages' own <link rel="alternate">. */
function articleUrls(origin: string, shown: Partial<Record<SiteLang, SitemapEntry[]>>): string[] {
  const byId = new Map<string, Partial<Record<SiteLang, SitemapEntry>>>();
  for (const lang of SITE_LANGS) {
    for (const article of shown[lang] ?? []) {
      const entry = byId.get(article.id) ?? {};
      entry[lang] = article;
      byId.set(article.id, entry);
    }
  }
  const urls: string[] = [];
  for (const entry of byId.values()) {
    const langs = SITE_LANGS.filter((l) => entry[l]);
    const links = langs.map((l) => `<xhtml:link rel="alternate" hreflang="${l}" href="${xml(origin + articlePath(l, entry[l]!))}"/>`).join("");
    for (const lang of langs) {
      const article = entry[lang]!;
      const added = parseTime(article.addedAt) ?? parseTime(article.publishedAt);
      urls.push(`<url><loc>${xml(origin + articlePath(lang, article))}</loc>${added ? `<lastmod>${isoTime(added)}</lastmod>` : ""}${links}</url>`);
    }
  }
  return urls;
}

/**
 * The latest sitemap (/sitemap-latest.xml): each language's latest list while
 * it has articles (an empty one is noindex), and every indexable article
 * (api/indexing.ts) of the API's 7 days, in each language its page may be indexed in.
 */
export function sitemapXml(origin: string, shown: Partial<Record<SiteLang, ListArticle[]>>): string {
  const withLists = SITE_LANGS.filter((lang) => (shown[lang] ?? []).length > 0);
  const urls: string[] = withLists.map((lang) => {
    const links = withLists.map((l) => `<xhtml:link rel="alternate" hreflang="${l}" href="${xml(origin + listPath(l))}"/>`).join("");
    return `<url><loc>${xml(origin + listPath(lang))}</loc>${lastmod(newest(shown[lang]!))}<changefreq>hourly</changefreq>${links}</url>`;
  });
  // Each country's page (#350): a list of its own, indexable (pages/list.ts), which no sitemap named
  // until 26 Nov. Listed in a language while the 7 days have something of that country there.
  const countries = new Map<string, Partial<Record<SiteLang, ListArticle[]>>>();
  for (const lang of withLists) {
    for (const article of shown[lang]!) {
      if (!isCountryPage(article.country)) continue;
      const entry = countries.get(article.country) ?? {};
      (entry[lang] ??= []).push(article);
      countries.set(article.country, entry);
    }
  }
  for (const [country, entry] of [...countries].sort(([a], [b]) => a.localeCompare(b))) {
    const langs = SITE_LANGS.filter((l) => entry[l]);
    const path = (l: SiteLang) => origin + listPath(l, { place: { country }, topic: null });
    const links = langs.map((l) => `<xhtml:link rel="alternate" hreflang="${l}" href="${xml(path(l))}"/>`).join("");
    for (const lang of langs) urls.push(`<url><loc>${xml(path(lang))}</loc>${lastmod(newest(entry[lang]!))}<changefreq>daily</changefreq>${links}</url>`);
  }
  const indexable = Object.fromEntries(SITE_LANGS.map((lang) => [lang, (shown[lang] ?? []).filter((a) => mayIndex(a, lang))]));
  urls.push(...articleUrls(origin, indexable));
  return `${URLSET}\n${urls.join("\n")}\n</urlset>\n`;
}

/** How far back the news sitemap goes: Google reads only articles of the last 2 days from one. */
export const NEWS_SITEMAP_MS = 48 * 3_600_000;

/**
 * The news sitemap (/sitemap-news.xml, #350): the indexable articles (api/indexing.ts)
 * that came in the last 2 days, in each language their page may be indexed in, with what a
 * news crawler reads first: the publication, the language, when it came and its headline.
 */
export function newsSitemapXml(origin: string, shown: Partial<Record<SiteLang, ListArticle[]>>, now: Date): string {
  const urls: string[] = [];
  for (const lang of SITE_LANGS) {
    for (const article of shown[lang] ?? []) {
      const added = parseTime(article.addedAt) ?? parseTime(article.publishedAt);
      if (!added || now.getTime() - added.getTime() > NEWS_SITEMAP_MS || !mayIndex(article, lang)) continue;
      urls.push(
        `<url><loc>${xml(origin + articlePath(lang, article))}</loc><news:news><news:publication><news:name>${xml(SITE_NAME)}</news:name><news:language>${lang}</news:language></news:publication>` +
          `<news:publication_date>${isoTime(added)}</news:publication_date><news:title>${xml(article.headline ?? article.originalTitle)}</news:title></news:news></url>`,
      );
    }
  }
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:news="http://www.google.com/schemas/sitemap-news/0.9">\n${urls.join("\n")}\n</urlset>\n`;
}

/** A month's sitemap (/sitemap-YYYY-MM.xml): every indexable article released that month (api/sitemap.ts filters them), in each language. Article pages never expire. */
export function monthSitemapXml(origin: string, shown: Partial<Record<SiteLang, SitemapEntry[]>>): string {
  return `${URLSET}\n${articleUrls(origin, shown).join("\n")}\n</urlset>\n`;
}

/** The first month with articles (the feed's first release, 14 Oct 2026): the oldest month file. */
export const FIRST_SITEMAP_MONTH = "2026-10";

/** Every month from FIRST_SITEMAP_MONTH to `now`'s, as `YYYY-MM`. */
export function sitemapMonths(now: Date): string[] {
  const months: string[] = [];
  let [y, m] = FIRST_SITEMAP_MONTH.split("-").map(Number);
  const last = now.getUTCFullYear() * 12 + now.getUTCMonth();
  while (y * 12 + (m - 1) <= last) {
    months.push(`${y}-${String(m).padStart(2, "0")}`);
    if (++m > 12) { m = 1; y++; }
  }
  return months;
}

/**
 * /sitemap.xml, the index robots.txt names: the latest file, then one file per
 * month. A file holds at most 50,000 addresses (sitemaps.org); a month is about
 * 5,000 today (1,300 articles × the languages they are shown in).
 */
export function sitemapIndexXml(origin: string, now: Date): string {
  // When each file last changed, so a crawler reads only what is new (#350; none until 26 Nov): the
  // latest file and the current month's now, to the hour (both are cached an hour); a past month's
  // at its end. No D1 read, as before.
  const hour = new Date(Math.floor(now.getTime() / 3_600_000) * 3_600_000);
  const months = sitemapMonths(now);
  const monthEnd = (m: string) => {
    const [y, mo] = m.split("-").map(Number);
    return new Date(Date.UTC(y, mo, 1));
  };
  const files: [string, Date][] = [
    [`${origin}/sitemap-latest.xml`, hour],
    [`${origin}/sitemap-news.xml`, hour],
    ...months.map((m, i): [string, Date] => [`${origin}/sitemap-${m}.xml`, i === months.length - 1 ? hour : monthEnd(m)]),
  ];
  return `<?xml version="1.0" encoding="UTF-8"?>\n<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${files.map(([f, at]) => `<sitemap><loc>${xml(f)}</loc>${lastmod(at)}</sitemap>`).join("\n")}\n</sitemapindex>\n`;
}
