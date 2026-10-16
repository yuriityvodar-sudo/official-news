// The Worker `site` (#88, wrangler.site.jsonc). Only the default export lives
// here: the Workers runtime treats every other export of the main module as an
// entrypoint. The site itself is handler.ts.
import type { SiteEnv } from "./env";
import { handleSite } from "./handler";

export default {
  fetch(request: Request, env: SiteEnv): Promise<Response> {
    return handleSite(request, env);
  },
} satisfies ExportedHandler<SiteEnv>;
