import { handleApi } from "./api";
import type { Env } from "./env";
import { runFetcher } from "./fetcher";
import { runCleanup } from "./health/cleanup";
import { recordChecks } from "./health/status";
import { runSummarizer } from "./summarizer";
import { TRANSLATIONS_PER_RUN, runTranslator } from "./translator";

/**
 * The cron triggers in wrangler.jsonc. Each trigger is its own run with its own
 * free-plan budget (at most 50 outside requests and 10 ms of CPU), so the AI
 * steps never share the fetcher's CPU (#41). The summarizer runs every odd
 * minute, the translator (#46) every even one. A newly added Cloudflare
 * schedule can take about an hour to start firing (#50).
 */
export const CRONS = {
  fetcher: "* * * * *",
  summarizer: "1-59/2 * * * *",
  translator: "0-58/2 * * * *",
  cleanup: "17 3 * * *",
} as const;

/** The step a cron trigger runs; anything else (such as a local test run) is the fetcher. */
export function stepFor(cron: string): keyof typeof CRONS {
  const steps = Object.keys(CRONS) as (keyof typeof CRONS)[];
  return steps.find((step) => CRONS[step] === cron) ?? "fetcher";
}

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handleApi(request, env);
  },

  async scheduled(controller: ScheduledController, env: Env): Promise<void> {
    const step = stepFor(controller.cron);
    if (step === "summarizer") {
      await runSummarizer(env, { maxArticles: 5 });
    } else if (step === "translator") {
      await runTranslator(env, { maxTranslations: TRANSLATIONS_PER_RUN });
    } else if (step === "cleanup") {
      await runCleanup(env);
    } else {
      // Every check gives its source a status straight away (item 8).
      await recordChecks(env, await runFetcher(env));
    }
  },
} satisfies ExportedHandler<Env>;
