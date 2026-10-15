import { env, exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { runFetcher, type SourceCheck } from "../src/fetcher";
import { runCleanup } from "../src/health/cleanup";
import { HEALTH, recordChecks } from "../src/health/status";

const NOW = new Date("2026-10-15T12:00:00Z");
const daysAgo = (days: number) => `${new Date(NOW.getTime() - days * 86_400_000).toISOString().slice(0, 19)}Z`;

async function addSource(id: string, status = "active", lastItemAt: string | null = daysAgo(1)) {
  await env.DB.prepare(
    `INSERT INTO sources (id, country, name, kind, url, language, verified_by, verified_at, status, last_item_at)
     VALUES (?, 'XX', ?, 'rss', ?, 'en', 'domain', '2026-10-14', ?, ?)`,
  )
    .bind(id, id, `https://${id}.test/feed`, status, lastItemAt)
    .run();
}

const source = (id: string) =>
  env.DB.prepare("SELECT status, failed_checks, last_ok_at, last_error FROM sources WHERE id = ?")
    .bind(id)
    .first<{ status: string; failed_checks: number; last_ok_at: string | null; last_error: string | null }>();

const ok = (sourceId: string): SourceCheck => ({ sourceId, ok: true, httpStatus: 200, found: 3, saved: 0, waiting: 0, undated: 0, offSite: 0, error: null });
const failed = (sourceId: string, httpStatus: number | null, error: string): SourceCheck => ({ ...ok(sourceId), ok: false, httpStatus, error });

describe("source status after each check", () => {
  it("is broken after 3 failed checks in a row, and active again after one that works", async () => {
    await addSource("xx-a");
    for (let i = 1; i < HEALTH.failuresToBreak; i++) {
      await recordChecks(env, [failed("xx-a", null, "The operation was aborted due to timeout")], NOW);
      // One or two failures keep the status: a single timeout is not a broken source.
      expect(await source("xx-a")).toMatchObject({ status: "active", failed_checks: i, last_error: "The operation was aborted due to timeout" });
    }
    await recordChecks(env, [failed("xx-a", 500, "HTTP 500")], NOW);
    expect(await source("xx-a")).toMatchObject({ status: "broken", failed_checks: 3, last_error: "HTTP 500" });

    await recordChecks(env, [ok("xx-a")], NOW);
    expect(await source("xx-a")).toMatchObject({ status: "active", failed_checks: 0, last_ok_at: "2026-10-15T12:00:00Z", last_error: null });
  });

  it("is moved when the list page keeps answering 404 or 410", async () => {
    await addSource("xx-gone");
    for (let i = 0; i < HEALTH.failuresToBreak; i++) await recordChecks(env, [failed("xx-gone", 404, "HTTP 404")], NOW);
    expect((await source("xx-gone"))?.status).toBe("moved");
  });

  it("is stale when it answers but lists nothing from the last 14 days", async () => {
    await addSource("xx-quiet", "active", daysAgo(HEALTH.staleDays + 1));
    await addSource("xx-never", "active", null);
    await addSource("xx-fresh", "stale", daysAgo(2));
    await recordChecks(env, [ok("xx-quiet"), ok("xx-never"), ok("xx-fresh")], NOW);
    expect((await source("xx-quiet"))?.status).toBe("stale");
    expect((await source("xx-never"))?.status).toBe("stale");
    expect((await source("xx-fresh"))?.status).toBe("active");
  });

  it("never changes a blocked source", async () => {
    await addSource("xx-blocked", "blocked");
    for (let i = 0; i < HEALTH.failuresToBreak; i++) await recordChecks(env, [failed("xx-blocked", null, "timeout")], NOW);
    await recordChecks(env, [ok("xx-blocked")], NOW);
    expect(await source("xx-blocked")).toMatchObject({ status: "blocked", failed_checks: 0, last_error: null });
  });

  it("a test source that never answers shows broken after the fetcher's checks (item 8 done when)", async () => {
    await addSource("xx-down");
    const down = (async () => {
      throw new Error("The operation was aborted due to timeout");
    }) as typeof globalThis.fetch;
    // The seed sources are never fetched, so each run takes xx-down.
    for (let minute = 0; minute < HEALTH.failuresToBreak; minute++) {
      const now = new Date(NOW.getTime() + minute * 60_000);
      await recordChecks(env, await runFetcher(env, { fetch: down, now }), now);
    }
    expect((await source("xx-down"))?.status).toBe("broken");
    const health = (await (await exports.default.fetch("https://api.test/health")).json()) as { sources: Record<string, number> };
    expect(health.sources.broken).toBe(1);
  });
});

describe("daily cleanup of old texts", () => {
  it("clears the text once it has expired and keeps the summary", async () => {
    const insert = (id: string, expires: string) =>
      env.DB.prepare(
        `INSERT INTO articles (id, source_id, url, original_title, published_at, fetched_at, text, text_expires_at, headline, summary, is_news)
         VALUES (?, 'de-federal-government', ?, 'Kabinett beschließt', ?, ?, 'Der Text.', ?, 'Cabinet decides', 'The summary.', 1)`,
      )
        .bind(id, `https://example.gov/${id}`, daysAgo(31), daysAgo(31), expires)
        .run();
    await insert("expired", daysAgo(1));
    await insert("kept", daysAgo(-1));

    expect(await runCleanup(env, NOW)).toBe(1);

    const rows = await env.DB.prepare("SELECT id, text, headline, summary FROM articles WHERE id IN ('expired', 'kept') ORDER BY id").all();
    expect(rows.results).toEqual([
      { id: "expired", text: null, headline: "Cabinet decides", summary: "The summary." },
      { id: "kept", text: "Der Text.", headline: "Cabinet decides", summary: "The summary." },
    ]);
  });
});
