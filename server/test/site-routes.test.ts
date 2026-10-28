// The website's routes and headers (#88): status and cache headers per kind of
// page, nothing indexed, one request per page view, no host in any page, and
// nothing from the data or the address ever becoming markup.
import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { ROBOTS_TXT } from "../src/site/handler";
import { CACHE } from "../src/site/respond";
import { INFO_PAGES, slugify } from "../src/site/urls";
import { SITE_LANGS } from "../src/site/texts";
import { hideSeed } from "./helpers";
import { ORIGIN, insertArticle, insertTranslation, reach, site, siteEnv, siteRowsRead as rowsRead, testId } from "./site-helpers";

const ID = testId(1);
const NOT_IN_UK = testId(2);
/** ID's own addresses: its slug is its headline in the language (site-helpers.ts's texts). */
const EN = `/en/de/${ID}-${slugify("Cabinet decision 0001 on the budget", "en")}`;
const UK = `/uk/de/${ID}-${slugify("[uk] Рішення 0001 про бюджет", "uk")}`;

beforeEach(async () => {
  await hideSeed();
  await insertArticle({ id: ID });
  await insertTranslation(ID, "uk");
  await insertArticle({ id: NOT_IN_UK });
});

/** [path, status, cache kind, content-language] for every kind of response. */
const ROUTES: [string, number, keyof typeof CACHE, string | null][] = [
  ["/", 200, "fixed", "en"],
  ["/robots.txt", 200, "fixed", null],
  ["/en", 200, "list", "en"],
  ["/uk?before=5", 200, "list", "uk"],
  [EN, 200, "article", "en"],
  [UK, 200, "article", "uk"],
  [`/en/de/${ID}`, 301, "moved", null],
  [`/uk/de/${ID}-slug`, 301, "moved", null],
  [`/uk/fr/${ID}`, 301, "moved", null],
  [`${EN}?fbclid=IwAR0abc`, 301, "redirect", null],
  [`/uk/de/${NOT_IN_UK}`, 404, "notInLanguage", "uk"],
  [`/en/de/${testId(99)}`, 404, "missing", "en"],
  ["/ru/about", 200, "fixed", "ru"],
  ["/es/privacy", 200, "fixed", "es"],
  ["/de/terms", 200, "fixed", "de"],
  ["/en/support", 200, "fixed", "en"],
  ["/nowhere", 404, "missing", "en"],
  ["/uk/nowhere", 404, "missing", "uk"],
  ["/en/de", 200, "list", "en"],
  ["/uk/de?topic=economy", 200, "list", "uk"],
  ["/en/g7", 200, "list", "en"],
  ["/uk/nato?topic=economy", 200, "list", "uk"],
  ["/en?topic=economy&before=5", 200, "list", "en"],
  ["/es/ua", 200, "list", "es"],
  ["/en/zz", 404, "missing", "en"],
  ["/en?topic=nonsense", 404, "missing", "en"],
  ["/en/de/economy", 404, "missing", "en"],
  ["/en/local", 404, "missing", "en"],
  ["/en?menu=where", 301, "redirect", null],
  ["/en/de/", 301, "redirect", null],
  ["/en/EU", 301, "redirect", null],
  ["/.well-known/apple-app-site-association", 404, "missing", "en"],
  ["/sitemap.xml", 404, "missing", "en"],
  ["/favicon.ico", 404, "icon", null],
  ["/apple-touch-icon.png", 200, "icon", null],
  ["/apple-touch-icon-precomposed.png", 200, "icon", null],
  ["/icon-512.png", 200, "icon", null],
  ["/en/", 301, "redirect", null],
  ["/en?utm_source=x", 301, "redirect", null],
  ["/?fbclid=1", 301, "redirect", null],
];

