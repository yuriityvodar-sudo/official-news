// Every visitor from Cloudflare Web Analytics (#60): visits and page views per
// day from Cloudflare's GraphQL, and its reason when it refuses.
import { describe, expect, it } from "vitest";
import { cloudflareDays, sumCloudflare } from "../src/admin/cloudflare";
import type { AdminEnv } from "../src/admin/env";

const env = { CF_ACCOUNT_ID: "acct", CF_ANALYTICS_TOKEN: "t" } as AdminEnv;

describe("Cloudflare's visits", () => {
  it("reads each day's visits and page views, and sums a range", async () => {
    const fetcher = (async () =>
      Response.json({
        data: { viewer: { accounts: [{ rumPageloadEventsAdaptiveGroups: [
          { count: 12, sum: { visits: 5 }, dimensions: { date: "2026-11-01" } },
          { count: 30, sum: { visits: 9 }, dimensions: { date: "2026-11-02" } },
        ] }] } },
        errors: null,
      })) as unknown as typeof fetch;
    const days = await cloudflareDays(env, "2026-11-01", "2026-11-02", fetcher);
    expect(sumCloudflare(days, "2026-11-01", "2026-11-02")).toEqual({ visits: 14, pageViews: 42 });
    expect(sumCloudflare(days, "2026-11-02", "2026-11-02")).toEqual({ visits: 9, pageViews: 30 });
  });

  it("says what is missing, or what Cloudflare said", async () => {
    await expect(cloudflareDays({ CF_ACCOUNT_ID: "acct" } as AdminEnv, "a", "b")).rejects.toThrow("No Cloudflare analytics token yet");
    const refused = (async () => Response.json({ data: null, errors: [{ message: "not authorized for that account" }] })) as unknown as typeof fetch;
    await expect(cloudflareDays(env, "2026-11-01", "2026-11-02", refused)).rejects.toThrow("Cloudflare: HTTP 200 not authorized for that account");
  });
});
