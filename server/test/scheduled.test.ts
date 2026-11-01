import { createScheduledController } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import type { SourceCheck } from "../src/fetcher";
import type { SourceRow } from "../src/fetcher/types";
import worker, { CRONS, stepFor } from "../src/index";

describe("cron triggers", () => {
  it("runs each step in its own trigger", () => {
    expect(stepFor(CRONS.summarizer)).toBe("summarizer");
    expect(stepFor(CRONS.translator)).toBe("translator");
    expect(stepFor(CRONS.fetcher)).toBe("fetcher");
    // The translator on even minutes, the summarizer on odd ones (#46, #45).
    expect(CRONS.translator).toBe("0-58/2 * * * *");
    expect(CRONS.summarizer).toBe("1-59/2 * * * *");
    expect(stepFor(CRONS.cleanup)).toBe("cleanup");
  });

  it("checks each source through a call of its own", async () => {
    await env.DB.prepare("INSERT INTO sources (id, country, name, kind, url, status) VALUES ('xx-one', 'XX', 'One', 'rss', 'https://one.test/feed', 'active'), ('xx-two', 'XX', 'Two', 'rss', 'https://two.test/feed', 'active')").run();
    const called: string[] = [];
    const check = async (source: SourceRow) => {
      called.push(source.id);
      return { sourceId: source.id, ok: true, saved: 0, unchanged: true } as SourceCheck;
    };
    await worker.scheduled(createScheduledController({ cron: CRONS.fetcher }), env, { exports: { SourceChecker: { check } } } as unknown as ExecutionContext);
    expect(called.sort()).toEqual(["xx-one", "xx-two"]);
  });

  it("knows every trigger in wrangler.jsonc, so no step is left without a run", () => {
    expect([...env.TEST_CRONS].sort()).toEqual(Object.values(CRONS).sort());
  });
});
