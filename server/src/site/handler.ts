// The website (#88), the Worker `site` (wrangler.site.jsonc; index.ts). Plain HTML
// rendered from what the app's API shows, one request per page view, nothing
// indexed before the domain. URLs (docs/contract.md, "Website"):
//   /{lang}/{cc}/{id}-{slug}       an article (looked up by its id; another country or slug is a 301 to its own)
//   /{lang}/about|privacy|terms|support
//   /robots.txt                    Disallow: /
import { type ApiArticle, articleInLanguages } from "./data";
import type { SiteEnv } from "./env";
import { APPLE_TOUCH_ICON, OG_IMAGE } from "./icon";
import { type Page, cssHash, layout } from "./layout";
import { articlePage, notInLanguagePage } from "./pages/article";
import { errorPage, notFoundPage } from "./pages/errors";
import { infoPage } from "./pages/info";
import { type CacheKind, type Reply, respond, robotsFor } from "./respond";
import { SITE_LANGS, type SiteLang, isSiteLang } from "./texts";
import { ARTICLE_ID, INFO_PAGES, type InfoPage, articlePath, originOf } from "./urls";

/** Nothing is indexed yet: crawlers stay out of every page. */
export const ROBOTS_TXT = "User-agent: *\nDisallow: /\n";

const LANG_PATH = new RegExp(`^/(${SITE_LANGS.join("|")})(/.*)?$`);
const INFO_PATH = new RegExp(`^/(${INFO_PAGES.join("|")})$`);
/** `/de/01JB…`, `/de/01JB…-slug`: a country, the 26-character id, then a hyphen or the end (any other country or slug is a 301). */
const ARTICLE_PATH = /^\/([A-Za-z]{2})\/([^/]+)$/;

/** A page's reply: its robots value is worked out once, for its header and its meta tag alike. */
function page(p: Page, status: number, kind: CacheKind): Reply {
  const robots = robotsFor(p);
  return { kind, status, body: layout(p, robots), lang: p.lang, robots };
}
const notFound = (lang: SiteLang): Reply => page(notFoundPage(lang), 404, "missing");

/** The article id at the start of a path segment, followed by a hyphen or nothing; else null. */
function articleId(segment: string): string | null {
  const id = segment.slice(0, 26);
  const rest = segment.slice(26);
  return ARTICLE_ID.test(id) && (rest === "" || rest.startsWith("-")) ? id : null;
}

/**
 * An article in `lang`, looked up by its id alone. A path with another
 * country or slug (an older headline's, a mistyped one) is a 301 to the
 * article's one URL, so each article has one cache entry and an old link
 * still lands once its headline is summarized again (#89 review).
 */
async function articleReply(env: SiteEnv, origin: string, lang: SiteLang, id: string, path: string): Promise<Reply> {
  const shown: Partial<Record<SiteLang, ApiArticle>> = await articleInLanguages(env, id);
  const article = shown[lang];
  if (article) {
    const own = articlePath(lang, article);
    if (path !== own) return { kind: "moved", status: 301, body: null, location: origin + own };
    return page(articlePage(lang, origin, shown), 200, "article");
  }
  // Shown in other languages: not translated into this one yet, or its translation failed.
  if (Object.keys(shown).length) return page(notInLanguagePage(lang, shown), 404, "notInLanguage");
  // Unknown, not released yet, or hidden (is_news = 0: classified as not news, never shown). A 410 waits for a real takedown state, in the API (#88 review).
  return notFound(lang);
}

async function route(request: Request, env: SiteEnv): Promise<Reply> {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return { kind: "none", status: 405, body: "Method not allowed\n", allow: "GET, HEAD" };
  }
  const url = new URL(request.url);
  const origin = originOf(env.SITE_ORIGIN);
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
  const rest = match[2] ?? "";

  const info = INFO_PATH.exec(rest);
  if (info) return page(infoPage(lang, origin, info[1] as InfoPage), 200, "fixed");

  const article = ARTICLE_PATH.exec(rest);
  const id = article ? articleId(article[2]) : null;
  if (id) {
    // `?fbclid=…`, `?utm_source=…`: the same page, so its own URL, without reading the article.
    if (url.search) return { kind: "redirect", status: 301, body: null, location: origin + path };
    return articleReply(env, origin, lang, id, path);
  }

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
