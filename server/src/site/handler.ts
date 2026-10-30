// The website (#88), the Worker `site` (wrangler.site.jsonc; index.ts). Plain HTML
// rendered from what the app's API shows, one request per page view, nothing
// indexed before the domain. URLs (docs/contract.md, "Website"):
//   /robots.txt                    Disallow: /
import type { SiteEnv } from "./env";
import { APPLE_TOUCH_ICON, OG_IMAGE } from "./icon";
import { type Page, cssHash, layout } from "./layout";
import { errorPage, notFoundPage } from "./pages/errors";
import { type CacheKind, type Reply, respond, robotsFor } from "./respond";
import { SITE_LANGS, type SiteLang, isSiteLang } from "./texts";

/** Nothing is indexed yet: crawlers stay out of every page. */
export const ROBOTS_TXT = "User-agent: *\nDisallow: /\n";

const LANG_PATH = new RegExp(`^/(${SITE_LANGS.join("|")})(/.*)?$`);

/** A page's reply: its robots value is worked out once, for its header and its meta tag alike. */
function page(p: Page, status: number, kind: CacheKind): Reply {
  const robots = robotsFor(p);
  return { kind, status, body: layout(p, robots), lang: p.lang, robots };
}
const notFound = (lang: SiteLang): Reply => page(notFoundPage(lang), 404, "missing");

async function route(request: Request, _env: SiteEnv): Promise<Reply> {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return { kind: "none", status: 405, body: "Method not allowed\n", allow: "GET, HEAD" };
  }
  const url = new URL(request.url);
  const path = url.pathname;

  if (path === "/robots.txt") return { kind: "fixed", status: 200, body: ROBOTS_TXT };
  // The icon (icon.ts): Safari's home-screen icon under any of its names, and
  // the link preview's picture. The tab icon is inline, so /favicon.ico stays a 404.
  if (/^\/apple-touch-icon[\w-]*\.png$/.test(path)) return { kind: "icon", status: 200, body: APPLE_TOUCH_ICON };
  if (path === "/icon-512.png") return { kind: "icon", status: 200, body: OG_IMAGE };
  if (path === "/favicon.ico") return { kind: "icon", status: 404, body: "Not found\n" };

  const match = LANG_PATH.exec(path);
  if (!match || !isSiteLang(match[1])) return notFound("en");
  const lang = match[1];

  return notFound(lang);
}

/** The site's request handler; tests call it with `{ DB, SITE_ORIGIN }`. */
export async function handleSite(request: Request, env: SiteEnv): Promise<Response> {
  const styleHash = await cssHash();
  let reply: Reply;
  try {
    reply = await route(request, env);
  } catch (error) {
    const path = new URL(request.url).pathname;
    console.error(JSON.stringify({ message: "site request failed", path, error: error instanceof Error ? error.message : String(error) }));
    const lang = LANG_PATH.exec(path)?.[1];
    reply = page(errorPage(lang && isSiteLang(lang) ? lang : "en"), 500, "none");
  }
  return respond(reply, request.method, styleHash);
}
