// What search engines read besides the page (#88, SEO, Yurii 28 Oct): an
// article's structured data (schema.org NewsArticle, in a JSON-LD block that
// browsers never run, so the CSP's no-scripts rule still holds) and the
// sitemap. Nothing is indexed until robots.txt and robotsFor() allow it.
import type { ApiArticle } from "./data";
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

/**
 * The sitemap: each language's latest list, and every article of the API's
 * 7 days in each language it is shown in, with its other languages as
 * hreflang alternates, as the pages' own <link rel="alternate">.
 */
export function sitemapXml(origin: string, shown: Partial<Record<SiteLang, ApiArticle[]>>): string {
  const byId = new Map<string, Partial<Record<SiteLang, ApiArticle>>>();
  for (const lang of SITE_LANGS) {
    for (const article of shown[lang] ?? []) {
      const entry = byId.get(article.id) ?? {};
      entry[lang] = article;
      byId.set(article.id, entry);
    }
  }
  const urls: string[] = SITE_LANGS.map((lang) => {
    const links = SITE_LANGS.map((l) => `<xhtml:link rel="alternate" hreflang="${l}" href="${xml(origin + listPath(l))}"/>`).join("");
    return `<url><loc>${xml(origin + listPath(lang))}</loc><changefreq>hourly</changefreq>${links}</url>`;
  });
  for (const entry of byId.values()) {
    const langs = SITE_LANGS.filter((l) => entry[l]);
    const links = langs.map((l) => `<xhtml:link rel="alternate" hreflang="${l}" href="${xml(origin + articlePath(l, entry[l]!))}"/>`).join("");
    for (const lang of langs) {
      const article = entry[lang]!;
      const added = parseTime(article.addedAt) ?? parseTime(article.publishedAt);
      urls.push(`<url><loc>${xml(origin + articlePath(lang, article))}</loc>${added ? `<lastmod>${isoTime(added)}</lastmod>` : ""}${links}</url>`);
    }
  }
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">\n${urls.join("\n")}\n</urlset>\n`;
}
