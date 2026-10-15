import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { CRONS, stepFor } from "../src/index";

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

  it("knows every trigger in wrangler.jsonc, so no step is left without a run", () => {
    expect([...env.TEST_CRONS].sort()).toEqual(Object.values(CRONS).sort());
  });
});
