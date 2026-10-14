import type { Env } from "../env";

/** Item 8. Counts sources per status for `GET /health`. */
export async function sourceHealth(env: Env): Promise<Record<string, number>> {
  const { results } = await env.DB.prepare(
    "SELECT status, COUNT(*) AS n FROM sources GROUP BY status",
  ).all<{ status: string; n: number }>();
  return Object.fromEntries(results.map((r) => [r.status, r.n]));
}
