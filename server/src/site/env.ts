/** What the site Worker gets (wrangler.site.jsonc): the database and its own address. No AI, no secrets. */
export interface SiteEnv {
  DB: D1Database;
  /** `https://site.officialnews.workers.dev` today; every absolute URL on a page starts with it. */
  SITE_ORIGIN: string;
}
