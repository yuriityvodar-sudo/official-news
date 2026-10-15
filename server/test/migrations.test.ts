import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";

describe("migration 0006 (feed_seq)", () => {
  it("numbers visible articles without summarized_at too, without duplicates", async () => {
    const backfill = env.TEST_MIGRATIONS.find((m) => m.name.startsWith("0006"))?.queries.find((q) => q.includes("SET feed_seq"));
    expect(backfill).toBeDefined();
    // Two visible rows the AI step never stamped: before the guard both got feed_seq 0
    // and the unique index stopped the deploy.
    for (const id of ["no-stamp-1", "no-stamp-2"]) {
      await env.DB.prepare(
        `INSERT INTO articles (id, source_id, url, original_title, published_at, fetched_at, is_news)
         VALUES (?1, 'de-federal-government', 'https://example.gov/' || ?1, 'T', '2026-10-14T08:00:00Z', '2026-10-14T08:00:00Z', 1)`,
      )
        .bind(id)
        .run();
    }
    await env.DB.prepare("UPDATE articles SET feed_seq = NULL, added_at = NULL").run();

    await env.DB.prepare(backfill!).run();

    const { results } = await env.DB.prepare("SELECT feed_seq, added_at FROM articles WHERE is_news = 1").all<{
      feed_seq: number | null;
      added_at: string | null;
    }>();
    const numbers = results.map((r) => r.feed_seq);
    expect(numbers.every((n) => typeof n === "number" && n > 0)).toBe(true);
    expect(new Set(numbers).size).toBe(numbers.length);
    expect(results.every((r) => r.added_at)).toBe(true);
  });
});
