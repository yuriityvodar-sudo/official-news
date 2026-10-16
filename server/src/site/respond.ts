// Every response of the site goes through respond(), the outermost layer:
// nothing runs after it, and zone rules do not apply to Workers Cache, so the
// headers set here are the ones readers and the cache get (LyFi lesson 7).
import type { Html } from "./html";

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
   * A latest list: 5 languages × 288 renders a day × about 260 rows ≈ 0.37M of
   * D1's 5M daily rows at most, whatever the traffic (300 s, not 120 s: #88 review).
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

/** Whether search engines may index a page. Nothing is indexed before the domain (#88); the reviewed pages come later, through here only. */
export const robotsFor = (_page: string) => "noindex";

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
    "x-robots-tag": robotsFor("any"),
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
