// Every response of the site goes through respond(), the outermost layer:
// nothing runs after it, and zone rules do not apply to Workers Cache, so the
// headers set here are the ones readers and the cache get (LyFi lesson 7).
import type { Html } from "./html";
import type { Page } from "./layout";

/**
 * What a response is, for its cache headers. `Cache-Control` is for the browser;
 * `Cloudflare-CDN-Cache-Control` is for Workers Cache in front of the Worker
 * (stripped before the browser). Every response sets both: without them
 * Workers Cache keeps a 200 for 2 hours and a 404 for 3 minutes. Never
 * `s-maxage` (it turns stale-while-revalidate off), and `stale-if-error` is
 * explicit because the default serves stale copies for ever. A deploy is a new
 * Worker version and starts with an empty cache.
 */
export const CACHE = {
  /** An article page: a re-summarized article shows within about 10 minutes (plus the browser's 5). */
  article: { browser: "public, max-age=300", edge: "max-age=600, stale-while-revalidate=3600, stale-if-error=86400" },
  /**
   * A latest list, 300 s (not 120 s: #88 review). Its D1 rows grow with the
   * news (measured 16 Oct, docs/plan.md "D1 rows read, website"): page 1 about
   * 45–65 rows plus about 6 per article of the last 24 hours, and a language
   * with few or no translations (German while it is off) about 2 more per
   * article of the 7 days, on every page. So the cache bounds renders per URL
   * (288 a day per cache tier), not rows.
   */
  list: { browser: "public, max-age=60", edge: "max-age=300, stale-while-revalidate=600, stale-if-error=86400" },
  /** The landing page, information pages, robots.txt: change only with a deploy. */
  fixed: { browser: "public, max-age=3600", edge: "max-age=86400" },
  /** An unknown page, or an article not released yet: short, it may appear soon. */
  missing: { browser: "public, max-age=60", edge: "max-age=60" },
  /** An article not translated into this language (yet). */
  notInLanguage: { browser: "public, max-age=300", edge: "max-age=300" },
  /** /favicon.ico and /apple-touch-icon*.png: a cheap 404 the browser keeps a day. */
  icon: { browser: "public, max-age=86400", edge: "max-age=86400" },
  /** A list or landing URL with a query it does not use, sent to its clean URL with no D1 read. */
  redirect: { browser: "public, max-age=86400", edge: "max-age=86400" },
  /** 405 and 500: never stored, so an outage is never cached as a page. */
  none: { browser: "no-store", edge: "no-store" },
} as const;

export type CacheKind = keyof typeof CACHE;

/**
 * Whether search engines may index a page: the one switch, computed once per
 * page (handler.ts) and used for both the X-Robots-Tag header and the robots
 * meta tag, so they never disagree (the stricter one would win). Nothing is
 * indexed before the domain (#88); the reviewed articles come later, by a flag
 * on the article, through here. While ROBOTS_TXT disallows every path a
 * crawler never reads this value at all (site-routes.test.ts keeps both
 * together): with the domain robots.txt must stop disallowing the pages.
 */
export const robotsFor = (_page: Page): string => "noindex";

/** What a response that is not a page (robots.txt, a redirect, an icon, a 405) says. */
export const ROBOTS_DEFAULT = "noindex";

/** The site's Content-Security-Policy: no scripts, no frames, nothing loaded from elsewhere; only our one inline stylesheet (by its hash) and data: icons. */
export const csp = (styleHash: string) =>
  `default-src 'none'; style-src '${styleHash}'; img-src data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`;

export interface Reply {
  kind: CacheKind;
  status: number;
  /** A page (Html), plain text, or nothing. */
  body: Html | string | null;
  /** The page's language, for Content-Language. */
  lang?: string;
  /** A page's robotsFor(), the same value as its meta tag; else ROBOTS_DEFAULT. */
  robots?: string;
  /** For a redirect: an absolute URL made from SITE_ORIGIN. */
  location?: string;
  allow?: string;
}

/** The one place that sets the site's headers. A HEAD request gets the same headers and no body. */
export function respond(reply: Reply, method: string, styleHash: string): Response {
  const cache = CACHE[reply.kind];
  const isText = typeof reply.body === "string";
  const headers = new Headers({
    "cache-control": cache.browser,
    "cloudflare-cdn-cache-control": cache.edge,
    "x-robots-tag": reply.robots ?? ROBOTS_DEFAULT,
    "x-content-type-options": "nosniff",
    "content-security-policy": csp(styleHash),
    "content-type": isText ? "text/plain; charset=utf-8" : "text/html; charset=utf-8",
  });
  if (reply.lang) headers.set("content-language", reply.lang);
  if (reply.location) headers.set("location", reply.location);
  if (reply.allow) headers.set("allow", reply.allow);
  const body = method === "HEAD" || reply.body === null ? null : String(reply.body);
  return new Response(body, { status: reply.status, headers });
}
