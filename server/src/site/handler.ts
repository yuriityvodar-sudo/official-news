// The website (#88), the Worker `site` (wrangler.site.jsonc; index.ts). Plain HTML
// rendered from what the app's API shows, one request per page view, nothing
// indexed before the domain. URLs (docs/contract.md, "Website"):
//   /                              landing page, 0 D1 rows
//   /{lang}                        latest list; ?before=<feedSeq> for the next page
//   /{lang}/{cc}/{id}-{slug}       an article (only the id is looked up)
//   /{lang}/about|privacy|terms|support
//   /robots.txt                    Disallow: /
import { type ApiArticle, articleInLanguages, latest } from "./data";
import type { SiteEnv } from "./env";
import { type Page, cssHash, layout } from "./layout";
import { articlePage, notInLanguagePage } from "./pages/article";
import { errorPage, notFoundPage } from "./pages/errors";
import { infoPage } from "./pages/info";
import { landingPage } from "./pages/landing";
import { listPage } from "./pages/list";
import { type CacheKind, type Reply, respond, robotsFor } from "./respond";
import { SITE_LANGS, type SiteLang, isSiteLang } from "./texts";
import { ARTICLE_ID, INFO_PAGES, type InfoPage, listPath, originOf } from "./urls";

/**
 * Keeps crawlers out on workers.dev: it saves requests from the account's
 * 100,000 a day. A crawler then never reads the noindex behind it, so a URL
 * linked from elsewhere can still be listed, without its content. With the
 * domain, it must stop disallowing the pages (keep only `/*?before=`), or
 * robotsFor() is never read (docs/plan.md, open points).
 */
export const ROBOTS_TXT = "User-agent: *\nDisallow: /\n";

const LANG_PATH = new RegExp(`^/(${SITE_LANGS.join("|")})(/.*)?$`);
const INFO_PATH = new RegExp(`^/(${INFO_PAGES.join("|")})$`);
/** `/de/01JB…`, `/de/01JB…-slug`: the 26-character id, then a hyphen or the end. */
const ARTICLE_PATH = /^\/([a-z]{2})\/([^/]+)$/;

/** A page's reply: its robots value is worked out once, for its header and its meta tag alike. */
function page(p: Page, status: number, kind: CacheKind): Reply {
  const robots = robotsFor(p);
  return { kind, status, body: layout(p, robots), lang: p.lang, robots };
}
const notFound = (lang: SiteLang): Reply => page(notFoundPage(lang), 404, "missing");

/** The site's paging parameter: a feedSeq, a whole number from 1. Anything else is not a page. */
function readBefore(params: URLSearchParams): number | null {
  const values = params.getAll("before");
  if (values.length !== 1 || !/^[1-9]\d{0,15}$/.test(values[0])) return null;
  const n = Number(values[0]);
  return Number.isSafeInteger(n) ? n : null;
}

/** The article id at the start of a path segment, followed by a hyphen or nothing; else null. */
function articleId(segment: string): string | null {
  const id = segment.slice(0, 26);
  const rest = segment.slice(26);
  return ARTICLE_ID.test(id) && (rest === "" || rest.startsWith("-")) ? id : null;
}

async function articleReply(env: SiteEnv, origin: string, lang: SiteLang, id: string): Promise<Reply> {
  const shown: Partial<Record<SiteLang, ApiArticle>> = await articleInLanguages(env, id);
  if (shown[lang]) return page(articlePage(lang, origin, shown), 200, "article");
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

  // A query a page does not use would be a new cache entry and a new render each time
  // (the cache key is path and query): lists and the landing page send it to their
  // clean URL, with no D1 read (#88 review). Article pages ignore queries (utm, fbclid).
  if (path === "/") return url.search ? { kind: "redirect", status: 301, body: null, location: `${origin}/` } : page(landingPage(origin), 200, "fixed");
  if (path === "/robots.txt") return { kind: "fixed", status: 200, body: ROBOTS_TXT };
  if (path === "/favicon.ico" || /^\/apple-touch-icon[\w-]*\.png$/.test(path)) return { kind: "icon", status: 404, body: "Not found\n" };

  const match = LANG_PATH.exec(path);
  if (!match || !isSiteLang(match[1])) return notFound("en");
  const lang = match[1];
  const rest = match[2] ?? "";

  if (rest === "" || rest === "/") {
    const before = readBefore(url.searchParams);
    const clean = listPath(lang, before);
    if (rest === "/" || url.search !== (before === null ? "" : `?before=${before}`)) {
      return { kind: "redirect", status: 301, body: null, location: origin + clean };
    }
    return page(listPage(lang, origin, before, await latest(env, lang, before)), 200, "list");
  }

  const info = INFO_PATH.exec(rest);
  if (info) return page(infoPage(lang, origin, info[1] as InfoPage), 200, "fixed");

  const article = ARTICLE_PATH.exec(rest);
  const id = article ? articleId(article[2]) : null;
  if (id) return articleReply(env, origin, lang, id);

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
