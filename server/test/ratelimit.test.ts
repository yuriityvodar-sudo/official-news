import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { API_LIMIT, handleApi } from "../src/api";
import type { Env } from "../src/env";

/** S2 of the release audit (4 Nov): a flood from one address is answered 429 before it reads D1. */
describe("the API's rate limit", () => {
  /** The API with a limiter that says yes or no, recording what it was asked about. */
  function limited(allow: boolean) {
    const keys: string[] = [];
    const limiter = {
      limit: async ({ key }: { key: string }) => {
        keys.push(key);
        return { success: allow };
      },
    } as unknown as RateLimit;
    return { keys, env: { ...(env as unknown as Env), API_LIMIT: limiter } };
  }
  const from = (path: string, address: string | null, init: RequestInit = {}) =>
    new Request(`https://api.test${path}`, { ...init, headers: address ? { "cf-connecting-ip": address } : {} });

  it("lets an address under the limit through, counted by its address", async () => {
    const { keys, env } = limited(true);
    const response = await handleApi(from("/topics", "203.0.113.7"), env);
    expect(response.status).toBe(200);
    expect(keys).toEqual(["203.0.113.7"]);
  });

  it("answers an address over the limit 429, never cached, with when to try again", async () => {
    const { env } = limited(false);
    const response = await handleApi(from("/articles", "203.0.113.7"), env);
    expect(response.status).toBe(429);
    expect(response.headers.get("retry-after")).toBe("60");
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(await response.json()).toEqual({ error: "Too many requests. Try again in a minute." });
  });

  it("never limits Apple's notifications, nor a request without an address", async () => {
    const { keys, env } = limited(false);
    const apple = await handleApi(from("/v1/appstore/notifications", "17.0.0.1", { method: "POST", body: "{}" }), env);
    expect(apple.status).not.toBe(429);
    const local = await handleApi(from("/topics", null), env);
    expect(local.status).toBe(200);
    expect(keys).toEqual([]);
  });

  it("allows far more than a reader's app asks: 300 a minute, as wrangler.jsonc has it (scripts/ratelimit.check.mjs)", () => {
    expect(API_LIMIT).toBe(300);
  });
});
