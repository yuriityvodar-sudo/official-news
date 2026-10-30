// What the site shows is what the app's API answers (#88). An article page
// is a rendering of `GET /articles/:id`, run through the API's own handler
// inside the same request (no second Worker invocation, no SQL of the site's
// own), so the visibility rules (released, not hidden, the translation that is
// shown, the source's name in the language) live in one place for the app and
// the site. A list page is the language's snapshot of that feed
// (api/snapshot.ts: one D1 row, built from the API's own queries by the api
// Worker's cron when the feed changes), filtered and paged in the Worker
// (snapshot.ts), since 30 Oct, when crawlers' list pages used up D1's free rows
// in a day; without a fresh snapshot the list is the API's queries as before.
// The rules are bundled into this Worker: they change on the site when
// `deploy:site` runs, right after the api deploy (.github/workflows/deploy.yml).
import { type toArticle, encodeCursor, handleApi } from "../api";
import { type SnapshotArticle, readSnapshot } from "../api/snapshot";
import { rankTopics } from "../api/filters";
import type { Env } from "../env";
import type { SiteEnv } from "./env";
import type { Topic } from "../summarizer/schema";
import { snapshotPage, snapshotTopics } from "./snapshot";
import { SITE_LANGS, type SiteLang } from "./texts";
import type { GroupId } from "../api/filters";
import type { ListFilter, Place } from "./urls";

/** An article as the API returns it (docs/contract.md); `lang` in a language other than English. */
export type ApiArticle = ReturnType<typeof toArticle> & { lang?: string };

/** An article as a list shows it: the snapshot's fields, which an API article has too. */
export type ListArticle = SnapshotArticle;

export interface ApiList {
  items: ListArticle[];
  nextCursor: string | null;
  top: ListArticle[];
  translationsDelayed?: boolean;
}

/** The API failed (its own 500): the site answers 500 too, never a cached 404. */
export class ApiError extends Error {}

/** The API's env from the site's: the database only. The site has no AI binding and no secrets to pass. */
const apiEnv = (env: SiteEnv) => ({ DB: env.DB }) as Env;

/** One API call, in process. The article routes read `env.DB` only. */
async function api<T>(env: SiteEnv, path: string): Promise<T | null> {
  const response = await handleApi(new Request(`https://api.internal${path}`), apiEnv(env));
  if (response.status === 404) return null;
  if (response.status !== 200) throw new ApiError(`API ${response.status} for ${path.split("?")[0]}`);
  return (await response.json()) as T;
}

/**
 * The article in every language the site has, as the API answers
 * `GET /articles/:id?lang=` for each, all at once: the languages it is shown in
 * (200), and so the page's status, its alternates and each one's slug.
 */
export async function articleInLanguages(env: SiteEnv, id: string): Promise<Partial<Record<SiteLang, ApiArticle>>> {
  const path = `/articles/${encodeURIComponent(id)}`;
  const answers = await Promise.all(SITE_LANGS.map((lang) => api<ApiArticle>(env, lang === "en" ? path : `${path}?lang=${lang}`)));
  const shown: Partial<Record<SiteLang, ApiArticle>> = {};
  SITE_LANGS.forEach((lang, i) => {
    const article = answers[i];
    if (article) shown[lang] = article;
  });
  return shown;
}

/** The API's Where parameter for a place: `country=DE`, `group=g7`, or nothing for all countries. */
function setPlace(params: URLSearchParams, place: Place) {
  if (place === null) return;
  if ("country" in place) params.set("country", place.country);
  else params.set("group", place.group);
}

/**
 * A page of the latest list in `lang` from the API, as the app gets it: 20
 * articles, and top stories on the first, with the app's filters (#67, #68:
 * `country` or `group`, and `topic`). `before` is the site's paging parameter,
 * the feedSeq after which the page continues, turned into the API's own cursor
 * (a place in the feed, so the next page continues within the filter).
 */
async function latest(env: SiteEnv, lang: SiteLang, filter: ListFilter, before: number | null): Promise<ApiList> {
  const params = new URLSearchParams({ limit: "20" });
  if (lang !== "en") params.set("lang", lang);
  setPlace(params, filter.place);
  if (filter.topic) params.set("topic", filter.topic);
  if (before !== null) params.set("cursor", encodeCursor(before));
  const list = await api<ApiList>(env, `/articles?${params}`);
  if (!list) throw new ApiError("API 404 for /articles");
  return list;
}

export interface ApiTopic {
  id: Topic;
  name: string;
}

export interface ApiCountry {
  code: string;
  name: string;
}

export interface ApiGroup {
  id: GroupId;
  name: string;
  /** The `country` values of the articles the group shows (`EU` for the EU institutions). */
  members: string[];
}

