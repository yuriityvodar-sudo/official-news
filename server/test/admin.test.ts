// The admin page (#60): its second lock (Cloudflare Access's sign-in token,
// checked by the Worker) and what it shows from Google Analytics.
import { env as workers } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { handleAdmin } from "../src/admin/index";
import type { AdminEnv } from "../src/admin/env";
import { eventLabel } from "../src/admin/page";
import { postSupportMessage } from "../src/support";

const TEAM = "test-team";
/** A KV namespace in memory, as the Worker's ADMIN_KV. */
function memoryKv(): KVNamespace {
  const store = new Map<string, string>();
  return {
    get: async (key: string, type?: string) => {
      const v = store.get(key);
      return v === undefined ? null : type === "json" ? JSON.parse(v) : v;
    },
    put: async (key: string, value: string) => void store.set(key, value),
  } as unknown as KVNamespace;
}

const baseEnv = () => ({ DB: workers.DB, GA_PROPERTY: "123", ACCESS_TEAM: TEAM, ACCESS_AUD: "aud-admin", ADMIN_EMAILS: "yurii@example.com, roman@example.com", GA_CLIENT_EMAIL: "reader@x.iam.gserviceaccount.com" });
const env: AdminEnv = { ...baseEnv(), ADMIN_KV: memoryKv() };

const b64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const b64urlText = (text: string) => b64url(new TextEncoder().encode(text));

async function keyPair() {
  return (await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  )) as CryptoKeyPair;
}

async function token(privateKey: CryptoKey, claims: Record<string, unknown>, kid = "k1") {
  const head = b64urlText(JSON.stringify({ alg: "RS256", kid }));
  const body = b64urlText(JSON.stringify(claims));
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", privateKey, new TextEncoder().encode(`${head}.${body}`)));
  return `${head}.${body}.${b64url(sig)}`;
}

/** Access's keys, and Google's sign-in and reports, all answered here. */
function fakeFetch(publicJwk: JsonWebKey, reports: unknown[] = [], kid = "k1"): typeof fetch {
  return (async (input: RequestInfo | URL) => {
    const url = String(input);
    if (url === `https://${TEAM}.cloudflareaccess.com/cdn-cgi/access/certs`) return Response.json({ keys: [{ ...publicJwk, kid }] });
    if (url === "https://oauth2.googleapis.com/token") return Response.json({ access_token: "t", expires_in: 3600 });
    if (url.includes(":batchRunReports")) return Response.json({ reports });
    return new Response("unexpected", { status: 500 });
  }) as typeof fetch;
}

const claims = (email: string, minutes = 60) => ({ iss: `https://${TEAM}.cloudflareaccess.com`, aud: ["aud-admin"], email, exp: Math.floor(Date.now() / 1000) + minutes * 60 });

describe("the admin page's lock", () => {
  it("answers 403 without Access's token, for anyone not on the list, for an expired or forged token", async () => {
    const { publicKey, privateKey } = await keyPair();
    const other = await keyPair();
    const jwk = (await crypto.subtle.exportKey("jwk", publicKey)) as JsonWebKey;
    const go = async (t?: string) =>
      (await handleAdmin(new Request("https://admin.test/", { headers: t ? { "cf-access-jwt-assertion": t } : {} }), env, fakeFetch(jwk))).status;
    expect(await go()).toBe(403);
    expect(await go(await token(privateKey, claims("stranger@example.com")))).toBe(403);
    expect(await go(await token(privateKey, claims("yurii@example.com", -5)))).toBe(403);
    expect(await go(await token(other.privateKey, claims("yurii@example.com")))).toBe(403);
    expect(await go(await token(privateKey, { ...claims("yurii@example.com"), iss: "https://evil.cloudflareaccess.com" }))).toBe(403);
    expect(await go(await token(privateKey, { ...claims("yurii@example.com"), aud: ["another-app"] }))).toBe(403);
    expect(await go(await token(privateKey, { ...claims("yurii@example.com"), aud: undefined }))).toBe(403);
    expect(await go(await token(privateKey, claims("Yurii@Example.com")))).toBe(200);
  });

  it("is never cached or indexed, offers to connect Google when there is no key, and takes a rotated Access key", async () => {
    const { publicKey, privateKey } = await keyPair();
    const jwk = (await crypto.subtle.exportKey("jwk", publicKey)) as JsonWebKey;
    const response = await handleAdmin(
      new Request("https://admin.test/?tab=app", { headers: { "cf-access-jwt-assertion": await token(privateKey, claims("roman@example.com"), "k2") } }),
      env,
      fakeFetch(jwk, [], "k2"),
    );
    expect(response.headers.get("cache-control")).toBe("private, no-store");
    expect(response.headers.get("x-robots-tag")).toBe("noindex, nofollow");
    expect(await response.text()).toContain("Connect Google Analytics");
  });
});

