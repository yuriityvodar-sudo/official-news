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

describe("migration 0010 (release together)", () => {
  it("turns German off, keeps a manual pause manual, and indexes the articles waiting for release", async () => {
    const { results } = await env.DB.prepare("SELECT lang, enabled, paused, paused_reason, down_since FROM translation_langs ORDER BY lang").all();
    expect(results).toEqual([
      { lang: "de", enabled: 0, paused: 0, paused_reason: null, down_since: null },
      { lang: "es", enabled: 1, paused: 0, paused_reason: null, down_since: null },
      { lang: "ru", enabled: 1, paused: 0, paused_reason: null, down_since: null },
      { lang: "uk", enabled: 1, paused: 0, paused_reason: null, down_since: null },
    ]);
    const manual = env.TEST_MIGRATIONS.find((m) => m.name.startsWith("0010"))?.queries.find((q) => q.includes("paused_reason = 'manual'"));
    expect(manual).toBeDefined();
    await env.DB.prepare("UPDATE translation_langs SET paused = 1 WHERE lang = 'ru'").run();
    await env.DB.prepare(manual!).run();
    expect(await env.DB.prepare("SELECT paused_reason FROM translation_langs WHERE lang = 'ru'").first("paused_reason")).toBe("manual");
    const indexes = await env.DB.prepare("SELECT name FROM sqlite_master WHERE type = 'index' AND name IN ('articles_unreleased', 'articles_unnumbered', 'article_translations_lang_time')").all();
    expect(indexes.results).toEqual([{ name: "articles_unreleased" }]);
  });

  it("keeps the migration names in order after #55's 0007_source_health", () => {
    const names = env.TEST_MIGRATIONS.map((m) => m.name);
    const ours = ["0006_feed_seq.sql", "0008_translations.sql", "0009_translation_queue.sql", "0010_release_together.sql"];
    expect(names.filter((n) => ours.includes(n))).toEqual(ours);
    // Every number once: 0007 is #55's.
    const numbers = names.map((n) => n.slice(0, 4));
    expect(new Set(numbers).size).toBe(numbers.length);
    expect(names.filter((n) => n.startsWith("0007") && n !== "0007_source_health.sql")).toEqual([]);
  });
});

describe("migration 0022 (show events, #230)", () => {
  it("has the events of the last 2 days summarized again after the deploy, and leaves older ones, released ones and decisions alone", async () => {
    const show = env.TEST_MIGRATIONS.find((m) => m.name.startsWith("0022"))?.queries.find((q) => q.includes("summarized_at = NULL"));
    expect(show).toBeDefined();
    for (const id of ["ww-wikipedia-en", "ww-wikipedia-ru"]) {
      await env.DB.prepare(
        `INSERT OR IGNORE INTO sources (id, country, name, kind, url, config, language)
         VALUES (?, 'WW', 'Wikipedia: Current events', 'api', 'https://wikipedia.org', '{"currentEvents":"en","hidden":true}', 'en')`,
      )
        .bind(id)
        .run();
    }
    const day = (n: number) => `${new Date(Date.now() - n * 86_400_000).toISOString().slice(0, 19)}Z`;
    for (const [id, source, publishedAt, feedSeq] of [
      ["event-new", "ww-wikipedia-en", day(1), null],
      ["event-ru", "ww-wikipedia-ru", day(0.5), null],
      ["event-old", "ww-wikipedia-en", day(3), null],
      ["event-shown", "ww-wikipedia-en", day(1), 990001],
      ["decision", "de-federal-government", day(1), null],
    ] as const) {
      await env.DB.prepare(
        `INSERT INTO articles (id, source_id, url, original_title, published_at, fetched_at, is_news, decision_type, summarized_at, summary_attempts, feed_seq)
         VALUES (?1, ?2, 'https://example.org/' || ?1, 'T', ?3, ?3, 0, 'event', ?3, 1, ?4)`,
      )
        .bind(id, source, publishedAt, feedSeq)
        .run();
    }

    await env.DB.prepare(show!).run();

    const { results } = await env.DB.prepare(
      `SELECT id, summarized_at IS NULL AS again, summary_attempts, summary_claimed_at >= ? AS claimed FROM articles
       WHERE id IN ('event-new', 'event-ru', 'event-old', 'event-shown', 'decision') ORDER BY id`,
    )
      .bind(day(0.01))
      .all();
    expect(results).toEqual([
      { id: "decision", again: 0, summary_attempts: 1, claimed: null },
      { id: "event-new", again: 1, summary_attempts: 0, claimed: 1 },
      { id: "event-old", again: 0, summary_attempts: 1, claimed: null },
      { id: "event-ru", again: 1, summary_attempts: 0, claimed: 1 },
      { id: "event-shown", again: 0, summary_attempts: 1, claimed: null },
    ]);
  });
});