describe("every route", () => {
  for (const [path, status, kind, lang] of ROUTES) {
    it(`${path}: ${status}, ${kind} cache, noindex, the CSP, no cookie`, async () => {
      for (const method of ["GET", "HEAD"]) {
        const { status: got, headers, body } = await site(path, { method });
        expect(got).toBe(status);
        expect(headers.get("cache-control")).toBe(CACHE[kind].browser);
        expect(headers.get("cloudflare-cdn-cache-control")).toBe(CACHE[kind].edge);
        expect(headers.get("x-robots-tag")).toBe("noindex");
        expect(headers.get("x-content-type-options")).toBe("nosniff");
        expect(headers.get("content-security-policy")).toMatch(/^default-src 'none'; style-src 'sha256-[A-Za-z0-9+/]+=*'; img-src data:;/);
        expect(headers.get("content-language")).toBe(lang);
        expect(headers.get("set-cookie")).toBeNull();
        expect(headers.get("vary")).toBeNull();
        if (method === "HEAD") expect(body).toBe("");
      }
    });
  }

  it("sends a query a list or the landing page does not use to the clean URL, with no D1 read", async () => {
    for (const [path, location] of [
      ["/en?x=1", "/en"],
      ["/en?before=12&utm=1", "/en?before=12"],
      ["/en?before=0", "/en"],
      ["/en?before=1&before=2", "/en"],
      ["/en?before=abc", "/en"],
      ["/uk/?before=7", "/uk?before=7"],
      ["/?lang=uk", "/"],
    ]) {
      let response: Awaited<ReturnType<typeof site>> | undefined;
      expect(await rowsRead(async () => (response = await site(path)))).toBe(0);
      expect(response!.status).toBe(301);
      expect(response!.headers.get("location")).toBe(ORIGIN + location);
    }
  });

  it("answers 405 to other methods, never stored", async () => {
    for (const method of ["POST", "PUT", "DELETE"]) {
      const { status, headers } = await site("/en", { method });
      expect(status).toBe(405);
      expect(headers.get("allow")).toBe("GET, HEAD");
      expect(headers.get("cache-control")).toBe("no-store");
    }
  });

  it("answers 500, never stored, when D1 fails: never a cached 404", async () => {
    const broken = { ...siteEnv(), DB: { prepare: () => { throw new Error("D1 is down"); } } as unknown as D1Database };
    for (const path of ["/en", `/uk/de/${ID}`]) {
      const { status, headers, body } = await site(path, {}, "site.test", broken);
      expect(status).toBe(500);
      expect(headers.get("cache-control")).toBe("no-store");
      expect(headers.get("cloudflare-cdn-cache-control")).toBe("no-store");
      expect(body).not.toContain("D1 is down");
    }
  });

  it("serves robots.txt that disallows everything", async () => {
    expect((await site("/robots.txt")).body).toBe("User-agent: *\nDisallow: /\n");
  });

  const PAGES = ROUTES.filter(([p, s]) => (s < 300 || s >= 400) && !p.endsWith(".txt") && !p.endsWith(".ico") && !p.endsWith(".png"));

  it("says in every page's head exactly what its X-Robots-Tag says (one value, never two that disagree)", async () => {
    for (const [path] of PAGES) {
      const { headers, body } = await site(path);
      const meta = /<meta name="robots" content="([^"]+)">/.exec(body)?.[1];
      expect(meta, path).toBe(headers.get("x-robots-tag"));
    }
  });

  it("keeps every page noindex while robots.txt disallows everything (a crawler would never read anything else)", async () => {
    expect(ROBOTS_TXT).toMatch(/^Disallow: \/$/m);
    for (const [path] of PAGES) {
      const { headers, body } = await site(path);
      // Letting a page be indexed needs robots.txt to stop disallowing it first (docs/plan.md, open points).
      expect(headers.get("x-robots-tag"), path).toBe("noindex");
      expect(body, path).toContain('<meta name="robots" content="noindex">');
    }
  });
});

