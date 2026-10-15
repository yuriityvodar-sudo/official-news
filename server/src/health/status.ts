import type { Env } from "../env";
import type { SourceCheck } from "../fetcher";
import { toStoredTime } from "../fetcher/text";

/** How a source's status follows its checks (docs/contract.md). */
export const HEALTH = {
  /** Checks that fail in a row before a source is broken: about an hour with 19 sources, 1 a minute. */
  failuresToBreak: 3,
  /** A source whose newest listed item is older than this is stale: it answers, but nothing new. */
  staleDays: 14,
} as const;

/**
 * Item 8. Gives each source checked in a fetcher run its status, right after the run:
 * - `active`: the check worked and the source listed an item from the last 14 days
 * - `stale`: the check worked, but nothing listed is newer than 14 days
 * - `broken`: 3 checks failed in a row (no answer, robots.txt, an HTTP error)
 * - `moved`: the same, but the list page answers 404 or 410, so it needs a new URL
 *
 * One failed check keeps the status, so a single timeout does not mark a source
 * broken. `blocked` is set by people (docs/sources.csv) and never changed here.
 */
export async function recordChecks(env: Env, checks: SourceCheck[], now = new Date()): Promise<void> {
  if (!checks.length) return;
  const staleBefore = toStoredTime(new Date(now.getTime() - HEALTH.staleDays * 86_400_000));
  await env.DB.batch(
    checks.map((check) =>
      // In SET, every column still holds its value from before this statement.
      env.DB.prepare(
        `UPDATE sources SET
           status = CASE
             WHEN ?1 THEN CASE WHEN last_item_at >= ?2 THEN 'active' ELSE 'stale' END
             WHEN failed_checks + 1 >= ?3 THEN CASE WHEN ?4 IN (404, 410) THEN 'moved' ELSE 'broken' END
             ELSE status
           END,
           failed_checks = CASE WHEN ?1 THEN 0 ELSE failed_checks + 1 END,
           last_ok_at = CASE WHEN ?1 THEN ?5 ELSE last_ok_at END,
           last_error = CASE WHEN ?1 THEN NULL ELSE ?6 END
         WHERE id = ?7 AND status != 'blocked'`,
      ).bind(check.ok ? 1 : 0, staleBefore, HEALTH.failuresToBreak, check.httpStatus, toStoredTime(now), check.error, check.sourceId),
    ),
  );
}
