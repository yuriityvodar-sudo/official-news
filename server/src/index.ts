import { handleApi } from "./api";
import type { Env } from "./env";
import { STEPS, stepFor } from "./schedule";

// Only the default export here: the Workers runtime reads every export of this
// file as an entrypoint and does not start if one is something else (such as a
// string constant), so shared constants live in their own modules.
export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handleApi(request, env);
  },

  /** One cron trigger, every minute; the steps take turns by minute (`ROTATION` in ./schedule). */
  async scheduled(controller: ScheduledController, env: Env): Promise<void> {
    const step = stepFor(controller.scheduledTime);
    // Every run says which step it took, so `wrangler tail` shows the rotation even
    // when a step has nothing to do (the summarizer logs nothing then).
    console.log(JSON.stringify({ message: "scheduled step", step, scheduledTime: new Date(controller.scheduledTime).toISOString() }));
    await STEPS[step](env);
  },
} satisfies ExportedHandler<Env>;