/** The Where menu as GET /countries answers it: every group, then the countries with active sources. */
export interface ApiWhere {
  groups: ApiGroup[];
  countries: ApiCountry[];
}

/** What the two menus offer: on the first page of a list only. */
export interface Menus {
  where: ApiWhere;
  topics: ApiTopic[];
}

/** The Topics menu from the API: `GET /topics`, the topics with articles in that place's (or the whole) feed in `lang`, busiest first. */
async function topicsMenu(env: SiteEnv, lang: SiteLang, place: Place): Promise<ApiTopic[]> {
  const params = new URLSearchParams();
  if (lang !== "en") params.set("lang", lang);
  setPlace(params, place);
  const query = params.toString();
  const answer = await api<{ topics: ApiTopic[] }>(env, query ? `/topics?${query}` : "/topics");
  if (!answer) throw new ApiError("API 404 for /topics");
  return answer.topics;
}

/**
 * The Where menu from the API: `GET /countries`, its groups (always all of
 * them, in their fixed order) and the countries with active sources, named in
 * `lang` and sorted by that name.
 */
async function whereMenu(env: SiteEnv, lang: SiteLang): Promise<ApiWhere> {
  const answer = await api<ApiWhere>(env, lang === "en" ? "/countries" : `/countries?lang=${lang}`);
  if (!answer) throw new ApiError("API 404 for /countries");
  return { groups: answer.groups, countries: answer.countries };
}

/** Which list: its filters and its page (`before`, null for the first). */
export interface ListView {
  filter: ListFilter;
  before: number | null;
}

/** What a list page shows: the page, and on a first page what the menus offer. */
export interface ListData {
  list: ApiList;
  menus: Menus | null;
}

/**
 * A list page's data from the API's queries, the way before the snapshot and
 * the way while there is no fresh one: the API's page with its filters and, on
 * a first page, what the two menus offer (GET /countries; GET /topics for the
 * place), all in this one request. A later page shows its filters without
 * menus. The Topics menu counts the place's (or the whole) feed without a
 * topic; a country's or a small group's first page without a topic often holds
 * all of it, and then the menu is its articles' topics counted as GET /topics
 * counts them (rankTopics), which saves walking the feed a second time.
 */
async function listDataFromApi(env: SiteEnv, lang: SiteLang, view: ListView): Promise<ListData> {
  const { filter, before } = view;
  if (before !== null) return { list: await latest(env, lang, filter, before), menus: null };
  const mayHoldAll = filter.place !== null && filter.topic === null;
  const [list, where, asked] = await Promise.all([
    latest(env, lang, filter, null),
    whereMenu(env, lang),
    mayHoldAll ? null : topicsMenu(env, lang, filter.place),
  ]);
  const topics =
    asked ?? (list.nextCursor === null ? rankTopics(list.items.map((a) => a.topics), lang) : await topicsMenu(env, lang, filter.place));
  return { list, menus: { where, topics } };
}

/**
 * A list page's data in `lang`: from the language's snapshot, one D1 row
 * whatever the filter and the page (the page, the top stories and both menus
 * are worked out from it, snapshot.ts); when there is none or it is older than
 * 30 minutes (the cron stopped; readSnapshot logs it), from the API's queries,
 * so the site never breaks.
 */
export async function listData(env: SiteEnv, lang: SiteLang, view: ListView, now = new Date()): Promise<ListData> {
  const snapshot = await readSnapshot(apiEnv(env), lang, now);
  if (!snapshot) return listDataFromApi(env, lang, view);
  const list = snapshotPage(snapshot, view.filter, view.before, now);
  const menus = view.before === null ? { where: snapshot.where, topics: snapshotTopics(snapshot, lang, view.filter.place) } : null;
  return { list, menus };
}

/** Pages of 50 the sitemap reads at most per language from the API (the API's 7 days are about 300 articles today). */
const SITEMAP_PAGES = 10;

/** Every article of the API's 7 days in `lang`, for the sitemap: the language's snapshot, else the API's pages of 50, newest first. */
export async function allLatest(env: SiteEnv, lang: SiteLang, now = new Date()): Promise<ListArticle[]> {
  const snapshot = await readSnapshot(apiEnv(env), lang, now);
  if (snapshot) return snapshot.articles;
  const out: ListArticle[] = [];
  let cursor: string | null = null;
  for (let page = 0; page < SITEMAP_PAGES; page++) {
    const params = new URLSearchParams({ limit: "50" });
    if (lang !== "en") params.set("lang", lang);
    if (cursor) params.set("cursor", cursor);
    const list: ApiList | null = await api<ApiList>(env, `/articles?${params}`);
    if (!list) throw new ApiError("API 404 for /articles");
    out.push(...list.items);
    cursor = list.nextCursor;
    if (!cursor) break;
  }
  return out;
}
