import type { Env } from "../env";
import { toStoredTime } from "../fetcher/text";

/**
 * Item 8. Once a day, clears the saved text of articles whose `text_expires_at`
 * has passed (30 days after fetching). The summary, the original title and the
 * link stay, so the article reads the same in the app.
 */
export async function runCleanup(env: Env, now = new Date()): Promise<number> {
  const { meta } = await env.DB.prepare("UPDATE articles SET text = NULL WHERE text IS NOT NULL AND text_expires_at <= ?")
    .bind(toStoredTime(now))
    .run();
  const cleared = meta.changes ?? 0;
  console.log(JSON.stringify({ message: "cleanup run", cleared }));
  return cleared;
}
