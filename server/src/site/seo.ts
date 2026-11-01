// What search engines read besides the page (#88, SEO, Yurii 28 Oct): an
// article's structured data (schema.org NewsArticle, in a JSON-LD block that
// browsers never run, so the CSP's no-scripts rule still holds) and the
// sitemap. Nothing is indexed until robots.txt and robotsFor() allow it.
import type { ApiArticle, ListArticle } from "./data";
import { isoTime, parseTime } from "./dates";
import { type Html, raw, safeHttps } from "./html";
import { SITE_NAME } from "./layout";
import { SITE_LANGS, type SiteLang, text } from "./texts";
import { articlePath, listPath } from "./urls";

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
 * it has articles (an empty one is noindex), and every article of the API's 7
 * days in each language it is shown in.
 */
export function sitemapXml(origin: string, shown: Partial<Record<SiteLang, ListArticle[]>>): string {
  const withLists = SITE_LANGS.filter((lang) => (shown[lang] ?? []).length > 0);
  const urls: string[] = withLists.map((lang) => {
    const links = withLists.map((l) => `<xhtml:link rel="alternate" hreflang="${l}" href="${xml(origin + listPath(l))}"/>`).join("");
    return `<url><loc>${xml(origin + listPath(lang))}</loc><changefreq>hourly</changefreq>${links}</url>`;
  });
  urls.push(...articleUrls(origin, shown));
  return `${URLSET}\n${urls.join("\n")}\n</urlset>\n`;
}

/** A month's sitemap (/sitemap-YYYY-MM.xml): every article released that month, in each language it is shown in. Article pages never expire. */
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
  const files = [`${origin}/sitemap-latest.xml`, ...sitemapMonths(now).map((m) => `${origin}/sitemap-${m}.xml`)];
  return `<?xml version="1.0" encoding="UTF-8"?>\n<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${files.map((f) => `<sitemap><loc>${xml(f)}</loc></sitemap>`).join("\n")}\n</sitemapindex>\n`;
}
