import { handleApi } from "./api";
import { snapshotStep } from "./api/snapshot";
import type { Env } from "./env";
import { runFetcher } from "./fetcher";
import { runCleanup } from "./health/cleanup";
import { recordChecks } from "./health/status";
import { popularityStep } from "./popularity";
import { runPush } from "./push";
import { runSummarizer } from "./summarizer";
import { sendReplyPushes } from "./support/cron";
import { TRANSLATIONS_PER_RUN, releaseReady, runTranslator, translatorRunning } from "./translator";

/**
 * The cron triggers in wrangler.jsonc. Each trigger is its own run with its own
 * free-plan budget (at most 50 outside requests and 10 ms of CPU), so the AI
 * steps never share the fetcher's CPU (#41). The summarizer runs every odd
 * minute, the translator (#46) every even one. A newly added Cloudflare
 * schedule can take about an hour to start firing (#50). Both end with the
 * release (translator/release.ts), so a decision reaches the feed also while
 * the translator's trigger is not firing. The translator's run then sends the
 * push notifications (push/index.ts, #62): at most one per language; while the
 * translator is not running, the summarizer's run sends them instead. Both
 * runs end with the website's snapshot of one language (api/snapshot.ts), so
 * each language gets a run every 5 minutes and is rebuilt when its feed changed.
 * Every 4th minute the summarizer's run also checks one item's popularity per
 * country (popularity/index.ts, #230 step 4).
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

/**
 * The push step at the end of a run. An error is logged, never thrown: a push
 * never breaks the translator, the summarizer or their release. With
 * `unlessTranslatorRuns` (the summarizer), it first reads whether the
 * translator ran in the last 10 minutes and then leaves the pushes to it.
 */
async function pushStep(env: Env, unlessTranslatorRuns = false): Promise<void> {
  try {
    // Replies to readers' messages (#220), in every run: a claim keeps two overlapping runs from both sending one.
    await sendReplyPushes(env);
  } catch (error) {
    console.error(JSON.stringify({ message: "support push error", error: error instanceof Error ? error.message : String(error) }));
  }
  try {
    if (unlessTranslatorRuns && (await translatorRunning(env, new Date()))) return;
    await runPush(env);
  } catch (error) {
    console.error(JSON.stringify({ message: "push error", error: error instanceof Error ? error.message : String(error) }));
  }
}

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handleApi(request, env);
  },

  async scheduled(controller: ScheduledController, env: Env): Promise<void> {
    const step = stepFor(controller.cron);
    if (step === "summarizer") {
      try {
        await runSummarizer(env, { maxArticles: 5 });
      } finally {
        // Releases what is ready, and everything summarized while the translator is not running.
        const released = await releaseReady(env, new Date());
        if (released.length) console.log(JSON.stringify({ message: "summarizer release", released }));
        // While the translator is not running, its pushes too (#62). A claim in push_log
        // keeps the two runs from both sending, also when they overlap.
        await pushStep(env, true);
        await snapshotStep(env, controller.scheduledTime);
        // Every 4th minute, one item's popularity per country (#230 step 4).
        await popularityStep(env, controller.scheduledTime);
      }
    } else if (step === "translator") {
      try {
        await runTranslator(env, { maxTranslations: TRANSLATIONS_PER_RUN });
      } finally {
        // After the release, so a decision released in this run can go out at once.
        await pushStep(env);
        await snapshotStep(env, controller.scheduledTime);
      }
    } else if (step === "cleanup") {
      await runCleanup(env);
    } else {
      // Every check gives its source a status straight away (item 8).
      await recordChecks(env, await runFetcher(env));
    }
  },
} satisfies ExportedHandler<Env>;
