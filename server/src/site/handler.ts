// The website (#88), the Worker `site` (wrangler.site.jsonc; index.ts). Plain HTML
// rendered from what the app's API shows, one request per page view, nothing
// indexed before the domain. URLs (docs/contract.md, "Website"):
//   /                              302 to the visitor's language (lang.ts), 0 D1 rows, never cached
//   /{lang}                        latest list (all countries); ?before=<feedSeq> for the next page
//   /{lang}/{cc}                   one country's list (#67, #68: only that country's sources)
//   /{lang}/{group}                a group of countries (eu, g7, g20, nato: its members' sources together)
//   …?topic=<id>                   any list, one topic; then &before=, as the next page
//   /{lang}/{cc}/{id}-{slug}       an article (looked up by its id; another country or slug is a 301 to its own)
//   /{lang}/about|privacy|terms|support
//   /robots.txt                    Disallow: /*?, and where the sitemap is
//   /sitemap.xml                   the lists and the 7 days' articles (seo.ts)
import { rankTopics } from "../api/filters";
import type { Topic } from "../summarizer/schema";
import { type ApiArticle, allLatest, articleInLanguages, latest, topicsMenu, whereMenu } from "./data";
import type { SiteEnv } from "./env";
import { APPLE_TOUCH_ICON, OG_IMAGE } from "./icon";
import { type Page, cssHash, layout } from "./layout";
import { sitemapXml } from "./seo";
import { consentHash } from "./consent";
import { visitorLang } from "./lang";
import { articlePage, notInLanguagePage } from "./pages/article";
import { errorPage, notFoundPage } from "./pages/errors";
import { infoPage } from "./pages/info";
import { type ListView, listPage } from "./pages/list";
import { type CacheKind, type Reply, respond, robotsFor } from "./respond";
import { SITE_LANGS, type SiteLang, isSiteLang } from "./texts";
import { ARTICLE_ID, INFO_PAGES, type InfoPage, type Place, articlePath, groupOf, isCountryPage, isTopic, listPath, originOf } from "./urls";

/**
 * Crawlers read every page without a query: the lists' first pages, the
 * articles and the information pages (robotsFor()). Every address with a
 * query (a topic, a later page) stays out: those repeat what the first pages
 * link, and keeping them out bounds what a crawl reads from D1 and the
 * account's 100,000 requests a day (about 26 lists a language instead of
 * 13 times as many).
 */
export const ROBOTS_TXT = "User-agent: *\nDisallow: /*?\n";

const LANG_PATH = new RegExp(`^/(${SITE_LANGS.join("|")})(/.*)?$`);
const INFO_PATH = new RegExp(`^/(${INFO_PAGES.join("|")})$`);
/** `/de/01JB…`, `/de/01JB…-slug`: a country, the 26-character id, then a hyphen or the end (any other country or slug is a 301). */
const ARTICLE_PATH = /^\/([A-Za-z]{2})\/([^/]+)$/;
/**
 * After the language, a list: nothing (all countries) or one segment (a
 * place: a country's code or a group's id, in any case), with or without a
 * trailing slash. An article always has a second segment after the country,
 * so the two never meet; information pages are matched first, and their
 * names are never a place's.
 */
const LIST_PATH = /^(?:\/([A-Za-z0-9]{2,8}))?(\/?)$/;

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

/** The site's topic parameter: absent (All topics), or exactly one id of the fixed list; anything else is not a page (undefined). */
function readTopic(params: URLSearchParams): Topic | null | undefined {
  const values = params.getAll("topic");
  if (values.length === 0) return null;
  return values.length === 1 && isTopic(values[0]) ? values[0] : undefined;
}

/**
 * The place a list path names, in any case: a group (`g7`, `NATO`; `eu` is
 * the European Union group, which also holds the EU institutions' decisions)
 * or a country with a page (`de`, `GB`); null without one (all countries);
 * undefined for anything else, which is no page.
 */
function readPlace(segment: string | undefined): Place | undefined {
  if (segment === undefined) return null;
  const group = groupOf(segment.toLowerCase());
  if (group) return { group };
  const code = segment.toUpperCase();
  return isCountryPage(code) ? { country: code } : undefined;
}

