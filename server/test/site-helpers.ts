// Shared by the website tests (#88): the site's handler on the test database.
import { env } from "cloudflare:workers";
import { handleSite } from "../src/site/handler";

export const ORIGIN = "https://site.test";

export const siteEnv = () => ({ DB: env.DB, SITE_ORIGIN: ORIGIN });

export async function site(path: string, init: RequestInit = {}, host = "site.test", e = siteEnv()) {
  const response = await handleSite(new Request(`https://${host}${path}`, init), e);
  return { status: response.status, headers: response.headers, body: await response.text() };
}
