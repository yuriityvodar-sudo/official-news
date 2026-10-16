// The website (#88), the Worker `site` (wrangler.site.jsonc; index.ts). Plain HTML
// rendered from what the app's API shows, one request per page view, nothing
// indexed before the domain. URLs (docs/contract.md, "Website"):
//   /                              landing page, 0 D1 rows
//   /{lang}                        latest list (Global); ?before=<feedSeq> for the next page
//   /{lang}/{cc}                   a country's list (#67, #68: Local's view, the EU's too for a member)
//   …?topic=<id>                   either list, one topic; then &before=, as the next page
//   /{lang}/local                  302 to the reader's country (from the request's IP country), never cached
//   /{lang}/{cc}/{id}-{slug}       an article (only the id is looked up)
//   /{lang}/about|privacy|terms|support
//   /robots.txt                    Disallow: /
import { localCountries, rankTopics } from "../api/filters";
import type { Topic } from "../summarizer/schema";
import { type ApiArticle, articleInLanguages, countriesMenu, latest, topicsMenu } from "./data";
import type { SiteEnv } from "./env";
import { type Page, cssHash, layout } from "./layout";
import { articlePage, notInLanguagePage } from "./pages/article";
import { errorPage, notFoundPage } from "./pages/errors";
import { infoPage } from "./pages/info";
import { landingPage } from "./pages/landing";
import { type ListView, listPage } from "./pages/list";
import { type CacheKind, type Reply, respond, robotsFor } from "./respond";
import { SITE_LANGS, type SiteLang, isSiteLang } from "./texts";
import { ARTICLE_ID, INFO_PAGES, type InfoPage, isBloc, isCountryPage, isTopic, listPath, originOf } from "./urls";

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
/**
 * After the language, a list: nothing (Global) or one 2-letter segment (a
 * country), with or without a trailing slash. An article always has a second
 * segment after the country, so the two never meet.
 */
const LIST_PATH = /^(?:\/([a-z]{2}))?(\/?)$/;

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

/** `menu=where`: the Global list with its Where menu open, where Local sends a reader it has no country for. */
const readMenu = (params: URLSearchParams) => {
  const values = params.getAll("menu");
  return values.length === 1 && values[0] === "where" ? ("where" as const) : null;
};

/** The request's country as Cloudflare reads it from the IP address (no permission asked); null without one. */
function ipCountry(request: Request): string | null {
  const cf = (request as { cf?: { country?: unknown } }).cf;
  return typeof cf?.country === "string" ? cf.country : null;
}

/**
 * Local (`/{lang}/local`), as in the app (#87): the reader's own country,
 * plus the EU's decisions for an EU member, never another country in its
 * place. A 302 to `/{lang}/{cc}` when the site has that country's page and its
 * Local feed has sources: its own active ones (GET /countries, a few dozen
 * rows), or a bloc's it belongs to (an EU member without sources of its own,
 * such as Poland or Finland, still gets the EU's, so no D1 read). Otherwise
 * (no IP country, Tor's T1, a country without active sources or without a
 * page, such as Norway, the EU itself) to the Global list with its Where menu
 * open. The topic goes along. Never stored: it differs per reader, and the
 * cache key has no country.
 */
async function localReply(env: SiteEnv, origin: string, lang: SiteLang, topic: Topic | null, code: string | null): Promise<Reply> {
  let country: string | null = null;
  if (code !== null && isCountryPage(code) && !isBloc(code)) {
    const inBloc = localCountries(code).length > 1;
    if (inBloc || (await countriesMenu(env, "en")).some((c) => c.code === code)) country = code;
  }
  const location = country ? listPath(lang, { country, topic }) : listPath(lang, { country: null, topic }, null, "where");
  return { kind: "local", status: 302, body: null, location: origin + location };
}

/**
 * A list page: the API's page with its filters and, on a first page, what the
 * two menus offer (GET /countries; GET /topics for the country), all in this
 * one request. A later page shows its filters without menus, so paging reads
 * no more rows than before the filters.
 *
 * The Topics menu counts the country's (or the whole) feed without a topic.
 * A country's first page without a topic usually holds all of it (live, 16
 * Oct: 15 of 17 countries had 20 decisions or fewer in 7 days); then the menu
 * is its articles' topics counted as GET /topics counts them (rankTopics),
 * which saves walking the feed a second time (about 230 rows). Otherwise, and
 * always for Global, the menu is GET /topics, asked in parallel when it is
 * certainly needed.
 */
async function listReply(env: SiteEnv, origin: string, lang: SiteLang, view: ListView): Promise<Reply> {
  const { filter, before } = view;
  if (before !== null) return page(listPage(lang, origin, view, { list: await latest(env, lang, filter, before), menus: null }), 200, "list");
  const mayHoldAll = filter.country !== null && filter.topic === null;
  const [list, countries, asked] = await Promise.all([
    latest(env, lang, filter, null),
    countriesMenu(env, lang),
    mayHoldAll ? null : topicsMenu(env, lang, filter.country),
  ]);
  const topics =
    asked ?? (list.nextCursor === null ? rankTopics(list.items.map((a) => a.topics), lang) : await topicsMenu(env, lang, filter.country));
  return page(listPage(lang, origin, view, { list, menus: { countries, topics } }), 200, "list");
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

  const list = LIST_PATH.exec(rest);
  if (list) {
    // An unknown country or topic is not a page: a 404 before any D1 read.
    const country = list[1] ? list[1].toUpperCase() : null;
    if (country !== null && !isCountryPage(country)) return notFound(lang);
    const topic = readTopic(url.searchParams);
    if (topic === undefined) return notFound(lang);
    const filter = { country, topic };
    const before = readBefore(url.searchParams);
    // Only Global's first page opens a menu (Local's fallback); elsewhere the parameter is dropped.
    const menu = country === null && before === null ? readMenu(url.searchParams) : null;
    // One URL per view: a trailing slash, another order, a repeated or unused parameter go to it.
    const clean = listPath(lang, filter, before, menu);
    if (path + url.search !== clean) return { kind: "redirect", status: 301, body: null, location: origin + clean };
    return listReply(env, origin, lang, { filter, before, menu });
  }

  if (rest === "/local") {
    const topic = readTopic(url.searchParams);
    if (topic === undefined) return notFound(lang);
    return localReply(env, origin, lang, topic, ipCountry(request));
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
