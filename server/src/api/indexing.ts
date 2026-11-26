// Which article pages search engines may index (#350, Yurii 26 Nov 2026). Until
// then every article was indexed in every language it was shown in: about 9,300
// pages for 2,394 items, most of them short AI summaries, and from 11 Nov
// Google stopped reading the sitemap (docs/decisions/2026-11-26-index-best-pages.md).
// Now only the pages worth a search engine's visit: an official decision (not an
// event from Wikipedia or the media), of importance 3 and up, in English and in
// the source's own language. Every other page stays on the site with `noindex`,
// out of the sitemap. One rule for the article page, its alternates and both
// sitemaps, so they never disagree.

/** The lowest importance (1–5, the summary's) an indexable article has. */
export const INDEX_MIN_IMPORTANCE = 3;

/** What the rule reads of an article; a missing field (a snapshot built before this) counts against. */
export interface IndexFacts {
  decisionType?: string | null;
  importance?: number | null;
  originalLanguage?: string | null;
}

/** Whether search engines may index the article's page in `lang`. */
export const mayIndex = (article: IndexFacts, lang: string): boolean =>
  !!article.decisionType &&
  article.decisionType !== "event" &&
  (article.importance ?? 0) >= INDEX_MIN_IMPORTANCE &&
  (lang === "en" || lang === article.originalLanguage);
