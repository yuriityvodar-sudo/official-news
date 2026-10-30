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
  /** Information pages, robots.txt: change only with a deploy. */
  fixed: { browser: "public, max-age=3600", edge: "max-age=86400" },
  /** An unknown page, or an article not released yet: short, it may appear soon. */
  missing: { browser: "public, max-age=60", edge: "max-age=60" },
  /** /apple-touch-icon*.png and /icon-512.png (icon.ts), and the 404 for /favicon.ico: kept a day. */
  icon: { browser: "public, max-age=86400", edge: "max-age=86400" },
  /** 405 and 500: never stored, so an outage is never cached as a page. */
  none: { browser: "no-store", edge: "no-store" },
} as const;

export type CacheKind = keyof typeof CACHE;

/**
 * Whether search engines may index a page: the one switch, computed once per
 * page (handler.ts) and used for both the X-Robots-Tag header and the robots
 * meta tag, so they never disagree (the stricter one would win). Nothing is
 * indexed yet, and robots.txt keeps crawlers from every page.
 */
export const robotsFor = (_page: Page): string => "noindex";

/** What a response that is not a page (robots.txt, a redirect, an icon, a 405) says. */
export const ROBOTS_DEFAULT = "noindex";

/** The site's Content-Security-Policy: our one inline stylesheet by its hash, data: icons, no scripts, no frames, nothing from elsewhere. */
export const csp = (styleHash: string) =>
  `default-src 'none'; style-src '${styleHash}'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`;

export interface Reply {
  kind: CacheKind;
  status: number;
  /** A page (Html), plain text, a PNG (icon.ts), or nothing. */
  body: Html | string | Uint8Array | null;
  /** The page's language, for Content-Language. */
  lang?: string;
  /** A page's robotsFor(), the same value as its meta tag; else ROBOTS_DEFAULT. */
  robots?: string;
  allow?: string;
}

/** The one place that sets the site's headers. A HEAD request gets the same headers and no body. */
export function respond(reply: Reply, method: string, styleHash: string): Response {
  const cache = CACHE[reply.kind];
  const isText = typeof reply.body === "string";
  const isPng = reply.body instanceof Uint8Array;
  const headers = new Headers({
    "cache-control": cache.browser,
    "cloudflare-cdn-cache-control": cache.edge,
    "x-robots-tag": reply.robots ?? ROBOTS_DEFAULT,
    "x-content-type-options": "nosniff",
    // https only, for a year: the site is served on its own domain (Roman's review of #233).
    "strict-transport-security": "max-age=31536000",
    "content-security-policy": csp(styleHash),
    "content-type": isPng ? "image/png" : isText ? "text/plain; charset=utf-8" : "text/html; charset=utf-8",
  });
  if (reply.lang) headers.set("content-language", reply.lang);
  if (reply.allow) headers.set("allow", reply.allow);
  const body = method === "HEAD" || reply.body === null ? null : reply.body instanceof Uint8Array ? reply.body : String(reply.body);
  return new Response(body, { status: reply.status, headers });
}
