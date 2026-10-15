import type { Env } from "./env";
import { runFetcher } from "./fetcher";
import { runSummarizer } from "./summarizer";

/**
 * The one cron trigger in wrangler.jsonc. A second trigger (`1-59/2`, #45) was
 * registered on Cloudflare but never ran (#50), so every step uses this one,
 * which is known to run, and the steps take turns by minute.
 */
export const CRON = "* * * * *";

/**
 * The steps in the order they take turns, one per minute: the fetcher on even
 * minutes, the summarizer on odd ones. Each run does one step, so each step has
 * the free plan's whole per-run budget (at most 50 outside requests and 10 ms
 * of CPU, #41). A new step (such as the translator, #49) joins by adding its
 * name here and its call in STEPS; each step then runs less often.
 */
export const ROTATION = ["fetcher", "summarizer"] as const;

export type Step = (typeof ROTATION)[number];

/** The step for the minute a run was scheduled for (`controller.scheduledTime`, ms since 1970 UTC). */
export function stepFor(scheduledTime: number): Step {
  return ROTATION[Math.floor(scheduledTime / 60_000) % ROTATION.length];
}

/** What each step runs. An object, so a test can replace a step and see which one ran. */
export const STEPS: Record<Step, (env: Env) => Promise<unknown>> = {
  fetcher: (env) => runFetcher(env),
  summarizer: (env) => runSummarizer(env, { maxArticles: 5 }),
};