/**
 * A list page: the API's page with its filters and, on a first page, what the
 * two menus offer (GET /countries; GET /topics for the place), all in this one
 * request. A later page shows its filters without menus, so paging reads no
 * more rows than before the filters.
 *
 * The Topics menu counts the place's (or the whole) feed without a topic. A
 * country's or a small group's first page without a topic often holds all of
 * it (live, 16 Oct: 15 of 17 countries had 20 decisions or fewer in 7 days);
 * then the menu is its articles' topics counted as GET /topics counts them
 * (rankTopics), which saves walking the feed a second time (about 230 rows).
 * Otherwise, and always for all countries, the menu is GET /topics, asked in
 * parallel when it is certainly needed.
 */
async function listReply(env: SiteEnv, origin: string, lang: SiteLang, view: ListView): Promise<Reply> {
  const { filter, before } = view;
  if (before !== null) return page(listPage(lang, origin, view, { list: await latest(env, lang, filter, before), menus: null }), 200, "list");
  const mayHoldAll = filter.place !== null && filter.topic === null;
  const [list, where, asked] = await Promise.all([
    latest(env, lang, filter, null),
    whereMenu(env, lang),
    mayHoldAll ? null : topicsMenu(env, lang, filter.place),
  ]);
  const topics =
    asked ?? (list.nextCursor === null ? rankTopics(list.items.map((a) => a.topics), lang) : await topicsMenu(env, lang, filter.place));
  return page(listPage(lang, origin, view, { list, menus: { where, topics } }), 200, "list");
}

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

  // A query a page does not use would be a new cache entry and a new render each time
  // (the cache key is path and query): lists, the landing page and article pages send
  // it to their clean URL, with no D1 read (#88 and #89 reviews).
  // `/` opens the visitor's own language (Yurii, 28 Oct: no page to choose one),
  // from the browser's languages, else the country Cloudflare sees; never cached.
  if (path === "/") {
    if (url.search) return { kind: "redirect", status: 301, body: null, location: `${origin}/` };
    const country = (request.cf as { country?: unknown } | undefined)?.country;
    const lang = visitorLang(request.headers.get("accept-language"), typeof country === "string" ? country : null);
    return { kind: "chooser", status: 302, body: null, location: `${origin}${listPath(lang)}` };
  }
  // robots.txt names the sitemap, so a crawler finds it once indexing is allowed.
  if (path === "/robots.txt") return { kind: "fixed", status: 200, body: `${ROBOTS_TXT}\nSitemap: ${origin}/sitemap.xml\n` };
  if (path === "/sitemap.xml") {
    if (url.search) return { kind: "redirect", status: 301, body: null, location: `${origin}/sitemap.xml` };
    const lists = await Promise.all(SITE_LANGS.map((lang) => allLatest(env, lang)));
    const shown = Object.fromEntries(SITE_LANGS.map((lang, i) => [lang, lists[i]]));
    return { kind: "sitemap", status: 200, body: sitemapXml(origin, shown), contentType: "application/xml; charset=utf-8" };
  }
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

  const list = LIST_PATH.exec(rest);
  if (list) {
    // An unknown place or topic is not a page: a 404 before any D1 read.
    const place = readPlace(list[1]);
    if (place === undefined) return notFound(lang);
    const topic = readTopic(url.searchParams);
    if (topic === undefined) return notFound(lang);
    const filter = { place, topic };
    const before = readBefore(url.searchParams);
    // One URL per view: a trailing slash, capitals, another order, a repeated or unused parameter go to it.
    const clean = listPath(lang, filter, before);
    if (path + url.search !== clean) return { kind: "redirect", status: 301, body: null, location: origin + clean };
    return listReply(env, origin, lang, { filter, before });
  }

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
  const [styleHash, scriptHash] = await Promise.all([cssHash(), consentHash()]);
  let reply: Reply;
  try {
    reply = await route(request, env);
  } catch (error) {
    const path = new URL(request.url).pathname;
    console.error(JSON.stringify({ message: "site request failed", path, error: error instanceof Error ? error.message : String(error) }));
    const lang = LANG_PATH.exec(path)?.[1];
    reply = page(errorPage(lang && isSiteLang(lang) ? lang : "en"), 500, "none");
  }
  return respond(reply, request.method, styleHash, scriptHash);
}