describe("one URL per article (#89 review)", () => {
  it("sends an address with a query (fbclid, utm_*) to the same address without it, with no D1 read", async () => {
    for (const [path, location] of [
      [`${EN}?fbclid=IwAR0abc`, EN],
      [`${UK}?utm_source=facebook&utm_medium=social`, UK],
      [`/uk/de/${ID}-old-slug?utm_campaign=x`, `/uk/de/${ID}-old-slug`],
    ] as const) {
      for (const method of ["GET", "HEAD"]) {
        let response: Awaited<ReturnType<typeof site>> | undefined;
        expect(await rowsRead(async () => (response = await site(path, { method }))), path).toBe(0);
        expect(response!.status, path).toBe(301);
        expect(response!.headers.get("location"), path).toBe(ORIGIN + location);
        expect(response!.headers.get("cloudflare-cdn-cache-control"), path).toBe(CACHE.redirect.edge);
      }
    }
  });

  it("sends another country, another slug or no slug to the article's own address, which is the page", async () => {
    for (const path of [`/en/de/${ID}`, `/en/fr/${ID}-cabinet-decision-0001-on-the-budget`, `/en/zz/${ID}-x`, `/en/DE/${EN.split("/").pop()}`, `/en/de/${ID}-`]) {
      const { status, headers, body } = await site(path);
      expect(status, path).toBe(301);
      expect(headers.get("location"), path).toBe(ORIGIN + EN);
      expect(headers.get("cache-control"), path).toBe(CACHE.moved.browser);
      expect(body).toBe("");
    }
    // In each language its own slug.
    expect((await site(`/uk/de/${ID}-cabinet-decision-0001-on-the-budget`)).headers.get("location")).toBe(ORIGIN + UK);
    // A link from Facebook with a stale slug: two hops at most, then the page.
    const first = await site(`/en/fr/${ID}-old?fbclid=1`);
    const second = await site(first.headers.get("location")!.slice(ORIGIN.length));
    expect(second.headers.get("location")).toBe(ORIGIN + EN);
    expect((await site(EN)).status).toBe(200);
  });

  it("follows a headline that is summarized again: the old address leads to the new one", async () => {
    await env.DB.prepare("UPDATE articles SET headline = 'Cabinet approves the 2027 budget' WHERE id = ?").bind(ID).run();
    const moved = await site(EN);
    expect(moved.status).toBe(301);
    expect(moved.headers.get("location")).toBe(`${ORIGIN}/en/de/${ID}-cabinet-approves-the-2027-budget`);
  });

  it("reads the article once to redirect, and keeps 404s as they were (no redirect for an article not in the language)", async () => {
    const rows = await rowsRead(() => site(`/en/zz/${ID}`));
    expect(rows).toBeGreaterThan(0);
    expect(rows).toBeLessThanOrEqual(20);
    expect((await site(`/uk/fr/${NOT_IN_UK}-x`)).status).toBe(404);
    expect((await site(`/en/fr/${testId(99)}-x`)).status).toBe(404);
  });
});

