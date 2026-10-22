// What the site shows is what the app's API answers (#88): every page is a
// rendering of `GET /articles…`, run through the API's own handler inside the
// same request (no second Worker invocation, no SQL of the site's own), so the
// visibility rules (released, not hidden, the translation that is shown, the
// source's name in the language) live in one place for the app and the site.
// The rules are bundled into this Worker: they change on the site when
// `deploy:site` runs, right after the api deploy (.github/workflows/deploy.yml).
import { type toArticle, encodeCursor, handleApi } from "../api";
import type { Env } from "../env";
import type { SiteEnv } from "./env";
import type { Topic } from "../summarizer/schema";
import { SITE_LANGS, type SiteLang } from "./texts";
import type { GroupId } from "../api/filters";
import type { ListFilter, Place } from "./urls";

/** An article as the API returns it (docs/contract.md); `lang` in a language other than English. */
export type ApiArticle = ReturnType<typeof toArticle> & { lang?: string };

export interface ApiList {
  items: ApiArticle[];
  nextCursor: string | null;
  top: ApiArticle[];
  translationsDelayed?: boolean;
}

/** The API failed (its own 500): the site answers 500 too, never a cached 404. */
export class ApiError extends Error {}

/**
 * One API call, in process. The article routes read `env.DB` only, so the
 * site passes nothing else: it has no AI binding and no secrets to pass.
 */
async function api<T>(env: SiteEnv, path: string): Promise<T | null> {
  const response = await handleApi(new Request(`https://api.internal${path}`), { DB: env.DB } as Env);
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
 * A page of the latest list in `lang`, as the app gets it: 20 articles, and top
 * stories on the first, with the app's filters (#67, #68: `country` or
 * `group`, and `topic`). `before` is the site's paging parameter, the feedSeq
 * after which the page continues, turned into the API's own cursor (a place
 * in the feed, so the next page continues within the filter).
 */
export async function latest(env: SiteEnv, lang: SiteLang, filter: ListFilter, before: number | null): Promise<ApiList> {
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

/** The Topics menu: `GET /topics`, the topics with articles in that place's (or the whole) feed in `lang`, busiest first. */
export async function topicsMenu(env: SiteEnv, lang: SiteLang, place: Place): Promise<ApiTopic[]> {
  const params = new URLSearchParams();
  if (lang !== "en") params.set("lang", lang);
  setPlace(params, place);
  const query = params.toString();
  const answer = await api<{ topics: ApiTopic[] }>(env, query ? `/topics?${query}` : "/topics");
  if (!answer) throw new ApiError("API 404 for /topics");
  return answer.topics;
}

/**
 * The Where menu: `GET /countries`, its groups (always all of them, in their
 * fixed order) and the countries with active sources, named in `lang` and
 * sorted by that name.
 */
export async function whereMenu(env: SiteEnv, lang: SiteLang): Promise<ApiWhere> {
  const answer = await api<ApiWhere>(env, lang === "en" ? "/countries" : `/countries?lang=${lang}`);
  if (!answer) throw new ApiError("API 404 for /countries");
  return { groups: answer.groups, countries: answer.countries };
}
