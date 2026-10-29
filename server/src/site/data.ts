// What the site shows is what the app's API answers (#88): every page is a
// rendering of `GET /articles…`, run through the API's own handler inside the
// same request (no second Worker invocation, no SQL of the site's own), so the
// visibility rules (released, not hidden, the translation that is shown, the
// source's name in the language) live in one place for the app and the site.
// The rules are bundled into this Worker: they change on the site when
// `deploy:site` runs, right after the api deploy (.github/workflows/deploy.yml).
import { type toArticle, handleApi } from "../api";
import type { Env } from "../env";
import type { SiteEnv } from "./env";
import { SITE_LANGS, type SiteLang } from "./texts";

/** An article as the API returns it (docs/contract.md); `lang` in a language other than English. */
export type ApiArticle = ReturnType<typeof toArticle> & { lang?: string };

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
