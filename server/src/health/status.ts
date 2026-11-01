import type { Env } from "../env";
import type { SourceCheck } from "../fetcher";
import { toStoredTime } from "../fetcher/text";

/** How a source's status follows its checks (docs/contract.md). */
export const HEALTH = {
  /** Checks that fail in a row before a source is broken: about an hour, one every 10 minutes (LIMITS.failedCheckMinutes). */
  failuresToBreak: 6,
  /** A source whose newest listed item is older than this is stale: it answers, but nothing new. */
  staleDays: 14,
} as const;

/**
 * Item 8. Gives a source its status, right after a check that has something to tell (checkOneSource):
 * - `active`: the check worked and the source listed an item from the last 14 days
 * - `stale`: the check worked, but nothing listed is newer than 14 days
 * - `broken`: 6 checks failed in a row, about an hour (no answer, robots.txt, an HTTP error)
 * - `moved`: the same, but the list page answers 404 or 410, so it needs a new URL
 *
 * One failed check keeps the status, so a single timeout does not mark a source
 * broken. `blocked` is set by people (docs/sources.csv) and never changed here.
 * A news outlet's checks (#230) go to `outlets`, which has the same columns.
 */
export async function recordChecks(env: Env, checks: SourceCheck[], now = new Date(), table: "sources" | "outlets" = "sources"): Promise<void> {
  if (!checks.length) return;
  const staleBefore = toStoredTime(new Date(now.getTime() - HEALTH.staleDays * 86_400_000));
  await env.DB.batch(
    checks.map((check) =>
      // In SET, every column still holds its value from before this statement.
      env.DB.prepare(
        `UPDATE ${table} SET
           status = CASE
             WHEN ?1 THEN CASE WHEN last_item_at >= ?2 THEN 'active' ELSE 'stale' END
             WHEN failed_checks + 1 >= ?3 THEN CASE WHEN ?4 IN (404, 410) THEN 'moved' ELSE 'broken' END
             ELSE status
           END,
           failed_checks = CASE WHEN ?1 THEN 0 ELSE failed_checks + 1 END,
           last_ok_at = CASE WHEN ?1 THEN ?5 ELSE last_ok_at END,
           last_error = CASE WHEN ?1 THEN NULL ELSE ?6 END,
           last_checked_at = CASE WHEN ?8 THEN ?5 ELSE last_checked_at END
         WHERE id = ?7 AND status != 'blocked'`,
      ).bind(check.ok ? 1 : 0, staleBefore, HEALTH.failuresToBreak, check.httpStatus, toStoredTime(now), check.error, check.sourceId, check.full || !check.ok ? 1 : 0),
    ),
  );
}
