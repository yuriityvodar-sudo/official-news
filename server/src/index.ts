import { handleApi } from "./api";
import type { Env } from "./env";
import { runFetcher } from "./fetcher";
import { runSummarizer } from "./summarizer";

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handleApi(request, env);
  },

  // Runs every minute (wrangler.jsonc). One run shares one free-plan budget:
  // at most 50 outside requests and 10 ms of CPU, so each step stays small.
  async scheduled(_controller: ScheduledController, env: Env): Promise<void> {
    await runFetcher(env);
    await runSummarizer(env, { maxArticles: 5 });
  },
} satisfies ExportedHandler<Env>;