describe("one request per page view", () => {
  it("no page refers to anything it would have to load: no script, image, stylesheet, font or frame", async () => {
    await env.DB.prepare("UPDATE articles SET image_url = 'https://www.bundesregierung.de/picture.jpg' WHERE id = ?").bind(ID).run();
    const paths = [
      "/", "/en", "/uk", EN, UK, "/en/de", "/uk/de?topic=economy", "/en/g7", "/uk/nato?topic=health", "/en/ua",
      ...SITE_LANGS.flatMap((l) => INFO_PAGES.map((p) => `/${l}/${p}`)),
    ];
    for (const path of paths) {
      const { body } = await site(path);
      expect(body, path).not.toMatch(/<script|<iframe|<object|<embed|<video|<audio|<source|rel="stylesheet"|rel="preload"|rel="prefetch"|rel="preconnect"|rel="dns-prefetch"|@import|@font-face/i);
      // CSS url() only for data:, and the tab icon a data: URL (no /favicon.ico request).
      for (const m of body.matchAll(/url\(([^)]*)\)/g)) expect(m[1], path).toMatch(/^["']?data:/);
      expect(body).toMatch(/<link rel="icon" href="data:image\/png;base64,/);
      for (const m of body.matchAll(/<link rel="([^"]+)" [^>]*href="([^"]+)"/g)) {
        if (m[1] === "icon") expect(m[2]).toMatch(/^data:/);
        else if (m[1] === "apple-touch-icon") expect(m[2]).toBe("/apple-touch-icon.png");
        else expect(["canonical", "alternate"], `${path}: <link rel="${m[1]}">`).toContain(m[1]);
      }
      expect(body).not.toContain("picture.jpg");
    }
  });

  it("shows the Smart App Banner tag and no source picture", async () => {
    const { body } = await site(EN);
    expect(body).toContain('<meta name="apple-itunes-app" content="app-id=6822820350">');
  });
});

describe("the request's host", () => {
  it("never appears in a page: every absolute URL is SITE_ORIGIN's (the cache key has no host)", async () => {
    for (const path of ["/", "/en", UK, `/uk/de/${ID}`, `${UK}?utm_source=x`, "/es/about", "/en/", `/uk/de/${NOT_IN_UK}`, "/en/de", "/en/de/", "/en/G7", "/en?topic=economy&x=1"]) {
      const { body, headers } = await site(path, {}, "evil.test");
      expect(body).not.toContain("evil.test");
      expect(headers.get("location") ?? "").not.toContain("evil.test");
    }
    expect((await site(UK, {}, "evil.test")).body).toContain(`<link rel="canonical" href="${ORIGIN}${UK}">`);
    expect((await site(`/uk/de/${ID}`, {}, "evil.test")).headers.get("location")).toBe(ORIGIN + UK);
  });
});

describe("text from the data and the address", () => {
  const XSS = testId(3);
  beforeEach(async () => {
    await insertArticle({
      id: XSS,
      headline: `"><script>alert(1)</script>`,
      shortSummary: `<img src=x onerror=alert(1)>`,
      summary: `First <b>bold</b> & "quoted"\n\n<svg onload=alert(1)>`,
      originalUrl: "javascript:alert(1)",
      decisionType: `"><script>`,
      originalLanguage: `x" onmouseover="alert(1)`,
    });
    await env.DB.prepare(`UPDATE sources SET name = ? WHERE id = 'de-federal-government'`).bind(`O'Brien & "Co" <b>`).run();
  });

  it("is always escaped: no tag, no attribute, no javascript: link", async () => {
    for (const path of [`/en/de/${XSS}`, "/en"]) {
      const { status, body } = await reach(path);
      expect(status).toBe(200);
      expect(body).not.toMatch(/<script|<img|<svg onload|<b>bold/i);
      // No tag carries an event handler: the escaped text may say "onerror=", a tag never does.
      // (Attribute values are blanked first: a meta description may quote the escaped text.)
      expect(body.replace(/"[^"]*"/g, '""')).not.toMatch(/<[^>]*\son\w+=/i);
      expect(body).not.toMatch(/href="javascript:/i);
      expect(body).toContain("&quot;&gt;&lt;script&gt;alert(1)&lt;/script&gt;");
      expect(body).toContain("O&#39;Brien &amp; &quot;Co&quot; &lt;b&gt;");
    }
    const { body } = await reach(`/en/de/${XSS}`);
    // In <title> and in attributes (meta, Open Graph), quotes are escaped too.
    expect(body).toContain("<title>&quot;&gt;&lt;script&gt;alert(1)&lt;/script&gt; · Outer News</title>");
    expect(body).toMatch(/<meta property="og:title" content="&quot;&gt;&lt;script&gt;/);
    // No official link for a URL that is not https, and an unknown type gets no label.
    expect(body).not.toContain('class="official"');
    expect(body).not.toContain('class="kind"');
    expect(body).not.toMatch(/<span lang="x/);
  });

  it("keeps an https link that tries to break out of its attribute inside it", async () => {
    await env.DB.prepare("UPDATE articles SET url = ? WHERE id = ?").bind(`https://x.gov/"onmouseover=alert(1)`, XSS).run();
    const { body } = await reach(`/en/de/${XSS}`);
    expect(body).toContain('class="official" href="https://x.gov/%22onmouseover=alert(1)"');
  });

  it("never repeats the address in a page", async () => {
    for (const path of ["/en/<script>alert(1)</script>", "/en/de/%3Cscript%3E", `/en/de/${ID}x<b>`, "/%3Cscript%3E"]) {
      const { status, body } = await site(path);
      expect(status).toBe(404);
      // (The tab icon's data: URL holds %3C, and "description" holds "script".)
      expect(body).not.toMatch(/alert|<script|%3Cscript|<b>|x%3Cb/i);
    }
  });
});
