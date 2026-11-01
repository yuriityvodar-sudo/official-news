import { WorkerEntrypoint } from "cloudflare:workers";
import { handleApi } from "./api";
import { snapshotStep } from "./api/snapshot";
import type { Env } from "./env";
import { type SourceCheck, checkOneSource, runFetcher } from "./fetcher";
import type { SourceRow } from "./fetcher/types";
import { runCleanup } from "./health/cleanup";
import { popularityStep } from "./popularity";
import { runPush } from "./push";
import { buildCountryStories, storiesStep } from "./stories";
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
 * country (popularity/index.ts, #230 step 4). Last, both build the stories of up
 * to 6 countries whose news outlets have new headlines (stories/index.ts, #230),
 * each in a call of its own (StoryBuilder).
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

/**
 * One source's check as a call of its own (#230, 1 Nov): Cloudflare counts 10 ms
 * of CPU and 50 outside requests per call, so sources never share them, and a
 * call stopped by a limit stops nothing else. Measured on a test Worker
 * (docs/decisions/2026-11-01-no-fetcher-line.md). Not reachable from the
 * internet: only the default export answers requests.
 */
export class SourceChecker extends WorkerEntrypoint<Env> {
  check(source: SourceRow): Promise<SourceCheck> {
    return checkOneSource(this.env, source);
  }
}

/** One country's stories (#230, src/stories/), as a call of its own: its own 10 ms of CPU for grouping its headlines. Not reachable from the internet. */
export class StoryBuilder extends WorkerEntrypoint<Env> {
  build(country: string, version: string): Promise<number> {
    return buildCountryStories(this.env, country, version);
  }
}

/** The stories step with each country in a call of its own, when the run has `ctx.exports` (storiesStep). */
const storyCalls = (ctx?: ExecutionContext) => {
  const builder = (ctx?.exports as unknown as { StoryBuilder?: Pick<StoryBuilder, "build"> } | undefined)?.StoryBuilder;
  return builder ? (country: string, version: string) => builder.build(country, version) : undefined;
};

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handleApi(request, env);
  },

  async scheduled(controller: ScheduledController, env: Env, ctx?: ExecutionContext): Promise<void> {
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
        // The countries whose outlets have new headlines get their stories again (#230).
        await storiesStep(env, storyCalls(ctx));
      }
    } else if (step === "translator") {
      try {
        await runTranslator(env, { maxTranslations: TRANSLATIONS_PER_RUN });
      } finally {
        // After the release, so a decision released in this run can go out at once.
        await pushStep(env);
        await snapshotStep(env, controller.scheduledTime);
        await storiesStep(env, storyCalls(ctx));
      }
    } else if (step === "cleanup") {
      await runCleanup(env);
    } else {
      const checker = (ctx?.exports as unknown as { SourceChecker?: Pick<SourceChecker, "check"> } | undefined)?.SourceChecker;
      await runFetcher(env, checker ? { call: (source) => checker.check(source) } : {});
    }
  },
} satisfies ExportedHandler<Env>;
