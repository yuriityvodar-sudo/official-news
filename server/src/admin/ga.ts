// Google Analytics' Data API, read only, as the analytics-reader service
// account (docs/setup.md): one batch of five reports per tab and the custom
// dimensions apart, so one with no data yet never fails the tab. Copied in
// spirit from LyFi's report (its lessons: batch the reports, at most a few
// in flight, a custom dimension is "unknown" before the day it was made).
import { type ServiceAccount, TOKEN_URL, parseServiceAccount, signedJwt } from "../push/fcm";
import type { AdminEnv } from "./env";
import type { SelfKey } from "./selfkey";

/** Where ADMIN_KV keeps the self-made key (selfkey.ts). */
export const KEY_NAME = "google-key";

/** The account to sign in as: the self-made key, or a JSON key secret when one is set. Null when neither exists yet. */
export async function account(env: AdminEnv): Promise<ServiceAccount | null> {
  if (env.GA_SERVICE_ACCOUNT) return parseServiceAccount(env.GA_SERVICE_ACCOUNT, "GA_SERVICE_ACCOUNT");
  const key = await env.ADMIN_KV.get<SelfKey>(KEY_NAME, "json");
  return key ? { client_email: env.GA_CLIENT_EMAIL, private_key: key.privateKeyPem, project_id: "" } : null;
}

const SCOPE = "https://www.googleapis.com/auth/analytics.readonly https://www.googleapis.com/auth/webmasters.readonly";
const API = "https://analyticsdata.googleapis.com/v1beta/properties";

let token: { email: string; value: string; until: number } | undefined;

async function accessToken(env: AdminEnv, fetcher: typeof fetch): Promise<string> {
  const who = await account(env);
  if (!who) throw new Error("No Google key yet: press Connect Google Analytics");
  if (token && token.email === who.client_email && token.until > Date.now()) return token.value;
  const assertion = await signedJwt(who, new Date(), SCOPE, "the admin page's Google key");
  const response = await fetcher(TOKEN_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }).toString(),
  });
  const body = (await response.json().catch(() => null)) as { access_token?: string; expires_in?: number; error_description?: string } | null;
  if (!response.ok || !body?.access_token) throw new Error(`Google sign-in: HTTP ${response.status} ${body?.error_description ?? ""}`.trim());
  token = { email: who.client_email, value: body.access_token, until: Date.now() + ((body.expires_in ?? 3600) - 300) * 1000 };
  return token.value;
}

/** One report's rows: the dimension values joined, and the metric values as numbers. */
export interface Rows {
  rows: { key: string[]; values: number[] }[];
}

export type Request = Record<string, unknown>;

function rows(report: { rows?: { dimensionValues?: { value: string }[]; metricValues?: { value: string }[] }[] }): Rows {
  return {
    rows: (report.rows ?? []).map((r) => ({
      key: (r.dimensionValues ?? []).map((d) => d.value),
      values: (r.metricValues ?? []).map((m) => Number(m.value) || 0),
    })),
  };
}

/** Up to five reports in one request. */
export async function batch(env: AdminEnv, requests: Request[], fetcher: typeof fetch = fetch): Promise<Rows[]> {
  const response = await fetcher(`${API}/${env.GA_PROPERTY}:batchRunReports`, {
    method: "POST",
    headers: { authorization: `Bearer ${await accessToken(env, fetcher)}`, "content-type": "application/json" },
    body: JSON.stringify({ requests }),
  });
  const body = (await response.json().catch(() => null)) as { reports?: Parameters<typeof rows>[0][]; error?: { message?: string } } | null;
  if (!response.ok || !body?.reports) throw new Error(`Google Analytics: HTTP ${response.status} ${body?.error?.message ?? ""}`.trim());
  return body.reports.map(rows);
}

/** One report on its own; null when Google refuses it (a custom dimension with no data yet). */
export async function single(env: AdminEnv, request: Request, fetcher: typeof fetch = fetch): Promise<Rows | null> {
  try {
    return (await batch(env, [request], fetcher))[0];
  } catch {
    return null;
  }
}

/** Forgets the cached sign-in, as after a new key. */
export const forgetToken = () => {
  token = undefined;
};