describe("the website tab", () => {
  it("shows the totals against the period before, and the tables", async () => {
    const { publicKey, privateKey } = await keyPair();
    const jwk = (await crypto.subtle.exportKey("jwk", publicKey)) as JsonWebKey;
    // A real-looking key: generated here, never one of ours.
    const pk = (await crypto.subtle.exportKey("pkcs8", privateKey)) as ArrayBuffer;
    const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...new Uint8Array(pk)))}\n-----END PRIVATE KEY-----\n`;
    const withKey = { ...env, GA_SERVICE_ACCOUNT: JSON.stringify({ client_email: "r@x.iam.gserviceaccount.com", private_key: pem, project_id: "x" }) };
    const row = (key: string[], values: number[]) => ({ dimensionValues: key.map((value) => ({ value })), metricValues: values.map((v) => ({ value: String(v) })) });
    const reports = [
      { rows: [row(["now"], [120, 80, 150, 400, 6000]), row(["before"], [100, 70, 120, 300, 4000])] },
      { rows: [row(["google / organic"], [90, 70])] },
      { rows: [row(["/uk"], [200, 60])] },
      { rows: [row(["Ukraine"], [50])] },
      { rows: [row(["new"], [80, 90]), row(["returning"], [55, 60])] },
    ];
    const html = await (
      await handleAdmin(
        new Request("https://admin.test/?tab=website&days=7", { headers: { "cf-access-jwt-assertion": await token(privateKey, claims("yurii@example.com"), "k3") } }),
        withKey,
        fakeFetch(jwk, reports, "k3"),
      )
    ).text();
    expect(html).toContain("<b>120</b><span class=\"up\">+20%</span>");
    // Returning users come from Google's new/returning split, not users less new users.
    expect(html).toContain("Returning users</p><b>55</b>");
    expect(html).toContain("google / organic");
    expect(html).toContain("/uk");
    expect(html).toContain('aria-current="page">7 days');
  });
});

describe("event names in words", () => {
  it("names the app's events, and the design and scroll ones by their value", () => {
    expect(eventLabel("open_article")).toBe("Articles opened");
    expect(eventLabel("design_garnet")).toBe("Design chosen: garnet");
    expect(eventLabel("feed_scroll_20")).toBe("Scrolled 20 rows");
    expect(eventLabel("something_new")).toBe("something_new");
  });
});

describe("Connect Google Analytics (the page's own key)", () => {
  it("makes the key once, only from the page itself, keeps the private part, and shows only the certificate", async () => {
    const { publicKey, privateKey } = await keyPair();
    const jwk = (await crypto.subtle.exportKey("jwk", publicKey)) as JsonWebKey;
    const kv = memoryKv();
    const e: AdminEnv = { ...baseEnv(), ADMIN_KV: kv };
    const signed = async (init: RequestInit = {}) => ({ ...init, headers: { ...(init.headers as Record<string, string>), "cf-access-jwt-assertion": await token(privateKey, claims("yurii@example.com"), "k4") } });
    // From another site: refused, and no key is made.
    const foreign = await handleAdmin(new Request("https://admin.test/connect", await signed({ method: "POST", headers: { origin: "https://evil.test" } })), e, fakeFetch(jwk, [], "k4"));
    expect(foreign.status).toBe(403);
    expect(await kv.get("google-key")).toBeNull();
    // From the page: a key is made and the page shows its certificate once Google refuses the unknown key.
    const made = await handleAdmin(new Request("https://admin.test/connect", await signed({ method: "POST", headers: { origin: "https://admin.test" } })), e, fakeFetch(jwk, [], "k4"));
    expect(made.status).toBe(303);
    // As Chrome sends it under the page's no-referrer policy: Origin "null", Sec-Fetch-Site same-origin.
    const viaChrome = await handleAdmin(new Request("https://admin.test/connect", await signed({ method: "POST", headers: { origin: "null", "sec-fetch-site": "same-origin" } })), e, fakeFetch(jwk, [], "k4"));
    expect(viaChrome.status).toBe(303);
    const crossSite = await handleAdmin(new Request("https://admin.test/connect", await signed({ method: "POST", headers: { origin: "null", "sec-fetch-site": "cross-site" } })), e, fakeFetch(jwk, [], "k4"));
    expect(crossSite.status).toBe(403);
    const stored = (await kv.get("google-key", "json")) as { privateKeyPem: string; certificatePem: string };
    expect(stored.privateKeyPem).toMatch(/^-----BEGIN PRIVATE KEY-----\n/);
    expect(stored.certificatePem).toMatch(/^-----BEGIN CERTIFICATE-----\n/);
    // A second press keeps the same key.
    await handleAdmin(new Request("https://admin.test/connect", await signed({ method: "POST", headers: { origin: "https://admin.test" } })), e, fakeFetch(jwk, [], "k4"));
    expect(((await kv.get("google-key", "json")) as { certificatePem: string }).certificatePem).toBe(stored.certificatePem);
    const refusing = (async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes("cloudflareaccess.com")) return Response.json({ keys: [{ ...jwk, kid: "k4" }] });
      if (url === "https://oauth2.googleapis.com/token") return Response.json({ error: "invalid_grant", error_description: "Invalid JWT Signature." }, { status: 400 });
      return new Response("unexpected", { status: 500 });
    }) as typeof fetch;
    const html = await (await handleAdmin(new Request("https://admin.test/?tab=website", await signed()), e, refusing)).text();
    expect(html).toContain("upload this certificate to Google");
    expect(html).toContain(stored.certificatePem);
    expect(html).not.toContain("PRIVATE KEY");
  });

  it("makes a certificate that verifies with its own public key", async () => {
    const { makeSelfKey } = await import("../src/admin/selfkey");
    const key = await makeSelfKey("Test", new Date("2026-10-29T00:00:00Z"));
    const der = Uint8Array.from(atob(key.certificatePem.replace(/-----[^-]+-----|\s/g, "")), (c) => c.charCodeAt(0));
    expect(der[0]).toBe(0x30);
    // The certificate's TBS part, its signature, and the SPKI inside it: the signature checks out.
    const len = (at: number): [number, number] => (der[at] < 0x80 ? [der[at], at + 1] : [[...der.slice(at + 1, at + 1 + (der[at] & 0x7f))].reduce((n, b) => n * 256 + b, 0), at + 1 + (der[at] & 0x7f)]);
    const [, outerBody] = len(1);
    const tbsStart = outerBody;
    const [tbsLen, tbsBody] = len(tbsStart + 1);
    const tbs = der.slice(tbsStart, tbsBody + tbsLen);
    const sigStart = der.lastIndexOf(0x03, der.length - 256);
    const sig = der.slice(der.length - 256);
    expect(sigStart).toBeGreaterThan(0);
    const priv = key.privateKeyPem.replace(/-----[^-]+-----|\s/g, "");
    const pk = await crypto.subtle.importKey("pkcs8", Uint8Array.from(atob(priv), (c) => c.charCodeAt(0)), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, true, ["sign"]);
    const pubJwk = (await crypto.subtle.exportKey("jwk", pk)) as JsonWebKey;
    const pub = await crypto.subtle.importKey("jwk", { kty: "RSA", n: pubJwk.n, e: pubJwk.e, alg: "RS256", ext: true }, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
    expect(await crypto.subtle.verify("RSASSA-PKCS1-v1_5", pub, sig, tbs)).toBe(true);
  });
});

describe("the Messages tab (#220)", () => {
  const device = "device-0123456789abcdef0123456789abcdef";
  const at = new Date("2026-10-29T10:00:00Z");
  const write = (text: string, lang = "en", app = "1.0.0 (47)") => postSupportMessage({ device, text, lang, app }, "203.0.113.1", workers, at);
  const threadId = async () => (await workers.DB.prepare("SELECT id FROM support_threads").first<string>("id"))!;
  /** Requests to the page as Yurii, signed in through Access (or without the token, `withLock` false). */
  const signedIn = async (kid: string) => {
    const { publicKey, privateKey } = await keyPair();
    const jwk = (await crypto.subtle.exportKey("jwk", publicKey)) as JsonWebKey;
    const lock = await token(privateKey, claims("yurii@example.com"), kid);
    return (path: string, init: { method?: string; headers?: Record<string, string>; form?: Record<string, string> } = {}, withLock = true) =>
      handleAdmin(
        new Request(`https://admin.test${path}`, {
          method: init.method ?? "GET",
          headers: { ...(withLock ? { "cf-access-jwt-assertion": lock } : {}), ...init.headers },
          body: init.form ? new URLSearchParams(init.form) : undefined,
        }),
        env,
        fakeFetch(jwk, [], kid),
      );
  };

  it("shows each conversation, waiting ones first, with everything escaped and no Google needed", async () => {
    await write('<script>alert("x")</script> & more', "uk", "1.0.0 <47>");
    const go = await signedIn("m1");
    const response = await go("/?tab=messages");
    expect(response.status).toBe(200);
    expect(response.headers.get("content-security-policy")).toContain("form-action 'self'");
    const html = await response.text();
    expect(html).toContain('aria-current="page">Messages');
    expect(html).toContain("Waiting for us");
    expect(html).toContain("Ukrainian · app 1.0.0 &lt;47&gt; · started 2026-10-29 10:00 UTC");
    expect(html).toContain("&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt; &amp; more");
    expect(html).not.toContain("<script>");
    expect(html).toContain('action="/messages/reply"');
    expect(html).not.toContain("Connect Google Analytics");
    expect(html).not.toContain('aria-label="Period"');
  });

  it("replies and closes only from the page itself and behind the lock, then goes back to the tab", async () => {
    await write("Hello");
    const thread = await threadId();
    const go = await signedIn("m2");
    const count = async () => workers.DB.prepare("SELECT COUNT(*) AS n FROM support_messages WHERE sender = 'team'").first("n");
    const post = (path: string, headers: Record<string, string>, form: Record<string, string>, withLock = true) => go(path, { method: "POST", headers, form }, withLock);

    // From another site, or without Access's token: refused, nothing written.
    expect((await post("/messages/reply", { origin: "https://evil.test" }, { thread, text: "Hi" })).status).toBe(403);
    expect((await post("/messages/reply", { origin: "null", "sec-fetch-site": "cross-site" }, { thread, text: "Hi" })).status).toBe(403);
    expect((await post("/messages/reply", { "sec-fetch-site": "same-origin" }, { thread, text: "Hi" }, false)).status).toBe(403);
    expect((await post("/messages/close", { origin: "https://evil.test" }, { thread })).status).toBe(403);
    expect((await post("/messages/close", { "sec-fetch-site": "same-origin" }, { thread }, false)).status).toBe(403);
    expect(await count()).toBe(0);
    expect(await workers.DB.prepare("SELECT status FROM support_threads").first("status")).toBe("waiting");

    // An empty reply: an error, nothing written.
    expect((await post("/messages/reply", { "sec-fetch-site": "same-origin" }, { thread, text: "  " })).status).toBe(400);

    const sent = await post("/messages/reply", { origin: "null", "sec-fetch-site": "same-origin" }, { thread, text: "Thanks for writing." });
    expect(sent.status).toBe(303);
    expect(sent.headers.get("location")).toBe("/?tab=messages");
    expect(await count()).toBe(1);
    expect(await workers.DB.prepare("SELECT status, reply_push_pending FROM support_threads").first()).toEqual({ status: "answered", reply_push_pending: 1 });

    const closed = await post("/messages/close", { origin: "https://admin.test" }, { thread });
    expect(closed.status).toBe(303);
    expect(await workers.DB.prepare("SELECT status, closed_at IS NOT NULL AS c FROM support_threads").first()).toEqual({ status: "closed", c: 1 });
    // No reply into a closed conversation, and the page offers none.
    await post("/messages/reply", { "sec-fetch-site": "same-origin" }, { thread, text: "Late" });
    expect(await count()).toBe(1);
    const html = await (await go("/?tab=messages")).text();
    expect(html).toContain("Closed");
    expect(html).not.toContain('action="/messages/reply"');
  });
});
