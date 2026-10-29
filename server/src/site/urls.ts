// The site's addresses (#88). Every absolute URL starts with SITE_ORIGIN,
// never the request's host: Workers Cache keys a page by path and query only,
// so a page rendered for one host is served on every other.
import type { SiteLang } from "./texts";

/** The pages every language has. */
export const INFO_PAGES = ["about", "privacy", "terms", "support"] as const;
export type InfoPage = (typeof INFO_PAGES)[number];

/** The site's origin without a trailing slash. */
export const originOf = (siteOrigin: string) => siteOrigin.replace(/\/+$/, "");

/** The latest list in a language: `/en`. */
export const listPath = (lang: SiteLang) => `/${lang}`;

export const infoPath = (lang: SiteLang, page: InfoPage) => `/${lang}/${page}`;
