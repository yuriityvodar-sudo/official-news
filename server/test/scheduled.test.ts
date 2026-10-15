import { createScheduledController } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { afterEach, describe, expect, it, vi } from "vitest";
import * as main from "../src/index";
import { CRON, ROTATION, STEPS, stepFor } from "../src/schedule";

const worker = main.default;

/** A time on 15 Oct 2026, UTC: 13:00 is an even minute, 13:01 an odd one. */
const at = (minute: number, second = 0, ms = 0) => Date.UTC(2026, 9, 15, 13, minute, second, ms);

describe("cron trigger", () => {
  it("is the one schedule known to run, exactly as in wrangler.jsonc", () => {
    // A second trigger was registered but never ran (#50); the steps take turns in this one instead.
    expect(CRON).toBe("* * * * *");
    expect(env.TEST_CRONS).toEqual(["* * * * *"]);
  });

  it("leaves src/index.ts with only its default export, which the Workers runtime needs to start", () => {
    // Every export of the main module is read as an entrypoint; an exported string once stopped the Worker from starting.
    expect(Object.keys(main)).toEqual(["default"]);
  });
});

describe("stepFor", () => {
  it("runs the fetcher on even minutes and the summarizer on odd ones", () => {
    expect([0, 1, 2, 3, 58, 59].map((m) => stepFor(at(m)))).toEqual(["fetcher", "summarizer", "fetcher", "summarizer", "fetcher", "summarizer"]);
  });

  it("gives every step in the rotation a turn, and two minutes in a row never run the same step", () => {
    for (let start = 0; start < ROTATION.length; start++) {
      const steps = ROTATION.map((_, i) => stepFor(at(start + i)));
      expect([...steps].sort()).toEqual([...ROTATION].sort());
      for (let i = 1; i < steps.length; i++) expect(steps[i]).not.toBe(steps[i - 1]);
    }
  });

  it("keeps one step for the whole minute, so a run that starts late still takes its own turn", () => {
    expect(stepFor(at(7, 59, 999))).toBe(stepFor(at(7)));
    expect(stepFor(at(8, 0, 1))).toBe(stepFor(at(8)));
  });

  it("has a run for every step in the rotation", () => {
    expect(Object.keys(STEPS).sort()).toEqual([...ROTATION].sort());
  });
});

describe("steps", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("the fetcher step checks the source next in line", async () => {
    await env.DB.prepare(
      `INSERT INTO sources (id, country, name, kind, url, language, verified_by, verified_at, status)
       VALUES ('xx-feed', 'XX', 'xx-feed', 'rss', 'https://gov.test/feed.xml', 'en', 'domain', '2026-10-14', 'active')`,
    ).run();
    const fetch = vi.spyOn(globalThis, "fetch").mockImplementation(async () => new Response("not found", { status: 404 }));

    expect(await STEPS.fetcher(env)).toMatchObject([{ sourceId: "xx-feed" }]);
    expect(fetch).toHaveBeenCalled();
  });

  it("the summarizer step sends at most 5 waiting articles to Workers AI", async () => {
    for (let i = 1; i <= 6; i++) {
      await env.DB.prepare(
        `INSERT INTO articles (id, source_id, url, original_title, published_at, fetched_at, text, original_language)
         VALUES (?, 'de-federal-government', ?, 'Kabinett beschließt', '2026-10-15T12:00:00Z', '2026-10-15T12:00:00Z', 'Text.', 'de')`,
      )
        .bind(`a${i}`, `https://example.gov/a${i}`)
        .run();
    }
    // An unusable answer, so the run goes on to the next article and every call shows.
    const ai = { run: vi.fn(async () => ({ choices: [{ finish_reason: "stop", message: { content: "not json" } }] })) };

    expect(await STEPS.summarizer({ ...env, AI: ai as unknown as Ai })).toHaveLength(5);
    expect(ai.run).toHaveBeenCalledTimes(5);
  });
});

describe("scheduled()", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  /** Runs the scheduled handler for `scheduledTime` with both steps replaced, and returns the spies. */
  async function runAt(scheduledTime: number) {
    const fetcher = vi.spyOn(STEPS, "fetcher").mockResolvedValue([]);
    const summarizer = vi.spyOn(STEPS, "summarizer").mockResolvedValue([]);
    await worker.scheduled(createScheduledController({ scheduledTime, cron: CRON }), env);
    return { fetcher, summarizer };
  }

  it("runs only the fetcher on an even minute", async () => {
    const { fetcher, summarizer } = await runAt(at(4, 0, 120));
    expect(fetcher).toHaveBeenCalledTimes(1);
    expect(fetcher).toHaveBeenCalledWith(env);
    expect(summarizer).not.toHaveBeenCalled();
  });

  it("runs only the summarizer on an odd minute", async () => {
    const { fetcher, summarizer } = await runAt(at(5, 0, 120));
    expect(summarizer).toHaveBeenCalledTimes(1);
    expect(summarizer).toHaveBeenCalledWith(env);
    expect(fetcher).not.toHaveBeenCalled();
  });
});
