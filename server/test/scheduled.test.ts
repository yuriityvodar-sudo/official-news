import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { CRONS, stepFor } from "../src/index";

describe("cron triggers", () => {
  it("runs the summarizer in its own trigger and the fetcher in the other", () => {
    expect(stepFor(CRONS.summarizer)).toBe("summarizer");
    expect(stepFor(CRONS.fetcher)).toBe("fetcher");
  });

  it("knows every trigger in wrangler.jsonc, so no step is left without a run", () => {
    expect([...env.TEST_CRONS].sort()).toEqual(Object.values(CRONS).sort());
  });
});
