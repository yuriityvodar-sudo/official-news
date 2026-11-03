// Every visitor of the website, also those who decline cookies (#60, Yurii
// 3 Nov): Cloudflare Web Analytics' cookieless beacon (docs/setup.md), read
// from Cloudflare's GraphQL with the read-only token "Outer News admin
// analytics" (Account Analytics: Read, the Outer News account only). Visits
// and page views per day, the whole account's Web Analytics, which is the one
// site outernews.app.
import type { AdminEnv } from "./env";

const GRAPHQL = "https://api.cloudflare.com/client/v4/graphql";

/** A day's visits and page views from Cloudflare. */
export interface CloudflareDay {
  visits: number;
  pageViews: number;
}

const QUERY = `query ($account: String!, $start: Date!, $end: Date!) {
  viewer {
    accounts(filter: { accountTag: $account }) {
      rumPageloadEventsAdaptiveGroups(limit: 100, filter: { date_geq: $start, date_leq: $end }, orderBy: [date_ASC]) {
        count
        sum { visits }
        dimensions { date }
      }
    }
  }
}`;

/** Each day's visits and page views from `start` to `end` (UTC dates); throws with Cloudflare's reason. */
export async function cloudflareDays(env: AdminEnv, start: string, end: string, fetcher: typeof fetch = fetch): Promise<Map<string, CloudflareDay>> {
  if (!env.CF_ANALYTICS_TOKEN) throw new Error("No Cloudflare analytics token yet (CF_ANALYTICS_TOKEN)");
  const response = await fetcher(GRAPHQL, {
    method: "POST",
    headers: { authorization: `Bearer ${env.CF_ANALYTICS_TOKEN}`, "content-type": "application/json" },
    body: JSON.stringify({ query: QUERY, variables: { account: env.CF_ACCOUNT_ID, start, end } }),
  });
  type Group = { count: number; sum: { visits: number }; dimensions: { date: string } };
  const body = (await response.json().catch(() => null)) as {
    data?: { viewer?: { accounts?: { rumPageloadEventsAdaptiveGroups?: Group[] }[] } };
    errors?: { message?: string }[] | null;
  } | null;
  if (!response.ok || !body || body.errors?.length) {
    throw new Error(`Cloudflare: HTTP ${response.status} ${body?.errors?.[0]?.message ?? ""}`.trim().replace(/[<>&]/g, ""));
  }
  const groups = body.data?.viewer?.accounts?.[0]?.rumPageloadEventsAdaptiveGroups ?? [];
  return new Map(groups.map((g) => [g.dimensions.date, { visits: g.sum.visits, pageViews: g.count }]));
}

/** The days of a range summed. */
export function sumCloudflare(days: Map<string, CloudflareDay>, start: string, end: string): CloudflareDay {
  let visits = 0;
  let pageViews = 0;
  for (const [date, day] of days) {
    if (date < start || date > end) continue;
    visits += day.visits;
    pageViews += day.pageViews;
  }
  return { visits, pageViews };
}
